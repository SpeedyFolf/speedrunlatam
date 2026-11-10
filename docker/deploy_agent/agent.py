from __future__ import annotations

import fcntl
import logging
import logging.handlers
import os
import signal
import sys
import time
from pathlib import Path
from typing import Any

from . import backup, release, resources, verify
from .apply import apply_delta, apply_full
from .config import Config
from .paths import normalize
from .status import Store
from .util import (
    DeployError,
    atomic_write_text,
    log_size,
    read_json,
    utc_now,
)

log = logging.getLogger(__name__)

ACTIONS = {"prepare", "apply", "verify", "rollback"}


def configure_logging(cfg: Config) -> None:
    cfg.logs_dir.mkdir(parents=True, exist_ok=True)
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    if getattr(root, "_deploy_configured", False):
        return
    formatter = logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s")
    stream = logging.StreamHandler(sys.stdout)
    stream.setFormatter(formatter)
    root.addHandler(stream)
    try:
        rotating = logging.handlers.RotatingFileHandler(
            cfg.logfile, maxBytes=5 * 1024 * 1024, backupCount=2, encoding="utf-8"
        )
        rotating.setFormatter(formatter)
        root.addHandler(rotating)
    except OSError as exc:
        root.warning("cannot open agent log file: %s", exc)
    root._deploy_configured = True  # type: ignore[attr-defined]


