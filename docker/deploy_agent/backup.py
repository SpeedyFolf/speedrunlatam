from __future__ import annotations

import logging
import shutil
import sqlite3
import subprocess
import tarfile
from pathlib import Path
from typing import Any, Iterable

from .config import Config
from .paths import normalize
from .util import (
    DeployError,
    atomic_write_json,
    copy_atomic,
    read_json,
    sanitize_tag,
    sha256_file,
    utc_now,
)

log = logging.getLogger(__name__)

DATABASES = [
    "mods/deathmatch/registry.db",
    "mods/deathmatch/internal.db",
]

SENSITIVE_DIRS = [
    "mods/deathmatch/databases",
    "mods/deathmatch/resources/[gamemodes]/[race]/[addons]/race_ghost/ghosts",
    "ghosts_server/ghosts",
]

SENSITIVE_FILES = [
    "mods/deathmatch/resources/[managers]/autologin/encryption_key.txt",
    "mods/deathmatch/server-id.keys",
    "mods/deathmatch/neon-identity.keys",
]

DB_COUNT_QUERIES = {
    "mods/deathmatch/registry.db": {
        "maptimes": "select count(*) from maptimes",
    },
    "mods/deathmatch/internal.db": {
        "accounts": "select count(*) from accounts",
        "userdata": "select count(*) from userdata",
    },
}


def new_backup(cfg: Config, tag: str) -> Path:
    stamp = utc_now().replace(":", "").replace("-", "").replace("T", "-").replace("Z", "")
    path = cfg.backups_dir / f"{stamp}-{sanitize_tag(tag)}"
    (path / "sensitive").mkdir(parents=True, exist_ok=True)
    (path / "code").mkdir(parents=True, exist_ok=True)
    return path


def _backup_sqlite(rel: str, db: Path, destination: Path) -> dict[str, Any]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    sqlite3_bin = shutil.which("sqlite3")
    info: dict[str, Any] = {"path": rel}
    if sqlite3_bin:
        subprocess.run(
            [sqlite3_bin, str(db), f'.backup "{destination}"'],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    else:
        log.warning("sqlite3 not found; copying %s without an online backup", db)
        shutil.copy2(db, destination)
    info["backup"] = destination.name
    info["size"] = destination.stat().st_size
    info["sha256"] = sha256_file(destination)

    counts: dict[str, int] = {}
    for table, query in DB_COUNT_QUERIES.get(rel, {}).items():
        try:
            connection = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            try:
                counts[table] = int(connection.execute(query).fetchone()[0])
            finally:
                connection.close()
        except sqlite3.Error as exc:
            log.warning("cannot count %s in %s: %s", table, db, exc)
    info["counts"] = counts
    return info


def _tar_paths(cfg: Config, destination: Path, rels: Iterable[str]) -> list[str]:
    added: list[str] = []
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(destination, "w:gz") as archive:
        for rel in rels:
            path = cfg.target / rel
            if not path.exists():
                continue
            archive.add(path, arcname=rel, recursive=True)
            added.append(rel)
    return added


def snapshot_sensitive(cfg: Config, backup_dir: Path, tag: str) -> dict[str, Any]:
    """Save the data that an update must never put at risk.

    registry.db contains maptimes (toptimes); internal.db contains the
    accounts used by autologin.  Ghost files live separately, so both the
    SQLite databases and the ghost directories are captured together.
    """
    sensitive = backup_dir / "sensitive"
    sensitive.mkdir(parents=True, exist_ok=True)

    report: dict[str, Any] = {
        "tag": tag,
        "created_at": utc_now(),
        "databases": [],
        "directories": [],
        "files": [],
    }

    for rel in DATABASES:
        source = cfg.target / rel
        if not source.is_file():
            continue
        destination = sensitive / Path(rel).name
        try:
            info = _backup_sqlite(rel, source, destination)
        except (subprocess.SubprocessError, OSError) as exc:
            raise DeployError(
                "E_BACKUP", f"cannot back up {rel} with sqlite3: {exc}"
            ) from exc
        report["databases"].append(info)

    existing_dirs = [rel for rel in SENSITIVE_DIRS if (cfg.target / rel).is_dir()]
    if existing_dirs:
        archive = sensitive / "directories.tar.gz"
        added = _tar_paths(cfg, archive, existing_dirs)
        report["directories"] = added
        report["directories_archive"] = {
            "name": archive.name,
            "size": archive.stat().st_size,
            "sha256": sha256_file(archive),
        }

    for rel in SENSITIVE_FILES:
        source = cfg.target / rel
        if not source.is_file():
            continue
        destination = sensitive / "files" / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        report["files"].append(
            {
                "path": rel,
                "name": destination.relative_to(sensitive).as_posix(),
                "size": destination.stat().st_size,
                "sha256": sha256_file(destination),
            }
        )

    atomic_write_json(backup_dir / "snapshot.json", report)
    return report


def backup_code(cfg: Config, backup_dir: Path, rels: Iterable[str]) -> list[dict[str, Any]]:
    """Copy the files an update is about to replace or delete."""
    journal: list[dict[str, Any]] = []
    code = backup_dir / "code"
    code.mkdir(parents=True, exist_ok=True)

    for raw in rels:
        rel = normalize(raw)
        source = cfg.target / rel
        existed = source.exists()
        if existed:
            destination = code / rel
            destination.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, destination, dirs_exist_ok=True)
            elif source.is_file():
                shutil.copy2(source, destination)
            else:
                existed = False
        journal.append({"path": rel, "existed": existed})

    atomic_write_json(backup_dir / "journal.json", {"entries": journal})
    return journal


def read_journal(backup_dir: Path) -> list[dict[str, Any]]:
    data = read_json(backup_dir / "journal.json", default={}) or {}
    entries = data.get("entries") if isinstance(data, dict) else None
    return entries if isinstance(entries, list) else []


def rollback(cfg: Config, backup_dir: Path) -> list[dict[str, Any]]:
    """Restore the code backup.  Data snapshots are intentionally not restored.

    The SQLite/ghosts snapshot is a safety export.  Restoring it automatically
    would discard times/accounts created after the deploy, so it stays manual.
    """
    entries = read_journal(backup_dir)
    if not entries:
        raise DeployError("E_ROLLBACK", "no code journal in backup")

    code = backup_dir / "code"
    for entry in entries:
        rel = normalize(str(entry.get("path") or ""))
        existed = bool(entry.get("existed"))
        target = cfg.target / rel
        if existed:
            source = code / rel
            if not source.exists():
                raise DeployError("E_ROLLBACK", f"backup entry is missing: {rel}")
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, target, dirs_exist_ok=True)
            else:
                copy_atomic(source, target)
        else:
            if target.is_dir():
                shutil.rmtree(target)
            elif target.exists():
                target.unlink()
    return entries


def prune(cfg: Config, keep_current: bool = True) -> list[Path]:
    if not cfg.backups_dir.is_dir():
        return []
    backups = sorted(
        (path for path in cfg.backups_dir.iterdir() if path.is_dir()),
        key=lambda path: path.name,
        reverse=True,
    )
    keep: set[Path] = {path.resolve() for path in backups[: max(cfg.backup_keep, 1)]}
    if keep_current:
        current = read_json(cfg.current_path, default={}) or {}
        backup = current.get("backup") if isinstance(current, dict) else None
        if isinstance(backup, str) and backup:
            candidate = cfg.target / backup
            if candidate.is_dir():
                keep.add(candidate.resolve())
    removed: list[Path] = []
    for path in backups:
        if path.resolve() in keep:
            continue
        shutil.rmtree(path, ignore_errors=True)
        removed.append(path)
    return removed
