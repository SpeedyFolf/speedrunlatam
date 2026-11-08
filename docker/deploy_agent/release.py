from __future__ import annotations

import json
import logging
import os
import re
import shutil
import tarfile
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path, PurePosixPath
from typing import Any

from .config import Config
from .paths import (
    PathError,
    ensure_managed,
    is_managed,
    is_runtime,
    is_under,
    normalize,
)
from .util import (
    DeployError,
    atomic_write_bytes,
    format_bytes,
    is_path_within,
    sha256_file,
)

log = logging.getLogger(__name__)

TAG_RE = re.compile(r"^v[0-9][0-9A-Za-z._-]*$")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
ASSET_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
MAX_REDIRECTS = 5


def validate_tag(tag: str) -> str:
    tag = (tag or "").strip()
    if not TAG_RE.match(tag):
        raise DeployError("E_TAG", f"invalid release tag: {tag!r}")
    return tag


def validate_repo(repo: str, expected: str) -> str:
    repo = (repo or "").strip()
    if not REPO_RE.match(repo):
        raise DeployError("E_REPO", f"invalid repository: {repo!r}")
    if repo != expected:
        raise DeployError(
            "E_REPO", f"repository {repo!r} is not allowed; expected {expected!r}"
        )
    return repo


def _release_url(cfg: Config, tag: str, name: str) -> str:
    return f"{cfg.release_base_url}/{cfg.repo}/releases/download/{tag}/{name}"


def _request(url: str, cfg: Config) -> urllib.request.Request:
    headers = {
        "User-Agent": "speedrunlatam-deploy-agent/1",
        "Accept": "application/json, application/octet-stream, */*",
    }
    if cfg.github_token and url.startswith(("http://", "https://")):
        headers["Authorization"] = f"Bearer {cfg.github_token}"
    return urllib.request.Request(url, headers=headers)


def _open(url: str, cfg: Config, timeout: int = 60):
    try:
        return urllib.request.urlopen(_request(url, cfg), timeout=timeout)
    except urllib.error.HTTPError as exc:
        detail = exc.read(2048).decode("utf-8", "replace").strip()
        raise DeployError(
            "E_HTTP", f"HTTP {exc.code} for {url}: {detail or exc.reason}"
        ) from exc
    except urllib.error.URLError as exc:
        raise DeployError("E_HTTP", f"cannot fetch {url}: {exc.reason}") from exc


def download(url: str, dest: Path, cfg: Config) -> Path:
    max_bytes = cfg.max_asset_mb * 1024 * 1024
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    total = 0
    try:
        with _open(url, cfg) as response:
            length = response.headers.get("Content-Length")
            if length and int(length) > max_bytes:
                raise DeployError(
                    "E_SIZE",
                    f"asset is too large ({format_bytes(int(length))} > "
                    f"{format_bytes(max_bytes)})",
                )
            with part.open("wb") as handle:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > max_bytes:
                        raise DeployError(
                            "E_SIZE",
                            f"asset exceeded the {format_bytes(max_bytes)} limit",
                        )
                    handle.write(chunk)
                handle.flush()
                os.fsync(handle.fileno())
        os.replace(part, dest)
    except Exception:
        try:
            part.unlink()
        except FileNotFoundError:
            pass
        raise
    return dest


