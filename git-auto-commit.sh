#!/bin/bash

WEBDAV_DIR="/data/webdav"
WATCH_INTERVAL=60
MIN_AGE=30
AGE_CHECK_FILE="/tmp/age_check"
LOG_PREFIX="[git-auto-commit]"

log() {
    echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Wait for webdav directory to exist
while [ ! -d "$WEBDAV_DIR" ]; do
    log "Waiting for WebDAV directory..."
    sleep 5
done

cd "$WEBDAV_DIR" || exit 1

# Initialize git repo if needed
if [ ! -d ".git" ]; then
    log "Initializing Git repository..."
    git init
    git config user.email "obsidian-sync@local"
    git config user.name "Obsidian Sync Server"

    # Only commit if there are files
    if [ -n "$(ls -A .)" ]; then
        git add -A
        git commit -m "Initial commit"
    else
        log "No files yet, skipping initial commit"
    fi
fi

# Create initial reference file
touch "$AGE_CHECK_FILE"

log "Starting auto-commit watcher (interval: ${WATCH_INTERVAL}s, min age: ${MIN_AGE}s)..."

while true; do
    sleep $WATCH_INTERVAL

    # Find files modified within last MIN_AGE seconds by comparing with reference file age
    CURRENT_TIME=$(date +%s)
    REF_TIME=$(stat -c %Y "$AGE_CHECK_FILE" 2>/dev/null || stat -f %m "$AGE_CHECK_FILE" 2>/dev/null)
    TIME_DIFF=$((CURRENT_TIME - REF_TIME))

    if [ $TIME_DIFF -lt $MIN_AGE ]; then
        # Reference file is too new, create a new one
        touch "$AGE_CHECK_FILE"
    fi

    # Find files modified more recently than reference file
    ACTIVE_FILES=$(find "$WEBDAV_DIR" \
        -not -path '*/.git/*' \
        -type f \
        -newer "$AGE_CHECK_FILE" \
        2>/dev/null | wc -l)

    if [ "$ACTIVE_FILES" -gt 0 ]; then
        log "Skipping commit - $ACTIVE_FILES file(s) modified within last ${MIN_AGE}s"
        continue
    fi

    # Check for uncommitted changes (works on empty and non-empty repos)
    UNTRACKED=$(git ls-files --others --exclude-standard | wc -l)
    MODIFIED=$(git status --short | wc -l)

    if [ "$UNTRACKED" -gt 0 ] || [ "$MODIFIED" -gt 0 ]; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        git add -A

        # Count staged changes
        STAGED=$(git diff --cached --name-only | wc -l)

        if [ "$STAGED" -gt 0 ]; then
            git commit -m "Auto-commit: $TIMESTAMP" -m "Files changed: $STAGED"
            log "Committed $STAGED file(s)"
        else
            log "Nothing staged to commit"
        fi
    else
        log "No changes detected"
    fi

    # Update reference file for next iteration
    touch "$AGE_CHECK_FILE"
done
