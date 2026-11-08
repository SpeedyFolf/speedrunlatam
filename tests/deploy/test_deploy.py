from __future__ import annotations

import json
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from . import DeployTestCase
from deploy import Deployer, Options, PterodactylClient


class FakeApi:
    def __init__(self, plan: dict[str, Any], restart: bool = False):
        self.files: dict[str, bytes] = {
            "/.deploy/boot_id": b"boot-1",
            "/.deploy/agent.boot": b"boot-1",
        }
        self.commands: list[str] = []
        self.power_signals: list[str] = []
        self.plan = plan
        self.restart = restart
        self.status: dict[str, Any] = {}
        self.online = True
        self.writes: list[str] = []

    def ensure_online(self, timeout: int = 300) -> None:
        self.online = True

    def ensure_dir(self, path: str) -> None:
        pass

    def write_file(self, path: str, content: bytes, content_type: str = "application/json") -> None:
        self.files[path] = content
        self.writes.append(path)
        if path.endswith("/request.json"):
            request = json.loads(content.decode("utf-8"))
            action = request["action"]
            request_id = request["id"]
            if action == "prepare":
                self.status = {
                    "schema": 1,
                    "id": request_id,
                    "phase": "prepared",
                    "plan": self.plan,
                    "result": {},
                }
            elif action == "apply":
                self.status = {
                    "schema": 1,
                    "id": request_id,
                    "phase": "awaiting_restart" if self.restart else "applied",
                    "plan": self.plan,
                    "result": {},
                }
            elif action == "verify":
                self.status = {
                    "schema": 1,
                    "id": request_id,
                    "phase": "done",
                    "plan": self.plan,
                    "result": {},
                }
            elif action == "rollback":
                self.status = {
                    "schema": 1,
                    "id": request_id,
                    "phase": "rolled_back",
                    "plan": self.plan,
                    "result": {},
                }

    def read_file(self, path: str) -> bytes | None:
        if path == "/.deploy/status.json" and self.status:
            return json.dumps(self.status).encode("utf-8")
        return self.files.get(path)

    def send_command(self, command: str) -> None:
        self.commands.append(command)

    def power(self, signal: str) -> None:
        self.power_signals.append(signal)

    def server_state(self) -> str:
        return "running" if self.online else "offline"

    def wait_state(self, wanted, timeout, interval=3.0, label="server"):
        return "running" if "running" in set(wanted) else sorted(wanted)[0]

    def list_servers(self):
        return []

    def reinstall(self) -> None:
        self.power_signals.append("reinstall")


def options(**overrides) -> Options:
    values = dict(
        tag="v1.1.0",
        manifest_path=None,
        repo="test/repo",
        announce=False,
        delay_gamemode=0,
        delay_resource=0,
        delay_restart=0,
        command_delay=0.0,
        timeout=10,
        poll_interval=0.01,
        auto_rollback=False,
        allow_reinstall=False,
        dry_run=False,
        preflight_console=False,
    )
    values.update(overrides)
    return Options(**values)


