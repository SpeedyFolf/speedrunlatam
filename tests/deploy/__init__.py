from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "docker"))
sys.path.insert(0, str(ROOT / "scripts"))


def has_sqlite3() -> bool:
    return bool(__import__("shutil").which("sqlite3"))


def env(**values: str):
    os.environ.update({key: str(value) for key, value in values.items()})


class DeployTestCase(unittest.TestCase):
    def setUp(self) -> None:
        import tempfile

        self._tmp = tempfile.TemporaryDirectory(prefix="deploy-test-")
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def config(self, **extra: str):
        from deploy_agent.config import Config

        env(DEPLOY_TARGET=str(self.root), DEPLOY_ALLOWED_REPO="test/repo", **extra)
        config = Config.from_env()
        config.ensure_dirs()
        return config
