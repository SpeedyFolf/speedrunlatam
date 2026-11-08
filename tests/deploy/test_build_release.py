from __future__ import annotations

import json
import subprocess
import sys
import tarfile
import unittest
from pathlib import Path

from . import DeployTestCase

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/build-release.py"


class BuildReleaseTests(DeployTestCase):
    def _git(self, *args: str) -> None:
        subprocess.run(
            ["git", "-C", str(self.repo), *args],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def _write(self, rel: str, content: str) -> None:
        path = self.repo / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def _commit(self, tag: str) -> None:
        self._git("add", "-A")
        self._git("commit", "-m", tag)
        self._git("tag", tag)

    def setUp(self) -> None:
        super().setUp()
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self._git("init")
        self._git("config", "user.email", "test@example.com")
        self._git("config", "user.name", "test")
        self._write(
            "server/mods/deathmatch/mtaserver.conf.template",
            '<config><resource src="race" startup="1" protected="0"></resource></config>\n',
        )
        self._write(
            "server/mods/deathmatch/resources/[gamemodes]/[race]/race/meta.xml",
            '<meta><info name="Race" type="gamemode" /></meta>\n',
        )
        self._write(
            "server/mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua",
            "-- v1\n",
        )
        self._write("server/mods/deathmatch/settings.xml", "<settings />\n")
        self._write("server/mta-server64", "binary-v1\n")
        self._write("docker/Dockerfile", "FROM debian\n")
        self._commit("v1.0.0")

    def _build(self, tag: str, previous: str, out: Path) -> dict:
        subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--tag",
                tag,
                "--previous-tag",
                previous,
                "--repo",
                "test/repo",
                "--out",
                str(out),
                "--server-dir",
                str(self.repo),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return json.loads((out / "update.json").read_text())

    def test_hot_resource_change(self) -> None:
        self._write(
            "server/mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua",
            "-- v2\n",
        )
        self._commit("v1.1.0")
        out = self.root / "dist1"
        manifest = self._build("v1.1.0", "v1.0.0", out)
        self.assertEqual(manifest["mode"], "hot")
        self.assertFalse(manifest["requires_process_restart"])
        self.assertEqual(manifest["resources"]["changed"], ["race"])
        self.assertEqual(
            manifest["changes"]["modified"],
            ["mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua"],
        )
        self.assertTrue((out / "server-update.tar.gz").is_file())
        with tarfile.open(out / "server-update.tar.gz") as archive:
            self.assertIn(
                "mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua",
                archive.getnames(),
            )
        with tarfile.open(out / "server-template.tar.gz") as archive:
            self.assertIn("version.json", archive.getnames())
            self.assertIn("mta-server64", archive.getnames())

    def test_restart_for_template_change(self) -> None:
        self._write(
            "server/mods/deathmatch/mtaserver.conf.template",
            '<config><!-- change --><resource src="race" startup="1" protected="0"></resource></config>\n',
        )
        self._commit("v1.2.0")
        out = self.root / "dist2"
        manifest = self._build("v1.2.0", "v1.0.0", out)
        self.assertEqual(manifest["mode"], "restart")
        self.assertTrue(manifest["requires_process_restart"])
        self.assertIn(
            "mods/deathmatch/mtaserver.conf.template",
            manifest["changes"]["modified"],
        )

    def test_recreate_for_docker_change(self) -> None:
        self._write("docker/Dockerfile", "FROM debian:trixie\n")
        self._commit("v1.3.0")
        out = self.root / "dist3"
        manifest = self._build("v1.3.0", "v1.0.0", out)
        self.assertEqual(manifest["mode"], "recreate")
        self.assertTrue(manifest["requires_container_recreate"])

    def test_manual_only_change(self) -> None:
        self._write("server/mods/deathmatch/settings.xml", "<settings changed=\"1\" />\n")
        self._commit("v1.4.0")
        out = self.root / "dist4"
        manifest = self._build("v1.4.0", "v1.0.0", out)
        self.assertEqual(manifest["mode"], "manual")
        self.assertIsNone(manifest["update"])
        self.assertIn("mods/deathmatch/settings.xml", manifest["changes"]["manual"])


if __name__ == "__main__":
    unittest.main()
