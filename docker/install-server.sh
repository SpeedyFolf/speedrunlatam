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
# The shared exclude file is baked into the image and also used by the
# hot-update agent. On a fresh install acl.xml/settings.xml do not exist yet,
# so they must come from the template. On updates they are preserved.
EXCLUDES_FILE="/opt/sync-excludes.txt"
if [ ! -f "$EXCLUDES_FILE" ]; then
    echo "[install] missing $EXCLUDES_FILE" >&2
    exit 1
fi
RSYNC_EXCLUDES=(--exclude-from="$EXCLUDES_FILE")

if [ -f "$TARGET/mods/deathmatch/acl.xml" ]; then
    RSYNC_EXCLUDES+=(
        --exclude='/mods/deathmatch/acl.xml'
        --exclude='/mods/deathmatch/settings.xml'
    )
fi

rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$SRC/" "$TARGET/"

mkdir -p "$TARGET/ghosts_server/ghosts" "$TARGET/logs"
mkdir -p "$TARGET/mods/deathmatch/resources/[gamemodes]/[race]/[addons]/race_ghost/ghosts"
mkdir -p "$TARGET/.deploy"

# Record which release was installed. The agent uses this marker to reconcile
# its current tag after a Reinstall. Old templates do not carry version.json,
# so fall back to resolving the tag from the release URL redirect.
TEMPLATE_TAG=""
if [ -f "$SRC/version.json" ]; then
    TEMPLATE_TAG=$(python3 - "$SRC/version.json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        print(json.load(handle).get("tag") or "")
except (OSError, ValueError):
    print("")
PY
)
fi
if [ -z "$TEMPLATE_TAG" ]; then
    # A tag-specific URL already contains the tag.
    TEMPLATE_TAG=$(printf '%s' "$URL" | sed -n 's#.*/releases/download/\([^/]*\)/.*#\1#p' || true)
fi
if [ -z "$TEMPLATE_TAG" ]; then
    # "latest" redirects to a signed asset URL that does not contain the tag.
    # Ask the GitHub API for the latest non-prerelease tag instead.
    API_JSON=$(curl "${CURL_ARGS[@]}" -sS "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)
    TEMPLATE_TAG=$(printf '%s' "$API_JSON" | python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)
    print(data.get("tag_name") or "")
except (ValueError, OSError):
    print("")
' 2>/dev/null || true)
fi
if [ -z "$TEMPLATE_TAG" ]; then
    EFFECTIVE_URL=$(curl "${CURL_ARGS[@]}" -sIL -o /dev/null -w '%{url_effective}' "$URL" 2>/dev/null || true)
    TEMPLATE_TAG=$(printf '%s' "$EFFECTIVE_URL" | sed -n 's#.*/releases/download/\([^/]*\)/.*#\1#p' || true)
fi
if [ -z "$TEMPLATE_TAG" ]; then
    TEMPLATE_TAG="unknown"
fi

python3 - "$TARGET/.deploy/installed.json" "$TEMPLATE_TAG" "$URL" <<'PY'
import json
import sys
from datetime import datetime, timezone

target, tag, url = sys.argv[1], sys.argv[2], sys.argv[3]
payload = {
    "schema": 1,
    "tag": tag,
    "source": "install",
    "template_url": url,
    "installed_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
}
with open(target, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

echo "[install] installed tag: $TEMPLATE_TAG"

if [ "$(id -u)" = "0" ]; then
    chown -R "${PUID:-999}:${PGID:-988}" "$TARGET"
fi

echo "[install] done"
