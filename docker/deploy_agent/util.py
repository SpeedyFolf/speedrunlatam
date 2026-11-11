from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")


class DeployError(RuntimeError):
    """An expected deployment error with a machine-readable code."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def sanitize_tag(tag: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", tag).strip("._") or "unknown"


def format_bytes(value: int) -> str:
    size = float(value)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if size < 1024 or unit == "GiB":
            return f"{size:.1f} {unit}" if unit != "B" else f"{int(size)} B"
        size /= 1024
    return f"{value} B"


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_write_bytes(path: Path, data: bytes, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        if mode is not None:
            os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass


def atomic_write_text(path: Path, text: str, mode: int | None = None) -> None:
    atomic_write_bytes(path, text.encode("utf-8"), mode=mode)


def atomic_write_json(path: Path, data: Any, mode: int | None = None) -> None:
    atomic_write_text(
        path,
        json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        mode=mode,
    )


def copy_atomic(source: Path, destination: Path) -> None:
    """Copy a file atomically, replacing the destination by rename.

    The rename means a running executable (for example ``mta-server64``) can be
    replaced without hitting ``ETXTBSY`` ("Text file busy"): the live process
    keeps the old inode and the new file lands for the next start.
    """
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


def read_json(path: Path, default: Any = None) -> Any:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return default
    except (json.JSONDecodeError, OSError):
        return default


def strip_ansi(text: str) -> str:
    return _ANSI_RE.sub("", text)


def run(
    args: list[str],
    *,
    cwd: Path | None = None,
    timeout: int | None = None,
    check: bool = True,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    merged_env = {**os.environ, "LC_ALL": "C", "LANG": "C"}
    if env:
        merged_env.update(env)
    proc = subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        timeout=timeout,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=merged_env,
        check=False,
    )
    if check and proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise DeployError(
            "E_COMMAND",
            f"command failed ({proc.returncode}): {' '.join(args)}: {detail}",
        )
    return proc


def log_size(path: Path) -> int:
    try:
        return path.stat().st_size
    except FileNotFoundError:
        return 0


def is_path_within(path: Path, base: Path) -> bool:
    """Filesystem path containment check (not the POSIX bundle helper)."""
    try:
        path.resolve().relative_to(base.resolve())
        return True
    except (ValueError, OSError):
        return False
