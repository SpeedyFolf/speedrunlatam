from __future__ import annotations

import logging
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from .paths import RESOURCE_ROOT, is_resource_path, normalize
from .util import DeployError

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class Resource:
    name: str
    path: str
    meta_path: str
    is_gamemode: bool
    includes: tuple[str, ...] = ()


class ResourceSet:
    def __init__(self, root: Path):
        self.root = root
        self.by_name: dict[str, Resource] = {}
        self.by_path: list[Resource] = []

    def add(self, resource: Resource) -> None:
        self.by_path.append(resource)
        self.by_path.sort(key=lambda item: len(item.path), reverse=True)
        if resource.name in self.by_name and self.by_name[resource.name].path != resource.path:
            log.warning(
                "duplicate resource name %s in %s and %s",
                resource.name,
                self.by_name[resource.name].path,
                resource.path,
            )
            return
        self.by_name[resource.name] = resource

    def names(self) -> set[str]:
        return set(self.by_name)

    def gamemodes(self) -> set[str]:
        return {name for name, res in self.by_name.items() if res.is_gamemode}

    def included(self) -> set[str]:
        names: set[str] = set()
        for resource in self.by_name.values():
            names.update(resource.includes)
        return names

    def map_path(self, rel: str) -> str | None:
        rel = normalize(rel)
        for resource in self.by_path:
            if rel == resource.path or rel.startswith(resource.path + "/"):
                return resource.name
        return None


def _regex_meta(text: str) -> tuple[bool, tuple[str, ...]]:
    is_gamemode = bool(
        re.search(
            r"<info\b[^>]*\btype\s*=\s*[\"']gamemode[\"']",
            text,
            re.IGNORECASE,
        )
    )
    includes = tuple(
        sorted(
            {
                name
                for name in re.findall(
                    r"<include\b[^>]*\bresource\s*=\s*[\"']([^\"']+)[\"']",
                    text,
                    re.IGNORECASE,
                )
                if name.strip()
            }
        )
    )
    return is_gamemode, includes


def _parse_meta(path: Path) -> tuple[bool, tuple[str, ...]]:
    try:
        text = path.read_text(encoding="utf-8-sig", errors="replace")
    except OSError as exc:
        log.warning("cannot read %s: %s", path, exc)
        return False, ()

    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        # MTA tolerates undeclared prefixes such as edf:definition.
        return _regex_meta(text)

    info = root.find("info")
    is_gamemode = bool(
        info is not None
        and (info.get("type") or "").strip().lower() == "gamemode"
    )
    includes = tuple(
        sorted(
            {
                (element.get("resource") or "").strip()
                for element in root.findall("include")
                if (element.get("resource") or "").strip()
            }
        )
    )
    return is_gamemode, includes


def scan_resources(root: Path) -> ResourceSet:
    """Find every directory below resources/ that contains meta.xml."""
    result = ResourceSet(root)
    base = root / RESOURCE_ROOT
    if not base.is_dir():
        return result

    for dirpath, dirnames, filenames in os_walk(base):
        if "meta.xml" not in filenames:
            continue
        directory = Path(dirpath)
        try:
            rel = directory.relative_to(root).as_posix()
        except ValueError:
            continue
        is_gamemode, includes = _parse_meta(directory / "meta.xml")
        resource = Resource(
            name=directory.name,
            path=rel,
            meta_path=f"{rel}/meta.xml",
            is_gamemode=is_gamemode,
            includes=includes,
        )
        result.add(resource)
    return result


def os_walk(base: Path):
    import os

    return os.walk(base)


def parse_server_conf(root: Path) -> tuple[set[str], set[str]]:
    """Return (autostart, protected) resource names from mtaserver.conf.template."""
    template = root / "mods/deathmatch/mtaserver.conf.template"
    autostart: set[str] = set()
    protected: set[str] = set()
    if not template.is_file():
        return autostart, protected
    try:
        tree = ET.parse(template)
    except (ET.ParseError, OSError) as exc:
        log.warning("cannot parse %s: %s", template, exc)
        return autostart, protected

    for element in tree.getroot().iter("resource"):
        name = (element.get("src") or "").strip()
        if not name:
            continue
        if (element.get("startup") or "0").strip() == "1":
            autostart.add(name)
        if (element.get("protected") or "0").strip() == "1":
            protected.add(name)
    return autostart, protected


def _ordered(names: Iterable[str], gamemodes: set[str], *, gamemodes_first: bool = False) -> list[str]:
    regular = sorted(name for name in names if name not in gamemodes)
    modes = sorted(name for name in names if name in gamemodes)
    if gamemodes_first:
        return modes + regular
    return regular + modes


def _add_reason(plan: dict[str, Any], reason: str) -> None:
    if reason not in plan["reasons"]:
        plan["reasons"].append(reason)


def _base_plan(mode: str) -> dict[str, Any]:
    return {
        "mode": mode,
        "manifest_mode": mode,
        "requires_process_restart": False,
        "requires_container_recreate": False,
        "commands_before_apply": [],
        "commands_after_apply": [],
        "resources": {
            "changed": [],
            "added": [],
            "removed": [],
            "start": [],
            "stop": [],
            "restart": [],
            "protected": [],
            "gamemodes": [],
            "autostart": [],
            "included": [],
        },
        "expected_resources": [],
        "reasons": [],
    }


