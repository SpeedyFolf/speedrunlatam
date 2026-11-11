from __future__ import annotations

import base64
import json
import urllib.error
import urllib.request
from typing import Any

from .config import Config


class MtaApiError(RuntimeError):
    """Raised when the MTA HTTP API cannot be reached or returns an error."""


class MtaApi:
    """Client for the deploy_api resource over MTA's HTTP interface.

    MTA exposes functions exported with ``http="true"`` at
    ``/<resource>/call/<function>`` using a POST whose body is a JSON array of
    arguments. It requires HTTP Basic auth and returns a JSON array with the
    function's return value(s).
    """

    def __init__(self, cfg: Config):
        self.base = cfg.mta_http_url.rstrip("/")
        self.user = cfg.bot_user
        self.password = cfg.bot_password
        self.timeout = cfg.mta_http_timeout
        token = base64.b64encode(
            f"{self.user}:{self.password}".encode("utf-8")
        ).decode("ascii")
        self._auth = f"Basic {token}"

    def _call(self, resource: str, function: str, *args: Any) -> Any:
        url = f"{self.base}/{resource}/call/{function}"
        body = json.dumps(list(args)).encode("utf-8")
        request = urllib.request.Request(url, data=body, method="POST")
        request.add_header("Content-Type", "application/json")
        request.add_header("Authorization", self._auth)
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                raw = response.read()
        except urllib.error.HTTPError as exc:
            if exc.code == 401:
                raise MtaApiError(
                    "MTA HTTP API rejected the deploy bot credentials (401); "
                    "check DEPLOY_BOT_PASSWORD and the DeployBot ACL group"
                ) from exc
            raise MtaApiError(
                f"MTA HTTP API returned {exc.code} for {function}"
            ) from exc
        except urllib.error.URLError as exc:
            raise MtaApiError(f"MTA HTTP API unreachable: {exc.reason}") from exc
        try:
            values = json.loads(raw.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise MtaApiError(f"invalid JSON from {function}: {exc}") from exc
        if isinstance(values, list) and values:
            return values[0]
        return None

    def resource_states(self) -> dict[str, str]:
        payload = self._call("deploy_api", "resourceStates")
        if isinstance(payload, str):
            try:
                data = json.loads(payload)
            except json.JSONDecodeError as exc:
                raise MtaApiError(f"invalid resourceStates payload: {exc}") from exc
        elif isinstance(payload, dict):
            data = payload
        else:
            raise MtaApiError("resourceStates returned an unexpected value")
        return {str(name): str(state) for name, state in data.items()}

    def resource_state(self, name: str) -> str:
        value = self._call("deploy_api", "stateOf", name)
        return str(value) if value is not None else "missing"

    def start_resource(self, name: str) -> bool:
        return bool(self._call("deploy_api", "startByName", name))
