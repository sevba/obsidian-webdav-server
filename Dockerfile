FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-webdav

FROM caddy:latest

# Install git and bash
RUN apk add --no-cache git bash coreutils

# Copy auto-commit script
COPY git-auto-commit.sh /usr/local/bin/git-auto-commit.sh
RUN chmod +x /usr/local/bin/git-auto-commit.sh

# Copy the built Caddy binary with WebDAV support
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Run both git-auto-commit script and Caddy
CMD ["/bin/bash", "-c", "/usr/local/bin/git-auto-commit.sh & caddy run --config /etc/caddy/Caddyfile --adapter caddyfile"]