def load_manifest(
    cfg: Config,
    tag: str,
    manifest_path: str | None = None,
) -> tuple[dict[str, Any], Path | None]:
    """Load update.json from the server volume or the GitHub release."""
    tag = validate_tag(tag)
    local: Path | None = None
    if manifest_path:
        candidate = (cfg.target / manifest_path).resolve()
        download_root = (cfg.state_dir / "download").resolve()
        if not is_path_within(candidate, download_root):
            raise DeployError(
                "E_MANIFEST", "manifest_path must be inside .deploy/download"
            )
        if not candidate.is_file():
            raise DeployError("E_MANIFEST", f"manifest not found: {manifest_path}")
        local = candidate
        try:
            data = json.loads(candidate.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            raise DeployError("E_MANIFEST", f"invalid manifest: {exc}") from exc
    else:
        url = _release_url(cfg, tag, "update.json")
        with _open(url, cfg) as response:
            raw = response.read(cfg.max_asset_mb * 1024 * 1024)
        try:
            data = json.loads(raw.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise DeployError("E_MANIFEST", f"invalid manifest: {exc}") from exc

    if not isinstance(data, dict):
        raise DeployError("E_MANIFEST", "manifest is not an object")
    if str(data.get("tag") or "") != tag:
        raise DeployError(
            "E_MANIFEST",
            f"manifest tag {data.get('tag')!r} does not match requested tag {tag!r}",
        )
    validate_repo(str(data.get("repo") or ""), cfg.repo)
    if data.get("schema") not in (1, None):
        raise DeployError("E_MANIFEST", f"unsupported manifest schema: {data.get('schema')!r}")
    return data, local


def _asset_name(entry: Any, field: str) -> str:
    if not isinstance(entry, dict):
        raise DeployError("E_MANIFEST", f"manifest.{field} is not an object")
    name = str(entry.get("name") or "")
    if not ASSET_RE.match(name):
        raise DeployError("E_MANIFEST", f"invalid asset name in {field}: {name!r}")
    if not name.endswith(".tar.gz"):
        raise DeployError("E_MANIFEST", f"asset in {field} is not a .tar.gz: {name!r}")
    return name


def ensure_asset(
    cfg: Config,
    manifest: dict[str, Any],
    field: str,
    request_asset_path: str | None = None,
) -> tuple[Path, dict[str, Any]]:
    entry = manifest.get(field)
    name = _asset_name(entry, field)
    expected_sha = str(entry.get("sha256") or "")
    expected_size = int(entry.get("size") or 0)

    local: Path | None = None
    if request_asset_path:
        candidate = (cfg.target / request_asset_path).resolve()
        download_root = (cfg.state_dir / "download").resolve()
        if not is_path_within(candidate, download_root):
            raise DeployError(
                "E_ASSET", "asset_path must be inside .deploy/download"
            )
        if candidate.is_file():
            local = candidate
    if local is None:
        candidate = cfg.download_dir / name
        if candidate.is_file():
            local = candidate
    if local is not None:
        if expected_size and local.stat().st_size != expected_size:
            log.warning("local asset size mismatch; downloading a fresh copy")
            local = None
        elif expected_sha and sha256_file(local) != expected_sha:
            log.warning("local asset hash mismatch; downloading a fresh copy")
            local = None

    if local is None:
        local = download(_release_url(cfg, str(manifest["tag"]), name), cfg.download_dir / name, cfg)

    size = local.stat().st_size
    if expected_size and size != expected_size:
        raise DeployError(
            "E_SIZE",
            f"asset {name} has size {size}, expected {expected_size}",
        )
    digest = sha256_file(local)
    if expected_sha and digest != expected_sha:
        raise DeployError(
            "E_SHA", f"asset {name} has sha256 {digest}, expected {expected_sha}"
        )
    return local, entry


def _member_mode(member: tarfile.TarInfo) -> int:
    if member.mode & (0o4000 | 0o2000):
        raise DeployError("E_TAR", f"setuid/setgid bit in {member.name!r}")
    mode = member.mode & 0o777
    if mode == 0:
        mode = 0o644
    return mode


def _extract_file(archive: tarfile.TarFile, member: tarfile.TarInfo, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    source = archive.extractfile(member)
    if source is None:
        raise DeployError("E_TAR", f"cannot read {member.name!r}")
    fd, tmp_name = tempfile.mkstemp(prefix=f".{dest.name}.", dir=str(dest.parent))
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            shutil.copyfileobj(source, handle, length=1024 * 1024)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, _member_mode(member))
        os.replace(tmp, dest)
    finally:
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass


def extract_asset(
    asset: Path,
    staging: Path,
    cfg: Config,
    *,
    allowed_paths: set[str] | None = None,
    allowed_prefixes: tuple[str, ...] | None = None,
    allow_managed: bool = False,
) -> list[str]:
    """Safely extract a release tarball into staging.

    Exactly one of allowed_paths, allowed_prefixes or allow_managed should be
    provided.  The caller decides whether this is a delta (exact paths) or a
    full template (managed paths).
    """
    staging.mkdir(parents=True, exist_ok=True)
    extracted: list[str] = []
    total_bytes = 0
    max_bytes = cfg.max_unpacked_mb * 1024 * 1024

    try:
        with tarfile.open(asset, "r:gz") as archive:
            for member in archive:
                rel = normalize(member.name)
                if member.isdir():
                    if allowed_paths is not None and not any(
                        path == rel or path.startswith(rel + "/") for path in allowed_paths
                    ):
                        raise DeployError("E_TAR", f"unexpected directory in bundle: {rel}")
                    if allowed_prefixes is not None and not any(
                        is_under(rel, prefix) for prefix in allowed_prefixes
                    ):
                        raise DeployError("E_TAR", f"unexpected directory in bundle: {rel}")
                    if allow_managed and not is_managed(rel):
                        if not is_runtime(rel):
                            raise DeployError("E_TAR", f"directory is not managed: {rel}")
                        if rel.startswith(".deploy"):
                            raise DeployError("E_TAR", f"refusing to stage {rel}")
                    (staging / rel).mkdir(parents=True, exist_ok=True)
                    continue

                if not member.isfile():
                    raise DeployError(
                        "E_TAR", f"unsupported archive member type: {rel}"
                    )
                if member.size < 0:
                    raise DeployError("E_TAR", f"invalid size for {rel}")

                if allowed_paths is not None:
                    if rel not in allowed_paths:
                        raise DeployError("E_TAR", f"unexpected file in bundle: {rel}")
                elif allowed_prefixes is not None:
                    if not any(is_under(rel, prefix) for prefix in allowed_prefixes):
                        raise DeployError("E_TAR", f"unexpected file in bundle: {rel}")
                elif allow_managed:
                    if rel.startswith(".deploy"):
                        raise DeployError("E_TAR", f"refusing to stage {rel}")
                    if not (is_managed(rel) or is_runtime(rel)):
                        raise DeployError("E_TAR", f"file is not managed: {rel}")
                else:
                    raise DeployError("E_TAR", "no path policy supplied")

                total_bytes += member.size
                if total_bytes > max_bytes:
                    raise DeployError(
                        "E_SIZE",
                        f"bundle exceeds the {format_bytes(max_bytes)} unpacked limit",
                    )
                if len(extracted) >= cfg.max_files:
                    raise DeployError(
                        "E_SIZE", f"bundle has more than {cfg.max_files} files"
                    )

                dest = staging / rel
                _extract_file(archive, member, dest)
                extracted.append(rel)
    except tarfile.TarError as exc:
        raise DeployError("E_TAR", f"invalid archive: {exc}") from exc
    except PathError as exc:
        raise DeployError("E_TAR", str(exc)) from exc

    if not extracted:
        raise DeployError("E_TAR", "bundle is empty")
    return extracted


def verify_hashes(staging: Path, files: dict[str, str]) -> None:
    for rel, expected in files.items():
        try:
            path = staging / normalize(rel)
        except PathError as exc:
            raise DeployError("E_HASH", str(exc)) from exc
        if not path.is_file():
            raise DeployError("E_HASH", f"file missing from bundle: {rel}")
        actual = sha256_file(path)
        if actual != expected:
            raise DeployError(
                "E_HASH", f"hash mismatch for {rel}: {actual} != {expected}"
            )
