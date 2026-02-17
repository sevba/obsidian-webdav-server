# Obsidian Sync Server

A self-hosted WebDAV server for syncing Obsidian vaults. Includes automatic HTTPS certificate provisioning, version control, and backup functionality. Works with Obsidian desktop and mobile clients using the Remotely Save community plugin.

## Table of Contents

1.  [Introduction](#introduction)
2.  [Prerequisites](#prerequisites)
3.  [Installation & Setup](#installation--setup)
4.  [Obsidian Configuration](#obsidian-configuration)
5.  [Testing & Validation](#testing--validation)
6.  [Verifying Sync is Working](#verifying-sync-is-working)
7.  [Maintenance Commands](#maintenance-commands)
8.  [Git Operations & GitHub](#git-operations--github)
9.  [Troubleshooting](#troubleshooting)
10. [Architecture](#architecture)

---

## Introduction

This project runs a **self-hosted Obsidian vault sync server** on a Docker container, allowing you to sync your local Obsidian vault to a remote server over HTTPS with automatic TSL certificate provisioning and renewal. All file changes are automatically committed to Git on the sync server, providing advanced version history and recovery options.

### Technology Stack & Rationale

| Technology                  | Role                             | Why                                                                                                                                                             |
| --------------------------- | -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Caddy**                   | Web server & reverse proxy       | Automatic HTTPS via Let's Encrypt with zero manual cert management; minimal, readable configuration syntax.                                                     |
| **caddy-webdav plugin**     | WebDAV protocol support          | The `mholt/caddy-webdav` plugin for Caddy adds PROPFIND, LOCK, UNLOCK, and other methods that the Remotely Save plug-in for Obsidian requires.                  |
| **Docker & docker-compose** | Containerization & orchestration | Reproducible isolated environment; easy restart policy (`unless-stopped`); built-in log rotation limits.                                                        |
| **Git**                     | Version control & backup         | Automatic timestamped commit history of all vault contents; enables rollback to any point in time; optional integration with GitHub/GitLab for off-site backup. |
| **Alpine Linux**            | Container base OS                | Minimal footprint; only essential packages installed (git, bash, coreutils). Well-known base image often used in small server setups.                           |


---

## Prerequisites

### System Requirements

- **OS**: Debian/Ubuntu (or any Linux with Docker support)
- **Disk**: Minimum 1 GB free space; but to be scaled based on vault requirements
- **CPU**: Any (minimal resource usage)
- **RAM**: 256 MB minimum; 512 MB recommended

### Software

- **Docker** (v20+): `docker --version`
- **Docker Compose** (v2+): `docker compose --version`
- **Git**: `git --version`
- **curl**: `curl --version`

**Installation:**
```bash
# Debian/Ubuntu
sudo apt update && sudo apt install -y docker.io docker-compose git curl
sudo usermod -aG docker $(whoami)  # Allow non-root docker commands
```

### Network Requirements

1. **DNS A record**: Point your domain (e.g., `obisian.your-domain.xyz`) to your server's public IP. The DNS record **MUST** be setup before installing Caddy, in order for automatic HTTPS certificate provisioning (Let's Encrypt ACME challenge) to work.
2. **Firewall**: Ports **80** and **443** must be open (needed for Let's Encrypt ACME challenge and WebDAV access).
3. **Internet**: Outbound HTTPS to `acme-v02.api.letsencrypt.org` for certificate provisioning.

---

## Installation & Setup

Before proceeding with the installation, check the prerequisites above. A valid (sub-)domain with proper DNS records resolving to your sync server's IP address is a hard requirement. The automatic certificate provisioning will fail otherwise.

### Step 1: Clone the Repository


```bash
git clone https://github.com/sevba/obsidian-sync-server.git
cd obsidian-sync-server
```

This repository contains all the necessary files:
- `Dockerfile` — Custom Caddy build with WebDAV plugin + Git support
- `docker-compose.yml` — Container orchestration config
- `Caddyfile` — Caddy web server configuration (template)
- `git-auto-commit.sh` — Automatic Git commit script

### Step 2: Generate Password Hash

Create a bcrypt-hashed password for WebDAV authentication:

```bash
# Using Caddy (if installed locally)
caddy hash-password

# Or use the temporary container method
docker run --rm -it caddy:latest caddy hash-password
```

Save the output hash for Step 3.

### Step 3: Configure Caddyfile

Edit the `Caddyfile` and replace the following placeholders:

1. **`YOUR_DOMAIN`** — Your server's domain (e.g., `obisian.your-domain.xyz`)
2. **`YOUR_HASHED_PASSWORD`** — The bcrypt hash generated in Step 2
3. **`obsidian`** — Change to your desired WebDAV username (if needed)

```bash
# Open the file in your editor
nano Caddyfile
# or
vim Caddyfile
```

Example section to update:

```caddyfile
YOUR_DOMAIN {
    ...
    basicauth {
        obsidian YOUR_HASHED_PASSWORD
    }
    ...
}
```

### Step 4: Verify DNS

Before starting the container, ensure DNS is correctly configured:

```bash
nslookup YOUR_DOMAIN
dig YOUR_DOMAIN +short
```

Should return your server's public IP address. **DNS must be set up BEFORE starting Caddy**, otherwise Let's Encrypt certificate provisioning will fail.

### Step 5: Build & Start

```bash
docker compose build
docker compose up -d
```

Check that the container starts successfully:

```bash
docker compose ps
```

Expected output: Container status should show `Up` and `healthy` after 40 seconds (certificate provisioning takes time on first startup).

---

## Obsidian Configuration

### Install Remotely Save Plugin

1. In Obsidian, go to **Settings → Community Plugins**
2. Search for **"Remotely Save"** and install
3. Enable the plugin

### Configure WebDAV Endpoint

1. Open the Remotely Save plugin settings
2. Choose **WebDAV** as the sync service
3. Fill in the following:

| Field                     | Value                           |
| ------------------------- | ------------------------------- |
| **URL**                   | `https://YOUR_DOMAIN/obsidian/` |
| **Username**              | `obsidian`                      |
| **Password**              | (your plaintext password)       |
| **Schedule For Auto Run** | Enabled (recommended)           |
| **Run Once on Startup**   | Enabled (recommended)           |
| **Sync on Save**          | Enabled (recommended)           |


---

## Testing & Validation

### 1. Health Check

```bash
curl https://YOUR_DOMAIN/health
# Expected: 200 OK
# Response: OK
```

### 2. WebDAV Without Auth (Should Fail)

```bash
curl -I https://YOUR_DOMAIN/obsidian/
# Expected: 401 Unauthorized
```

### 3. WebDAV With Auth (Should Succeed)

```bash
curl -u obsidian:your_password https://YOUR_DOMAIN/obsidian/
# Expected: 200 OK or 207 Multi-Status
# (207 is common for empty WebDAV directories)
```

### 4. HTTPS Certificate Validation

```bash
curl -v https://YOUR_DOMAIN/health 2>&1 | grep -i certificate
# Should show a valid Let's Encrypt certificate
```

### 5. Container Health

```bash
docker compose ps
# Container should show status: "Up X seconds (healthy)"
```

### 6. Validate Caddy Configuration

```bash
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
# Should show success messages (not errors)
```

---

## Verifying Sync is Working

### Check Files in WebDAV Directory

After syncing from Obsidian:

```bash
docker exec obsidian-caddy ls -la /data/webdav/
```

You should see your vault structure (folders and notes).

### Check Git Commit History

```bash
docker exec obsidian-caddy git -C /data/webdav log --oneline -10
# Expected output:
# abc1234 Auto-commit: 2026-02-17 09:42:00
# def5678 Auto-commit: 2026-02-17 09:41:00
# ...
```

### Monitor git-auto-commit Logs

```bash
docker compose logs caddy | grep "\[git-auto-commit\]"
# Expected output:
# [git-auto-commit] 2026-02-17 09:42:00 Committed 3 file(s)
```

---

## Maintenance Commands

Below are useful but **optional** commands to view and manage your Obsidian sync server. 

### View Container Logs

```bash
# Follow logs (live)
docker compose logs -f caddy

# View last 50 lines
docker compose logs --tail=50 caddy
```

### View Caddy Access Log

```bash
# Follow in real-time
docker exec obsidian-caddy tail -f /data/logs/access.log

# View last 20 requests
docker exec obsidian-caddy tail -20 /data/logs/access.log
```

### Start, Stop, Restart Container

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Restart (preserves volumes)
docker compose restart
```

### Reload Caddy Config Without Downtime

Update `Caddyfile` and reload:

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

No container restart needed.

### Backup Vault

Create a compressed archive of your vault (for copying to off-site backup server). This will back up the complete Git repository.

```bash
docker run --rm \
  -v obsidian-sync-server_caddy_data:/data \
  -v ~/backups:/backup \
  alpine tar czf /backup/obsidian_backup.tar.gz /data/webdav/

# Verify backup
tar tzf obsidian_backup.tar.gz | head -20
```

---

## Git Operations & GitHub

Below are useful but **optional** commands to view and manage Git version history. 

### View Commit History

```bash
# List commits with one-line messages
docker exec obsidian-caddy git -C /data/webdav log --oneline -20

# Show detailed commit with diff
docker exec obsidian-caddy git -C /data/webdav show <commit-hash>

# Show files changed in a commit
docker exec obsidian-caddy git -C /data/webdav show --stat <commit-hash>
```

### View Differences

```bash
# Changes between HEAD and previous commit
docker exec obsidian-caddy git -C /data/webdav diff HEAD~1

# All uncommitted changes
docker exec obsidian-caddy git -C /data/webdav diff

# Staged changes only
docker exec obsidian-caddy git -C /data/webdav diff --cached
```

### Rollback a Single File

Restore a file to a previous version:

```bash
# Find the commit hash
docker exec obsidian-caddy git -C /data/webdav log --oneline path/to/note.md

# Restore the file
docker exec obsidian-caddy git -C /data/webdav checkout <commit-hash> -- path/to/note.md

# Verify restoration
docker exec obsidian-caddy git -C /data/webdav diff HEAD
```

The restored file's timestamp will be set to the moment you execute the commend, so Remotely Save will consider this version to be the latest and will download it from the sync server to your local Obsidian client (as long as the Action For Conflict setting of Remotely Save is set to "newer version survives" which is the default setting).

### Full Rollback (Reset to Previous State)

**WARNING**: This discards all changes since the target commit.

```bash
# Find the target commit
docker exec obsidian-caddy git -C /data/webdav log --oneline

# Reset to that commit (discards all changes after)
docker exec obsidian-caddy git -C /data/webdav reset --hard <commit-hash>

# Verify
docker exec obsidian-caddy git -C /data/webdav log --oneline -5
```

### Push to Remote Server 

Below are useful but **optional** commands to sync your Git repository to a remote Git server. This can be considered an "off-site backup" and offers additional protection against dataloss in case of hard drive failure.
**WARNING:** Make sure you trust the remote Git server and ensure privacy settings (e.g. private repository) are configured accordingly. All your Obisian data will be pushed to this remote repository. 
The examples below use Github as remote server, however it is recommended not to store any sensitive data in a Github repository regardless of it being private or not. For sensitive data, make sure you fully trust your remote Git service provider.

**Configure Git inside container:**

```bash
# Use a GitHub token in the remote URL (single command)
docker exec obsidian-caddy git -C /data/webdav remote add origin https://TOKEN@github.com/YOUR_USERNAME/YOUR_REPO.git

# Then git will prompt for password once (enter the token)
docker exec obsidian-caddy git -C /data/webdav push -u origin main
```

**Push to remote server:**

```bash
# Verify remote is configured
docker exec obsidian-caddy git -C /data/webdav remote -v

# Push all commits
docker exec obsidian-caddy git -C /data/webdav push -u origin main

# Subsequent pushes (after auto-commits)
docker exec obsidian-caddy git -C /data/webdav push
```

**Automate pushes:**

Add a cron job or modify `git-auto-commit.sh` to push after each commit:

```bash
docker exec obsidian-caddy git -C /data/webdav push origin main
```

---

## Troubleshooting

### Container Won't Start

**Check logs:**

```bash
docker compose logs caddy
```

**Common causes:**

- **Port already in use**: `docker ps -a` to find conflicting container
  - Solution: Change port mapping in `docker-compose.yml` (e.g., `8443:443`)
  - Important: Note that Caddy requires port 80 to be open in order to receive the ACME challenges for provisioning HTTPS certificates. I highly recommend the use of ports 80 and 443 for your Obsidian sync server. If these ports are not available, consider requesting your hosting provider to provision an additional public IP address.
- **DNS not resolving**: `nslookup YOUR_DOMAIN` returns no result
  - Solution: Wait for DNS propagation (up to 24 hours) or update DNS record
- **File permissions**: Cannot write to `caddy_data` volume
  - Solution: Check volume ownership: `docker exec obsidian-caddy ls -ld /data`

### WebDAV Returns 404 or 500

**Validate Caddyfile syntax:**

```bash
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
```

**Verify `order webdav before file_server` is present** at the top of the config.

```bash
docker exec obsidian-caddy cat /etc/caddy/Caddyfile | head -20
```

### HTTPS Certificate Not Obtained

**Check Let's Encrypt logs:**

```bash
docker compose logs caddy | grep -i "acme\|certificate\|let"
```

**Common causes:**

- **DNS not propagated**: Domain doesn't resolve to server IP yet (wait up to 24 hours)
- **Port 80 blocked by firewall**: Let's Encrypt uses port 80 for ACME challenge
  - Solution: Open port 80 in firewall, or configure ACME via DNS challenge (requires Caddyfile modification)
- **Rate limited**: Let's Encrypt has limits (50 failures/domain/hour)
  - Solution: Wait 1 hour before retrying; use staging environment for testing

**Manual trigger (if needed):**

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

### Obsidian Sync Fails

**Check credentials:**

```bash
curl -u obsidian:your_password https://YOUR_DOMAIN/obsidian/
```

Should return 200 or 207, not 401.

**Verify URL format:**

- URL must end with `/`: `https://YOUR_DOMAIN/obsidian/`
- Check that `YOUR_DOMAIN` matches DNS and certificate

**Check Caddy health:**

```bash
curl https://YOUR_DOMAIN/health
# Expected: "OK" 200
```

### Git Not Committing

**Check git-auto-commit script is running:**

```bash
docker compose logs caddy | grep "\[git-auto-commit\]" | tail -5
```

**Verify Git repo exists:**

```bash
docker exec obsidian-caddy git -C /data/webdav status
# Should show branch, commit count, etc. (not "fatal")
```

**Manually trigger a commit:**

```bash
docker exec obsidian-caddy bash -c 'cd /data/webdav && git add -A && git commit -m "Manual commit test"'
```

### Port Already in Use

**Find conflicting container:**

```bash
docker ps -a
lsof -i :443  # (if lsof installed on host)
netstat -tuln | grep 443
```

---

## Support & Resources

- **Caddy Documentation**: https://caddyserver.com/docs/
- **caddy-webdav Plugin**: https://github.com/mholt/caddy-webdav
- **Obsidian Remotely Save**: https://github.com/remotely-save/remotely-save

---

## Architecture

### Data Flow

```
Obsidian Client
      ↓ (HTTPS WebDAV)
   obisian.your-domain.xyz:443
      ↓
   Caddy Server
      ├─ /obsidian/*  → [Basic Auth] → WebDAV handler → /data/webdav/
      └─ /health      → "OK" 200
      ↓
   Git Auto-Commit Watcher (background process)
      ├─ Every 60 seconds: check for changes
      └─ Skip if files modified within last 30 seconds (sync is still ongoing)
```

### File Locations Inside Container

```
/data/
├── webdav/              ← Your vault files + .git/ repo
│   ├── folder1/
│   ├── note.md
│   └── .git/            ← Git history (managed by git-auto-commit.sh)
├── logs/
│   └── access.log       ← JSON formatted request log (rotated)
└── caddy/
    ├── certificates/    ← Let's Encrypt TLS certs
    └── autosave.json    ← Caddy config backup
```

### Git Auto-Commit Logic

The `git-auto-commit.sh` script runs continuously in the background:

1. **Startup**: Initializes a Git repo in `/data/webdav/` if one doesn't exist
2. **Loop** (every 60 seconds):
   - Checks for files modified in the last 30 seconds (ignores if active syncs detected to prevent committing partially written files)
   - If no recent activity, stages all changes (`git add -A`)
   - Commits with a timestamped message: `Auto-commit: 2026-02-17 09:42:00`
   - Updates reference timestamp for next cycle

**Key Parameters:**
- `WATCH_INTERVAL=60` — Check for changes every 60 seconds
- `MIN_AGE=30` — Ignore files modified within last 30 seconds (still syncing)

---

**Last Updated**: February 2026
**Version**: 1.0
