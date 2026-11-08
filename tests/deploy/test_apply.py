from __future__ import annotations

import shutil
import unittest
from pathlib import Path

from . import DeployTestCase, ROOT
from deploy_agent import apply, backup


@unittest.skipUnless(shutil.which("rsync"), "rsync is required")
class FullApplyTests(DeployTestCase):
    def test_apply_full_preserves_runtime_and_rolls_back(self) -> None:
        cfg = self.config(DEPLOY_SYNC_EXCLUDES=str(ROOT / "docker/sync-excludes.txt"))
        target = self.root
        (target / "mods/deathmatch/resources/[gameplay]").mkdir(parents=True)
        old = target / "mods/deathmatch/resources/[gameplay]/old.lua"
        old.write_text("old\n", encoding="utf-8")
        (target / "mods/deathmatch/registry.db").write_text("db\n", encoding="utf-8")
        (target / "mods/deathmatch/settings.xml").write_text("settings\n", encoding="utf-8")
        (target / "mods/deathmatch/resources/[managers]/autologin").mkdir(parents=True)
        (target / "mods/deathmatch/resources/[managers]/autologin/encryption_key.txt").write_text(
            "key\n", encoding="utf-8"
        )
        (target / ".deploy").mkdir(parents=True, exist_ok=True)
        (target / ".deploy/state.json").write_text("state\n", encoding="utf-8")
        (target / "logs/server.log").write_text("log\n", encoding="utf-8")

        staging = cfg.staging_dir / "test"
        (staging / "mods/deathmatch/resources/[gameplay]/new").mkdir(parents=True)
        new = staging / "mods/deathmatch/resources/[gameplay]/new/new.lua"
        new.write_text("new\n", encoding="utf-8")
        (staging / "mods/deathmatch/registry.db").write_text("new-db\n", encoding="utf-8")
        (staging / "mods/deathmatch/settings.xml").write_text("new-settings\n", encoding="utf-8")
        (staging / "version.json").write_text('{"tag":"v1.1.0"}\n', encoding="utf-8")
        (staging / "mta-server64").write_text("binary\n", encoding="utf-8")

        backup_dir = backup.new_backup(cfg, "v1.1.0")
        result = apply.apply_full(
            cfg,
            staging,
            {"tag": "v1.1.0", "previous_tag": "v1.0.0"},
            backup_dir,
        )
        self.assertTrue((target / "mods/deathmatch/resources/[gameplay]/new/new.lua").is_file())
        self.assertFalse(old.exists())
        self.assertEqual((target / "mods/deathmatch/registry.db").read_text(), "db\n")
        self.assertEqual((target / "mods/deathmatch/settings.xml").read_text(), "settings\n")
        self.assertEqual(
            (target / "mods/deathmatch/resources/[managers]/autologin/encryption_key.txt").read_text(),
            "key\n",
        )
        self.assertEqual((target / ".deploy/state.json").read_text(), "state\n")
        self.assertEqual((target / "logs/server.log").read_text(), "log\n")
        self.assertTrue((backup_dir / "journal.json").is_file())
        self.assertTrue(result["written"])

        backup.rollback(cfg, backup_dir)
        self.assertEqual(old.read_text(), "old\n")
        self.assertFalse((target / "mods/deathmatch/resources/[gameplay]/new/new.lua").exists())


if __name__ == "__main__":
    unittest.main()
