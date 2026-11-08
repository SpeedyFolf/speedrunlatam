from __future__ import annotations

import unittest

from . import DeployTestCase
from deploy_agent.paths import (
    PathError,
    is_managed,
    is_resource_path,
    is_runtime,
    normalize,
)


class PathTests(DeployTestCase):
    def test_normalize(self) -> None:
        self.assertEqual(normalize("./mods/deathmatch/x"), "mods/deathmatch/x")
        self.assertEqual(normalize("mods//deathmatch/x"), "mods/deathmatch/x")
        for bad in ("/etc/passwd", "../x", "mods/../../x", "a\\b", "", "mods/./x/../y"):
            with self.assertRaises(PathError, msg=bad):
                normalize(bad)

    def test_runtime_paths(self) -> None:
        self.assertTrue(is_runtime("mods/deathmatch/registry.db"))
        self.assertTrue(is_runtime("mods/deathmatch/internal.db"))
        self.assertTrue(is_runtime("mods/deathmatch/databases/tuning.db"))
        self.assertTrue(
            is_runtime(
                "mods/deathmatch/resources/[gamemodes]/[race]/[addons]/race_ghost/ghosts/a.ghost"
            )
        )
        self.assertTrue(is_runtime("ghosts_server/ghosts/a.ghost"))
        self.assertTrue(
            is_runtime("mods/deathmatch/resources/[managers]/autologin/encryption_key.txt")
        )
        self.assertTrue(is_runtime(".deploy/request.json"))
        self.assertFalse(is_runtime("mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua"))

    def test_managed(self) -> None:
        self.assertTrue(is_managed("mods/deathmatch/resources/foo/meta.xml"))
        self.assertTrue(is_managed("x64/deathmatch.so"))
        self.assertTrue(is_managed("mta-server64"))
        self.assertFalse(is_managed("mods/deathmatch/registry.db"))
        self.assertFalse(is_managed(".deploy/state.json"))

    def test_resource(self) -> None:
        self.assertTrue(is_resource_path("mods/deathmatch/resources/x/meta.xml"))
        self.assertFalse(is_resource_path("x64/core.so"))


if __name__ == "__main__":
    unittest.main()
