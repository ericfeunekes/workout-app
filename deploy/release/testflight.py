#!/usr/bin/env python3
"""Local TestFlight release runner for Setmark.

The release path is intentionally local and stdlib-only. It is designed for
Codex-operated releases from this Mac: no GitHub macOS CI, no Xcode GUI, no
login-keychain prompts, and no uncommitted source in release artifacts.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import dataclasses
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG_PATHS = (REPO_ROOT / ".release.env", REPO_ROOT / ".env.release")
ASC_API_ROOT = "https://api.appstoreconnect.apple.com/v1"
DEFAULT_RELEASE_ROOT = REPO_ROOT / "scratch" / "qa-runs"
LOGIN_KEYCHAIN_HINTS = ("login.keychain", "login.keychain-db")


class ReleaseError(RuntimeError):
    """A release-blocking error with an operator-readable message."""


@dataclasses.dataclass(frozen=True)
class ReleaseConfig:
    team_id: str
    app_store_app_id: str
    bundle_id: str
    watch_bundle_id: str
    beta_group_id: str
    asc_key_id: str
    asc_issuer_id: str
    asc_key_path: Path
    keychain_path: Path
    sign_identity: str
    ios_profile_name: str
    watch_profile_name: str
    developer_dir: Path
    project_path: Path
    scheme: str
    configuration: str
    archive_path: Path | None
    export_path: Path | None
    release_root: Path
    require_healthkit_entitlement: bool
    expected_internal_tester_count: int | None

    @classmethod
    def from_env(cls, env: dict[str, str]) -> ReleaseConfig:
        return cls(
            team_id=required(env, "SETMARK_RELEASE_TEAM_ID"),
            app_store_app_id=required(env, "SETMARK_RELEASE_APP_STORE_APP_ID"),
            bundle_id=required(env, "SETMARK_RELEASE_BUNDLE_ID"),
            watch_bundle_id=required(env, "SETMARK_RELEASE_WATCH_BUNDLE_ID"),
            beta_group_id=required(env, "SETMARK_RELEASE_BETA_GROUP_ID"),
            asc_key_id=required(env, "SETMARK_RELEASE_ASC_KEY_ID"),
            asc_issuer_id=required(env, "SETMARK_RELEASE_ASC_ISSUER_ID"),
            asc_key_path=Path(required(env, "SETMARK_RELEASE_ASC_KEY_PATH")).expanduser(),
            keychain_path=Path(required(env, "SETMARK_RELEASE_KEYCHAIN_PATH")).expanduser(),
            sign_identity=env.get("SETMARK_RELEASE_SIGN_IDENTITY", "Apple Distribution"),
            ios_profile_name=required(env, "SETMARK_RELEASE_IOS_PROFILE_NAME"),
            watch_profile_name=required(env, "SETMARK_RELEASE_WATCH_PROFILE_NAME"),
            developer_dir=Path(
                env.get(
                    "SETMARK_RELEASE_DEVELOPER_DIR",
                    "/Applications/Xcode-26.5.app/Contents/Developer",
                )
            ).expanduser(),
            project_path=Path(env.get("SETMARK_RELEASE_PROJECT_PATH", "app/WorkoutDB.xcodeproj")),
            scheme=env.get("SETMARK_RELEASE_SCHEME", "WorkoutDB"),
            configuration=env.get("SETMARK_RELEASE_CONFIGURATION", "Release"),
            archive_path=optional_path(env.get("SETMARK_RELEASE_ARCHIVE_PATH")),
            export_path=optional_path(env.get("SETMARK_RELEASE_EXPORT_PATH")),
            release_root=Path(
                env.get("SETMARK_RELEASE_ROOT", str(DEFAULT_RELEASE_ROOT))
            ).expanduser(),
            require_healthkit_entitlement=parse_bool(
                env.get("SETMARK_RELEASE_REQUIRE_HEALTHKIT_ENTITLEMENT", "true")
            ),
            expected_internal_tester_count=optional_int(
                env.get("SETMARK_RELEASE_EXPECTED_INTERNAL_TESTER_COUNT")
            ),
        )


@dataclasses.dataclass(frozen=True)
class BuildVersion:
    marketing: str
    build: str


@dataclasses.dataclass
class ReleaseRun:
    run_id: str
    root: Path
    archive_path: Path
    export_path: Path
    manifest_path: Path
    worktree_path: Path | None
    source_sha: str
    source_ref: str
    version: BuildVersion
    created_at: str
    dirty_ok_reason: str | None = None
    gate_results: list[dict[str, Any]] = dataclasses.field(default_factory=list)
    ipa_path: Path | None = None
    ipa_sha256: str | None = None
    asc_build_id: str | None = None
    readiness: dict[str, Any] = dataclasses.field(default_factory=dict)

    def manifest(self, config: ReleaseConfig) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "created_at": self.created_at,
            "source": {
                "ref": self.source_ref,
                "sha": self.source_sha,
                "dirty_ok_reason": self.dirty_ok_reason,
                "worktree_path": str(self.worktree_path) if self.worktree_path else None,
            },
            "version": dataclasses.asdict(self.version),
            "paths": {
                "run_root": str(self.root),
                "archive": str(self.archive_path),
                "export": str(self.export_path),
                "ipa": str(self.ipa_path) if self.ipa_path else None,
            },
            "xcode": {
                "developer_dir": str(config.developer_dir),
                "project_path": str(config.project_path),
                "scheme": config.scheme,
                "configuration": config.configuration,
            },
            "signing": {
                "team_id": config.team_id,
                "keychain_path": str(config.keychain_path),
                "identity": config.sign_identity,
                "ios_profile_name": config.ios_profile_name,
                "watch_profile_name": config.watch_profile_name,
            },
            "app_store_connect": {
                "key_id": config.asc_key_id,
                "issuer_id": config.asc_issuer_id,
                "app_id": config.app_store_app_id,
                "beta_group_id": config.beta_group_id,
                "build_id": self.asc_build_id,
            },
            "gates": self.gate_results,
            "artifacts": {"ipa_sha256": self.ipa_sha256},
            "readiness": self.readiness,
        }

    def write_manifest(self, config: ReleaseConfig) -> None:
        self.manifest_path.parent.mkdir(parents=True, exist_ok=True)
        self.manifest_path.write_text(json.dumps(self.manifest(config), indent=2) + "\n")


def required(env: dict[str, str], key: str) -> str:
    value = env.get(key, "").strip()
    if not value:
        raise ReleaseError(f"missing required release config: {key}")
    return value


def optional_path(value: str | None) -> Path | None:
    if value is None or not value.strip():
        return None
    return Path(value).expanduser()


def parse_bool(value: str) -> bool:
    return value.strip().lower() not in {"0", "false", "no", "off"}


def optional_int(value: str | None) -> int | None:
    if value is None or not value.strip():
        return None
    return int(value)


def load_env(config_path: Path | None) -> dict[str, str]:
    env = dict(os.environ)
    paths: list[Path] = []
    if config_path is not None:
        paths.append(config_path)
    else:
        paths.extend(path for path in DEFAULT_CONFIG_PATHS if path.exists())

    for path in paths:
        if not path.exists():
            raise ReleaseError(f"release config file not found: {path}")
        mode = path.stat().st_mode & 0o777
        if mode & 0o077:
            raise ReleaseError(f"release config is too permissive: {path}")
        for line in path.read_text().splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if "=" not in stripped:
                raise ReleaseError(f"invalid config line in {path}: {line}")
            key, value = stripped.split("=", 1)
            env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def parse_project_version(text: str) -> BuildVersion:
    marketing_match = re.search(r'CFBundleShortVersionString:\s*"([^"]+)"', text)
    build_matches = re.findall(r'CFBundleVersion:\s*"([^"]+)"', text)
    if marketing_match is None or not build_matches:
        raise ReleaseError("could not read CFBundleShortVersionString/CFBundleVersion")
    if len(set(build_matches)) != 1:
        raise ReleaseError(
            "project.yml has inconsistent CFBundleVersion values: "
            + ", ".join(sorted(set(build_matches)))
        )
    return BuildVersion(marketing=marketing_match.group(1), build=build_matches[0])


def read_project_version(project_yml: Path) -> BuildVersion:
    return parse_project_version(project_yml.read_text())


def bump_project_build(project_yml: Path, new_build: str | None) -> BuildVersion:
    current = read_project_version(project_yml)
    if new_build is None:
        if not current.build.isdigit():
            raise ReleaseError(f"cannot auto-increment non-numeric build: {current.build}")
        new_build = str(int(current.build) + 1)
    if not re.fullmatch(r"[A-Za-z0-9.]+", new_build):
        raise ReleaseError(f"invalid CFBundleVersion: {new_build}")
    text = project_yml.read_text()
    text = re.sub(r'CFBundleVersion:\s*"[^"]+"', f'CFBundleVersion: "{new_build}"', text)
    text = re.sub(
        r'CURRENT_PROJECT_VERSION:\s*"[^"]+"',
        f'CURRENT_PROJECT_VERSION: "{new_build}"',
        text,
    )
    project_yml.write_text(text)
    return BuildVersion(marketing=current.marketing, build=new_build)


def run(
    args: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    dry_run: bool = False,
    capture: bool = False,
    timeout: int | None = None,
) -> subprocess.CompletedProcess[str] | None:
    print("+ " + " ".join(args))
    if dry_run:
        return None
    return subprocess.run(
        args,
        cwd=cwd,
        check=True,
        text=True,
        capture_output=capture,
        env=env,
        timeout=timeout,
    )


def captured(args: list[str], *, cwd: Path = REPO_ROOT, timeout: int = 30) -> str:
    result = subprocess.run(
        args,
        cwd=cwd,
        check=True,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    return result.stdout.strip()


def git_sha(ref: str, *, cwd: Path = REPO_ROOT) -> str:
    return captured(["git", "rev-parse", "--verify", ref], cwd=cwd)


def git_show(ref: str, path: str, *, cwd: Path = REPO_ROOT) -> str:
    return captured(["git", "show", f"{ref}:{path}"], cwd=cwd)


def git_dirty(cwd: Path = REPO_ROOT) -> bool:
    return bool(captured(["git", "status", "--porcelain"], cwd=cwd))


def git_default_branch_ref(cwd: Path = REPO_ROOT) -> str:
    try:
        return captured(
            ["git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
            cwd=cwd,
        )
    except subprocess.CalledProcessError:
        return "origin/main"


def read_project_version_at_ref(ref: str) -> BuildVersion:
    return parse_project_version(git_show(ref, "app/project.yml"))


def create_release_run(
    config: ReleaseConfig,
    version: BuildVersion,
    *,
    release_ref: str,
    dirty_ok_reason: str | None,
) -> ReleaseRun:
    source_sha = git_sha(release_ref)
    now = dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ")
    run_id = f"release-{now}-{version.marketing}-{version.build}"
    root = config.release_root / run_id
    archive_path = config.archive_path or root / "Setmark.xcarchive"
    export_path = config.export_path or root / "export"
    return ReleaseRun(
        run_id=run_id,
        root=root,
        archive_path=archive_path,
        export_path=export_path,
        manifest_path=root / "manifest.json",
        worktree_path=None,
        source_sha=source_sha,
        source_ref=release_ref,
        version=version,
        created_at=dt.datetime.now(dt.UTC).isoformat(),
        dirty_ok_reason=dirty_ok_reason,
    )


@contextlib.contextmanager
def release_worktree(run_state: ReleaseRun, *, dry_run: bool = False) -> Any:
    path = run_state.root / "source"
    run_state.worktree_path = path
    if dry_run:
        yield path
        return
    run(["git", "worktree", "add", "--detach", str(path), run_state.source_sha])
    try:
        yield path
    finally:
        try:
            run(["git", "worktree", "remove", "--force", str(path)])
        except subprocess.CalledProcessError as error:
            print(f"warning: failed to remove release worktree: {error}", file=sys.stderr)


def xcode_env(config: ReleaseConfig) -> dict[str, str]:
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = str(config.developer_dir)
    return env


def export_options(config: ReleaseConfig) -> dict[str, Any]:
    return {
        "method": "app-store-connect",
        "signingStyle": "manual",
        "teamID": config.team_id,
        "signingCertificate": config.sign_identity,
        "stripSwiftSymbols": True,
        "uploadSymbols": True,
        "provisioningProfiles": {
            config.bundle_id: config.ios_profile_name,
            config.watch_bundle_id: config.watch_profile_name,
        },
    }


def write_export_options(config: ReleaseConfig, run_state: ReleaseRun) -> Path:
    path = run_state.root / "ExportOptions.plist"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        plistlib.dump(export_options(config), handle)
    return path


def write_signing_xcconfig(config: ReleaseConfig, run_state: ReleaseRun) -> Path:
    path = run_state.root / "ManualSigning.xcconfig"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "\n".join(
            [
                "CODE_SIGN_STYLE = Manual",
                f"DEVELOPMENT_TEAM = {config.team_id}",
                f"CODE_SIGN_IDENTITY = {config.sign_identity}",
                (f"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*] = {config.ios_profile_name}"),
                (f"PROVISIONING_PROFILE_SPECIFIER[sdk=watchos*] = {config.watch_profile_name}"),
                f"OTHER_CODE_SIGN_FLAGS = --keychain {config.keychain_path}",
                "",
            ]
        )
    )
    return path


def decode_mobileprovision(path: Path) -> dict[str, Any] | None:
    for command in (
        ["security", "cms", "-D", "-i", str(path)],
        ["openssl", "smime", "-verify", "-inform", "DER", "-noverify", "-in", str(path)],
    ):
        plist = decode_mobileprovision_with(command)
        if plist is not None:
            return plist
    return None


def decode_mobileprovision_with(command: list[str]) -> dict[str, Any] | None:
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=False,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        return None
    if result.returncode != 0:
        return None
    try:
        return plistlib.loads(result.stdout)
    except Exception:
        return None


def installed_profiles(profile_name: str) -> list[tuple[Path, dict[str, Any]]]:
    profile_root = Path.home() / "Library/MobileDevice/Provisioning Profiles"
    if not profile_root.exists():
        return []
    matches = []
    for path in profile_root.glob("*.mobileprovision"):
        plist = decode_mobileprovision(path)
        if plist is not None and plist.get("Name") == profile_name:
            matches.append((path, plist))
    return matches


def validate_profile(
    profile_name: str,
    *,
    bundle_id: str,
    team_id: str,
    require_healthkit: bool,
    signing_certificate_sha1: str | None = None,
) -> list[str]:
    matches = installed_profiles(profile_name)
    if not matches:
        return [f"missing installed provisioning profile: {profile_name}"]
    failures: list[str] = []
    now = dt.datetime.now(dt.UTC)
    for path, plist in matches:
        entitlements = plist.get("Entitlements", {})
        app_identifier = entitlements.get("application-identifier", "")
        team_ids = plist.get("TeamIdentifier", [])
        expiration = plist.get("ExpirationDate")
        profile_failures: list[str] = []
        if team_id not in team_ids:
            profile_failures.append(f"team mismatch in {path}")
        expected_app_id = f"{team_id}.{bundle_id}"
        if app_identifier != expected_app_id:
            profile_failures.append(f"bundle mismatch in {path}: {app_identifier}")
        if isinstance(expiration, dt.datetime):
            expiry = expiration if expiration.tzinfo else expiration.replace(tzinfo=dt.UTC)
            if expiry <= now:
                profile_failures.append(f"expired profile: {path}")
        else:
            profile_failures.append(f"missing profile expiration: {path}")
        if require_healthkit and entitlements.get("com.apple.developer.healthkit") is not True:
            profile_failures.append(f"missing HealthKit entitlement: {path}")
        if signing_certificate_sha1 is not None and not profile_includes_certificate(
            plist,
            signing_certificate_sha1,
        ):
            profile_failures.append(
                f"profile does not include signing certificate {signing_certificate_sha1}: {path}"
            )
        if not profile_failures:
            return []
        failures.extend(profile_failures)
    return failures


def profile_includes_certificate(plist: dict[str, Any], sha1_fingerprint: str) -> bool:
    expected = sha1_fingerprint.upper().replace(":", "")
    for certificate in plist.get("DeveloperCertificates", []):
        try:
            digest = hashlib.sha1(bytes(certificate)).hexdigest().upper()
        except TypeError:
            continue
        if digest == expected:
            return True
    return False


def preflight_local(
    config: ReleaseConfig,
    *,
    repo_root: Path = REPO_ROOT,
    skip_codesign: bool = False,
) -> list[str]:
    failures: list[str] = []
    xcodebuild = config.developer_dir / "usr/bin/xcodebuild"

    checks = [
        ((repo_root / "app/project.yml").exists(), f"missing project.yml under {repo_root}/app"),
        (xcodebuild.exists(), f"missing xcodebuild under {config.developer_dir}"),
        (config.keychain_path.exists(), f"missing release keychain: {config.keychain_path}"),
        (config.asc_key_path.exists(), f"missing App Store Connect key: {config.asc_key_path}"),
    ]
    failures.extend(message for ok, message in checks if not ok)

    failures.extend(validate_secret_paths(config))

    if config.asc_key_path.exists():
        mode = config.asc_key_path.stat().st_mode & 0o777
        if mode & 0o077:
            failures.append(
                f"App Store Connect private key is too permissive: {config.asc_key_path}"
            )

    env_paths = [path for path in DEFAULT_CONFIG_PATHS if path.exists()]
    for path in env_paths:
        mode = path.stat().st_mode & 0o777
        if mode & 0o077:
            failures.append(f"release config is too permissive: {path}")

    if any(hint in config.keychain_path.name for hint in LOGIN_KEYCHAIN_HINTS):
        failures.append(f"release keychain must not be the login keychain: {config.keychain_path}")

    signing_fingerprint: str | None = None
    if not skip_codesign and config.keychain_path.exists():
        signing_failures, signing_fingerprint = codesign_preflight(config)
        failures.extend(signing_failures)

    failures.extend(
        validate_profile(
            config.ios_profile_name,
            bundle_id=config.bundle_id,
            team_id=config.team_id,
            require_healthkit=config.require_healthkit_entitlement,
            signing_certificate_sha1=signing_fingerprint,
        )
    )
    failures.extend(
        validate_profile(
            config.watch_profile_name,
            bundle_id=config.watch_bundle_id,
            team_id=config.team_id,
            require_healthkit=False,
            signing_certificate_sha1=signing_fingerprint,
        )
    )

    return failures


def validate_secret_paths(config: ReleaseConfig) -> list[str]:
    failures: list[str] = []
    repo_root = REPO_ROOT.resolve()
    for label, path in {
        "App Store Connect private key": config.asc_key_path,
        "release keychain": config.keychain_path,
    }.items():
        try:
            resolved = path.resolve()
        except FileNotFoundError:
            resolved = path.expanduser().absolute()
        if resolved == repo_root or repo_root in resolved.parents:
            failures.append(f"{label} must not live inside the repo: {path}")
    return failures


def codesign_preflight(config: ReleaseConfig) -> tuple[list[str], str | None]:
    result = subprocess.run(
        [
            "security",
            "find-identity",
            "-v",
            "-p",
            "codesigning",
            str(config.keychain_path),
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )
    if result.returncode != 0:
        return (
            [
                "release keychain is locked or unavailable to security find-identity: "
                + (result.stderr.strip() or result.stdout.strip())
            ],
            None,
        )
    identities = [line for line in result.stdout.splitlines() if config.sign_identity in line]
    if not identities:
        return [f"signing identity not found in release keychain: {config.sign_identity}"], None
    if len(identities) > 1:
        return [
            f"multiple signing identities match in release keychain: {config.sign_identity}"
        ], None
    match = re.search(r"\b([0-9A-Fa-f]{40})\b", identities[0])
    if match is None:
        return [f"could not parse signing identity fingerprint: {identities[0]}"], None
    return [], match.group(1).upper()


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_to_raw_ecdsa(der: bytes) -> bytes:
    if len(der) < 8 or der[0] != 0x30:
        raise ReleaseError("unexpected ECDSA signature DER sequence")
    index = 2
    if der[1] & 0x80:
        length_bytes = der[1] & 0x7F
        index = 2 + length_bytes
    parts: list[bytes] = []
    for _ in range(2):
        if der[index] != 0x02:
            raise ReleaseError("unexpected ECDSA signature integer")
        length = der[index + 1]
        value = der[index + 2 : index + 2 + length].lstrip(b"\x00")
        parts.append(value.rjust(32, b"\x00"))
        index += 2 + length
    return b"".join(parts)


def make_jwt(config: ReleaseConfig, *, now: int | None = None) -> str:
    issued_at = int(time.time() if now is None else now)
    header = {"alg": "ES256", "kid": config.asc_key_id, "typ": "JWT"}
    payload = {
        "iss": config.asc_issuer_id,
        "iat": issued_at,
        "exp": issued_at + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    signing_input = (
        b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(config.asc_key_path)],
        input=signing_input.encode(),
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise ReleaseError(
            "failed to sign App Store Connect JWT non-interactively: "
            + result.stderr.decode(errors="replace").strip()
        )
    return signing_input + "." + b64url(der_to_raw_ecdsa(result.stdout))


def asc_request(
    config: ReleaseConfig,
    method: str,
    path: str,
    *,
    query: dict[str, str] | None = None,
    body: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    url = ASC_API_ROOT + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {make_jwt(config)}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise ReleaseError(f"App Store Connect API {method} {path} failed: {detail}") from error
    except (urllib.error.URLError, TimeoutError) as error:
        raise ReleaseError(f"App Store Connect API {method} {path} failed: {error}") from error
    if not payload:
        return None
    try:
        return json.loads(payload)
    except json.JSONDecodeError as error:
        raise ReleaseError(
            f"App Store Connect API {method} {path} returned invalid JSON"
        ) from error


def asc_paginated(
    config: ReleaseConfig,
    path: str,
    *,
    query: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    next_url: str | None = path
    current_query = dict(query or {})
    data: list[dict[str, Any]] = []
    while next_url:
        if next_url.startswith(ASC_API_ROOT):
            parsed = urllib.parse.urlparse(next_url)
            next_path = parsed.path.removeprefix("/v1")
            page_query = dict(urllib.parse.parse_qsl(parsed.query))
        else:
            next_path = next_url
            page_query = current_query
        response = asc_request(config, "GET", next_path, query=page_query)
        if response is None:
            break
        data.extend(response.get("data", []))
        next_url = response.get("links", {}).get("next")
        current_query = {}
    return data


def build_attrs(build: dict[str, Any]) -> dict[str, Any]:
    return build.get("attributes", {})


def build_number(build: dict[str, Any]) -> str | None:
    attrs = build_attrs(build)
    return attrs.get("version") or attrs.get("buildNumber")


def build_marketing_version(build: dict[str, Any]) -> str | None:
    attrs = build_attrs(build)
    return (
        attrs.get("marketingVersion")
        or attrs.get("preReleaseVersion")
        or attrs.get("appVersion")
        or attrs.get("versionString")
    )


def find_build(config: ReleaseConfig, version: BuildVersion) -> dict[str, Any] | None:
    builds = asc_paginated(
        config,
        "/builds",
        query={
            "filter[app]": config.app_store_app_id,
            "limit": "200",
            "include": "preReleaseVersion",
        },
    )
    matches = [build for build in builds if build_number(build) == version.build]
    marketing_matches = [
        build for build in matches if build_marketing_version(build) in {None, version.marketing}
    ]
    if len(marketing_matches) > 1:
        raise ReleaseError(
            f"App Store Connect returned multiple builds for {version.marketing} ({version.build})"
        )
    return marketing_matches[0] if marketing_matches else None


def assign_build_to_group(config: ReleaseConfig, build_id: str) -> None:
    body = {"data": [{"type": "betaGroups", "id": config.beta_group_id}]}
    try:
        asc_request(config, "POST", f"/builds/{build_id}/relationships/betaGroups", body=body)
    except ReleaseError as error:
        if "RELATIONSHIP_ALREADY_EXISTS" not in str(error):
            raise


def group_build_ids(config: ReleaseConfig) -> set[str]:
    data = asc_paginated(
        config,
        f"/betaGroups/{config.beta_group_id}/relationships/builds",
        query={"limit": "200"},
    )
    return {item["id"] for item in data}


def beta_group(config: ReleaseConfig) -> dict[str, Any] | None:
    return asc_request(config, "GET", f"/betaGroups/{config.beta_group_id}")


def assert_build_number_unused(config: ReleaseConfig, version: BuildVersion) -> None:
    if find_build(config, version) is not None:
        raise ReleaseError(
            f"App Store Connect already has build {version.marketing} ({version.build}); "
            "run `make release-bump-build` and commit the version change"
        )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_gates(
    run_state: ReleaseRun,
    gate_cmds: list[str],
    *,
    cwd: Path,
    dry_run: bool = False,
) -> None:
    for command in gate_cmds:
        started = dt.datetime.now(dt.UTC)
        result = {
            "command": command,
            "cwd": str(cwd),
            "source_sha": run_state.source_sha,
            "started_at": started.isoformat(),
            "dry_run": dry_run,
        }
        print("+ " + command)
        if dry_run:
            result["exit_code"] = 0
        else:
            completed = subprocess.run(shlex.split(command), cwd=cwd, text=True)
            result["exit_code"] = completed.returncode
            if completed.returncode != 0:
                run_state.gate_results.append(result)
                raise ReleaseError(f"release gate failed: {command}")
        result["finished_at"] = dt.datetime.now(dt.UTC).isoformat()
        run_state.gate_results.append(result)


def archive(
    config: ReleaseConfig,
    run_state: ReleaseRun,
    *,
    source_root: Path,
    dry_run: bool = False,
) -> None:
    xcconfig = write_signing_xcconfig(config, run_state)
    run(["make", "xcodegen"], cwd=source_root, dry_run=dry_run)
    run(
        [
            str(config.developer_dir / "usr/bin/xcodebuild"),
            "archive",
            "-project",
            str(source_root / config.project_path),
            "-scheme",
            config.scheme,
            "-configuration",
            config.configuration,
            "-destination",
            "generic/platform=iOS",
            "-archivePath",
            str(run_state.archive_path),
            "-xcconfig",
            str(xcconfig),
        ],
        env=xcode_env(config),
        dry_run=dry_run,
    )


def export_archive(
    config: ReleaseConfig,
    run_state: ReleaseRun,
    *,
    dry_run: bool = False,
) -> Path:
    options = write_export_options(config, run_state)
    run(
        [
            str(config.developer_dir / "usr/bin/xcodebuild"),
            "-exportArchive",
            "-archivePath",
            str(run_state.archive_path),
            "-exportPath",
            str(run_state.export_path),
            "-exportOptionsPlist",
            str(options),
        ],
        env=xcode_env(config),
        dry_run=dry_run,
    )
    ipa_path = run_state.export_path / "WorkoutDB.ipa"
    run_state.ipa_path = ipa_path
    if not dry_run and not ipa_path.exists():
        raise ReleaseError(f"IPA not found after export: {ipa_path}")
    if not dry_run:
        run_state.ipa_sha256 = sha256_file(ipa_path)
    return ipa_path


def upload_manifest_ipa(
    config: ReleaseConfig,
    run_state: ReleaseRun,
    *,
    dry_run: bool = False,
) -> None:
    if run_state.ipa_path is None:
        raise ReleaseError("manifest has no IPA path to upload")
    if not dry_run:
        if not run_state.ipa_path.exists():
            raise ReleaseError(f"IPA not found: {run_state.ipa_path}")
        actual_sha = sha256_file(run_state.ipa_path)
        if actual_sha != run_state.ipa_sha256:
            raise ReleaseError("refusing to upload IPA whose SHA-256 differs from manifest")
    run(
        [
            str(config.developer_dir / "usr/bin/xcrun"),
            "altool",
            "--upload-app",
            "--type",
            "ios",
            "-f",
            str(run_state.ipa_path),
            "--apiKey",
            config.asc_key_id,
            "--apiIssuer",
            config.asc_issuer_id,
        ],
        env=xcode_env(config),
        dry_run=dry_run,
    )


def wait_for_build(config: ReleaseConfig, version: BuildVersion) -> dict[str, Any]:
    deadline = time.time() + 30 * 60
    while time.time() < deadline:
        build = find_build(config, version)
        if build is not None:
            state = build_attrs(build).get("processingState")
            if state == "VALID":
                return build
            if state in {"FAILED", "INVALID"}:
                raise ReleaseError(f"App Store Connect build processing failed with state {state}")
            print(f"App Store Connect build is {state}; waiting 30s")
        else:
            print("App Store Connect build not visible yet; waiting 30s")
        time.sleep(30)
    raise ReleaseError(f"timed out waiting for build {version.marketing} ({version.build})")


def first_present(attrs: dict[str, Any], keys: tuple[str, ...]) -> Any:
    for key in keys:
        if key in attrs:
            return attrs[key]
    return None


def readiness(config: ReleaseConfig, build: dict[str, Any]) -> dict[str, Any]:
    attrs = build_attrs(build)
    groups = group_build_ids(config)
    group = beta_group(config) or {}
    group_attrs = group.get("data", {}).get("attributes", {}) if group else {}
    beta_review_state = attrs.get("betaReviewState")
    compliance = (
        attrs.get("usesNonExemptEncryption")
        if "usesNonExemptEncryption" in attrs
        else attrs.get("appEncryptionDeclarationState")
    )
    assigned = build["id"] in groups
    tester_count = first_present(
        group_attrs,
        ("testerCount", "betaTesterCount", "betaTestersCount", "internalTesterCount"),
    )
    expected_tester_count = config.expected_internal_tester_count
    tester_count_matches = expected_tester_count is None or tester_count == expected_tester_count
    processing_valid = attrs.get("processingState") == "VALID"
    not_expired = attrs.get("expired") is False
    compliance_answered = compliance is not None
    ready = (
        processing_valid
        and assigned
        and not_expired
        and compliance_answered
        and tester_count_matches
    )
    blockers: list[str] = []
    if not processing_valid:
        blockers.append("processing_not_valid")
    if not assigned:
        blockers.append("not_assigned_to_internal_group")
    if not not_expired:
        blockers.append("expired_or_unknown")
    if not compliance_answered:
        blockers.append("compliance_unknown")
    if not tester_count_matches:
        blockers.append("tester_count_mismatch")
    return {
        "verdict": "ready" if ready else "blocked",
        "blockers": blockers,
        "processingState": attrs.get("processingState"),
        "expired": attrs.get("expired"),
        "betaReviewState": beta_review_state,
        "compliance": compliance,
        "assignedToInternalGroup": assigned,
        "betaGroup": {
            "id": config.beta_group_id,
            "name": group_attrs.get("name"),
            "publicLinkEnabled": group_attrs.get("publicLinkEnabled"),
            "testerCount": tester_count,
            "expectedTesterCount": expected_tester_count,
        },
        "observedGroupBuildCount": len(groups),
    }


def assert_ready_state(state: dict[str, Any]) -> None:
    if state.get("verdict") != "ready":
        blockers = state.get("blockers") or ["unknown"]
        raise ReleaseError("TestFlight readiness blocked: " + ", ".join(blockers))


def command_preflight(config: ReleaseConfig, *, skip_remote: bool, release_ref: str) -> None:
    source_sha = git_sha(release_ref)
    version = read_project_version_at_ref(release_ref)
    failures = preflight_local(config)
    if not skip_remote:
        try:
            assert_build_number_unused(config, version)
        except ReleaseError as error:
            failures.append(str(error))
    if failures:
        raise ReleaseError("release preflight failed:\n- " + "\n- ".join(failures))
    print(f"release preflight passed for {version.marketing} ({version.build}) at {source_sha}")


def command_status(
    config: ReleaseConfig,
    *,
    version: str | None = None,
    build_number_value: str | None = None,
) -> None:
    current = read_project_version(REPO_ROOT / "app/project.yml")
    target = BuildVersion(version or current.marketing, build_number_value or current.build)
    build = find_build(config, target)
    if build is None:
        raise ReleaseError(f"build not found in App Store Connect: {target}")
    attrs = build_attrs(build)
    state = readiness(config, build)
    print(
        json.dumps(
            {
                "build_id": build["id"],
                "marketingVersion": target.marketing,
                "buildNumber": build_number(build),
                "processingState": attrs.get("processingState"),
                "expired": attrs.get("expired"),
                **state,
            },
            indent=2,
        )
    )


def command_release(
    config: ReleaseConfig,
    *,
    dry_run: bool,
    release_ref: str,
    dirty_ok_reason: str | None,
    gate_cmds: list[str],
    gate_override_reason: str | None,
) -> None:
    if git_dirty() and dirty_ok_reason is None:
        raise ReleaseError("release requires a clean git tree or --dirty-ok <reason>")
    version = read_project_version_at_ref(release_ref)
    run_state = create_release_run(
        config,
        version,
        release_ref=release_ref,
        dirty_ok_reason=dirty_ok_reason,
    )
    run_state.root.mkdir(parents=True, exist_ok=True)
    failures = preflight_local(config)
    try:
        assert_build_number_unused(config, version)
    except ReleaseError as error:
        failures.append(str(error))
    if failures:
        raise ReleaseError("release preflight failed:\n- " + "\n- ".join(failures))

    if not gate_cmds and gate_override_reason is None:
        raise ReleaseError("release requires --gate-cmd or --gate-override <reason>")
    with release_worktree(run_state, dry_run=dry_run) as source_root:
        if gate_override_reason is not None:
            run_state.gate_results.append({"override_reason": gate_override_reason})
        run_gates(run_state, gate_cmds, cwd=source_root, dry_run=dry_run)
        run_state.write_manifest(config)
        archive(config, run_state, source_root=source_root, dry_run=dry_run)
        export_archive(config, run_state, dry_run=dry_run)
        run_state.write_manifest(config)
        upload_manifest_ipa(config, run_state, dry_run=dry_run)
        if dry_run:
            run_state.write_manifest(config)
            print(f"dry-run release manifest: {run_state.manifest_path}")
            return
        build = wait_for_build(config, version)
        run_state.asc_build_id = build["id"]
        if build["id"] not in group_build_ids(config):
            assign_build_to_group(config, build["id"])
        build = find_build(config, version) or build
        run_state.readiness = readiness(config, build)
        run_state.write_manifest(config)
        assert_ready_state(run_state.readiness)
    print(
        f"released TestFlight build {version.marketing} "
        f"({version.build}) as {run_state.asc_build_id}"
    )
    print(f"manifest: {run_state.manifest_path}")


def command_resume(config: ReleaseConfig, manifest_path: Path, *, dry_run: bool) -> None:
    manifest = json.loads(manifest_path.read_text())
    version_data = manifest["version"]
    version = BuildVersion(marketing=version_data["marketing"], build=version_data["build"])
    build = find_build(config, version)
    if build is None:
        raise ReleaseError(f"cannot resume; build not found in App Store Connect: {version}")
    if not dry_run and build["id"] not in group_build_ids(config):
        assign_build_to_group(config, build["id"])
        build = find_build(config, version) or build
    manifest["app_store_connect"]["build_id"] = build["id"]
    manifest["readiness"] = readiness(config, build)
    if not dry_run:
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    assert_ready_state(manifest["readiness"])
    print(json.dumps(manifest["readiness"], indent=2))


def command_bump_build(config: ReleaseConfig | None, new_build: str | None) -> None:
    project_yml = REPO_ROOT / "app/project.yml"
    if new_build is None and config is not None:
        current = read_project_version(project_yml)
        used = {
            build_number(build)
            for build in asc_paginated(
                config,
                "/builds",
                query={"filter[app]": config.app_store_app_id, "limit": "200"},
            )
        }
        if current.build.isdigit():
            candidate = int(current.build) + 1
            while str(candidate) in used:
                candidate += 1
            new_build = str(candidate)
    version = bump_project_build(project_yml, new_build)
    print(f"bumped project build to {version.marketing} ({version.build})")
    print("commit app/project.yml before running release, or pass --dirty-ok with a reason")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Setmark TestFlight release runner")
    parser.add_argument("--config", type=Path, help="Path to a release env file")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print commands without running them",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    preflight = subparsers.add_parser("preflight")
    preflight.add_argument(
        "--skip-remote",
        action="store_true",
        help="Skip App Store Connect duplicate-build checks",
    )
    preflight.add_argument("--release-ref", default="HEAD")

    bump = subparsers.add_parser("bump-build")
    bump.add_argument("--to", dest="new_build")

    status = subparsers.add_parser("status")
    status.add_argument("--version")
    status.add_argument("--build")

    release = subparsers.add_parser("release")
    release.add_argument("--release-ref", default="HEAD")
    release.add_argument("--dirty-ok")
    release.add_argument("--gate-cmd", action="append", default=[])
    release.add_argument("--gate-override")

    resume = subparsers.add_parser("resume")
    resume.add_argument("--manifest", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        config: ReleaseConfig | None = None
        if args.command != "bump-build" or args.new_build is None:
            config = ReleaseConfig.from_env(load_env(args.config))
        if args.command == "bump-build":
            command_bump_build(config, args.new_build)
            return 0
        assert config is not None
        if args.command == "preflight":
            command_preflight(config, skip_remote=args.skip_remote, release_ref=args.release_ref)
        elif args.command == "status":
            command_status(config, version=args.version, build_number_value=args.build)
        elif args.command == "release":
            command_release(
                config,
                dry_run=args.dry_run,
                release_ref=args.release_ref,
                dirty_ok_reason=args.dirty_ok,
                gate_cmds=args.gate_cmd,
                gate_override_reason=args.gate_override,
            )
        elif args.command == "resume":
            command_resume(config, args.manifest, dry_run=args.dry_run)
    except (ReleaseError, subprocess.CalledProcessError, TimeoutError) as error:
        print(f"release error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
