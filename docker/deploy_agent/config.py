from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_REPO = "ferecece/speedrunlatam"
DEFAULT_RELEASE_BASE = "https://github.com"
DEFAULT_READY_PATTERN = "Server started and is ready to accept connections!"


def env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    try:
        return int(value)
    except ValueError:
        return default


def env_float(name: str, default: float) -> float:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    try:
        return float(value)
    except ValueError:
        return default


@dataclass(frozen=True)
class Config:
    target: Path
    state_dir: Path
    logs_dir: Path

    repo: str
    release_base_url: str
    github_token: str

    enabled: bool
    dry_run: bool
    backup_keep: int
    max_asset_mb: int
    max_files: int
    max_unpacked_mb: int

    poll_interval: float
    ready_timeout: int
    verify_timeout: int
    ready_pattern: str

    logfile: Path
    request_path: Path
    status_path: Path
    state_path: Path
    current_path: Path
    installed_path: Path
    version_path: Path
    download_dir: Path
    staging_dir: Path
    backups_dir: Path

    @classmethod
    def from_env(cls) -> "Config":
        target = Path(os.environ.get("DEPLOY_TARGET", "/home/container")).resolve()
        state_dir = target / ".deploy"
        logs_dir = target / "logs"
        return cls(
            target=target,
            state_dir=state_dir,
            logs_dir=logs_dir,
            repo=os.environ.get("DEPLOY_ALLOWED_REPO", DEFAULT_REPO).strip(),
            release_base_url=os.environ.get(
                "DEPLOY_RELEASE_BASE_URL", DEFAULT_RELEASE_BASE
            ).rstrip("/"),
            github_token=os.environ.get("GITHUB_TOKEN", "").strip(),
            enabled=env_bool("DEPLOY_AGENT", True),
            dry_run=env_bool("DEPLOY_DRY_RUN", False),
            backup_keep=env_int("DEPLOY_BACKUP_KEEP", 3),
            max_asset_mb=env_int("DEPLOY_MAX_ASSET_MB", 160),
            max_files=env_int("DEPLOY_MAX_FILES", 30000),
            max_unpacked_mb=env_int("DEPLOY_MAX_UNPACKED_MB", 512),
            poll_interval=env_float("DEPLOY_POLL_INTERVAL", 2.0),
            ready_timeout=env_int("DEPLOY_READY_TIMEOUT", 300),
            verify_timeout=env_int("DEPLOY_VERIFY_TIMEOUT", 120),
            ready_pattern=os.environ.get("DEPLOY_READY_PATTERN", DEFAULT_READY_PATTERN),
            logfile=logs_dir / "update-agent.log",
            request_path=state_dir / "request.json",
            status_path=state_dir / "status.json",
            state_path=state_dir / "state.json",
            current_path=state_dir / "current.json",
            installed_path=state_dir / "installed.json",
            version_path=target / "version.json",
            download_dir=state_dir / "download",
            staging_dir=state_dir / "staging",
            backups_dir=state_dir / "backups",
        )

    def ensure_dirs(self) -> None:
        for directory in (
            self.state_dir,
            self.logs_dir,
            self.download_dir,
            self.staging_dir,
            self.backups_dir,
        ):
            directory.mkdir(parents=True, exist_ok=True)

    @property
    def server_log(self) -> Path:
        # MTA runs from mods/deathmatch, so <logfile>logs/server.log</logfile>
        # resolves there. The container-level logs/ directory is for the agent,
        # nginx and the ghosts API.
        return self.target / "mods/deathmatch/logs/server.log"

    @property
    def sync_excludes(self) -> Path:
        override = os.environ.get("DEPLOY_SYNC_EXCLUDES")
        return Path(override) if override else Path("/opt/sync-excludes.txt")
