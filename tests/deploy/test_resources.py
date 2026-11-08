from __future__ import annotations

import shutil
import unittest
from pathlib import Path

from . import DeployTestCase
from deploy_agent import resources


def make_resource(root: Path, rel: str, *, kind: str = "script", body: str = "-- test\n") -> str:
    directory = root / rel
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "meta.xml").write_text(
        f'<meta><info name="{directory.name}" type="{kind}" /></meta>\n',
        encoding="utf-8",
    )
    (directory / "server.lua").write_text(body, encoding="utf-8")
    return f"{rel}/server.lua"


def make_conf(root: Path, resources: dict[str, dict[str, str]]) -> None:
    path = root / "mods/deathmatch/mtaserver.conf.template"
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["<config>"]
    for name, attrs in resources.items():
        bits = " ".join(f'{key}="{value}"' for key, value in attrs.items())
        lines.append(f"  <resource src=\"{name}\" {bits}></resource>")
    lines.append("</config>\n")
    path.write_text("\n".join(lines), encoding="utf-8")


class ResourcePlanTests(DeployTestCase):
    def test_scan(self) -> None:
        make_resource(self.root, "mods/deathmatch/resources/[gamemodes]/[race]/race", kind="gamemode")
        make_resource(self.root, "mods/deathmatch/resources/[gameplay]/joinquit")
        found = resources.scan_resources(self.root)
        self.assertEqual(found.names(), {"race", "joinquit"})
        self.assertIn("race", found.gamemodes())
        self.assertNotIn("joinquit", found.gamemodes())
        self.assertEqual(
            found.map_path("mods/deathmatch/resources/[gameplay]/joinquit/server.lua"),
            "joinquit",
        )

    def test_delta_plan_hot(self) -> None:
        current = self.root / "current"
        staging = self.root / "staging"
        make_resource(current, "mods/deathmatch/resources/[gamemodes]/[race]/race", kind="gamemode")
        make_resource(current, "mods/deathmatch/resources/[gameplay]/oldmod")
        make_resource(current, "mods/deathmatch/resources/[gameplay]/joinquit")
        shutil.copytree(current, staging)
        make_resource(staging, "mods/deathmatch/resources/[gameplay]/newmod")
        shutil.rmtree(staging / "mods/deathmatch/resources/[gameplay]/oldmod")
        (staging / "mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua").write_text(
            "-- changed\n", encoding="utf-8"
        )
        make_conf(
            staging,
            {
                "race": {"startup": "1", "protected": "0"},
                "joinquit": {"startup": "1", "protected": "0"},
                "newmod": {"startup": "1", "protected": "0"},
            },
        )

        manifest = {
            "mode": "hot",
            "changes": {
                "modified": [
                    "mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua"
                ],
                "added": [
                    "mods/deathmatch/resources/[gameplay]/newmod/meta.xml",
                    "mods/deathmatch/resources/[gameplay]/newmod/server.lua",
                ],
                "deleted": [
                    "mods/deathmatch/resources/[gameplay]/oldmod/meta.xml",
                    "mods/deathmatch/resources/[gameplay]/oldmod/server.lua",
                ],
            },
        }
        plan = resources.delta_plan(manifest, current, staging)
        self.assertFalse(plan["requires_process_restart"])
        self.assertEqual(plan["resources"]["changed"], ["race"])
        self.assertEqual(plan["resources"]["added"], ["newmod"])
        self.assertEqual(plan["resources"]["removed"], ["oldmod"])
        self.assertEqual(plan["commands_before_apply"], ["stop oldmod"])
        self.assertEqual(
            plan["commands_after_apply"],
            ["refresh", "start newmod", "restart race"],
        )
        self.assertEqual(plan["expected_resources"], ["newmod", "race"])

    def test_changed_included_resource_is_restarted(self) -> None:
        current = self.root / "current"
        staging = self.root / "staging"
        make_resource(current, "mods/deathmatch/resources/[gameplay]/killmessages")
        make_resource(current, "mods/deathmatch/resources/[gamemodes]/[race]/race", kind="gamemode")
        (current / "mods/deathmatch/resources/[gamemodes]/[race]/race/meta.xml").write_text(
            '<meta><info name="Race" type="gamemode" />'
            '<include resource="killmessages"></include></meta>\n',
            encoding="utf-8",
        )
        make_conf(
            current,
            {"race": {"startup": "1", "protected": "0"}},
        )
        icon = staging / "mods/deathmatch/resources/[gameplay]/killmessages/icons"
        icon.mkdir(parents=True)
        (icon / "explosion.png").write_bytes(b"png")

        manifest = {
            "mode": "hot",
            "changes": {
                "modified": [
                    "mods/deathmatch/resources/[gameplay]/killmessages/icons/explosion.png"
                ],
                "added": [],
                "deleted": [],
            },
        }
        plan = resources.delta_plan(manifest, current, staging)
        self.assertFalse(plan["requires_process_restart"])
        self.assertEqual(plan["resources"]["changed"], ["killmessages"])
        self.assertIn("killmessages", plan["resources"]["included"])
        self.assertEqual(plan["resources"]["restart"], ["killmessages"])
        self.assertEqual(plan["commands_after_apply"], ["restart killmessages"])
        self.assertEqual(plan["expected_resources"], ["killmessages"])

    def test_protected_forces_restart(self) -> None:
        current = self.root / "current"
        staging = self.root / "staging"
        make_resource(current, "mods/deathmatch/resources/[gamemodes]/[race]/race", kind="gamemode")
        shutil.copytree(current, staging)
        make_conf(
            staging,
            {"race": {"startup": "1", "protected": "1"}},
        )
        manifest = {
            "mode": "hot",
            "changes": {
                "modified": [
                    "mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua"
                ],
                "added": [],
                "deleted": [],
            },
        }
        plan = resources.delta_plan(manifest, current, staging)
        self.assertTrue(plan["requires_process_restart"])
        self.assertEqual(plan["commands_after_apply"], [])
        self.assertEqual(plan["expected_resources"], ["race"])

    def test_full_plan(self) -> None:
        staging = self.root / "staging"
        make_resource(staging, "mods/deathmatch/resources/[gamemodes]/[race]/race", kind="gamemode")
        make_conf(staging, {"race": {"startup": "1", "protected": "0"}})
        plan = resources.full_plan(staging, "test")
        self.assertEqual(plan["mode"], "full")
        self.assertTrue(plan["requires_process_restart"])
        self.assertEqual(plan["expected_resources"], ["race"])


if __name__ == "__main__":
    unittest.main()
