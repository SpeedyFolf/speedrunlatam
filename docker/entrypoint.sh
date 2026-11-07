#!/bin/bash
set -u

cd /home/container || exit 1

mkdir -p /home/container/logs /home/container/ghosts_server/ghosts

# Per-deployment secrets that must never be committed.
AUTOLOGIN_KEY="/home/container/mods/deathmatch/resources/[managers]/autologin/encryption_key.txt"
if [ -d "$(dirname "$AUTOLOGIN_KEY")" ] && [ ! -s "$AUTOLOGIN_KEY" ]; then
    openssl rand -hex 32 > "$AUTOLOGIN_KEY"
    chmod 600 "$AUTOLOGIN_KEY"
fi

# Generate mtaserver.conf from the template using the deployment environment.
SERVER_NAME="${SERVER_NAME:-Speedrun LATAM}"
OWNER_EMAIL="${OWNER_EMAIL:-}"
HTTP_DOWNLOAD_URL="${HTTP_DOWNLOAD_URL:-}"
SERVER_MAXPLAYERS="${SERVER_MAXPLAYERS:-70}"
SERVER_FPSLIMIT="${SERVER_FPSLIMIT:-300}"
SERVER_DOWNLOAD_PORT="${SERVER_DOWNLOAD_PORT:-22005}"

# Nginx serves thousands of small files; the default soft limit is too low.
ulimit -n 65536 2>/dev/null || true

mkdir -p /home/container/logs \
    /home/container/mods/deathmatch/resource-cache/http-client-files

CONF="/home/container/mods/deathmatch/mtaserver.conf"
TEMPLATE="/home/container/mods/deathmatch/mtaserver.conf.template"
if [ -f "$TEMPLATE" ]; then
    SERVER_NAME="$SERVER_NAME" OWNER_EMAIL="$OWNER_EMAIL" HTTP_DOWNLOAD_URL="$HTTP_DOWNLOAD_URL" \
        SERVER_MAXPLAYERS="$SERVER_MAXPLAYERS" SERVER_FPSLIMIT="$SERVER_FPSLIMIT" \
        python3 - "$TEMPLATE" "$CONF" <<'PY'
import os
import sys

source, target = sys.argv[1], sys.argv[2]
text = open(source, encoding="utf-8").read()
text = text.replace("{{SERVER_NAME}}", os.environ.get("SERVER_NAME", "Speedrun LATAM"))
text = text.replace("{{OWNER_EMAIL}}", os.environ.get("OWNER_EMAIL", ""))
text = text.replace("{{HTTP_DOWNLOAD_URL}}", os.environ.get("HTTP_DOWNLOAD_URL", ""))
text = text.replace("{{SERVER_MAXPLAYERS}}", os.environ.get("SERVER_MAXPLAYERS", "70"))
text = text.replace("{{SERVER_FPSLIMIT}}", os.environ.get("SERVER_FPSLIMIT", "300"))
open(target, "w", encoding="utf-8").write(text)
PY
fi

# Nginx serves only resource downloads. MTA keeps its HTTP server internal
# (STARTUP uses --httpport 22007) for webadmin and web resources.
NGINX_TEMPLATE="/opt/nginx/nginx.conf.template"
NGINX_CONF="/home/container/logs/nginx.conf"
if [ -f "$NGINX_TEMPLATE" ] && command -v nginx >/dev/null 2>&1; then
    SERVER_DOWNLOAD_PORT="$SERVER_DOWNLOAD_PORT" python3 - "$NGINX_TEMPLATE" "$NGINX_CONF" <<'PY'
import os
import sys

source, target = sys.argv[1], sys.argv[2]
text = open(source, encoding="utf-8").read()
text = text.replace("{{SERVER_DOWNLOAD_PORT}}", os.environ.get("SERVER_DOWNLOAD_PORT", "22005"))
open(target, "w", encoding="utf-8").write(text)
PY
    if ! nginx -c "$NGINX_CONF" 2>>/home/container/logs/nginx-error.log; then
        echo "[entrypoint] nginx failed to start; resource downloads will fail" >&2
    fi
fi

# Start the ghost API inside the same container.
if [ -f /opt/ghosts_server/main.py ]; then
    (
        cd /opt/ghosts_server || exit 0
        GHOSTS_DIR=/home/container/ghosts_server/ghosts \
            /opt/ghosts-venv/bin/gunicorn --bind 127.0.0.1:5000 --workers 2 main:app \
            >>/home/container/logs/ghosts.log 2>&1
    ) &
fi

STARTUP="${STARTUP:-./mta-server64 --port 22003 --httpport 22007 -n}"
MODIFIED_STARTUP=$(printf '%s' "$STARTUP" | sed -e 's/{{/${/g' -e 's/}}/}/g')

echo ":/home/container$ $MODIFIED_STARTUP"
exec bash -c "$MODIFIED_STARTUP"