def _finish_expected(plan: dict[str, Any], autostart: set[str]) -> None:
    if plan["requires_process_restart"] or plan["mode"] == "full":
        expected = sorted(set(plan["resources"]["gamemodes"]) & autostart)
        if not expected:
            expected = ["race"] if "race" in autostart else []
        plan["expected_resources"] = expected
    else:
        plan["expected_resources"] = sorted(
            set(plan["resources"]["start"]) | set(plan["resources"]["restart"])
        )


def full_plan(staging_root: Path, reason: str) -> dict[str, Any]:
    plan = _base_plan("full")
    plan["requires_process_restart"] = True
    _add_reason(plan, reason)
    staging = scan_resources(staging_root)
    autostart, protected = parse_server_conf(staging_root)
    gamemodes = staging.gamemodes()
    plan["resources"]["gamemodes"] = sorted(gamemodes)
    plan["resources"]["autostart"] = sorted(autostart)
    plan["resources"]["protected"] = sorted(protected)
    plan["resources"]["included"] = sorted(staging.included())
    _finish_expected(plan, autostart)
    return plan


def delta_plan(
    manifest: dict[str, Any],
    current_root: Path,
    staging_root: Path,
) -> dict[str, Any]:
    changes = manifest.get("changes") or {}
    modified = [normalize(p) for p in changes.get("modified", [])]
    added = [normalize(p) for p in changes.get("added", [])]
    deleted = [normalize(p) for p in changes.get("deleted", [])]
    changed_paths = modified + added

    manifest_mode = str(manifest.get("mode") or "hot")
    plan = _base_plan(manifest_mode)
    current = scan_resources(current_root)
    staging = scan_resources(staging_root)
    autostart, protected = parse_server_conf(staging_root)
    if not autostart and not protected:
        autostart, protected = parse_server_conf(current_root)

    gamemodes = staging.gamemodes() | current.gamemodes()
    plan["resources"]["autostart"] = sorted(autostart)
    plan["resources"]["protected"] = sorted(protected)
    plan["resources"]["gamemodes"] = sorted(gamemodes)
    included = current.included() | staging.included()
    plan["resources"]["included"] = sorted(included)

    changed_resources: set[str] = set()
    added_resources: set[str] = set()
    removed_resources: set[str] = set()

    for rel in changed_paths:
        if is_resource_path(rel):
            name = staging.map_path(rel) or current.map_path(rel)
            if name:
                changed_resources.add(name)
            else:
                _add_reason(plan, f"resource path without resource root: {rel}")
                plan["requires_process_restart"] = True
        else:
            _add_reason(plan, f"non-resource path changed: {rel}")
            plan["requires_process_restart"] = True

    for rel in deleted:
        if not is_resource_path(rel):
            _add_reason(plan, f"non-resource path deleted: {rel}")
            plan["requires_process_restart"] = True
            continue
        current_name = current.map_path(rel)
        staging_name = staging.map_path(rel) or current.map_path(rel)
        if current_name and current_name not in staging.by_name:
            removed_resources.add(current_name)
        elif staging_name:
            changed_resources.add(staging_name)
        elif current_name:
            changed_resources.add(current_name)

    for name in staging.names() - current.names():
        resource = staging.by_name.get(name)
        if resource and any(
            rel == resource.path or rel.startswith(resource.path + "/")
            for rel in changed_paths
        ):
            added_resources.add(name)

    changed_resources -= added_resources
    changed_resources -= removed_resources

    protected_changed = (changed_resources | added_resources) & protected
    if protected_changed:
        plan["requires_process_restart"] = True
        _add_reason(
            plan,
            "protected resources changed: " + ", ".join(sorted(protected_changed)),
        )

    if manifest_mode in {"restart", "full"} or manifest.get("requires_process_restart"):
        plan["requires_process_restart"] = True
        _add_reason(plan, f"manifest requires a process restart ({manifest_mode})")
    if manifest_mode == "recreate" or manifest.get("requires_container_recreate"):
        plan["requires_container_recreate"] = True
        _add_reason(plan, "manifest requires a container recreate")

    plan["resources"]["changed"] = sorted(changed_resources)
    plan["resources"]["added"] = sorted(added_resources)
    plan["resources"]["removed"] = sorted(removed_resources)

    if plan["requires_container_recreate"]:
        _finish_expected(plan, autostart)
        return plan

    if plan["requires_process_restart"]:
        _finish_expected(plan, autostart)
        return plan

    stop = set(removed_resources)
    available = autostart | included
    start = added_resources & available
    restart = changed_resources & available

    plan["resources"]["stop"] = _ordered(stop, gamemodes, gamemodes_first=True)
    plan["resources"]["start"] = _ordered(start, gamemodes)
    plan["resources"]["restart"] = _ordered(restart, gamemodes)

    plan["commands_before_apply"] = [f"stop {name}" for name in plan["resources"]["stop"]]
    after: list[str] = []
    if plan["resources"]["added"] or plan["resources"]["removed"]:
        after.append("refresh")
    after.extend(f"start {name}" for name in plan["resources"]["start"])
    after.extend(f"restart {name}" for name in plan["resources"]["restart"])
    plan["commands_after_apply"] = after

    _finish_expected(plan, autostart)
    return plan


def validate_plan(plan: dict[str, Any]) -> None:
    if not isinstance(plan, dict):
        raise DeployError("E_PLAN", "plan is not an object")
    for key in ("mode", "commands_before_apply", "commands_after_apply", "resources"):
        if key not in plan:
            raise DeployError("E_PLAN", f"plan is missing {key}")
    for command in plan["commands_before_apply"] + plan["commands_after_apply"]:
        if not isinstance(command, str) or not command.strip():
            raise DeployError("E_PLAN", "plan contains an invalid command")
