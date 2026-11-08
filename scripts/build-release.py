#!/usr/bin/env python3
"""Build the release assets for a Speedrun LATAM tag.

Outputs (in --out, default dist/):
  server-template.tar.gz  full server tree + version.json (for installs)
  server-update.tar.gz    changed/added files since the previous tag
  update.json             manifest consumed by the in-container agent

The script reads blobs from git, so it does not depend on the working tree
being clean and it never includes ignored runtime data.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "docker"))

from deploy_agent.paths import is_runtime, is_resource_path, normalize  # noqa: E402
from deploy_agent.release import validate_repo, validate_tag  # noqa: E402
from deploy_agent.util import sha256_bytes, sha256_file, utc_now  # noqa: E402

SERVER_PREFIX = "server/"
RESOURCE_PREFIX = "server/mods/deathmatch/resources/"
TEMPLATE_NAME = "server-template.tar.gz"
UPDATE_NAME = "server-update.tar.gz"
MANUAL_PATHS = {
    "mods/deathmatch/settings.xml",
    "mods/deathmatch/acl.xml",
}
IGNORED_FILES = {
    "NOTICE",
    "LICENSE",
    "README",
    "version.json",
}


@dataclass
class Change:
    status: str
    path: str
    old_path: str | None = None


@dataclass
class ResourceInfo:
    name: str
    path: str
    meta: str


class Repo:
    def __init__(self, root: Path):
        self.root = root

    def run(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
        proc = subprocess.run(
            ["git", "-C", str(self.root), *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if check and proc.returncode != 0:
            detail = proc.stderr.decode("utf-8", "replace").strip()
            raise SystemExit(f"git {' '.join(args)} failed: {detail}")
        return proc

    def text(self, *args: str, check: bool = True) -> str:
        return self.run(*args, check=check).stdout.decode("utf-8", "replace")

    def resolve(self, ref: str) -> str:
        return self.text("rev-parse", "--verify", f"{ref}^{{commit}}").strip()

    def previous_tag(self, ref: str) -> str | None:
        proc = self.run(
            "describe", "--tags", "--abbrev=0", "--match", "v*", f"{ref}^",
            check=False,
        )
        if proc.returncode != 0:
            return None
        return proc.stdout.decode("utf-8", "replace").strip() or None

    def docker_changed(self, previous: str | None, ref: str) -> bool:
        if not previous:
            return False
        proc = self.run(
            "diff", "--name-only", "-z", previous, ref, "--", "docker",
            check=False,
        )
        return bool(proc.stdout.strip(b"\x00"))

    def diff(self, previous: str, ref: str) -> list[Change]:
        raw = self.run(
            "diff",
            "--name-status",
            "-z",
            "--find-renames",
            "--no-ext-diff",
            previous,
            ref,
            "--",
            "server",
        ).stdout
        parts = raw.split(b"\x00")
        changes: list[Change] = []
        index = 0
        while index < len(parts):
            status_raw = parts[index]
            if not status_raw:
                index += 1
                continue
            status = os.fsdecode(status_raw)
            if status[0] in {"R", "C"}:
                if index + 2 >= len(parts):
                    break
                old = os.fsdecode(parts[index + 1])
                new = os.fsdecode(parts[index + 2])
                changes.append(Change(status[0], new, old))
                index += 3
            else:
                if index + 1 >= len(parts):
                    break
                path = os.fsdecode(parts[index + 1])
                changes.append(Change(status[0], path))
                index += 2
        return changes

    def tree_files(self, ref: str, path: str) -> list[str]:
        raw = self.run("ls-tree", "-r", "-z", "--name-only", ref, "--", path).stdout
        return [os.fsdecode(item) for item in raw.split(b"\x00") if item]

    def show(self, ref: str, path: str) -> bytes:
        return self.run("show", f"{ref}:{path}").stdout

    def file_mode(self, ref: str, path: str) -> int:
        raw = self.run("ls-tree", "-z", ref, "--", path).stdout
        if not raw:
            return 0o644
        first = raw.split(b"\x00", 1)[0].decode("ascii", "replace")
        mode = first.split(" ", 1)[0]
        return 0o755 if mode == "100755" else 0o644


def strip_server(path: str) -> str:
    return path[len(SERVER_PREFIX) :] if path.startswith(SERVER_PREFIX) else path


def classify(rel: str) -> str:
    rel = normalize(rel)
    if rel in MANUAL_PATHS:
        return "manual"
    if rel in IGNORED_FILES:
        return "ignored"
    if is_runtime(rel):
        return "ignored"
    if is_resource_path(rel):
        return "resource"
    return "managed"


def resource_infos(repo: Repo, ref: str | None) -> tuple[list[ResourceInfo], dict[str, ResourceInfo]]:
    if not ref:
        return [], {}
    by_path: list[ResourceInfo] = []
    by_name: dict[str, ResourceInfo] = {}
    for path in repo.tree_files(ref, "server/mods/deathmatch/resources"):
        if not path.endswith("/meta.xml"):
            continue
        root = path[: -len("/meta.xml")]
        rel = strip_server(root)
        name = Path(rel).name
        info = ResourceInfo(name=name, path=rel, meta=strip_server(path))
        by_path.append(info)
        by_name.setdefault(name, info)
    by_path.sort(key=lambda item: len(item.path), reverse=True)
    return by_path, by_name


def map_resource(by_path: list[ResourceInfo], rel: str) -> str | None:
    rel = normalize(rel)
    for resource in by_path:
        if rel == resource.path or rel.startswith(resource.path + "/"):
            return resource.name
    return None


def parse_protected(repo: Repo, ref: str) -> set[str]:
    path = "server/mods/deathmatch/mtaserver.conf.template"
    try:
        raw = repo.show(ref, path)
        root = ET.fromstring(raw)
    except (subprocess.CalledProcessError, ET.ParseError, KeyError):
        return set()
    protected: set[str] = set()
    for element in root.iter("resource"):
        if (element.get("protected") or "0").strip() == "1":
            name = (element.get("src") or "").strip()
            if name:
                protected.add(name)
    return protected


def parse_gamemodes(repo: Repo, ref: str, resources: Iterable[ResourceInfo]) -> set[str]:
    modes: set[str] = set()
    for resource in resources:
        try:
            raw = repo.show(ref, f"server/{resource.meta}")
        except subprocess.CalledProcessError:
            continue
        text = raw.decode("utf-8-sig", errors="replace")
        try:
            root = ET.fromstring(text)
        except ET.ParseError:
            if re.search(
                r"<info\b[^>]*\btype\s*=\s*[\"']gamemode[\"']",
                text,
                re.IGNORECASE,
            ):
                modes.add(resource.name)
            continue
        info = root.find("info")
        if info is not None and (info.get("type") or "").strip().lower() == "gamemode":
            modes.add(resource.name)
    return modes


def build_template(repo: Repo, ref: str, tag: str, repo_name: str, out: Path) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="speedrun-template-") as tmp:
        tmp_path = Path(tmp)
        archive = tmp_path / "template.tar"
        repo.run(
            "archive",
            "--format=tar",
            "-o",
            str(archive),
            ref,
            "server",
        )
        extracted = tmp_path / "root"
        extracted.mkdir()
        with tarfile.open(archive) as tar:
            try:
                tar.extractall(extracted, filter="data")
            except TypeError:
                tar.extractall(extracted)
        version = {
            "schema": 1,
            "tag": tag,
            "repo": repo_name,
            "built_at": utc_now(),
        }
        (extracted / "server" / "version.json").write_text(
            json.dumps(version, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        target = out / TEMPLATE_NAME
        with tarfile.open(target, "w:gz") as tar:
            base = extracted / "server"
            for path in sorted(base.rglob("*")):
                tar.add(
                    path,
                    arcname=path.relative_to(base).as_posix(),
                    recursive=False,
                )
    return {
        "name": TEMPLATE_NAME,
        "sha256": sha256_file(out / TEMPLATE_NAME),
        "size": (out / TEMPLATE_NAME).stat().st_size,
    }


def build_update(
    repo: Repo,
    ref: str,
    files: list[str],
    out: Path,
) -> tuple[dict[str, Any] | None, dict[str, str]]:
    if not files:
        return None, {}
    target = out / UPDATE_NAME
    hashes: dict[str, str] = {}
    with tarfile.open(target, "w:gz") as tar:
        for rel in sorted(set(files)):
            data = repo.show(ref, f"server/{rel}")
            digest = sha256_bytes(data)
            hashes[rel] = digest
            info = tarfile.TarInfo(rel)
            info.size = len(data)
            info.mode = repo.file_mode(ref, f"server/{rel}")
            info.mtime = int(time.time())
            tar.addfile(info, io.BytesIO(data))
    return (
        {
            "name": UPDATE_NAME,
            "sha256": sha256_file(target),
            "size": target.stat().st_size,
        },
        hashes,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True, help="release tag, e.g. v1.7.0")
    parser.add_argument("--previous-tag", default=None, help="tag to diff from")
    parser.add_argument("--ref", default=None, help="git ref to build (default: tag)")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "ferecece/speedrunlatam"))
    parser.add_argument("--out", default="dist")
    parser.add_argument("--server-dir", default=str(REPO_ROOT))
    args = parser.parse_args(argv)

    tag = validate_tag(args.tag)
    validate_repo(args.repo, args.repo)  # shape check only
    ref = args.ref or tag
    repo = Repo(Path(args.server_dir))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    previous = args.previous_tag
    if previous == "":
        previous = None
    if previous is None and args.ref is None:
        previous = repo.previous_tag(ref)

    changes = repo.diff(previous, ref) if previous else []
    docker_changed = repo.docker_changed(previous, ref) if previous else False

    modified: list[str] = []
    added: list[str] = []
    deleted: list[str] = []
    manual: list[str] = []
    ignored: list[str] = []

    for change in changes:
        new_rel = strip_server(change.path)
        kind = classify(new_rel)
        if kind == "manual":
            if change.status in {"A", "M", "T"} or change.status.startswith("R"):
                manual.append(new_rel)
            continue
        if kind == "ignored":
            ignored.append(new_rel)
            continue
        if change.status == "D":
            deleted.append(new_rel)
        elif change.status in {"A"}:
            added.append(new_rel)
        else:
            modified.append(new_rel)
        if change.old_path:
            old_rel = strip_server(change.old_path)
            if change.old_path != change.path:
                deleted.append(old_rel)

    modified = sorted(set(modified))
    added = sorted(set(added))
    deleted = sorted(set(deleted))
    manual = sorted(set(manual))

    new_by_path, new_by_name = resource_infos(repo, ref)
    old_by_path, old_by_name = resource_infos(repo, previous) if previous else ([], {})
    new_names = set(new_by_name)
    old_names = set(old_by_name)
    protected = parse_protected(repo, ref)

    changed_resources: set[str] = set()
    added_resources: set[str] = set()
    removed_resources: set[str] = set()

    for rel in modified + added:
        name = map_resource(new_by_path, rel)
        if name:
            changed_resources.add(name)
    for rel in deleted:
        old_name = map_resource(old_by_path, rel)
        if old_name and old_name not in new_names:
            removed_resources.add(old_name)
        elif old_name:
            changed_resources.add(old_name)
        else:
            new_name = map_resource(new_by_path, rel)
            if new_name:
                changed_resources.add(new_name)

    for name in new_names - old_names:
        resource = new_by_name[name]
        if any(
            rel == resource.path or rel.startswith(resource.path + "/")
            for rel in added
        ):
            added_resources.add(name)
    changed_resources -= added_resources
    changed_resources -= removed_resources

    protected_changed = (changed_resources | added_resources) & protected
    changed_infos = [
        new_by_name[name] for name in sorted(changed_resources | added_resources)
        if name in new_by_name
    ]
    gamemodes = parse_gamemodes(repo, ref, changed_infos)

    non_resource = [rel for rel in modified + added if not is_resource_path(rel)]
    non_resource_deleted = [rel for rel in deleted if not is_resource_path(rel)]
    restart = bool(non_resource or non_resource_deleted or protected_changed)

    reasons: list[str] = []
    if docker_changed:
        reasons.append("docker/** changed: a container recreate is required")
    if previous is None:
        reasons.append("no previous tag: full install template")
    if protected_changed:
        reasons.append(
            "protected resources changed: " + ", ".join(sorted(protected_changed))
        )
    if non_resource:
        reasons.append("non-resource files changed: " + ", ".join(non_resource[:8]))
    if non_resource_deleted:
        reasons.append(
            "non-resource files deleted: " + ", ".join(non_resource_deleted[:8])
        )

    deployable = modified + added + deleted
    if docker_changed:
        mode = "recreate"
    elif previous is None:
        mode = "full"
    elif not deployable and manual:
        mode = "manual"
    elif not deployable:
        mode = "noop"
    elif restart:
        mode = "restart"
    else:
        mode = "hot"

    template_entry = build_template(repo, ref, tag, args.repo, out)
    update_entry, file_hashes = (None, {})
    if mode in {"hot", "restart", "recreate"} and (modified or added):
        update_entry, file_hashes = build_update(repo, ref, modified + added, out)

    manifest: dict[str, Any] = {
        "schema": 1,
        "tag": tag,
        "previous_tag": previous,
        "repo": args.repo,
        "generated_at": utc_now(),
        "mode": mode,
        "requires_process_restart": mode in {"restart", "full"},
        "requires_container_recreate": mode == "recreate",
        "docker_changed": docker_changed,
        "reasons": reasons,
        "changes": {
            "modified": modified,
            "added": added,
            "deleted": deleted,
            "manual": manual,
            "ignored": sorted(set(ignored)),
        },
        "files": file_hashes,
        "resources": {
            "changed": sorted(changed_resources),
            "added": sorted(added_resources),
            "removed": sorted(removed_resources),
            "protected": sorted(protected_changed),
            "gamemodes": sorted(gamemodes),
        },
        "update": update_entry,
        "template": template_entry,
    }

    (out / "update.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    with (out / "sha256sums.txt").open("w", encoding="utf-8") as handle:
        for name in (TEMPLATE_NAME, UPDATE_NAME):
            path = out / name
            if path.is_file():
                handle.write(f"{sha256_file(path)}  {name}\n")

    print(json.dumps(
        {
            "tag": tag,
            "previous_tag": previous,
            "mode": mode,
            "resources": manifest["resources"],
            "manual": manual,
            "update": update_entry,
            "template": template_entry,
        },
        indent=2,
        sort_keys=True,
    ))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
