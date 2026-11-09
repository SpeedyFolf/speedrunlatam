from __future__ import annotations

import io
import json
import tarfile
import unittest

from . import DeployTestCase
from deploy_agent import release
from deploy_agent.util import DeployError, sha256_bytes, sha256_file


class ReleaseTests(DeployTestCase):
    def _tar(self, name: str, members: dict[str, bytes]) -> None:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(path, "w:gz") as archive:
            for rel, data in members.items():
                info = tarfile.TarInfo(rel)
                info.size = len(data)
                info.mode = 0o644
                archive.addfile(info, io.BytesIO(data))

    def test_load_manifest_local_and_ensure_asset(self) -> None:
        cfg = self.config()
        download = cfg.download_dir
        manifest = {
            "schema": 1,
            "tag": "v1.0.0",
            "repo": "test/repo",
            "previous_tag": None,
            "mode": "hot",
            "changes": {"modified": [], "added": [], "deleted": []},
            "update": None,
            "template": None,
        }
        (download / "update.json").write_text(json.dumps(manifest), encoding="utf-8")
        loaded, local = release.load_manifest(cfg, "v1.0.0", ".deploy/download/update.json")
        self.assertEqual(loaded["tag"], "v1.0.0")
        self.assertTrue(local and local.is_file())

        asset = download / "server-update.tar.gz"
        asset.write_bytes(b"payload")
        manifest["update"] = {
            "name": "server-update.tar.gz",
            "sha256": sha256_file(asset),
            "size": asset.stat().st_size,
        }
        (download / "update.json").write_text(json.dumps(manifest), encoding="utf-8")
        path, entry = release.ensure_asset(cfg, manifest, "update")
        self.assertEqual(path, asset)
        self.assertEqual(entry["sha256"], sha256_file(asset))

    def test_extract_allowed_paths(self) -> None:
        cfg = self.config()
        self._tar(
            "bundle.tar.gz",
            {
                "mods/deathmatch/resources/x/a.lua": b"a",
                "mods/deathmatch/resources/x/b.lua": b"b",
            },
        )
        staging = self.root / "staging"
        extracted = release.extract_asset(
            self.root / "bundle.tar.gz",
            staging,
            cfg,
            allowed_paths={
                "mods/deathmatch/resources/x/a.lua",
                "mods/deathmatch/resources/x/b.lua",
            },
        )
        self.assertEqual(sorted(extracted), [
            "mods/deathmatch/resources/x/a.lua",
            "mods/deathmatch/resources/x/b.lua",
        ])
        self.assertEqual((staging / "mods/deathmatch/resources/x/a.lua").read_bytes(), b"a")

    def test_extract_rejects_traversal(self) -> None:
        cfg = self.config()
        self._tar("evil.tar.gz", {"../evil.lua": b"evil"})
        with self.assertRaises(DeployError):
            release.extract_asset(
                self.root / "evil.tar.gz",
                self.root / "staging",
                cfg,
                allowed_paths={"../evil.lua"},
            )

    def test_extract_rejects_unexpected_file(self) -> None:
        cfg = self.config()
        self._tar(
            "bundle.tar.gz",
            {
                "mods/deathmatch/resources/x/a.lua": b"a",
                "mods/deathmatch/resources/x/b.lua": b"b",
            },
        )
        with self.assertRaises(DeployError):
            release.extract_asset(
                self.root / "bundle.tar.gz",
                self.root / "staging2",
                cfg,
                allowed_paths={"mods/deathmatch/resources/x/a.lua"},
            )

    def test_extract_rejects_symlink(self) -> None:
        cfg = self.config()
        path = self.root / "link.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            info = tarfile.TarInfo("mods/deathmatch/resources/x/link")
            info.type = tarfile.SYMTYPE
            info.linkname = "/etc/passwd"
            archive.addfile(info)
        with self.assertRaises(DeployError):
            release.extract_asset(
                path,
                self.root / "staging3",
                cfg,
                allowed_paths={"mods/deathmatch/resources/x/link"},
            )

    def test_extract_template_allows_parent_directories(self) -> None:
        cfg = self.config()
        path = self.root / "template.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            for rel in ("mods", "mods/deathmatch", "mods/deathmatch/resources", "x64"):
                info = tarfile.TarInfo(rel)
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                archive.addfile(info)
            data = b"binary"
            info = tarfile.TarInfo("x64/deathmatch.so")
            info.size = len(data)
            info.mode = 0o755
            archive.addfile(info, io.BytesIO(data))
        staging = self.root / "staging-template"
        extracted = release.extract_asset(path, staging, cfg, allow_managed=True)
        self.assertEqual(extracted, ["x64/deathmatch.so"])
        self.assertTrue((staging / "mods/deathmatch/resources").is_dir())
        self.assertEqual((staging / "x64/deathmatch.so").read_bytes(), b"binary")

    def test_verify_hashes(self) -> None:
        cfg = self.config()
        staging = self.root / "staging"
        target = staging / "mods/deathmatch/resources/x/a.lua"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b"hello")
        release.verify_hashes(
            staging, {"mods/deathmatch/resources/x/a.lua": sha256_bytes(b"hello")}
        )
        with self.assertRaises(DeployError):
            release.verify_hashes(
                staging, {"mods/deathmatch/resources/x/a.lua": sha256_bytes(b"other")}
            )


if __name__ == "__main__":
    unittest.main()
