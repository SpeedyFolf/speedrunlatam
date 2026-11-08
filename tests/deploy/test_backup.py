from __future__ import annotations

import json
import sqlite3
import unittest
from pathlib import Path

from . import DeployTestCase, has_sqlite3
from deploy_agent import backup


@unittest.skipUnless(has_sqlite3(), "sqlite3 CLI is required")
class BackupTests(DeployTestCase):
    def _make_data(self) -> None:
        db = self.root / "mods/deathmatch/registry.db"
        db.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(db)
        connection.execute("create table maptimes (mapName text, playerName text, time int)")
        connection.execute("insert into maptimes values ('MapA', 'Alice', 1000)")
        connection.commit()
        connection.close()

        internal = self.root / "mods/deathmatch/internal.db"
        connection = sqlite3.connect(internal)
        connection.execute("create table accounts (name text)")
        connection.execute("insert into accounts values ('alice')")
        connection.execute("create table userdata (k text)")
        connection.commit()
        connection.close()

        (self.root / "mods/deathmatch/databases").mkdir(parents=True, exist_ok=True)
        (self.root / "mods/deathmatch/databases/tuning.db").write_bytes(b"tuning")

        ghost = self.root / "mods/deathmatch/resources/[gamemodes]/[race]/[addons]/race_ghost/ghosts"
        ghost.mkdir(parents=True, exist_ok=True)
        (ghost / "a.ghost").write_text("local ghost", encoding="utf-8")

        remote = self.root / "ghosts_server/ghosts"
        remote.mkdir(parents=True, exist_ok=True)
        (remote / "b.ghost").write_bytes(b"remote ghost")

        key = self.root / "mods/deathmatch/resources/[managers]/autologin/encryption_key.txt"
        key.parent.mkdir(parents=True, exist_ok=True)
        key.write_text("0123456789abcdef", encoding="utf-8")

    def test_snapshot_sensitive(self) -> None:
        self._make_data()
        cfg = self.config()
        backup_dir = backup.new_backup(cfg, "v1.0.0")
        report = backup.snapshot_sensitive(cfg, backup_dir, "v1.0.0")

        self.assertTrue((backup_dir / "sensitive/registry.db").is_file())
        self.assertTrue((backup_dir / "sensitive/internal.db").is_file())
        self.assertTrue((backup_dir / "sensitive/directories.tar.gz").is_file())
        self.assertTrue(
            (
                backup_dir
                / "sensitive/files/mods/deathmatch/resources/[managers]/autologin/encryption_key.txt"
            ).is_file()
        )
        self.assertEqual(report["databases"][0]["counts"]["maptimes"], 1)
        self.assertEqual(report["databases"][1]["counts"]["accounts"], 1)
        self.assertEqual(
            json.loads((backup_dir / "snapshot.json").read_text())["tag"], "v1.0.0"
        )

        connection = sqlite3.connect(backup_dir / "sensitive/registry.db")
        try:
            self.assertEqual(connection.execute("select count(*) from maptimes").fetchone()[0], 1)
        finally:
            connection.close()

    def test_backup_and_rollback_code(self) -> None:
        self._make_data()
        cfg = self.config()
        backup_dir = backup.new_backup(cfg, "v1.0.0")
        target = self.root / "mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("old\n", encoding="utf-8")

        rel = "mods/deathmatch/resources/[gamemodes]/[race]/race/server.lua"
        backup.backup_code(cfg, backup_dir, [rel])
        target.write_text("new\n", encoding="utf-8")
        backup.rollback(cfg, backup_dir)
        self.assertEqual(target.read_text(encoding="utf-8"), "old\n")

    def test_rollback_deletes_created_files(self) -> None:
        cfg = self.config()
        backup_dir = backup.new_backup(cfg, "v1.0.0")
        rel = "mods/deathmatch/resources/x/created.lua"
        backup.backup_code(cfg, backup_dir, [rel])
        created = self.root / rel
        created.parent.mkdir(parents=True, exist_ok=True)
        created.write_text("created\n", encoding="utf-8")
        backup.rollback(cfg, backup_dir)
        self.assertFalse(created.exists())


if __name__ == "__main__":
    unittest.main()