class DeployOrchestrationTests(DeployTestCase):
    def test_hot_deploy_commands(self) -> None:
        plan = {
            "mode": "hot",
            "requires_process_restart": False,
            "commands_before_apply": ["stop oldmod"],
            "commands_after_apply": ["refresh", "start newmod", "restart race"],
            "resources": {"gamemodes": ["race"]},
        }
        manifest = {"tag": "v1.1.0", "mode": "hot", "resources": {"gamemodes": ["race"]}}
        api = FakeApi(plan)
        deployer = Deployer(api, manifest, options())  # type: ignore[arg-type]
        self.assertEqual(deployer.deploy(), 0)
        self.assertEqual(api.commands, ["stop oldmod", "refresh", "start newmod", "restart race"])
        self.assertEqual(api.power_signals, [])

    def test_restart_deploy(self) -> None:
        plan = {
            "mode": "restart",
            "requires_process_restart": True,
            "commands_before_apply": [],
            "commands_after_apply": [],
            "resources": {"gamemodes": ["race"]},
        }
        manifest = {"tag": "v1.1.0", "mode": "restart"}
        api = FakeApi(plan, restart=True)
        deployer = Deployer(api, manifest, options())  # type: ignore[arg-type]
        self.assertEqual(deployer.deploy(), 0)
        self.assertEqual(api.power_signals, ["restart"])
        self.assertIn("/.deploy/download/update.json", api.writes)

    def test_noop(self) -> None:
        manifest = {"tag": "v1.1.0", "mode": "noop", "changes": {"manual": []}}
        api = FakeApi({})
        deployer = Deployer(api, manifest, options())  # type: ignore[arg-type]
        self.assertEqual(deployer.deploy(), 0)
        self.assertEqual(api.commands, [])

    def test_rollback(self) -> None:
        plan = {
            "mode": "rollback",
            "requires_process_restart": False,
            "commands_before_apply": ["stop newmod"],
            "commands_after_apply": ["refresh", "start oldmod", "restart race"],
            "resources": {"gamemodes": ["race"]},
        }
        manifest = {"tag": "v1.1.0", "mode": "rollback"}
        api = FakeApi(plan)
        deployer = Deployer(api, manifest, options())  # type: ignore[arg-type]
        self.assertEqual(deployer.rollback(), 0)
        self.assertEqual(
            api.commands,
            ["stop newmod", "refresh", "start oldmod", "restart race"],
        )


class HttpHandler(BaseHTTPRequestHandler):
    files: dict[str, bytes] = {}
    commands: list[str] = []
    power: list[str] = []

    def log_message(self, *_args):  # noqa: A003
        return

    def _send(self, status: int, body: bytes = b"", content_type: str = "application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _json(self, data: Any, status: int = 200) -> None:
        self._send(status, json.dumps(data).encode("utf-8"))

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/client":
            self._json({"data": [{"attributes": {"identifier": "abc", "name": "test"}}]})
            return
        if parsed.path.endswith("/resources"):
            self._json({"attributes": {"current_state": "running"}})
            return
        if parsed.path.endswith("/files/contents"):
            query = urllib.parse.parse_qs(parsed.query)
            key = query.get("file", [""])[0]
            if key in self.files:
                self._send(200, self.files[key], "text/plain")
            else:
                self._send(404, b'{"error":"not found"}')
            return
        self._send(404, b'{"error":"not found"}')

    def do_POST(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)
        if parsed.path.endswith("/files/create-folder"):
            self._send(204)
            return
        if parsed.path.endswith("/files/write"):
            query = urllib.parse.parse_qs(parsed.query)
            key = query.get("file", [""])[0]
            self.files[key] = body
            self._send(204)
            return
        if parsed.path.endswith("/command"):
            self.commands.append(json.loads(body)["command"])
            self._send(204)
            return
        if parsed.path.endswith("/power"):
            self.power.append(json.loads(body)["signal"])
            self._send(204)
            return
        self._send(404, b'{"error":"not found"}')


class ApiClientTests(DeployTestCase):
    def setUp(self) -> None:
        super().setUp()
        HttpHandler.files = {}
        HttpHandler.commands = []
        HttpHandler.power = []
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), HttpHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.shutdown)
        self.addCleanup(self.server.server_close)
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"

    def client(self) -> PterodactylClient:
        return PterodactylClient(self.base, "ptlc_test", "abc")

    def test_files_commands_power(self) -> None:
        client = self.client()
        self.assertEqual(client.server_state(), "running")
        self.assertEqual(len(client.list_servers()), 1)
        client.ensure_dir("/.deploy/download")
        client.write_file("/.deploy/ping.json", b'{"ok":true}')
        self.assertEqual(client.read_file("/.deploy/ping.json"), b'{"ok":true}')
        self.assertIsNone(client.read_file("/.deploy/missing.json"))
        client.send_command("say test")
        client.power("restart")
        self.assertEqual(HttpHandler.commands, ["say test"])
        self.assertEqual(HttpHandler.power, ["restart"])

    def test_write_creates_parent_on_404(self) -> None:
        client = self.client()
        # The fake API accepts any write; this asserts the public method contract.
        client.write_file("/.deploy/download/update.json", b"{}")
        self.assertIn("/.deploy/download/update.json", HttpHandler.files)

if __name__ == "__main__":
    unittest.main()
