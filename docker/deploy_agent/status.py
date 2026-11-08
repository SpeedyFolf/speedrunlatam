from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from .config import Config
from .util import atomic_write_json, read_json, utc_now

log = logging.getLogger(__name__)

SUCCESS_PHASES = {"done", "up_to_date", "rolled_back", "idle"}
FAILURE_PHASES = {"failed"}


class Store:
    """Small JSON store with atomic writes.

    The status file is the contract with GitHub Actions.  Keep it small and
    stable; large payloads (like the complete manifest) belong in state.json.
    """

    def __init__(self, config: Config):
        self.config = config

    # -- status ---------------------------------------------------------
    def status(self) -> dict[str, Any]:
        data = read_json(self.config.status_path, default={}) or {}
        return data if isinstance(data, dict) else {}

    def write_status(self, phase: str, message: str = "", **fields: Any) -> dict[str, Any]:
        data = self.status()
        data.update(fields)
        data["schema"] = 1
        data["phase"] = phase
        data["message"] = message
        data["updated_at"] = utc_now()
        atomic_write_json(self.config.status_path, data)
        return data

    def clear_status(self) -> None:
        try:
            self.config.status_path.unlink()
        except FileNotFoundError:
            pass

    # -- state ----------------------------------------------------------
    def state(self) -> dict[str, Any]:
        data = read_json(self.config.state_path, default={}) or {}
        return data if isinstance(data, dict) else {}

    def write_state(self, data: dict[str, Any]) -> None:
        data = {**data, "schema": 1, "updated_at": utc_now()}
        atomic_write_json(self.config.state_path, data)

    def clear_state(self) -> None:
        try:
            self.config.state_path.unlink()
        except FileNotFoundError:
            pass

    # -- current / installed -------------------------------------------
    def current(self) -> dict[str, Any]:
        data = read_json(self.config.current_path, default={}) or {}
        return data if isinstance(data, dict) else {}

    def write_current(self, data: dict[str, Any]) -> None:
        data = {**data, "updated_at": utc_now()}
        atomic_write_json(self.config.current_path, data)

    def installed(self) -> dict[str, Any]:
        data = read_json(self.config.installed_path, default={}) or {}
        return data if isinstance(data, dict) else {}

    def write_installed(self, data: dict[str, Any]) -> None:
        data = {**data, "updated_at": utc_now()}
        atomic_write_json(self.config.installed_path, data)

    def version(self) -> dict[str, Any]:
        data = read_json(self.config.version_path, default={}) or {}
        return data if isinstance(data, dict) else {}

    def write_version(self, tag: str, previous_tag: str | None = None, **extra: Any) -> None:
        payload = {
            "schema": 1,
            "tag": tag,
            "previous_tag": previous_tag,
            "deployed_at": utc_now(),
            **extra,
        }
        atomic_write_json(self.config.version_path, payload)

    def deployed_tag(self) -> str | None:
        for source in (self.current(), self.installed(), self.version()):
            tag = source.get("tag") if isinstance(source, dict) else None
            if isinstance(tag, str) and tag and tag != "unknown":
                return tag
        return None

    # -- request --------------------------------------------------------
    def request(self) -> dict[str, Any] | None:
        data = read_json(self.config.request_path, default=None)
        return data if isinstance(data, dict) else None

    def clear_request(self) -> None:
        try:
            self.config.request_path.unlink()
        except FileNotFoundError:
            pass

    def archive_request(self, request: dict[str, Any]) -> None:
        """Keep a small audit trail of processed requests."""
        request_id = str(request.get("id") or "unknown")
        action = str(request.get("action") or "unknown")
        archive = self.config.state_dir / "requests"
        archive.mkdir(parents=True, exist_ok=True)
        atomic_write_json(archive / f"{request_id}-{action}.json", request)

    def log_path(self) -> Path:
        return self.config.logfile
