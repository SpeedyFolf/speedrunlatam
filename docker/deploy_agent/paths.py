"""Path rules shared by the agent and the release builder.

The list mirrors docker/sync-excludes.txt.  Keep both files in sync: the
shell installer uses the exclude file with rsync, while the Python code
uses these helpers to decide what may be written or deleted.
"""

from __future__ import annotations

import posixpath
from pathlib import PurePosixPath

RESOURCE_ROOT = "mods/deathmatch/resources"

RUNTIME_EXACT = {
    "mods/deathmatch/registry.db",
    "mods/deathmatch/internal.db",
    "mods/deathmatch/banlist.xml",
    "mods/deathmatch/server-id.keys",
    "mods/deathmatch/neon-identity.keys",
    "mods/deathmatch/mtaserver.conf",
    "mods/deathmatch/resources/[managers]/autologin/encryption_key.txt",
}

RUNTIME_PREFIXES = (
    "mods/deathmatch/databases/",
    "mods/deathmatch/resource-cache/",
    "mods/deathmatch/logs/",
    "mods/deathmatch/backups/",
    "mods/deathmatch/dumps/",
    "mods/deathmatch/resources/[gamemodes]/[race]/[addons]/race_ghost/ghosts/",
    "ghosts_server/ghosts/",
    "logs/",
    "backups/",
    ".deploy/",
)

# Files that the release may manage.  Runtime data is never included.
MANAGED_EXACT = {
    "mta-server64",
    "NOTICE",
    "LICENSE",
    "README",
    "version.json",
}

MANAGED_PREFIXES = (
    "x64/",
    "mods/deathmatch/",
    "ghosts_server/",
)


class PathError(ValueError):
    """Raised when a bundle contains a path we refuse to touch."""


def normalize(rel: str) -> str:
    """Return a normalized POSIX path or raise PathError."""
    if not isinstance(rel, str):
        raise PathError(f"invalid path type: {type(rel)!r}")
    if not rel or "\x00" in rel:
        raise PathError("empty path")
    if "\\" in rel:
        raise PathError(f"backslashes are not allowed: {rel!r}")

    # Strip a single leading "./" as produced by tar archives.
    while rel.startswith("./"):
        rel = rel[2:]

    if rel.startswith("/"):
        raise PathError(f"absolute path is not allowed: {rel!r}")

    parts = PurePosixPath(rel).parts
    if any(part in ("", ".", "..") for part in parts):
        raise PathError(f"unsafe path: {rel!r}")

    normalized = posixpath.normpath(rel)
    if normalized == "." or normalized.startswith("../") or normalized == "..":
        raise PathError(f"unsafe path: {rel!r}")
    return normalized


def is_under(rel: str, prefix: str) -> bool:
    rel = rel.rstrip("/")
    prefix = prefix.rstrip("/")
    return rel == prefix or rel.startswith(prefix + "/")


def is_runtime(rel: str) -> bool:
    rel = normalize(rel)
    if rel in RUNTIME_EXACT:
        return True
    if any(rel.startswith(prefix) for prefix in RUNTIME_PREFIXES):
        return True
    # Patterns that the shell exclude file matches anywhere.
    if rel.endswith("/autologin/encryption_key.txt"):
        return True
    if "/race_ghost/ghosts/" in rel or rel.endswith("/race_ghost/ghosts"):
        return True
    return False


def is_resource_path(rel: str) -> bool:
    rel = normalize(rel)
    return is_under(rel, RESOURCE_ROOT)


def _is_ancestor_of(rel: str, candidates: tuple[str, ...]) -> bool:
    rel = normalize(rel).rstrip("/")
    for candidate in candidates:
        candidate = candidate.rstrip("/")
        if candidate == rel or candidate.startswith(rel + "/"):
            return True
    return False


def is_managed_ancestor(rel: str) -> bool:
    """Whether rel is a parent directory of a managed path.

    Full templates contain directory entries such as ``mods`` or ``x64`` that
    are not managed paths themselves but are needed to create their children.
    """
    return _is_ancestor_of(rel, (*MANAGED_EXACT, *MANAGED_PREFIXES))


def is_runtime_ancestor(rel: str) -> bool:
    return _is_ancestor_of(rel, (*RUNTIME_EXACT, *RUNTIME_PREFIXES))


def is_managed(rel: str) -> bool:
    """Whether a release is allowed to manage this path at all."""
    rel = normalize(rel)
    if is_runtime(rel):
        return False
    if rel in MANAGED_EXACT:
        return True
    return any(rel.startswith(prefix) for prefix in MANAGED_PREFIXES)


def ensure_managed(rel: str) -> str:
    rel = normalize(rel)
    if not is_managed(rel):
        raise PathError(f"path is not managed by a release: {rel!r}")
    return rel


def is_settings_or_acl(rel: str) -> bool:
    return rel in {
        "mods/deathmatch/settings.xml",
        "mods/deathmatch/acl.xml",
    }
