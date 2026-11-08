from __future__ import annotations

import logging
import os
import shutil
import tempfile
from pathlib import Path
from typing import Any, Iterable

from .config import Config
from .paths import (
    RESOURCE_ROOT,
    is_managed,
    is_resource_path,
    is_settings_or_acl,
    normalize,
)
from .util import DeployError, atomic_write_json, read_json, run, utc_now

log = logging.getLogger(__name__)


def _is_within(path: Path, base: Path) -> bool:
    try:
        path.resolve().relative_to(base.resolve())
        return True
    except ValueError:
        return False


def _copy_atomic(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", dir=str(destination.parent)
    )
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            with source.open("rb") as input_handle:
                shutil.copyfileobj(input_handle, handle, length=1024 * 1024)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, source.stat().st_mode & 0o777)
        os.replace(tmp, destination)
    finally:
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass


def _remove_empty_parents(path: Path, target: Path) -> None:
    stop = target
    if is_resource_path(path.relative_to(target).as_posix()):
        stop = target / RESOURCE_ROOT
    parent = path.parent
    while parent != stop and _is_within(parent, stop):
        try:
            parent.rmdir()
        except OSError:
            break
        parent = parent.parent


def write_version(cfg: Config, tag: str, previous_tag: str | None, source: str) -> None:
    atomic_write_json(
        cfg.version_path,
        {
            "schema": 1,
            "tag": tag,
            "previous_tag": previous_tag,
            "deployed_at": utc_now(),
            "source": source,
        },
    )


def apply_delta(
    cfg: Config,
    staging: Path,
    manifest: dict[str, Any],
    backup_dir: Path,
) -> dict[str, Any]:
    changes = manifest.get("changes") or {}
    modified = [normalize(p) for p in changes.get("modified", [])]
    added = [normalize(p) for p in changes.get("added", [])]
    deleted = [normalize(p) for p in changes.get("deleted", [])]

    result = {"written": [], "deleted": [], "skipped": []}
    for rel in modified + added:
        if is_settings_or_acl(rel):
            raise DeployError("E_APPLY", f"refusing to overwrite preserved file: {rel}")
        if not is_managed(rel):
            raise DeployError("E_APPLY", f"refusing to write unmanaged path: {rel}")
        source = staging / rel
        destination = cfg.target / rel
        if not source.is_file():
            raise DeployError("E_APPLY", f"file missing from staged bundle: {rel}")
        if not _is_within(destination, cfg.target):
            raise DeployError("E_APPLY", f"destination escapes the server: {rel}")
        _copy_atomic(source, destination)
        result["written"].append(rel)

    for rel in deleted:
        if is_settings_or_acl(rel):
            raise DeployError("E_APPLY", f"refusing to delete preserved file: {rel}")
        if not is_managed(rel):
            raise DeployError("E_APPLY", f"refusing to delete unmanaged path: {rel}")
        destination = cfg.target / rel
        if not _is_within(destination, cfg.target):
            raise DeployError("E_APPLY", f"destination escapes the server: {rel}")
        if destination.is_dir():
            shutil.rmtree(destination)
            result["deleted"].append(rel)
        elif destination.exists():
            destination.unlink()
            result["deleted"].append(rel)
            _remove_empty_parents(destination, cfg.target)
        else:
            result["skipped"].append(rel)

    write_version(
        cfg,
        str(manifest["tag"]),
        manifest.get("previous_tag"),
        source="hot-update",
    )
    return result


def _parse_itemized(output: str) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for line in output.splitlines():
        if "\t" not in line:
            continue
        item, rel = line.split("\t", 1)
        rel = rel.strip()
        if not rel:
            continue
        if item.startswith("*deleting"):
            entries.append({"path": rel, "existed": True, "action": "deleted"})
        elif item.startswith(">f"):
            if "+++++++++" in item:
                entries.append({"path": rel, "existed": False, "action": "created"})
            else:
                entries.append({"path": rel, "existed": True, "action": "modified"})
        elif item.startswith("cd"):
            entries.append({"path": rel, "existed": False, "action": "dir"})
        elif item.startswith(".d"):
            # Directory metadata changed; no file content to restore.
            continue
        elif item.startswith(">d"):
            continue
    # De-duplicate by path, preferring the first occurrence.
    seen: set[str] = set()
    unique: list[dict[str, Any]] = []
    for entry in entries:
        if entry["path"] in seen:
            continue
        seen.add(entry["path"])
        unique.append(entry)
    return unique


def apply_full(
    cfg: Config,
    staging: Path,
    manifest: dict[str, Any],
    backup_dir: Path,
) -> dict[str, Any]:
    code = backup_dir / "code"
    code.mkdir(parents=True, exist_ok=True)

    args = [
        "rsync",
        "-a",
        "--delete",
        "--itemize-changes",
        "--out-format=%i\t%n",
        "--backup",
        "--backup-dir",
        str(code),
    ]
    if cfg.sync_excludes.is_file():
        args.append(f"--exclude-from={cfg.sync_excludes}")
    args.extend(
        [
            "--exclude=/.deploy/",
            "--exclude=/mods/deathmatch/acl.xml",
            "--exclude=/mods/deathmatch/settings.xml",
            f"{staging}/",
            f"{cfg.target}/",
        ]
    )

    proc = run(args, check=False)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise DeployError("E_APPLY", f"rsync failed ({proc.returncode}): {detail}")

    entries = _parse_itemized(proc.stdout)
    atomic_write_json(backup_dir / "journal.json", {"entries": entries})

    write_version(
        cfg,
        str(manifest["tag"]),
        manifest.get("previous_tag"),
        source="full-update",
    )
    return {
        "written": [e["path"] for e in entries if e["action"] in {"created", "modified", "dir"}],
        "deleted": [e["path"] for e in entries if e["action"] == "deleted"],
        "skipped": [],
    }


def read_apply_result(backup_dir: Path) -> dict[str, Any]:
    """Best-effort result for a full apply whose journal was written."""
    entries = read_json(backup_dir / "journal.json", default={}) or {}
    return entries if isinstance(entries, dict) else {}
