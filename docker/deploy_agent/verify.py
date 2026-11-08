from __future__ import annotations

import logging
import re
import time
from dataclasses import dataclass, field
from pathlib import Path

from .config import Config
from .util import log_size, strip_ansi

log = logging.getLogger(__name__)


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


def _name(name: str) -> str:
    return rf"(?<![\w-]){re.escape(name)}(?![\w-])"


def _success_re(name: str) -> re.Pattern[str]:
    token = _name(name)
    return re.compile(
        rf"(?:Resource\s+['\"]?{token}['\"]?\s+(?:has\s+been\s+)?(?:started|restarted)"
        rf"|Starting\s+(?:resource\s+)?['\"]?{token}['\"]?)",
        re.IGNORECASE,
    )


def _failure_re(name: str) -> re.Pattern[str]:
    token = _name(name)
    return re.compile(
        rf"(?:(?:failed\s+to\s+start|could\s+not\s+start|unable\s+to\s+start"
        rf"|error\s+(?:starting|loading)).*{token}"
        rf"|{token}.*(?:failed\s+to\s+start|could\s+not\s+start|unable\s+to\s+start))",
        re.IGNORECASE,
    )


def verify_resources(
    cfg: Config,
    expected: list[str],
    offset: int,
    timeout: int,
) -> VerifyResult:
    result = VerifyResult()
    if not expected:
        return result

    pending = set(expected)
    deadline = time.monotonic() + timeout
    current = offset
    buffer = ""

    while time.monotonic() < deadline:
        data, current = _read_from(cfg.server_log, current)
        if data:
            buffer += data
            # Keep the buffer bounded; only recent lines matter for matching.
            if len(buffer) > 2 * 1024 * 1024:
                buffer = buffer[-2 * 1024 * 1024 :]

        for name in list(pending):
            if _failure_re(name).search(buffer):
                result.failures.append(name)
                pending.discard(name)
                continue
            if _success_re(name).search(buffer):
                result.found.append(name)
                pending.discard(name)

        if not pending:
            break
        time.sleep(1)

    result.missing = sorted(pending)
    result.excerpt = buffer[-4000:] if result.missing or result.failures else ""
    return result
