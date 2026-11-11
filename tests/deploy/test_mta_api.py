from __future__ import annotations

import base64
import json
import os
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import DeployTestCase
from deploy_agent.config import Config
from deploy_agent.mta_api import MtaApi, MtaApiError

_EXPECTED_AUTH = "Basic " + base64.b64encode(b"deploy_bot:secret").decode("ascii")


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # keep test output clean
        pass

    def do_POST(self):  # noqa: N802 (stdlib naming)
        if self.headers.get("Authorization", "") != _EXPECTED_AUTH:
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"Access denied, please login")
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw_body = self.rfile.read(length) if length else b"[]"
        args = json.loads(raw_body.decode("utf-8")) if raw_body else []
        if self.path.endswith("/resourceStates"):
            payload = [json.dumps({"race": "running", "race_playerstats": "loaded"})]
        elif self.path.endswith("/stateOf"):
            states = {"race": "running"}
            payload = [states.get(args[0], "missing") if args else "missing"]
        elif self.path.endswith("/startByName"):
            payload = [True]
        else:
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class MtaApiTests(DeployTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def _cfg(self, password: str = "secret") -> Config:
        os.environ.update(
            {
                "DEPLOY_BOT_URL": f"http://127.0.0.1:{self.server.server_address[1]}",
                "DEPLOY_BOT_USER": "deploy_bot",
                "DEPLOY_BOT_PASSWORD": password,
            }
        )
        return Config.from_env()

    def test_resource_states_and_state(self) -> None:
        api = MtaApi(self._cfg())
        self.assertEqual(
            api.resource_states(), {"race": "running", "race_playerstats": "loaded"}
        )
        self.assertEqual(api.resource_state("race"), "running")
        self.assertEqual(api.resource_state("nope"), "missing")
        self.assertTrue(api.start_resource("race"))

    def test_bad_credentials_raise(self) -> None:
        api = MtaApi(self._cfg(password="wrong"))
        with self.assertRaises(MtaApiError):
            api.resource_states()


if __name__ == "__main__":
    unittest.main()