class Agent:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.store = Store(cfg)
        self.boot_offset = 0
        self.boot_id: str | None = None
        self.resumed = False
        self.pending_boot_verify = False
        self.processed: set[str] = set()
        self.stop = False
        self._lock = None

    # -- lifecycle ------------------------------------------------------
    def acquire_lock(self) -> bool:
        self.cfg.state_dir.mkdir(parents=True, exist_ok=True)
        lock_path = self.cfg.state_dir / "agent.lock"
        self._lock = lock_path.open("w", encoding="utf-8")
        try:
            fcntl.flock(self._lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log.warning("another update agent is already running")
            return False
        return True

    def _read_boot_id(self) -> None:
        boot_path = self.cfg.state_dir / "boot_id"
        try:
            self.boot_id = boot_path.read_text(encoding="utf-8").strip() or None
        except OSError:
            self.boot_id = None
        marker = self.cfg.state_dir / "agent.boot"
        try:
            previous = marker.read_text(encoding="utf-8").strip()
        except OSError:
            previous = ""
        self.resumed = bool(self.boot_id and previous == self.boot_id)
        try:
            atomic_write_text(marker, self.boot_id or "")
        except OSError:
            pass

    def setup(self) -> None:
        self.cfg.ensure_dirs()
        self._read_boot_id()
        self.boot_offset = log_size(self.cfg.server_log)
        self._reconcile_install()
        self._recover_interrupted()
        self._cleanup_stale_staging()
        log.info(
            "agent ready (resumed=%s, boot_offset=%s, deployed=%s)",
            self.resumed,
            self.boot_offset,
            self.store.deployed_tag(),
        )

    def _cleanup_stale_staging(self) -> None:
        import shutil

        state = self.store.state()
        keep = Path(str(state.get("staging") or "")).name
        try:
            entries = list(self.cfg.staging_dir.iterdir())
        except OSError:
            return
        for entry in entries:
            if not entry.is_dir() or entry.name == keep:
                continue
            shutil.rmtree(entry, ignore_errors=True)

    def _reconcile_install(self) -> None:
        installed = self.store.installed()
        installed_tag = str(installed.get("tag") or "")
        current = self.store.current()
        current_tag = str(current.get("tag") or "")

        if installed_tag and installed_tag != "unknown" and installed_tag != current_tag:
            log.info("reinstall marker moved deployment to %s", installed_tag)
            self.store.write_current(
                {
                    **current,
                    "tag": installed_tag,
                    "previous_tag": current_tag or None,
                    "source": "install",
                    "installed_at": installed.get("installed_at"),
                }
            )
            status = self.store.status()
            if status.get("phase") in {
                "preparing",
                "prepared",
                "applying",
                "applied",
                "awaiting_restart",
                "booting",
                "verifying",
            }:
                self.store.clear_state()
                self.store.write_status(
                    "idle",
                    f"Reinstall installed {installed_tag}; pending update cleared",
                    id=None,
                    tag=installed_tag,
                    plan=None,
                    result={},
                )

        if not self.store.current().get("tag"):
            version_tag = str(self.store.version().get("tag") or "")
            if version_tag and version_tag != "unknown":
                self.store.write_current(
                    {
                        "tag": version_tag,
                        "source": "version.json",
                        "installed_at": utc_now(),
                    }
                )

    def _recover_interrupted(self) -> None:
        status = self.store.status()
        state = self.store.state()
        phase = str(status.get("phase") or "")
        if phase == "applying":
            backup_rel = state.get("backup")
            message = "Agent restarted while applying files"
            if backup_rel:
                backup_dir = self.cfg.target / str(backup_rel)
                try:
                    backup.rollback(self.cfg, backup_dir)
                    message += "; code rolled back"
                except Exception as exc:  # noqa: BLE001
                    log.exception("automatic rollback failed")
                    message += f"; rollback failed: {exc}"
            self.store.clear_state()
            self.store.write_status(
                "failed",
                message,
                error={"code": "E_INTERRUPTED", "message": message},
            )
        elif phase in {"awaiting_restart", "booting", "verifying"}:
            self.pending_boot_verify = True
            self.store.write_status(
                "booting",
                "Waiting for MTA to become ready after restart",
                plan=status.get("plan"),
                id=status.get("id"),
                tag=status.get("tag"),
            )

    def run(self) -> int:
        if not self.cfg.enabled:
            log.info("DEPLOY_AGENT=0; update agent disabled")
            return 0
        configure_logging(self.cfg)
        if not self.acquire_lock():
            return 0
        self.setup()

        def _stop(_signum, _frame):
            log.info("stop signal received")
            self.stop = True

        signal.signal(signal.SIGTERM, _stop)
        signal.signal(signal.SIGINT, _stop)

        while not self.stop:
            try:
                self.maybe_boot_verify()
                request = self.store.request()
                if request:
                    self.process(request)
            except Exception:  # noqa: BLE001
                log.exception("unexpected error in agent loop")
            time.sleep(max(self.cfg.poll_interval, 0.5))
        log.info("agent stopped")
        return 0

    # -- request handling ----------------------------------------------
    def process(self, request: dict[str, Any]) -> None:
        request_id = str(request.get("id") or "").strip()
        action = str(request.get("action") or "").strip()
        if not request_id or action not in ACTIONS:
            log.warning("ignoring invalid request: %r", request)
            self.store.clear_request()
            return

        key = f"{request_id}:{action}"
        if key in self.processed:
            self.store.clear_request()
            return

        status = self.store.status()
        if (
            status.get("id") == request_id
            and status.get("phase") in {"done", "failed"}
            and action != "rollback"
        ):
            self.store.clear_request()
            return

        repo = str(request.get("repo") or self.cfg.repo)
        try:
            release.validate_repo(repo, self.cfg.repo)
            log.info("request %s: %s", action, request_id)
            if action == "prepare":
                self.handle_prepare(request)
            elif action == "apply":
                self.handle_apply(request)
            elif action == "verify":
                self.handle_verify(request)
            else:
                self.handle_rollback(request)
        except DeployError as exc:
            log.error("request %s failed: %s", action, exc.message)
            self.store.write_status(
                "failed",
                exc.message,
                id=request_id,
                tag=request.get("tag") or status.get("tag"),
                error={"code": exc.code, "message": exc.message},
            )
            if action == "apply":
                self._rollback_after_failure(request_id)
        except Exception as exc:  # noqa: BLE001
            log.exception("request %s crashed", action)
            message = f"{type(exc).__name__}: {exc}"
            self.store.write_status(
                "failed",
                message,
                id=request_id,
                tag=request.get("tag") or status.get("tag"),
                error={"code": "E_UNEXPECTED", "message": message},
            )
            if action == "apply":
                self._rollback_after_failure(request_id)
        finally:
            self.processed.add(key)
            self.store.archive_request(request)
            self.store.clear_request()

    def _rollback_after_failure(self, request_id: str) -> None:
        state = self.store.state()
        backup_rel = state.get("backup")
        if not backup_rel:
            return
        backup_dir = self.cfg.target / str(backup_rel)
        try:
            backup.rollback(self.cfg, backup_dir)
            log.info("rolled back code after a failed apply")
        except Exception:  # noqa: BLE001
            log.exception("rollback after failed apply also failed")

    # -- prepare --------------------------------------------------------
    def handle_prepare(self, request: dict[str, Any]) -> None:
        request_id = str(request["id"])
        tag = release.validate_tag(str(request.get("tag") or ""))
        self.store.clear_status()
        self.store.write_status(
            "preparing",
            f"Preparing {tag}",
            id=request_id,
            tag=tag,
            plan=None,
            result={},
            error=None,
        )

        current_tag = self.store.deployed_tag()
        if current_tag == tag:
            self.store.write_status(
                "done",
                f"{tag} is already deployed",
                id=request_id,
                tag=tag,
                result={"up_to_date": True},
            )
            return

        manifest, _ = release.load_manifest(
            self.cfg, tag, request.get("manifest_path")
        )
        previous_tag = str(manifest.get("previous_tag") or "") or None

        if manifest.get("mode") == "recreate" or manifest.get("requires_container_recreate"):
            if request.get("image_current"):
                manifest = dict(manifest)
                manifest["mode"] = "hot"
                manifest["requires_container_recreate"] = False
                log.info("image_current override: applying server changes without Reinstall")
            else:
                raise DeployError(
                    "E_RECREATE_REQUIRED",
                    "This release changed the container image (docker/**). "
                    "Reinstall the server to apply it.",
                )

        force_full = False
        reasons: list[str] = []
        manifest_mode = str(manifest.get("mode") or "")
        if manifest_mode == "full":
            force_full = True
            reasons.append("manifest requests a full update")
        if current_tag and previous_tag and current_tag != previous_tag:
            force_full = True
            reasons.append(
                f"installed tag {current_tag} does not match previous tag {previous_tag}"
            )
        elif not current_tag:
            force_full = True
            reasons.append("the installed tag is unknown")

        if force_full and not isinstance(manifest.get("template"), dict):
            raise DeployError(
                "E_BASE_MISMATCH",
                f"cannot update from {current_tag or 'unknown'} to {tag}: "
                "no full template is available in the release",
            )

        if manifest.get("mode") in {"noop", "manual"} and not force_full:
            self.store.write_status(
                "done",
                "Release has no deployable server changes",
                id=request_id,
                tag=tag,
                result={
                    "up_to_date": True,
                    "manual": (manifest.get("changes") or {}).get("manual", []),
                },
            )
            return

        staging = self.cfg.staging_dir / request_id
        if staging.exists():
            import shutil

            shutil.rmtree(staging)
        staging.mkdir(parents=True, exist_ok=True)

        if force_full:
            asset, _ = release.ensure_asset(
                self.cfg, manifest, "template", request.get("template_path")
            )
            release.extract_asset(
                asset,
                staging,
                self.cfg,
                allow_managed=True,
            )
            plan = resources.full_plan(staging, "; ".join(reasons) or "full update")
        else:
            changes = manifest.get("changes") or {}
            allowed = {
                normalize(path)
                for path in changes.get("modified", []) + changes.get("added", [])
            }
            if isinstance(manifest.get("update"), dict):
                if not allowed:
                    raise DeployError("E_EMPTY", "update bundle contains no files")
                asset, _ = release.ensure_asset(
                    self.cfg, manifest, "update", request.get("asset_path")
                )
                release.extract_asset(
                    asset,
                    staging,
                    self.cfg,
                    allowed_paths=allowed,
                )
                files = manifest.get("files") or {}
                if isinstance(files, dict) and files:
                    release.verify_hashes(staging, files)
            else:
                # A deletion-only release has no files to download.  The
                # manifest still lists what must be removed.
                if allowed:
                    raise DeployError(
                        "E_MANIFEST",
                        "manifest has modified/added files but no update asset",
                    )
                if not changes.get("deleted"):
                    raise DeployError("E_EMPTY", "nothing to apply")
            plan = resources.delta_plan(
                manifest,
                self.cfg.target,
                staging,
                running=verify.running_resources(self.cfg),
            )

        resources.validate_plan(plan)
        if plan.get("requires_container_recreate"):
            raise DeployError(
                "E_RECREATE_REQUIRED",
                "This release requires a container recreate. Reinstall the server.",
            )

        backup_dir = backup.new_backup(self.cfg, tag)
        snapshot = backup.snapshot_sensitive(self.cfg, backup_dir, tag)
        if not force_full:
            changes = manifest.get("changes") or {}
            code_paths = (
                list(changes.get("modified", []))
                + list(changes.get("added", []))
                + list(changes.get("deleted", []))
                + ["version.json"]
            )
            backup.backup_code(self.cfg, backup_dir, code_paths)

        state = {
            "id": request_id,
            "tag": tag,
            "previous_tag": current_tag or previous_tag,
            "manifest": manifest,
            "staging": staging.relative_to(self.cfg.target).as_posix(),
            "backup": backup_dir.relative_to(self.cfg.target).as_posix(),
            "force_full": force_full,
            "plan": plan,
            "verify_offset": None,
            "created_at": utc_now(),
        }
        self.store.write_state(state)
        self.store.write_status(
            "prepared",
            f"{tag} prepared",
            id=request_id,
            tag=tag,
            plan=plan,
            backup=state["backup"],
            force_full=force_full,
            previous_tag=state["previous_tag"],
            result={
                "files": sum(
                    len(manifest.get("changes", {}).get(key, []))
                    for key in ("modified", "added")
                ),
                "deleted": len(manifest.get("changes", {}).get("deleted", [])),
                "snapshot": {
                    "databases": len(snapshot.get("databases", [])),
                    "directories": len(snapshot.get("directories", [])),
                    "files": len(snapshot.get("files", [])),
                },
            },
        )

    # -- apply ----------------------------------------------------------
    def handle_apply(self, request: dict[str, Any]) -> None:
        request_id = str(request["id"])
        state = self.store.state()
        if state.get("id") != request_id:
            raise DeployError("E_STATE", "no prepared state for this request")
        status = self.store.status()
        if status.get("id") == request_id and status.get("phase") in {
            "applied",
            "awaiting_restart",
            "done",
        }:
            return

        self.store.write_status(
            "applying",
            "Applying files",
            id=request_id,
            tag=state.get("tag"),
            plan=state.get("plan"),
        )
        staging = self.cfg.target / str(state["staging"])
        backup_dir = self.cfg.target / str(state["backup"])
        manifest = state.get("manifest") or {}

        try:
            if state.get("force_full"):
                result = apply_full(self.cfg, staging, manifest, backup_dir)
            else:
                result = apply_delta(self.cfg, staging, manifest, backup_dir)
        except Exception:
            self._rollback_after_failure(request_id)
            raise

        offset = log_size(self.cfg.server_log)
        apply_result = {
            "written": len(result.get("written", [])),
            "deleted": len(result.get("deleted", [])),
            "backup": state.get("backup"),
        }
        state["verify_offset"] = offset
        state["apply"] = apply_result
        self.store.write_state(state)
        self.store.write_current(
            {
                "tag": state["tag"],
                "previous_tag": state.get("previous_tag"),
                "backup": state.get("backup"),
                "mode": "full" if state.get("force_full") else "hot",
                "applied_at": utc_now(),
            }
        )

        plan = state.get("plan") or {}
        common = {
            "id": request_id,
            "tag": state.get("tag"),
            "plan": plan,
            "verify_offset": offset,
            "result": dict(apply_result),
        }
        if plan.get("requires_process_restart"):
            self.store.write_status(
                "awaiting_restart",
                "Files applied; waiting for the panel to restart the process",
                **common,
            )
        else:
            self.store.write_status(
                "applied",
                "Files applied; waiting for the panel to reload resources",
                **common,
            )

    # -- verify ---------------------------------------------------------
    def handle_verify(self, request: dict[str, Any]) -> None:
        request_id = str(request["id"])
        state = self.store.state()
        status = self.store.status()
        if not state:
            if status.get("id") == request_id and status.get("phase") in {"done", "failed"}:
                return
            raise DeployError("E_STATE", "no state available to verify")
        if state.get("id") != request_id:
            raise DeployError("E_STATE", "state belongs to a different request")
        if status.get("id") == request_id and status.get("phase") in {"done", "failed"}:
            return

        self.store.write_status(
            "verifying",
            "Verifying resources",
            id=request_id,
            tag=state.get("tag"),
            plan=state.get("plan"),
        )
        plan = state.get("plan") or {}
        restart = bool(plan.get("requires_process_restart") or state.get("force_full"))
        result = self._run_verify(state, restart=restart)
        self._finish_verify(request_id, state, result)

    def _run_verify(self, state: dict[str, Any], restart: bool) -> verify.VerifyResult:
        plan = state.get("plan") or {}
        expected = list(plan.get("expected_resources") or [])

        if restart:
            if self.resumed:
                ready = verify.log_ready_already(self.cfg) or verify.ready_after(
                    self.cfg, self.boot_offset
                )
            else:
                ready = verify.ready_after(
                    self.cfg, self.boot_offset
                ) or verify.wait_ready(
                    self.cfg, self.boot_offset, self.cfg.ready_timeout
                )
            if not ready:
                return verify.VerifyResult(
                    missing=expected,
                    excerpt="MTA did not report readiness",
                )
            if self.resumed:
                offset = max(0, log_size(self.cfg.server_log) - 1024 * 1024)
            else:
                offset = self.boot_offset
        else:
            offset = int(state.get("verify_offset") or 0)

        return verify.verify_resources(
            self.cfg, expected, offset, self.cfg.verify_timeout
        )

    def _finish_verify(
        self,
        request_id: str,
        state: dict[str, Any],
        result: verify.VerifyResult,
    ) -> None:
        plan = state.get("plan") or {}
        applied = state.get("apply") or {}
        common = {
            "id": request_id,
            "tag": state.get("tag"),
            "plan": plan,
            "result": {
                "written": applied.get("written", 0),
                "deleted": applied.get("deleted", 0),
                "backup": applied.get("backup") or state.get("backup"),
                "found": result.found,
                "missing": result.missing,
                "failures": result.failures,
                "excerpt": result.excerpt,
            },
        }
        if result.failures or result.missing:
            self.store.write_status(
                "failed",
                "Resource verification failed",
                error={
                    "code": "E_VERIFY",
                    "message": "resources did not start cleanly",
                    "missing": result.missing,
                    "failures": result.failures,
                },
                **common,
            )
        else:
            self.store.write_status("done", "Deployment verified", **common)
        self._cleanup_staging()
        backup.prune(self.cfg)

    def maybe_boot_verify(self) -> None:
        if not self.pending_boot_verify:
            return
        status = self.store.status()
        state = self.store.state()
        if status.get("phase") not in {"awaiting_restart", "booting", "verifying"}:
            self.pending_boot_verify = False
            return
        if not state:
            self.pending_boot_verify = False
            return
        ready = (
            verify.log_ready_already(self.cfg)
            if self.resumed
            else verify.ready_after(self.cfg, self.boot_offset)
        )
        if not ready:
            return
        self.pending_boot_verify = False
        log.info("server is ready; verifying resources after restart")
        self.store.write_status(
            "verifying",
            "Verifying resources after restart",
            id=status.get("id"),
            tag=state.get("tag"),
            plan=state.get("plan"),
        )
        result = self._run_verify(state, restart=True)
        self._finish_verify(str(status.get("id") or state.get("id")), state, result)

    # -- rollback -------------------------------------------------------
    def handle_rollback(self, request: dict[str, Any]) -> None:
        request_id = str(request["id"])
        current = self.store.current()
        state = self.store.state()
        backup_rel = request.get("backup") or current.get("backup") or state.get("backup")
        if not backup_rel:
            raise DeployError("E_ROLLBACK", "no backup is recorded for this deployment")
        backup_dir = self.cfg.target / str(backup_rel)
        if not (backup_dir / "journal.json").is_file():
            raise DeployError("E_ROLLBACK", f"backup has no journal: {backup_rel}")

        self.store.write_status(
            "rolling_back",
            "Restoring the previous files",
            id=request_id,
            tag=state.get("tag") or current.get("tag"),
            plan=state.get("plan"),
        )
        restored = backup.rollback(self.cfg, backup_dir)

        previous_tag = (
            current.get("previous_tag")
            or state.get("previous_tag")
            or None
        )
        self.store.write_current(
            {
                "tag": previous_tag or "unknown",
                "previous_tag": current.get("tag"),
                "backup": None,
                "mode": "rollback",
                "applied_at": utc_now(),
            }
        )
        if previous_tag:
            self.store.write_version(previous_tag, current.get("tag"), source="rollback")

        rollback_plan = self._rollback_plan(state, current)
        state.update(
            {
                "id": request_id,
                "tag": previous_tag or "unknown",
                "plan": rollback_plan,
                "force_full": False,
                "verify_offset": log_size(self.cfg.server_log),
                "apply": {
                    "written": len(restored),
                    "deleted": 0,
                    "backup": str(backup_rel),
                },
            }
        )
        self.store.write_state(state)
        self.store.write_status(
            "rolled_back",
            "Previous files restored",
            id=request_id,
            tag=previous_tag,
            plan=rollback_plan,
            result={
                "written": len(restored),
                "deleted": 0,
                "backup": str(backup_rel),
            },
        )
        self._cleanup_staging()

    def _rollback_plan(
        self, state: dict[str, Any], current: dict[str, Any]
    ) -> dict[str, Any]:
        plan = state.get("plan") or {}
        res = plan.get("resources") or {}
        gamemodes = set(res.get("gamemodes") or [])
        autostart = set(res.get("autostart") or [])
        included = set(res.get("included") or [])
        available = autostart | included
        changed = set(res.get("changed") or [])
        added = set(res.get("added") or [])
        removed = set(res.get("removed") or [])

        stop = sorted(added & available)
        start = sorted(removed & available)
        restart = sorted(changed & available)
        requires_restart = bool(plan.get("requires_process_restart")) or plan.get("mode") == "full"

        def order(names: list[str], modes_first: bool = False) -> list[str]:
            regular = sorted(name for name in names if name not in gamemodes)
            modes = sorted(name for name in names if name in gamemodes)
            return (modes + regular) if modes_first else (regular + modes)

        rollback = {
            "mode": "rollback",
            "manifest_mode": "rollback",
            "requires_process_restart": requires_restart,
            "requires_container_recreate": False,
            "commands_before_apply": [f"stop {name}" for name in order(stop, True)],
            "commands_after_apply": [],
            "resources": {
                "changed": sorted(changed),
                "added": sorted(added),
                "removed": sorted(removed),
                "start": order(start),
                "stop": order(stop, True),
                "restart": order(restart),
                "protected": [],
                "gamemodes": sorted(gamemodes),
                "autostart": sorted(autostart),
            },
            "expected_resources": (
                sorted(gamemodes & autostart) or (["race"] if "race" in autostart else [])
                if requires_restart
                else order(start + restart)
            ),
            "reasons": [f"rollback from {current.get('tag')}"],
        }
        if not requires_restart:
            after: list[str] = []
            if added or removed:
                after.append("refresh")
            after.extend(f"start {name}" for name in rollback["resources"]["start"])
            after.extend(f"restart {name}" for name in rollback["resources"]["restart"])
            rollback["commands_after_apply"] = after
        return rollback

    # -- helpers --------------------------------------------------------
    def _cleanup_staging(self) -> None:
        state = self.store.state()
        staging_rel = state.get("staging")
        if not staging_rel:
            return
        import shutil

        staging = self.cfg.target / str(staging_rel)
        try:
            if staging.is_dir() and staging.resolve().is_relative_to(
                self.cfg.state_dir.resolve()
            ):
                shutil.rmtree(staging)
        except (OSError, ValueError):
            log.warning("could not clean staging directory %s", staging)


def main() -> int:
    cfg = Config.from_env()
    configure_logging(cfg)
    agent = Agent(cfg)
    try:
        return agent.run()
    except Exception:  # noqa: BLE001
        log.exception("update agent crashed")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
