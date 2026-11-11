from __future__ import annotations

import io
import json
import tarfile
import unittest
from pathlib import Path

from . import DeployTestCase
from deploy_agent.agent import Agent
from deploy_agent.util import DeployError, sha256_bytes


RACE = "mods/deathmatch/resources/[gamemodes]/[race]/race"
JOIN = "mods/deathmatch/resources/[gameplay]/joinquit"
RACE_FILE = f"{RACE}/server.lua"


class FakeMta:
    """Stand-in for MtaApi: returns a fixed resource-state map."""

    def __init__(self, states: dict[str, str] | None = None):
        self.states = dict(states or {})

    def resource_states(self) -> dict[str, str]:
        return dict(self.states)

    def resource_state(self, name: str) -> str:
        return self.states.get(name, "missing")

    def start_resource(self, name: str) -> bool:
        self.states[name] = "running"
        return True


class AgentFlowTests(DeployTestCase):
    def _resource(self, rel: str, body: str, kind: str = "script") -> None:
        directory = self.root / rel
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "meta.xml").write_text(
            f'<meta><info name="{directory.name}" type="{kind}" /></meta>\n',
            encoding="utf-8",
        )
        (directory / "server.lua").write_text(body, encoding="utf-8")

    def _conf(self) -> None:
        path = self.root / "mods/deathmatch/mtaserver.conf.template"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            '<config>'
            '<resource src="race" startup="1" protected="0"></resource>'
            '<resource src="joinquit" startup="1" protected="0"></resource>'
            "</config>\n",
            encoding="utf-8",
        )

    def _tar(self, name: str, members: dict[str, bytes]) -> bytes:
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
            for rel, data in members.items():
                info = tarfile.TarInfo(rel)
                info.size = len(data)
                info.mode = 0o644
                archive.addfile(info, io.BytesIO(data))
        return buffer.getvalue()

    def _cfg_with_tree(self):
        cfg = self.config()
        self._resource(RACE, "old\n", kind="gamemode")
        self._resource(JOIN, "-- join\n")
        self._conf()
        cfg.current_path.write_text(
            json.dumps({"schema": 1, "tag": "v1.0.0"}), encoding="utf-8"
        )
        (cfg.server_log.parent).mkdir(parents=True, exist_ok=True)
        cfg.server_log.write_text("", encoding="utf-8")
        return cfg

    def _manifest(self, cfg, *, mode: str, changes: dict, asset: bytes, files: dict | None = None, template: bytes | None = None):
        manifest = {
            "schema": 1,
            "tag": "v1.1.0",
            "repo": "test/repo",
            "previous_tag": "v1.0.0",
            "mode": mode,
            "requires_process_restart": mode in {"restart", "full"},
            "requires_container_recreate": mode == "recreate",
            "changes": changes,
            "files": files or {},
            "update": {
                "name": "server-update.tar.gz",
                "sha256": sha256_bytes(asset),
                "size": len(asset),
            },
            "template": None,
        }
        (cfg.download_dir / "server-update.tar.gz").write_bytes(asset)
        if template is not None:
            (cfg.download_dir / "server-template.tar.gz").write_bytes(template)
            manifest["template"] = {
                "name": "server-template.tar.gz",
                "sha256": sha256_bytes(template),
                "size": len(template),
            }
        (cfg.download_dir / "update.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )
        return manifest

    def test_hot_prepare_apply_verify_rollback(self) -> None:
        cfg = self._cfg_with_tree()
        with cfg.server_log.open("a", encoding="utf-8") as handle:
            handle.write("start: Resource 'race' started\n")
        new_body = b"-- new\n"
        asset = self._tar(
            "server-update.tar.gz",
            {RACE_FILE: new_body},
        )
        self._manifest(
            cfg,
            mode="hot",
            changes={"modified": [RACE_FILE], "added": [], "deleted": []},
            asset=asset,
            files={RACE_FILE: sha256_bytes(new_body)},
        )
        agent = Agent(cfg, mta=FakeMta({"race": "running"}))
        prepare = {
            "schema": 1,
            "id": "d1",
            "action": "prepare",
            "repo": "test/repo",
            "tag": "v1.1.0",
            "manifest_path": ".deploy/download/update.json",
        }
        agent.handle_prepare(prepare)
        status = agent.store.status()
        self.assertEqual(status["phase"], "prepared")
        self.assertFalse(status["plan"]["requires_process_restart"])
        self.assertEqual(status["plan"]["resources"]["changed"], ["race"])
        self.assertEqual(status["plan"]["commands_after_apply"], ["refresh", "restart race"])
        self.assertTrue((self.root / RACE_FILE).read_text() == "old\n")

        agent.handle_apply({"id": "d1", "action": "apply"})
        status = agent.store.status()
        self.assertEqual(status["phase"], "applied")
        self.assertEqual(status["result"]["written"], 1)
        self.assertEqual((self.root / RACE_FILE).read_text(), "-- new\n")
        self.assertEqual(agent.store.current()["tag"], "v1.1.0")
        self.assertEqual(agent.store.version()["tag"], "v1.1.0")

        with cfg.server_log.open("a", encoding="utf-8") as handle:
            handle.write("Resource 'race' started\n")
        agent.handle_verify({"id": "d1", "action": "verify"})
        status = agent.store.status()
        self.assertEqual(status["phase"], "done")
        self.assertEqual(status["result"]["found"], ["race"])
        self.assertEqual(status["result"]["written"], 1)

        current_backup = agent.store.current()["backup"]
        self.assertTrue((self.root / current_backup / "journal.json").is_file())
        agent.handle_rollback({"id": "d2", "action": "rollback", "repo": "test/repo"})
        status = agent.store.status()
        self.assertEqual(status["phase"], "rolled_back")
        self.assertEqual((self.root / RACE_FILE).read_text(), "old\n")
        self.assertEqual(agent.store.current()["tag"], "v1.0.0")

    def test_restart_mode(self) -> None:
        cfg = self._cfg_with_tree()
        template = b"<config><resource src=\"race\" startup=\"1\" protected=\"0\"></resource></config>\n"
        asset = self._tar(
            "server-update.tar.gz",
            {"mods/deathmatch/mtaserver.conf.template": template},
        )
        self._manifest(
            cfg,
            mode="restart",
            changes={
                "modified": ["mods/deathmatch/mtaserver.conf.template"],
                "added": [],
                "deleted": [],
            },
            asset=asset,
            files={"mods/deathmatch/mtaserver.conf.template": sha256_bytes(template)},
        )
        agent = Agent(cfg, mta=FakeMta({"race": "running"}))
        agent.handle_prepare(
            {
                "schema": 1,
                "id": "r1",
                "action": "prepare",
                "repo": "test/repo",
                "tag": "v1.1.0",
                "manifest_path": ".deploy/download/update.json",
            }
        )
        status = agent.store.status()
        self.assertEqual(status["phase"], "prepared")
        self.assertTrue(status["plan"]["requires_process_restart"])
        self.assertEqual(status["plan"]["expected_resources"], ["race"])
        agent.handle_apply({"id": "r1", "action": "apply"})
        self.assertEqual(agent.store.status()["phase"], "awaiting_restart")

        offset = agent.boot_offset
        with cfg.server_log.open("a", encoding="utf-8") as handle:
            handle.write("Server started and is ready to accept connections!\n")
            handle.write("Resource 'race' started\n")
        agent.boot_offset = offset
        agent.handle_verify({"id": "r1", "action": "verify"})
        self.assertEqual(agent.store.status()["phase"], "done")

    def test_deletion_only_release(self) -> None:
        cfg = self._cfg_with_tree()
        with cfg.server_log.open("a", encoding="utf-8") as handle:
            handle.write("start: Resource 'oldmod' started\n")
        old = self.root / "mods/deathmatch/resources/[gameplay]/oldmod"
        old.mkdir(parents=True)
        (old / "meta.xml").write_text('<meta><info name="oldmod" /></meta>', encoding="utf-8")
        (old / "server.lua").write_text("-- old\n", encoding="utf-8")
        manifest = {
            "schema": 1,
            "tag": "v1.1.0",
            "repo": "test/repo",
            "previous_tag": "v1.0.0",
            "mode": "hot",
            "changes": {
                "modified": [],
                "added": [],
                "deleted": [
                    "mods/deathmatch/resources/[gameplay]/oldmod/meta.xml",
                    "mods/deathmatch/resources/[gameplay]/oldmod/server.lua",
                ],
            },
            "files": {},
            "update": None,
            "template": None,
        }
        (cfg.download_dir / "update.json").write_text(json.dumps(manifest), encoding="utf-8")
        agent = Agent(cfg, mta=FakeMta({"oldmod": "running"}))
        agent.handle_prepare(
            {
                "schema": 1,
                "id": "del1",
                "action": "prepare",
                "repo": "test/repo",
                "tag": "v1.1.0",
                "manifest_path": ".deploy/download/update.json",
            }
        )
        status = agent.store.status()
        self.assertEqual(status["phase"], "prepared")
        self.assertEqual(status["plan"]["resources"]["removed"], ["oldmod"])
        self.assertEqual(status["plan"]["commands_before_apply"], ["stop oldmod"])
        self.assertEqual(status["plan"]["commands_after_apply"], ["refresh"])
        agent.handle_apply({"id": "del1", "action": "apply"})
        self.assertFalse(old.exists())
        agent.handle_verify({"id": "del1", "action": "verify"})
        self.assertEqual(agent.store.status()["phase"], "done")

    def test_full_manifest_for_known_tag(self) -> None:
        cfg = self._cfg_with_tree()
        template = self._tar(
            "server-template.tar.gz",
            {
                "mods/deathmatch/resources/[gamemodes]/[race]/race/meta.xml": b'<meta><info type="gamemode"/></meta>',
                "mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua": b"new\n",
                "mods/deathmatch/mtaserver.conf.template": b'<config><resource src="race" startup="1" protected="0"></resource></config>',
            },
        )
        asset = self._tar("server-update.tar.gz", {RACE_FILE: b"new\n"})
        self._manifest(
            cfg,
            mode="full",
            changes={"modified": [], "added": [], "deleted": []},
            asset=asset,
            template=template,
        )
        agent = Agent(cfg, mta=FakeMta({}))
        agent.handle_prepare(
            {
                "schema": 1,
                "id": "g1",
                "action": "prepare",
                "repo": "test/repo",
                "tag": "v1.1.0",
                "manifest_path": ".deploy/download/update.json",
            }
        )
        status = agent.store.status()
        self.assertEqual(status["phase"], "prepared")
        self.assertEqual(status["plan"]["mode"], "full")
        self.assertTrue(status["plan"]["requires_process_restart"])

    def test_recreate_is_refused(self) -> None:
        cfg = self._cfg_with_tree()
        asset = self._tar("server-update.tar.gz", {RACE_FILE: b"x"})
        self._manifest(
            cfg,
            mode="recreate",
            changes={"modified": [RACE_FILE], "added": [], "deleted": []},
            asset=asset,
            files={RACE_FILE: sha256_bytes(b"x")},
        )
        agent = Agent(cfg, mta=FakeMta())
        with self.assertRaises(DeployError) as raised:
            agent.handle_prepare(
                {
                    "schema": 1,
                    "id": "x1",
                    "action": "prepare",
                    "repo": "test/repo",
                    "tag": "v1.1.0",
                    "manifest_path": ".deploy/download/update.json",
                }
            )
        self.assertEqual(raised.exception.code, "E_RECREATE_REQUIRED")

    def test_recreate_can_be_overridden_when_image_is_current(self) -> None:
        cfg = self._cfg_with_tree()
        with cfg.server_log.open("a", encoding="utf-8") as handle:
            handle.write("start: Resource 'race' started\n")
        asset = self._tar("server-update.tar.gz", {RACE_FILE: b"-- new\n"})
        self._manifest(
            cfg,
            mode="recreate",
            changes={"modified": [RACE_FILE], "added": [], "deleted": []},
            asset=asset,
            files={RACE_FILE: sha256_bytes(b"-- new\n")},
        )
        agent = Agent(cfg, mta=FakeMta({"race": "running"}))
        agent.handle_prepare(
            {
                "schema": 1,
                "id": "x2",
                "action": "prepare",
                "repo": "test/repo",
                "tag": "v1.1.0",
                "manifest_path": ".deploy/download/update.json",
                "image_current": True,
            }
        )
        status = agent.store.status()
        self.assertEqual(status["phase"], "prepared")
        self.assertFalse(status["plan"]["requires_container_recreate"])
        self.assertEqual(status["plan"]["commands_after_apply"], ["refresh", "restart race"])

    def test_full_fallback_for_unknown_tag(self) -> None:
        cfg = self.config()
        self._resource(RACE, "old\n", kind="gamemode")
        self._conf()
        template = self._tar(
            "server-template.tar.gz",
            {
                "mods/deathmatch/resources/[gamemodes]/[race]/race/meta.xml": b'<meta><info type="gamemode"/></meta>',
                "mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua": b"new\n",
                "mods/deathmatch/mtaserver.conf.template": b'<config><resource src="race" startup="1" protected="0"></resource></config>',
            },
        )
        asset = self._tar("server-update.tar.gz", {RACE_FILE: b"new\n"})
        manifest = {
            "schema": 1,
            "tag": "v1.1.0",
            "repo": "test/repo",
            "previous_tag": "v1.0.0",
            "mode": "hot",
            "changes": {"modified": [RACE_FILE], "added": [], "deleted": []},
            "files": {RACE_FILE: sha256_bytes(b"new\n")},
            "update": {"name": "server-update.tar.gz", "sha256": sha256_bytes(asset), "size": len(asset)},
            "template": {"name": "server-template.tar.gz", "sha256": sha256_bytes(template), "size": len(template)},
        }
        (cfg.download_dir / "server-update.tar.gz").write_bytes(asset)
        (cfg.download_dir / "server-template.tar.gz").write_bytes(template)
        (cfg.download_dir / "update.json").write_text(json.dumps(manifest), encoding="utf-8")
        agent = Agent(cfg, mta=FakeMta({}))
        agent.handle_prepare(
            {
                "schema": 1,
                "id": "f1",
                "action": "prepare",
                "repo": "test/repo",
                "tag": "v1.1.0",
                "manifest_path": ".deploy/download/update.json",
            }
        )
        status = agent.store.status()
        self.assertEqual(status["phase"], "prepared")
        self.assertTrue(status["plan"]["requires_process_restart"])
        self.assertEqual(status["plan"]["mode"], "full")


    def test_verify_starts_addons_from_meta(self) -> None:
        cfg = self._cfg_with_tree()
        (self.root / RACE / "meta.xml").write_text(
            '<meta><info name="race" type="gamemode"/>'
            '<setting name="#addons" value="race_playerstats,race_playerstatsgui" '
            'accept="*"></setting></meta>',
            encoding="utf-8",
        )
        new_body = b"-- new\n"
        asset = self._tar("server-update.tar.gz", {RACE_FILE: new_body})
        self._manifest(
            cfg,
            mode="hot",
            changes={"modified": [RACE_FILE], "added": [], "deleted": []},
            asset=asset,
            files={RACE_FILE: sha256_bytes(new_body)},
        )
        fake = FakeMta(
            {
                "race": "running",
                "race_playerstats": "loaded",
                "race_playerstatsgui": "loaded",
            }
        )
        agent = Agent(cfg, mta=fake)
        agent.handle_prepare(
            {
                "schema": 1,
                "id": "a1",
                "action": "prepare",
                "repo": "test/repo",
                "tag": "v1.1.0",
                "manifest_path": ".deploy/download/update.json",
            }
        )
        agent.handle_apply({"id": "a1", "action": "apply"})
        agent.handle_verify({"id": "a1", "action": "verify"})
        self.assertEqual(agent.store.status()["phase"], "done")
        self.assertEqual(fake.states.get("race_playerstats"), "running")
        self.assertEqual(fake.states.get("race_playerstatsgui"), "running")


if __name__ == "__main__":
    unittest.main()
