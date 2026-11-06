#!/bin/bash
set -euo pipefail

TARGET="${1:-/mnt/server}"
REPO="${GITHUB_REPOSITORY:-ferecece/speedrunlatam}"
URL="${SERVER_TEMPLATE_URL:-https://github.com/${REPO}/releases/latest/download/server-template.tar.gz}"
# Wings mounts a 100MB tmpfs on /tmp. That is enough for the compressed
# template but not for the extracted server, so stage on the container's
# writable layer instead.
TMP="$(mktemp -d "${TMPDIR:-/var/tmp}/speedrunlatam-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TARGET"

echo "[install] repository: $REPO"
echo "[install] template: $URL"
echo "[install] target: $TARGET"

CURL_ARGS=(-fL --retry 3 --retry-delay 2)
if [ -n "${GITHUB_TOKEN:-}" ]; then
    CURL_ARGS+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

curl "${CURL_ARGS[@]}" "$URL" -o "$TMP/server-template.tar.gz"
mkdir -p "$TMP/new"
tar -xzf "$TMP/server-template.tar.gz" -C "$TMP/new"

if [ -f "$TMP/new/server/mta-server64" ]; then
    SRC="$TMP/new/server"
else
    SRC="$TMP/new"
fi

if [ ! -f "$SRC/mta-server64" ]; then
    echo "[install] invalid template: mta-server64 not found" >&2
    exit 1
fi

BACKUP=""
if [ -f "$TARGET/mta-server64" ]; then
    BACKUP="$TARGET/backups/pre-update-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    echo "[install] backup: $BACKUP"

    copy_item() {
        local rel="$1"
        if [ -e "$TARGET/$rel" ]; then
            mkdir -p "$BACKUP/$(dirname "$rel")"
            cp -a "$TARGET/$rel" "$BACKUP/$rel"
        fi
    }

    for item in \
        mods/deathmatch/registry.db \
        mods/deathmatch/internal.db \
        mods/deathmatch/settings.xml \
        mods/deathmatch/acl.xml \
        mods/deathmatch/banlist.xml \
        mods/deathmatch/server-id.keys \
        mods/deathmatch/neon-identity.keys \
        mods/deathmatch/databases \
        mods/deathmatch/resources/[managers]/autologin/encryption_key.txt \
        mods/deathmatch/resources/[gamemodes]/[race]/[addons]/race_ghost/ghosts \
        ghosts_server/ghosts; do
        copy_item "$item"
    done
fi

# Managed files are replaced. Runtime data and per-deployment secrets stay.
# On a fresh install acl.xml/settings.xml do not exist yet, so they must come
# from the template. On updates they are preserved.
RSYNC_EXCLUDES=(
    --exclude='/mods/deathmatch/registry.db'
    --exclude='/mods/deathmatch/internal.db'
    --exclude='/mods/deathmatch/banlist.xml'
    --exclude='/mods/deathmatch/server-id.keys'
    --exclude='/mods/deathmatch/neon-identity.keys'
    --exclude='/mods/deathmatch/databases/'
    --exclude='/mods/deathmatch/resource-cache/'
    --exclude='/mods/deathmatch/logs/'
    --exclude='/mods/deathmatch/backups/'
    --exclude='/mods/deathmatch/dumps/'
    --exclude='/mods/deathmatch/mtaserver.conf'
    --exclude='*/autologin/encryption_key.txt'
    --exclude='race_ghost/ghosts/'
    --exclude='/ghosts_server/ghosts/'
    --exclude='/logs/'
    --exclude='/backups/'
)

if [ -f "$TARGET/mods/deathmatch/acl.xml" ]; then
    RSYNC_EXCLUDES+=(
        --exclude='/mods/deathmatch/acl.xml'
        --exclude='/mods/deathmatch/settings.xml'
    )
fi

rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$SRC/" "$TARGET/"

mkdir -p "$TARGET/ghosts_server/ghosts" "$TARGET/logs"
mkdir -p "$TARGET/mods/deathmatch/resources/[gamemodes]/[race]/[addons]/race_ghost/ghosts"

if [ "$(id -u)" = "0" ]; then
    chown -R "${PUID:-999}:${PGID:-988}" "$TARGET"
fi

echo "[install] done"
