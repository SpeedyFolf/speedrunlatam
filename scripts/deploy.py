#!/usr/bin/env python3
"""Drive a Speedrun LATAM deployment through the Pterodactyl Client API.

GitHub Actions only needs:
  PTERODACTYL_URL       public panel URL (Cloudflare/cloudflared)
  PTERODACTYL_API_KEY   client API key (ptlc_...)
  PTERODACTYL_SERVER_ID short server UUID

No Wings address, SSH, game port, playit or nginx access is required.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

DEFAULT_REPO = "ferecece/speedrunlatam"
DEFAULT_TIMEOUT = 900
JSON_ACCEPT = "application/vnd.pterodactyl.v1+json"
RETRY_STATUS = {429, 500, 502, 503, 504}
SERVER_LOG = "/mods/deathmatch/logs/server.log"
CONSOLE_MARKER = "[deploy] console ok"


def console_command(command: str) -> str:
    """Strip non-ASCII from a console command.

    MTA reads stdin with getwchar(). Under the C/POSIX locale a non-ASCII byte
    makes it fail with EILSEQ and stdin stays broken until the process is
    restarted, so a single accented announce can kill the console for every
    later command (restart, stop, shutdown...). The image now runs with a
    UTF-8 locale, but keep commands ASCII as a second line of defence.
    """
    return (
        unicodedata.normalize("NFKD", command)
        .encode("ascii", "ignore")
        .decode("ascii")
    )


class ApiError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(f"HTTP {status}: {message}")
        self.status = status
        self.message = message


class DeployFailure(RuntimeError):
    def __init__(self, message: str, status: dict[str, Any] | None = None):
        super().__init__(message)
        self.status = status or {}


class PterodactylClient:
    def __init__(self, base_url: str, api_key: str, server_id: str, timeout: int = 30):
        self.base = base_url.rstrip("/")
        self.api_key = api_key
        self.server_id = server_id
        self.timeout = timeout

    # -- HTTP -----------------------------------------------------------
    def _url(self, suffix: str) -> str:
        return f"{self.base}/api/client/servers/{self.server_id}{suffix}"

    def _request(
        self,
        method: str,
        url: str,
        *,
        body: bytes | None = None,
        json_body: Any = None,
        accept: str = JSON_ACCEPT,
        content_type: str = "application/json",
        json_response: bool = True,
    ) -> Any:
        if json_body is not None:
            body = json.dumps(json_body).encode("utf-8")
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Accept": accept,
            "User-Agent": "speedrunlatam-cd/1",
        }
        if body is not None:
            headers["Content-Type"] = content_type
        last_error: Exception | None = None
        for attempt in range(4):
            request = urllib.request.Request(
                url, data=body, headers=headers, method=method
            )
            try:
                with urllib.request.urlopen(request, timeout=self.timeout) as response:
                    raw = response.read()
                if not raw:
                    return None
                if json_response:
                    try:
                        return json.loads(raw.decode("utf-8"))
                    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
                        raise ApiError(
                            response.status,
                            f"invalid JSON response: {exc}",
                        ) from exc
                return raw
            except urllib.error.HTTPError as exc:
                detail = exc.read(4096).decode("utf-8", "replace").strip()
                error = ApiError(exc.code, detail or exc.reason)
                if exc.code in RETRY_STATUS and attempt < 3:
                    last_error = error
                    time.sleep(2**attempt)
                    continue
                raise error from exc
            except urllib.error.URLError as exc:
                last_error = exc
                if attempt < 3:
                    time.sleep(2**attempt)
                    continue
                raise ApiError(0, f"connection error: {exc.reason}") from exc
        raise ApiError(0, f"request failed: {last_error}")

    def list_servers(self) -> list[dict[str, Any]]:
        data = self._request("GET", f"{self.base}/api/client")
        return data.get("data", []) if isinstance(data, dict) else []

    def server_state(self) -> str:
        data = self._request("GET", self._url("/resources"))
        attributes = data.get("attributes", {}) if isinstance(data, dict) else {}
        return str(attributes.get("current_state") or "unknown")

    def server_info(self) -> dict[str, Any]:
        data = self._request("GET", self._url(""))
        return data.get("attributes", {}) if isinstance(data, dict) else {}

    def wait_install(self, timeout: int) -> None:
        """Wait for a Pterodactyl Reinstall to finish, then ensure it runs."""
        deadline = time.monotonic() + timeout
        saw_installing = False
        grace = time.monotonic() + 15
        while time.monotonic() < deadline:
            info = self.server_info()
            status = str(info.get("status") or "")
            installing = bool(info.get("is_installing")) or status == "installing"
            if installing:
                saw_installing = True
                print("[api] reinstall state: installing")
            elif status == "install_failed":
                raise DeployFailure("Pterodactyl reported install_failed")
            elif saw_installing or (not installing and time.monotonic() > grace):
                break
            time.sleep(3)
        else:
            raise DeployFailure("timed out waiting for the reinstall to finish")

        if self.server_state() == "offline":
            print("[api] starting server after reinstall")
            self.power("start")
        self.wait_state({"running"}, timeout, label="server")

    def wait_state(
        self,
        wanted: Iterable[str],
        timeout: int,
        interval: float = 15.0,
        label: str = "server",
    ) -> str:
        wanted_set = set(wanted)
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            state = self.server_state()
            if state != last:
                print(f"[api] {label} state: {state}")
                last = state
            if state in wanted_set:
                return state
            time.sleep(interval)
        raise DeployFailure(f"timed out waiting for {label} state {sorted(wanted_set)}")

    def ensure_online(self, timeout: int = 300) -> None:
        state = self.server_state()
        if state == "running":
            return
        if state == "stopping":
            self.wait_state({"offline", "running"}, timeout, label="server")
            state = self.server_state()
        if state in {"offline", "unknown"}:
            print("[api] starting server")
            self.power("start")
        self.wait_state({"running"}, timeout, label="server")

    def power(self, signal: str) -> None:
        self._request("POST", self._url("/power"), json_body={"signal": signal})

    def send_command(self, command: str) -> str:
        safe = console_command(command)
        self._request("POST", self._url("/command"), json_body={"command": safe})
        return safe

    def reinstall(self) -> None:
        self._request("POST", self._url("/settings/reinstall"), json_body={})

    # -- files ----------------------------------------------------------
    def ensure_dir(self, path: str) -> None:
        parts = [part for part in path.strip("/").split("/") if part]
        root = "/"
        for part in parts:
            try:
                self._request(
                    "POST",
                    self._url("/files/create-folder"),
                    json_body={"root": root, "name": part},
                )
            except ApiError as exc:
                if exc.status not in {409, 422}:
                    raise
            root = f"/{part}" if root == "/" else f"{root}/{part}"

    def write_file(self, path: str, content: bytes, content_type: str = "application/json") -> None:
        query = urllib.parse.urlencode({"file": path})
        url = f"{self._url('/files/write')}?{query}"
        try:
            self._request(
                "POST",
                url,
                body=content,
                content_type=content_type,
                json_response=False,
            )
        except ApiError as exc:
            if exc.status != 404:
                raise
            parent = str(Path(path).parent)
            self.ensure_dir(parent)
            self._request(
                "POST",
                url,
                body=content,
                content_type=content_type,
                json_response=False,
            )

    def read_file(self, path: str) -> bytes | None:
        query = urllib.parse.urlencode({"file": path})
        url = f"{self._url('/files/contents')}?{query}"
        try:
            data = self._request(
                "GET",
                url,
                accept="*/*",
                json_response=False,
            )
            return data if isinstance(data, bytes) else None
        except ApiError as exc:
            if exc.status == 404:
                return None
            raise


@dataclass
class Options:
    tag: str
    manifest_path: str | None
    repo: str
    announce: bool
    delay_gamemode: int
    delay_resource: int
    delay_restart: int
    command_delay: float
    timeout: int
    poll_interval: float
    auto_rollback: bool
    allow_reinstall: bool
    allow_image_current: bool
    dry_run: bool
    preflight_console: bool
    console_check: bool = True
    console_check_timeout: int = 20


def env_flag(name: str, default: bool) -> bool:
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


def load_manifest(path: str | None, tag: str, repo: str) -> dict[str, Any]:
    if path:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    else:
        url = f"https://github.com/{repo}/releases/download/{tag}/update.json"
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": "speedrunlatam-cd/1",
                "Accept": "application/json",
            },
        )
        token = os.environ.get("GITHUB_TOKEN", "")
        if token:
            request.add_header("Authorization", f"Bearer {token}")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                data = json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, json.JSONDecodeError) as exc:
            raise DeployFailure(f"cannot load manifest {url}: {exc}") from exc
    if not isinstance(data, dict):
        raise DeployFailure("manifest is not an object")
    if str(data.get("tag") or "") != tag:
        raise DeployFailure(
            f"manifest tag {data.get('tag')!r} does not match {tag!r}"
        )
    return data


class Deployer:
    def __init__(self, api: PterodactylClient, manifest: dict[str, Any], opts: Options):
        self.api = api
        self.manifest = manifest
        self.opts = opts
        self.steps: list[str] = []

    # -- helpers --------------------------------------------------------
    def note(self, message: str) -> None:
        print(f"[deploy] {message}")
        self.steps.append(message)

    def _delay(self) -> int:
        if not self.opts.announce:
            return 0
        if self.manifest.get("mode") in {"restart", "full"} or self.manifest.get(
            "requires_process_restart"
        ):
            return max(self.opts.delay_restart, 0)
        resources = self.manifest.get("resources") or {}
        if resources.get("gamemodes"):
            return max(self.opts.delay_gamemode, 0)
        return max(self.opts.delay_resource, 0)

    def _write_request(self, request_id: str, action: str, **fields: Any) -> None:
        payload = {
            "schema": 1,
            "id": request_id,
            "action": action,
            "repo": self.opts.repo,
            **fields,
        }
        if action == "prepare" and self.opts.allow_image_current:
            payload["image_current"] = True
        self.api.write_file(
            "/.deploy/request.json",
            json.dumps(payload).encode("utf-8"),
        )

    def _read_status(self, request_id: str) -> dict[str, Any] | None:
        raw = self.api.read_file("/.deploy/status.json")
        if not raw:
            return None
        try:
            status = json.loads(raw.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            return None
        if not isinstance(status, dict):
            return None
        if status.get("id") not in (None, request_id):
            return None
        return status

    def _poll(
        self,
        request_id: str,
        wanted: set[str],
        *,
        label: str,
        timeout: int | None = None,
    ) -> dict[str, Any]:
        timeout = timeout or self.opts.timeout
        deadline = time.monotonic() + timeout
        last_phase = None
        while time.monotonic() < deadline:
            status = self._read_status(request_id)
            if status:
                phase = str(status.get("phase") or "")
                if phase != last_phase:
                    print(f"[agent] {label}: {phase} {status.get('message') or ''}".rstrip())
                    last_phase = phase
                if phase == "failed":
                    raise DeployFailure(
                        f"agent reported failure: {status.get('message')}",
                        status,
                    )
                if phase in wanted:
                    return status
            time.sleep(self.opts.poll_interval)
        raise DeployFailure(
            f"timed out waiting for agent phase {sorted(wanted)} ({label})"
        )

    def _execute(self, commands: list[str]) -> None:
        for command in commands:
            sent = self.api.send_command(command)
            print(f"[mta] {sent}")
            time.sleep(max(self.opts.command_delay, 0.2))
            if sent.strip() == "refresh":
                time.sleep(2)

    def _recover(self, plan: dict[str, Any]) -> None:
        """Best-effort recovery when the API fails mid-deploy.

        Resources stopped before apply must be started again if the agent
        rolled back the files. Repeating refresh/start/restart is idempotent
        at MTA level and avoids leaving the server with stopped resources.
        """
        resources = plan.get("resources") or {}
        commands = ["refresh"]
        seen: set[str] = set()
        # Only resources that were stopped because they were running must be
        # started again. Added resources are never started by the agent.
        for key, verb in (("stop", "start"), ("restart", "restart")):
            for name in resources.get(key) or []:
                if name in seen:
                    continue
                seen.add(name)
                commands.append(f"{verb} {name}")
        try:
            self.note("attempting best-effort recovery")
            self._execute(commands)
        except Exception as exc:  # noqa: BLE001
            self.note(f"recovery failed: {exc}")

    def _announce(self) -> None:
        delay = self._delay()
        if delay <= 0:
            return
        # Keep the console command ASCII: see console_command().
        self.api.send_command(
            f"say [deploy] Actualizacion en {delay}s. El server sigue online."
        )
        self.note(f"announced {delay}s before reload")
        time.sleep(delay)

    def _console_log(self) -> bytes:
        try:
            return self.api.read_file(SERVER_LOG) or b""
        except ApiError as exc:
            if exc.status in {404, 500}:
                return b""
            raise

    def _check_console(self, timeout: int | None = None) -> None:
        """Fail fast when MTA is not consuming console input.

        MTA logs `CONSOLECHAT: <text>` for a console `say`, so the marker only
        appears once the command has actually been read and executed. Without
        this check a broken console waits for the 120s verify timeout, rolls
        back and waits another 120s.
        """
        limit = self.opts.console_check_timeout if timeout is None else timeout
        before = self._console_log()
        offset = len(before)
        sent = self.api.send_command(f"say {CONSOLE_MARKER}")
        print(f"[console] {sent}")
        deadline = time.monotonic() + limit
        while time.monotonic() < deadline:
            current = self._console_log()
            chunk = current[offset:] if len(current) >= offset else current
            if CONSOLE_MARKER.encode("ascii").lower() in chunk.lower():
                print("[console] input ok")
                return
            time.sleep(1)
        raise DeployFailure(
            "console input is not reaching MTA (server.log did not record the "
            "marker); the server process needs a restart or the container is "
            "missing a UTF-8 locale"
        )

    def _wait_agent_ready(self, timeout: int = 60) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            boot = self.api.read_file("/.deploy/boot_id")
            agent = self.api.read_file("/.deploy/agent.boot")
            if boot and agent and boot.strip() == agent.strip():
                self.note("update agent is running")
                return
            time.sleep(2)
        raise DeployFailure(
            "update agent is not running; Reinstall once to install the image "
            "with docker/deploy_agent, or check DEPLOY_AGENT"
        )

    def _summary(self, title: str, status: dict[str, Any] | None = None) -> None:
        lines = [f"## {title}"]
        lines.append(f"- tag: `{self.manifest.get('tag')}`")
        lines.append(f"- mode: `{self.manifest.get('mode')}`")
        if status:
            plan = status.get("plan") or {}
            if plan:
                lines.append(
                    "- process restart: "
                    + ("yes" if plan.get("requires_process_restart") else "no")
                )
                resources = plan.get("resources") or {}
                for key in ("start", "restart", "stop"):
                    if resources.get(key):
                        lines.append(f"- {key}: " + ", ".join(resources[key]))
            result = status.get("result") or {}
            if result:
                if "written" in result or "deleted" in result:
                    lines.append(
                        f"- result: written={result.get('written', 0)} "
                        f"deleted={result.get('deleted', 0)}"
                    )
                else:
                    changes = self.manifest.get("changes") or {}
                    lines.append(
                        "- files: "
                        f"modified={len(changes.get('modified') or [])} "
                        f"added={len(changes.get('added') or [])} "
                        f"deleted={len(changes.get('deleted') or [])}"
                    )
                found = result.get("found") or []
                if found or result.get("missing") or result.get("failures"):
                    lines.append(
                        "- verified: " + (", ".join(found) if found else "none")
                    )
                    if result.get("missing"):
                        lines.append("- missing: " + ", ".join(result["missing"]))
                    if result.get("failures"):
                        lines.append(
                            "- failures: " + ", ".join(result["failures"])
                        )
        lines.extend(f"- {step}" for step in self.steps)
        text = "\n".join(lines) + "\n"
        print(text)
        summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary_path:
            try:
                with open(summary_path, "a", encoding="utf-8") as handle:
                    handle.write(text)
            except OSError:
                pass

    # -- actions --------------------------------------------------------
    def deploy(self) -> int:
        mode = str(self.manifest.get("mode") or "")
        if mode == "recreate" and self.opts.allow_image_current:
            # The image was already updated (Reinstall). Rewrite the manifest
            # for the agent that is already running in the container, which may
            # predate the image_current request flag.
            self.manifest = dict(self.manifest)
            self.manifest["mode"] = (
                "restart" if self.manifest.get("requires_process_restart") else "hot"
            )
            self.manifest["requires_container_recreate"] = False
            self.manifest["image_current_override"] = True
            mode = str(self.manifest["mode"])
            self.note(
                "docker/** changed, but the image is already current; "
                "applying only the server-side changes"
            )
        if mode in {"noop", "manual"}:
            self.note(f"nothing to deploy (mode={mode})")
            if self.manifest.get("changes", {}).get("manual"):
                self.note(
                    "manual files: "
                    + ", ".join(self.manifest["changes"]["manual"])
                )
            self._summary(f"Deploy {self.opts.tag} skipped")
            return 0

        if mode == "recreate":
            if not self.opts.allow_reinstall:
                raise DeployFailure(
                    "this release changed docker/** and requires a Reinstall; "
                    "run again with --allow-reinstall if you accept the downtime, "
                    "or --allow-image-current if the Reinstall was already done"
                )
            self.note("calling Pterodactyl Reinstall")
            self.api.reinstall()
            self.api.wait_install(self.opts.timeout)
            self._summary(f"Reinstalled {self.opts.tag}")
            return 0

        self.api.ensure_online(self.opts.timeout)
        self.api.ensure_dir("/.deploy/download")
        self._wait_agent_ready()
        manifest_json = json.dumps(
            self.manifest, indent=2, ensure_ascii=False, sort_keys=True
        ).encode("utf-8")
        self.api.write_file("/.deploy/download/update.json", manifest_json)
        self.note("manifest staged on the server volume")

        deploy_id = str(uuid.uuid4())
        self._write_request(
            deploy_id,
            "prepare",
            tag=self.opts.tag,
            manifest_path=".deploy/download/update.json",
        )
        status = self._poll(deploy_id, {"prepared", "done"}, label="prepare")
        if status.get("phase") == "done":
            self.note("already up to date")
            self._summary(f"Deploy {self.opts.tag} already current", status)
            return 0

        plan = status.get("plan") or {}
        if plan.get("requires_container_recreate"):
            raise DeployFailure("agent says a container recreate is required", status)

        # A process restart regenerates the console, so only hot deploys need a
        # working console before we touch files.
        if self.opts.console_check and not plan.get("requires_process_restart"):
            self._check_console()

        self._announce()

        try:
            if plan.get("requires_process_restart"):
                self._write_request(deploy_id, "apply")
                self._poll(
                    deploy_id,
                    {"applied", "awaiting_restart"},
                    label="apply",
                )
                self.note("restarting the server process")
                self.api.power("restart")
                time.sleep(2)
                self.api.wait_state({"running"}, self.opts.timeout, label="restart")
                self._write_request(deploy_id, "verify")
                status = self._poll(deploy_id, {"done"}, label="verify")
            else:
                self._execute(plan.get("commands_before_apply") or [])
                self._write_request(deploy_id, "apply")
                self._poll(deploy_id, {"applied"}, label="apply")
                self._execute(plan.get("commands_after_apply") or [])
                self._write_request(deploy_id, "verify")
                status = self._poll(deploy_id, {"done"}, label="verify")
        except (DeployFailure, ApiError) as exc:
            error = (exc.status.get("error") or {}) if isinstance(exc, DeployFailure) else {}
            if (
                self.opts.auto_rollback
                and isinstance(exc, DeployFailure)
                and error.get("code") == "E_VERIFY"
            ):
                self.note("verification failed; attempting rollback")
                try:
                    self.rollback()
                except Exception as rollback_error:  # noqa: BLE001
                    self.note(f"rollback failed: {rollback_error}")
            else:
                self._recover(plan)
            raise exc

        self._summary(f"Deployed {self.opts.tag}", status)
        return 0

    def rollback(self) -> int:
        self.api.ensure_online(self.opts.timeout)
        rollback_id = str(uuid.uuid4())
        self._write_request(rollback_id, "rollback")
        status = self._poll(rollback_id, {"rolled_back"}, label="rollback")
        plan = status.get("plan") or {}
        self._execute(plan.get("commands_before_apply") or [])
        if plan.get("requires_process_restart"):
            self.note("restarting the server process after rollback")
            self.api.power("restart")
            time.sleep(2)
            self.api.wait_state({"running"}, self.opts.timeout, label="restart")
        else:
            self._execute(plan.get("commands_after_apply") or [])
        self._write_request(rollback_id, "verify")
        status = self._poll(rollback_id, {"done"}, label="verify")
        self._summary("Rollback complete", status)
        return 0

    def preflight(self) -> int:
        servers = self.api.list_servers()
        print(f"[preflight] servers visible: {len(servers)}")
        for server in servers[:10]:
            attributes = server.get("attributes", {})
            print(
                f"[preflight] {attributes.get('identifier')} "
                f"{attributes.get('name')} state={attributes.get('status')}"
            )
        state = self.api.server_state()
        print(f"[preflight] server state: {state}")
        self.api.ensure_dir("/.deploy/download")
        payload = json.dumps({"ok": True, "at": time.time()}).encode("utf-8")
        self.api.write_file("/.deploy/ping.json", payload)
        read_back = self.api.read_file("/.deploy/ping.json")
        if read_back != payload:
            raise DeployFailure("file write/read preflight failed")
        print("[preflight] file write/read: ok")
        if self.opts.preflight_console:
            self.api.ensure_online(self.opts.timeout)
            self._check_console()
            print("[preflight] console command: ok")
        return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", choices=["deploy", "rollback", "preflight"], default="deploy")
    parser.add_argument("--tag", default="")
    parser.add_argument("--manifest", default="")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", DEFAULT_REPO))
    parser.add_argument("--url", default=os.environ.get("PTERODACTYL_URL", ""))
    parser.add_argument("--api-key", default=os.environ.get("PTERODACTYL_API_KEY", ""))
    parser.add_argument("--server", default=os.environ.get("PTERODACTYL_SERVER_ID", ""))
    parser.add_argument("--announce", dest="announce", action="store_true", default=None)
    parser.add_argument("--no-announce", dest="announce", action="store_false")
    parser.add_argument("--delay-gamemode", type=int, default=None)
    parser.add_argument("--delay-resource", type=int, default=None)
    parser.add_argument("--delay-restart", type=int, default=None)
    parser.add_argument("--command-delay", type=float, default=1.0)
    parser.add_argument("--timeout", type=int, default=int(os.environ.get("DEPLOY_TIMEOUT", DEFAULT_TIMEOUT)))
    parser.add_argument("--poll-interval", type=float, default=3.0)
    parser.add_argument("--auto-rollback", action="store_true")
    parser.add_argument("--allow-reinstall", action="store_true")
    parser.add_argument("--allow-image-current", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--preflight-console", action="store_true")
    parser.add_argument(
        "--skip-console-check",
        dest="skip_console_check",
        action="store_true",
        help="skip the pre-apply console health check (hot deploys only)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not args.url or not args.api_key or not args.server:
        print(
            "missing PTERODACTYL_URL, PTERODACTYL_API_KEY or PTERODACTYL_SERVER_ID",
            file=sys.stderr,
        )
        return 2

    prerelease = "-" in args.tag
    if args.announce is None:
        default = env_flag("DEPLOY_ANNOUNCE", not prerelease)
        announce = False if prerelease and os.environ.get("DEPLOY_ANNOUNCE") is None else default
    else:
        announce = args.announce

    def delay(value: int | None, env_name: str, default: int) -> int:
        if value is not None:
            return value
        if prerelease and os.environ.get(env_name) is None:
            return 0
        return env_int(env_name, default)

    opts = Options(
        tag=args.tag,
        manifest_path=args.manifest or None,
        repo=args.repo,
        announce=announce,
        delay_gamemode=delay(args.delay_gamemode, "DEPLOY_DELAY_GAMEMODE", 30),
        delay_resource=delay(args.delay_resource, "DEPLOY_DELAY_RESOURCE", 10),
        delay_restart=delay(args.delay_restart, "DEPLOY_DELAY_RESTART", 30),
        command_delay=args.command_delay,
        timeout=args.timeout,
        poll_interval=args.poll_interval,
        auto_rollback=args.auto_rollback,
        allow_reinstall=args.allow_reinstall,
        allow_image_current=args.allow_image_current,
        dry_run=args.dry_run,
        preflight_console=args.preflight_console,
        console_check=not args.skip_console_check,
    )

    api = PterodactylClient(args.url, args.api_key, args.server)

    try:
        if args.action == "preflight":
            return Deployer(api, {}, opts).preflight()

        if args.action == "rollback":
            manifest = {"tag": args.tag or "rollback", "mode": "rollback"}
            return Deployer(api, manifest, opts).rollback()

        if not args.tag:
            raise DeployFailure("--tag is required for deploy")
        manifest = load_manifest(args.manifest or None, args.tag, args.repo)
        deployer = Deployer(api, manifest, opts)
        if opts.dry_run:
            print(json.dumps(manifest, indent=2, sort_keys=True))
            return 0
        return deployer.deploy()
    except (DeployFailure, ApiError, OSError) as exc:
        print(f"[deploy] error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
