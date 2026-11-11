from __future__ import annotations

import time
from dataclasses import dataclass, field
from pathlib import Path

from .config import Config
from .mta_api import MtaApi
from .util import strip_ansi


@dataclass
class VerifyResult:
    found: list[str] = field(default_factory=list)
    missing: list[str] = field(default_factory=list)
    failures: list[str] = field(default_factory=list)
    excerpt: str = ""

    @property
    def ok(self) -> bool:
        return not self.failures and not self.missing


def _read_from(path: Path, offset: int) -> tuple[str, int]:
    try:
        size = path.stat().st_size
    except FileNotFoundError:
        return "", 0
    if size < offset:
        offset = 0
    try:
        with path.open("rb") as handle:
            handle.seek(offset)
            data = handle.read()
        return strip_ansi(data.decode("utf-8", "replace")), size
    except OSError:
        return "", offset


def _tail(path: Path, max_bytes: int = 1024 * 1024) -> str:
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            handle.seek(max(0, size - max_bytes))
            data = handle.read()
        return strip_ansi(data.decode("utf-8", "replace"))
    except OSError:
        return ""


def running_resources(api: MtaApi) -> set[str]:
    """Return resources currently running, from the MTA HTTP API.

    This is authoritative: it uses getResourceState() inside the server via the
    deploy_api resource. If the API is unreachable it raises instead of guessing
    from server.log.
    """
    states = api.resource_states()
    return {name for name, state in states.items() if state == "running"}


def wait_ready(cfg: Config, offset: int, timeout: int) -> bool:
    """Wait for MTA's ready line after the given log offset."""
    deadline = time.monotonic() + timeout
    current = offset
    while time.monotonic() < deadline:
        data, current = _read_from(cfg.server_log, current)
        if cfg.ready_pattern.lower() in data.lower():
            return True
        time.sleep(1)
    return False


def log_ready_already(cfg: Config) -> bool:
    return cfg.ready_pattern.lower() in _tail(cfg.server_log).lower()


def ready_after(cfg: Config, offset: int) -> bool:
    data, _ = _read_from(cfg.server_log, offset)
    return cfg.ready_pattern.lower() in data.lower()


def verify_resources(
    api: MtaApi,
    expected: list[str],
    timeout: int,
) -> VerifyResult:
    """Verify the expected resources are running, using the MTA HTTP API.

    Uses getResourceState() through the deploy_api resource, so the result is
    authoritative.
    """
    result = VerifyResult()
    if not expected:
        return result

    pending = set(expected)
    deadline = time.monotonic() + timeout
    states: dict[str, str] = {}

    while True:
        states = api.resource_states()
        for name in list(pending):
            state = states.get(name, "missing")
            if state == "running":
                result.found.append(name)
                pending.discard(name)
            elif state in {"failed to load", "missing"}:
                result.failures.append(name)
                pending.discard(name)
        if not pending or time.monotonic() >= deadline:
            break
        time.sleep(1)

    result.missing = sorted(pending)
    if result.missing or result.failures:
        affected = sorted(set(result.missing) | set(result.failures))
        result.excerpt = "; ".join(
            f"{name}={states.get(name, 'missing')}" for name in affected
        )
    return result
