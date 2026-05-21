from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "deploy/release/testflight.py"
spec = importlib.util.spec_from_file_location("testflight_release", MODULE_PATH)
assert spec is not None and spec.loader is not None
testflight = importlib.util.module_from_spec(spec)
sys.modules["testflight_release"] = testflight
spec.loader.exec_module(testflight)


def valid_env(tmp_path: Path) -> dict[str, str]:
    key = tmp_path / "AuthKey_TEST.p8"
    key.write_text("private key placeholder")
    key.chmod(0o600)
    keychain = tmp_path / "release.keychain-db"
    keychain.write_text("keychain placeholder")
    return {
        "SETMARK_RELEASE_TEAM_ID": "TEAMID1234",
        "SETMARK_RELEASE_APP_STORE_APP_ID": "1234567890",
        "SETMARK_RELEASE_BUNDLE_ID": "com.example.App",
        "SETMARK_RELEASE_WATCH_BUNDLE_ID": "com.example.App.watchkitapp",
        "SETMARK_RELEASE_BETA_GROUP_ID": "group-id",
        "SETMARK_RELEASE_ASC_KEY_ID": "KEYID12345",
        "SETMARK_RELEASE_ASC_ISSUER_ID": "issuer-id",
        "SETMARK_RELEASE_ASC_KEY_PATH": str(key),
        "SETMARK_RELEASE_KEYCHAIN_PATH": str(keychain),
        "SETMARK_RELEASE_IOS_PROFILE_NAME": "iOS Profile",
        "SETMARK_RELEASE_WATCH_PROFILE_NAME": "Watch Profile",
    }


def test_release_config_requires_non_repo_secret_paths(tmp_path: Path) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))

    assert config.asc_key_path == tmp_path / "AuthKey_TEST.p8"
    assert config.keychain_path == tmp_path / "release.keychain-db"
    assert config.keychain_password_path is None
    assert config.signing_p12_path is None
    assert config.signing_p12_password_path is None
    assert config.signing_chain_paths == ()
    assert config.sign_identity == "Apple Distribution"
    assert config.uses_non_exempt_encryption is False


def test_release_config_reads_signing_repair_paths(tmp_path: Path) -> None:
    env = valid_env(tmp_path)
    password = tmp_path / "keychain.password"
    p12 = tmp_path / "signing.p12"
    password.write_text("password")
    p12.write_text("p12")
    password.chmod(0o600)
    p12.chmod(0o600)
    env["SETMARK_RELEASE_KEYCHAIN_PASSWORD_PATH"] = str(password)
    env["SETMARK_RELEASE_SIGNING_P12_PATH"] = str(p12)
    env["SETMARK_RELEASE_SIGNING_P12_PASSWORD_PATH"] = str(password)

    config = testflight.ReleaseConfig.from_env(env)

    assert config.keychain_password_path == password
    assert config.signing_p12_path == p12
    assert config.signing_p12_password_path == password


def test_release_config_reads_signing_chain_paths(tmp_path: Path) -> None:
    env = valid_env(tmp_path)
    first = tmp_path / "AppleWWDRCAG3.cer"
    second = tmp_path / "AppleRootCA.cer"
    first.write_text("cert")
    second.write_text("cert")
    env["SETMARK_RELEASE_SIGNING_CHAIN_PATHS"] = f"{first}:{second}"

    config = testflight.ReleaseConfig.from_env(env)

    assert config.signing_chain_paths == (first, second)


def test_release_config_fails_when_required_value_missing(tmp_path: Path) -> None:
    env = valid_env(tmp_path)
    env.pop("SETMARK_RELEASE_ASC_KEY_PATH")

    with pytest.raises(testflight.ReleaseError, match="SETMARK_RELEASE_ASC_KEY_PATH"):
        testflight.ReleaseConfig.from_env(env)


def test_project_version_reads_project_yml() -> None:
    version = testflight.read_project_version(REPO_ROOT / "app/project.yml")

    assert version.marketing
    assert version.build


def test_project_version_rejects_inconsistent_build_values(tmp_path: Path) -> None:
    project = tmp_path / "project.yml"
    project.write_text(
        'CFBundleShortVersionString: "0.0.1"\nCFBundleVersion: "1"\nCFBundleVersion: "2"\n'
    )

    with pytest.raises(testflight.ReleaseError, match="inconsistent"):
        testflight.read_project_version(project)


def test_bump_project_build_updates_every_bundle_version(tmp_path: Path) -> None:
    project = tmp_path / "project.yml"
    project.write_text(
        'CFBundleShortVersionString: "0.0.1"\n'
        'CFBundleVersion: "1"\n'
        "name: watch\n"
        'CFBundleVersion: "1"\n'
    )

    version = testflight.bump_project_build(project, None)

    assert version == testflight.BuildVersion(marketing="0.0.1", build="2")
    assert project.read_text().count('CFBundleVersion: "2"') == 2


def test_export_options_pin_manual_signing_and_profiles(tmp_path: Path) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    options = testflight.export_options(config)

    assert options["method"] == "app-store-connect"
    assert options["signingStyle"] == "manual"
    assert options["provisioningProfiles"] == {
        "com.example.App": "iOS Profile",
        "com.example.App.watchkitapp": "Watch Profile",
    }


def test_app_store_connect_signature_der_converts_to_raw_p1363() -> None:
    der = bytes.fromhex(
        "3046022100"
        "dff1d77f2a671c5f36183726db2341be58feae1da2dec6a37a522a69b010f80b"
        "022100"
        "f23f25191d34b5f5d3cb19d68eab3bfad7f8f03e8e2f80641d26e5d3b54ccf2a"
    )
    raw = testflight.der_to_raw_ecdsa(der)

    assert len(raw) == 64
    assert raw[:4] == bytes.fromhex("dff1d77f")
    assert raw[32:36] == bytes.fromhex("f23f2519")


def test_no_private_key_material_in_example_config() -> None:
    example = (REPO_ROOT / "deploy/release/testflight.env.example").read_text()

    assert "BEGIN PRIVATE KEY" not in example
    assert "5B5JYBD64U" not in example


def test_manifest_omits_private_key_material(tmp_path: Path) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    run_state = testflight.ReleaseRun(
        run_id="release-test",
        root=tmp_path / "release-test",
        archive_path=tmp_path / "release-test" / "Setmark.xcarchive",
        export_path=tmp_path / "release-test" / "export",
        manifest_path=tmp_path / "release-test" / "manifest.json",
        worktree_path=tmp_path / "release-test" / "source",
        source_sha="abc123",
        source_ref="HEAD",
        version=testflight.BuildVersion(marketing="0.0.1", build="2"),
        created_at="2026-05-19T00:00:00+00:00",
    )

    manifest = run_state.manifest(config)
    encoded = str(manifest)

    assert "private key placeholder" not in encoded
    assert str(config.asc_key_path) not in encoded
    assert manifest["app_store_connect"]["key_id"] == "KEYID12345"
    assert manifest["created_at"] == "2026-05-19T00:00:00+00:00"


def test_upload_refuses_ipa_that_does_not_match_manifest_hash(tmp_path: Path) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    ipa = tmp_path / "WorkoutDB.ipa"
    ipa.write_text("new bytes")
    run_state = testflight.ReleaseRun(
        run_id="release-test",
        root=tmp_path,
        archive_path=tmp_path / "Setmark.xcarchive",
        export_path=tmp_path,
        manifest_path=tmp_path / "manifest.json",
        worktree_path=None,
        source_sha="abc123",
        source_ref="HEAD",
        version=testflight.BuildVersion(marketing="0.0.1", build="2"),
        created_at="2026-05-19T00:00:00+00:00",
        ipa_path=ipa,
        ipa_sha256="not-the-real-hash",
    )

    with pytest.raises(testflight.ReleaseError, match="SHA-256"):
        testflight.upload_manifest_ipa(config, run_state)


def test_upload_uses_system_xcrun_with_selected_developer_dir(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    ipa = tmp_path / "WorkoutDB.ipa"
    ipa.write_text("ipa bytes")
    run_state = testflight.ReleaseRun(
        run_id="release-test",
        root=tmp_path,
        archive_path=tmp_path / "Setmark.xcarchive",
        export_path=tmp_path,
        manifest_path=tmp_path / "manifest.json",
        worktree_path=None,
        source_sha="abc123",
        source_ref="HEAD",
        version=testflight.BuildVersion(marketing="0.0.1", build="2"),
        created_at="2026-05-19T00:00:00+00:00",
        ipa_path=ipa,
        ipa_sha256=testflight.sha256_file(ipa),
    )
    calls: list[tuple[list[str], dict[str, str] | None]] = []

    def capture_run(
        command: list[str],
        *,
        cwd: Path | None = None,
        env: dict[str, str] | None = None,
        dry_run: bool = False,
        input_bytes: bytes | None = None,
    ) -> None:
        calls.append((command, env))

    monkeypatch.setattr(testflight, "run", capture_run)

    testflight.upload_manifest_ipa(config, run_state)

    assert calls == [
        (
            [
                "/usr/bin/xcrun",
                "altool",
                "--upload-app",
                "--type",
                "ios",
                "-f",
                str(ipa),
                "--apiKey",
                config.asc_key_id,
                "--apiIssuer",
                config.asc_issuer_id,
            ],
            testflight.xcode_env(config),
        )
    ]


def test_release_requires_clean_tree_or_dirty_reason(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    monkeypatch.setattr(testflight, "git_dirty", lambda: True)

    with pytest.raises(testflight.ReleaseError, match="clean git tree"):
        testflight.command_release(
            config,
            dry_run=True,
            release_ref="HEAD",
            dirty_ok_reason=None,
            gate_cmds=[],
            gate_override_reason="tool validation",
        )


def test_release_requires_gate_or_override(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    monkeypatch.setattr(testflight, "git_dirty", lambda: False)
    monkeypatch.setattr(testflight, "git_sha", lambda _ref: "abc123")
    monkeypatch.setattr(
        testflight,
        "read_project_version_at_ref",
        lambda _ref: testflight.BuildVersion(marketing="0.0.1", build="2"),
    )
    monkeypatch.setattr(testflight, "preflight_local", lambda _config: [])
    monkeypatch.setattr(testflight, "assert_build_number_unused", lambda _config, _version: None)

    with pytest.raises(testflight.ReleaseError, match="gate-cmd"):
        testflight.command_release(
            config,
            dry_run=True,
            release_ref="HEAD",
            dirty_ok_reason=None,
            gate_cmds=[],
            gate_override_reason=None,
        )


def test_release_reads_version_from_release_ref(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    observed: dict[str, str] = {}

    monkeypatch.setattr(testflight, "git_dirty", lambda: False)
    monkeypatch.setattr(testflight, "git_sha", lambda _ref: "abc123")
    monkeypatch.setattr(
        testflight,
        "read_project_version_at_ref",
        lambda ref: (
            observed.setdefault("ref", ref)
            and testflight.BuildVersion(marketing="9.9.9", build="42")
        ),
    )
    monkeypatch.setattr(testflight, "preflight_local", lambda _config: [])
    monkeypatch.setattr(testflight, "assert_build_number_unused", lambda _config, _version: None)

    with pytest.raises(testflight.ReleaseError, match="gate-cmd"):
        testflight.command_release(
            config,
            dry_run=True,
            release_ref="main",
            dirty_ok_reason=None,
            gate_cmds=[],
            gate_override_reason=None,
        )

    assert observed["ref"] == "main"


def test_run_gates_execute_in_release_worktree(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    run_state = testflight.create_release_run(
        testflight.ReleaseConfig.from_env(valid_env(tmp_path)),
        testflight.BuildVersion(marketing="0.0.1", build="2"),
        release_ref="HEAD",
        dirty_ok_reason=None,
    )
    source_root = tmp_path / "source"
    observed: dict[str, Path] = {}

    class Completed:
        returncode = 0

    def fake_run(args: list[str], *, cwd: Path, text: bool) -> Completed:
        del args, text
        observed["cwd"] = cwd
        return Completed()

    monkeypatch.setattr(testflight.subprocess, "run", fake_run)

    testflight.run_gates(run_state, ["make pre-qa"], cwd=source_root)

    assert observed["cwd"] == source_root
    assert run_state.gate_results[0]["cwd"] == str(source_root)


def test_preflight_rejects_repo_local_secret_paths(tmp_path: Path) -> None:
    env = valid_env(tmp_path)
    env["SETMARK_RELEASE_ASC_KEY_PATH"] = str(REPO_ROOT / "AuthKey_TEST.p8")
    config = testflight.ReleaseConfig.from_env(env)

    failures = testflight.validate_secret_paths(config)

    assert any("must not live inside the repo" in failure for failure in failures)


def test_signing_repair_requires_complete_non_repo_secret_paths(tmp_path: Path) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))

    failures = testflight.prepare_release_keychain(config)

    assert failures == [
        "SETMARK_RELEASE_KEYCHAIN_PASSWORD_PATH is required for release preflight",
    ]


def test_signing_repair_requires_complete_repair_secret_paths(tmp_path: Path) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))

    failures = testflight.validate_signing_repair_config(config)

    assert failures == [
        "SETMARK_RELEASE_KEYCHAIN_PASSWORD_PATH is required for release preflight",
        "SETMARK_RELEASE_SIGNING_P12_PATH is required for signing repair",
        "SETMARK_RELEASE_SIGNING_P12_PASSWORD_PATH is required for signing repair",
    ]


def test_signing_repair_reports_partial_secret_paths(tmp_path: Path) -> None:
    env = valid_env(tmp_path)
    password = tmp_path / "keychain.password"
    password.write_text("password")
    password.chmod(0o600)
    env["SETMARK_RELEASE_KEYCHAIN_PASSWORD_PATH"] = str(password)
    config = testflight.ReleaseConfig.from_env(env)

    failures = testflight.validate_signing_repair_config(config)

    assert failures == [
        "SETMARK_RELEASE_SIGNING_P12_PATH is required for signing repair",
        "SETMARK_RELEASE_SIGNING_P12_PASSWORD_PATH is required for signing repair",
    ]


def test_preflight_unlocks_but_does_not_rebuild_when_identity_is_missing(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    env = valid_env(tmp_path)
    password = tmp_path / "keychain.password"
    password.write_text("password")
    password.chmod(0o600)
    env["SETMARK_RELEASE_KEYCHAIN_PASSWORD_PATH"] = str(password)
    config = testflight.ReleaseConfig.from_env(env)
    calls: list[str] = []

    monkeypatch.setattr(
        testflight,
        "unlock_release_keychain",
        lambda _config: calls.append("unlock"),
    )
    monkeypatch.setattr(
        testflight,
        "rebuild_release_keychain",
        lambda _config: calls.append("rebuild"),
    )

    failures = testflight.prepare_release_keychain(config)

    assert failures == []
    assert calls == ["unlock"]


def test_command_preflight_fails_without_repairing_missing_identity(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    env = valid_env(tmp_path)
    password = tmp_path / "keychain.password"
    password.write_text("password")
    password.chmod(0o600)
    env["SETMARK_RELEASE_KEYCHAIN_PASSWORD_PATH"] = str(password)
    config = testflight.ReleaseConfig.from_env(env)
    calls: list[str] = []

    monkeypatch.setattr(testflight, "git_sha", lambda _ref: "abc123")
    monkeypatch.setattr(
        testflight,
        "read_project_version_at_ref",
        lambda _ref: testflight.BuildVersion(marketing="0.0.1", build="3"),
    )
    monkeypatch.setattr(testflight, "unlock_release_keychain", lambda _config: None)
    monkeypatch.setattr(
        testflight,
        "rebuild_release_keychain",
        lambda _config: calls.append("rebuild"),
    )
    monkeypatch.setattr(
        testflight,
        "codesign_preflight",
        lambda _config: (["signing identity not found in release keychain"], None),
    )
    monkeypatch.setattr(testflight, "validate_profile", lambda *args, **kwargs: [])

    with pytest.raises(testflight.ReleaseError, match="release preflight failed"):
        testflight.command_preflight(config, skip_remote=True, release_ref="ecaff57")

    assert calls == []


def test_signing_repair_keeps_existing_keychain_when_candidate_fails(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    env = valid_env(tmp_path)
    password = tmp_path / "keychain.password"
    p12 = tmp_path / "signing.p12"
    password.write_text("password")
    p12.write_text("p12")
    password.chmod(0o600)
    p12.chmod(0o600)
    env["SETMARK_RELEASE_KEYCHAIN_PASSWORD_PATH"] = str(password)
    env["SETMARK_RELEASE_SIGNING_P12_PATH"] = str(p12)
    env["SETMARK_RELEASE_SIGNING_P12_PASSWORD_PATH"] = str(password)
    config = testflight.ReleaseConfig.from_env(env)
    config.keychain_path.write_text("original")
    security_calls: list[list[str]] = []

    def fake_security(args: list[str], *, check: bool = True) -> object:
        del check
        security_calls.append(args)
        if args[1:4] == ["list-keychains", "-d", "user"] and "-s" not in args:
            return type("Completed", (), {"stdout": f'"{config.keychain_path}"\n'})()
        if args[1] == "create-keychain":
            testflight.physical_keychain_path(Path(args[-1])).write_text("candidate")
        return object()

    monkeypatch.setattr(testflight, "security_quiet", fake_security)
    monkeypatch.setattr(testflight, "codesign_preflight", lambda _config: (["not usable"], None))

    with pytest.raises(testflight.ReleaseError, match="not usable"):
        testflight.rebuild_release_keychain(config)

    assert config.keychain_path.read_text() == "original"
    assert any(call[1] == "delete-keychain" for call in security_calls)
    assert not list(tmp_path.glob("release.candidate-*.keychain-db"))


def test_command_repair_signing_rebuilds_explicitly(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    env = valid_env(tmp_path)
    password = tmp_path / "keychain.password"
    p12 = tmp_path / "signing.p12"
    password.write_text("password")
    p12.write_text("p12")
    password.chmod(0o600)
    p12.chmod(0o600)
    env["SETMARK_RELEASE_KEYCHAIN_PASSWORD_PATH"] = str(password)
    env["SETMARK_RELEASE_SIGNING_P12_PATH"] = str(p12)
    env["SETMARK_RELEASE_SIGNING_P12_PASSWORD_PATH"] = str(password)
    config = testflight.ReleaseConfig.from_env(env)
    calls: list[str] = []

    monkeypatch.setattr(
        testflight,
        "rebuild_release_keychain",
        lambda _config: calls.append("rebuild"),
    )
    monkeypatch.setattr(
        testflight,
        "codesign_preflight",
        lambda _config: ([], "99EAB1BF5E2B37C62C465831AFC05427936039D2"),
    )

    testflight.command_repair_signing(config)

    assert calls == ["rebuild"]


def test_signing_repair_rejects_profile_incompatible_candidate(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    env = valid_env(tmp_path)
    password = tmp_path / "keychain.password"
    p12 = tmp_path / "signing.p12"
    password.write_text("password")
    p12.write_text("p12")
    password.chmod(0o600)
    p12.chmod(0o600)
    env["SETMARK_RELEASE_KEYCHAIN_PASSWORD_PATH"] = str(password)
    env["SETMARK_RELEASE_SIGNING_P12_PATH"] = str(p12)
    env["SETMARK_RELEASE_SIGNING_P12_PASSWORD_PATH"] = str(password)
    config = testflight.ReleaseConfig.from_env(env)
    config.keychain_path.write_text("original")
    security_calls: list[list[str]] = []

    def fake_security(args: list[str], *, check: bool = True) -> object:
        del check
        security_calls.append(args)
        if args[1:4] == ["list-keychains", "-d", "user"] and "-s" not in args:
            return type("Completed", (), {"stdout": f'"{config.keychain_path}"\n'})()
        if args[1] == "create-keychain":
            testflight.physical_keychain_path(Path(args[-1])).write_text("candidate")
        return object()

    monkeypatch.setattr(testflight, "security_quiet", fake_security)
    monkeypatch.setattr(
        testflight,
        "codesign_preflight",
        lambda _config: ([], "99EAB1BF5E2B37C62C465831AFC05427936039D2"),
    )
    monkeypatch.setattr(
        testflight,
        "validate_release_profiles_for_signing",
        lambda *_args: ["profile does not include signing certificate"],
    )

    with pytest.raises(testflight.ReleaseError, match="profile does not include"):
        testflight.rebuild_release_keychain(config)

    assert config.keychain_path.read_text() == "original"
    assert any(call[1] == "delete-keychain" for call in security_calls)


def test_replace_release_keychain_rolls_back_when_candidate_swap_fails(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    keychain = tmp_path / "release.keychain-db"
    candidate = tmp_path / "release.candidate.keychain"
    physical_candidate = tmp_path / "release.candidate.keychain-db"
    keychain.write_text("original")
    physical_candidate.write_text("candidate")
    original_rename = Path.rename

    def fake_rename(self: Path, target: Path) -> Path:
        if self == physical_candidate:
            raise OSError("swap failed")
        return original_rename(self, target)

    monkeypatch.setattr(Path, "rename", fake_rename)

    with pytest.raises(OSError, match="swap failed"):
        testflight.replace_release_keychain(keychain, candidate)

    assert keychain.read_text() == "original"
    assert physical_candidate.read_text() == "candidate"
    assert not list(tmp_path.glob("release.keychain-db.bak-*"))


def test_rebuild_release_keychain_rolls_back_when_final_swap_fails(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    env = valid_env(tmp_path)
    password = tmp_path / "keychain.password"
    p12 = tmp_path / "signing.p12"
    password.write_text("password")
    p12.write_text("p12")
    password.chmod(0o600)
    p12.chmod(0o600)
    env["SETMARK_RELEASE_KEYCHAIN_PASSWORD_PATH"] = str(password)
    env["SETMARK_RELEASE_SIGNING_P12_PATH"] = str(p12)
    env["SETMARK_RELEASE_SIGNING_P12_PASSWORD_PATH"] = str(password)
    config = testflight.ReleaseConfig.from_env(env)
    config.keychain_path.write_text("original")

    def fake_security(args: list[str], *, check: bool = True) -> object:
        del check
        if args[1:4] == ["list-keychains", "-d", "user"] and "-s" not in args:
            return type("Completed", (), {"stdout": f'"{config.keychain_path}"\n'})()
        if args[1] == "create-keychain":
            testflight.physical_keychain_path(Path(args[-1])).write_text("candidate")
        return object()

    original_rename = Path.rename

    def fake_rename(self: Path, target: Path) -> Path:
        if ".candidate-" in self.name and self.name.endswith(".keychain-db"):
            raise OSError("swap failed")
        return original_rename(self, target)

    monkeypatch.setattr(testflight, "security_quiet", fake_security)
    monkeypatch.setattr(
        testflight,
        "codesign_preflight",
        lambda _config: ([], "99EAB1BF5E2B37C62C465831AFC05427936039D2"),
    )
    monkeypatch.setattr(testflight, "validate_release_profiles_for_signing", lambda *_args: [])
    monkeypatch.setattr(Path, "rename", fake_rename)

    with pytest.raises(OSError, match="swap failed"):
        testflight.rebuild_release_keychain(config)

    assert config.keychain_path.read_text() == "original"


def test_keychain_path_helpers_separate_logical_and_physical_paths(tmp_path: Path) -> None:
    physical = tmp_path / "release.keychain-db"
    logical = tmp_path / "release.keychain"

    assert testflight.logical_keychain_path(physical) == logical
    assert testflight.logical_keychain_path(logical) == logical
    assert testflight.physical_keychain_path(logical) == physical
    assert testflight.physical_keychain_path(physical) == physical


def test_readiness_blocks_unknown_compliance(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    monkeypatch.setattr(testflight, "group_build_ids", lambda _config: {"build-id"})
    monkeypatch.setattr(
        testflight,
        "beta_group",
        lambda _config: {"data": {"attributes": {"name": "Internal Testing"}}},
    )

    state = testflight.readiness(
        config,
        {
            "id": "build-id",
            "attributes": {"processingState": "VALID", "expired": False},
        },
    )

    assert state["verdict"] == "blocked"
    assert "compliance_unknown" in state["blockers"]


def test_readiness_enforces_expected_tester_count(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    env = valid_env(tmp_path)
    env["SETMARK_RELEASE_EXPECTED_INTERNAL_TESTER_COUNT"] = "2"
    config = testflight.ReleaseConfig.from_env(env)
    monkeypatch.setattr(testflight, "group_build_ids", lambda _config: {"build-id"})
    monkeypatch.setattr(
        testflight,
        "beta_group",
        lambda _config: {"data": {"attributes": {"name": "Internal Testing", "testerCount": 1}}},
    )

    state = testflight.readiness(
        config,
        {
            "id": "build-id",
            "attributes": {
                "processingState": "VALID",
                "expired": False,
                "usesNonExemptEncryption": False,
            },
        },
    )

    assert state["verdict"] == "blocked"
    assert "tester_count_mismatch" in state["blockers"]


def test_readiness_treats_all_build_access_group_as_assigned(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    monkeypatch.setattr(testflight, "group_build_ids", lambda _config: set())
    monkeypatch.setattr(
        testflight,
        "beta_group",
        lambda _config: {
            "data": {
                "attributes": {
                    "name": "Internal Testing",
                    "isInternalGroup": True,
                    "hasAccessToAllBuilds": True,
                }
            }
        },
    )

    state = testflight.readiness(
        config,
        {
            "id": "build-id",
            "attributes": {
                "processingState": "VALID",
                "expired": False,
                "usesNonExemptEncryption": False,
            },
        },
    )

    assert state["verdict"] == "ready"
    assert state["assignedToInternalGroup"] is True
    assert state["betaGroup"]["hasAccessToAllBuilds"] is True


def test_assign_build_skips_all_build_access_groups(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    assigned: list[str] = []
    monkeypatch.setattr(
        testflight,
        "beta_group",
        lambda _config: {"data": {"attributes": {"hasAccessToAllBuilds": True}}},
    )
    monkeypatch.setattr(
        testflight,
        "assign_build_to_group",
        lambda _config, build_id: assigned.append(build_id),
    )

    testflight.assign_build_if_needed(config, {"id": "build-id", "attributes": {}})

    assert assigned == []


def test_ensure_build_encryption_compliance_patches_missing_value(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    calls: list[tuple[str, str, dict[str, object] | None]] = []

    def fake_asc_request(
        _config: testflight.ReleaseConfig,
        method: str,
        path: str,
        *,
        query: dict[str, str] | None = None,
        body: dict[str, object] | None = None,
    ) -> dict[str, object]:
        del query
        calls.append((method, path, body))
        return {
            "data": {
                "id": "build-id",
                "attributes": {"usesNonExemptEncryption": False},
            }
        }

    monkeypatch.setattr(testflight, "asc_request", fake_asc_request)

    updated = testflight.ensure_build_encryption_compliance(
        config,
        {"id": "build-id", "attributes": {"usesNonExemptEncryption": None}},
    )

    assert updated["attributes"]["usesNonExemptEncryption"] is False
    assert calls[0] == (
        "PATCH",
        "/builds/build-id",
        {
            "data": {
                "type": "builds",
                "id": "build-id",
                "attributes": {"usesNonExemptEncryption": False},
            }
        },
    )
    assert calls[1] == ("GET", "/builds/build-id", None)


def test_assert_ready_state_raises_on_blocked_readiness() -> None:
    with pytest.raises(testflight.ReleaseError, match="compliance_unknown"):
        testflight.assert_ready_state({"verdict": "blocked", "blockers": ["compliance_unknown"]})


def test_find_build_paginates_and_matches_marketing_version(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))

    def fake_asc_request(
        _config: testflight.ReleaseConfig,
        _method: str,
        path: str,
        *,
        query: dict[str, str] | None = None,
        body: dict[str, object] | None = None,
    ) -> dict[str, object]:
        del body
        if path == "/builds" and query != {"page": "2"}:
            return {
                "data": [
                    {
                        "id": "old",
                        "attributes": {"version": "2", "marketingVersion": "0.0.0"},
                    }
                ],
                "links": {"next": "https://api.appstoreconnect.apple.com/v1/builds?page=2"},
            }
        return {
            "data": [
                {
                    "id": "wanted",
                    "attributes": {"version": "2", "marketingVersion": "0.0.1"},
                }
            ],
            "links": {},
        }

    monkeypatch.setattr(testflight, "asc_request", fake_asc_request)

    build = testflight.find_build(
        config,
        testflight.BuildVersion(marketing="0.0.1", build="2"),
    )

    assert build is not None
    assert build["id"] == "wanted"


def test_profile_validation_rejects_wrong_bundle(monkeypatch: pytest.MonkeyPatch) -> None:
    expiration = testflight.dt.datetime.now(testflight.dt.UTC) + testflight.dt.timedelta(days=30)
    monkeypatch.setattr(
        testflight,
        "installed_profiles",
        lambda _name: [
            (
                Path("/tmp/profile.mobileprovision"),
                {
                    "Name": "iOS Profile",
                    "TeamIdentifier": ["TEAMID1234"],
                    "ExpirationDate": expiration,
                    "Entitlements": {
                        "application-identifier": "TEAMID1234.com.example.Other",
                        "com.apple.developer.healthkit": True,
                    },
                },
            )
        ],
    )

    failures = testflight.validate_profile(
        "iOS Profile",
        bundle_id="com.example.App",
        team_id="TEAMID1234",
        require_healthkit=True,
    )

    assert any("bundle mismatch" in failure for failure in failures)


def test_profile_validation_rejects_missing_signing_certificate(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    expiration = testflight.dt.datetime.now(testflight.dt.UTC) + testflight.dt.timedelta(days=30)
    included_certificate = b"other certificate"
    required_sha1 = testflight.hashlib.sha1(b"required certificate").hexdigest().upper()
    monkeypatch.setattr(
        testflight,
        "installed_profiles",
        lambda _name: [
            (
                Path("/tmp/profile.mobileprovision"),
                {
                    "Name": "iOS Profile",
                    "TeamIdentifier": ["TEAMID1234"],
                    "ExpirationDate": expiration,
                    "DeveloperCertificates": [included_certificate],
                    "Entitlements": {
                        "application-identifier": "TEAMID1234.com.example.App",
                        "com.apple.developer.healthkit": True,
                    },
                },
            )
        ],
    )

    failures = testflight.validate_profile(
        "iOS Profile",
        bundle_id="com.example.App",
        team_id="TEAMID1234",
        require_healthkit=True,
        signing_certificate_sha1=required_sha1,
    )

    assert any("does not include signing certificate" in failure for failure in failures)


def test_profile_validation_accepts_matching_signing_certificate(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    expiration = testflight.dt.datetime.now(testflight.dt.UTC) + testflight.dt.timedelta(days=30)
    included_certificate = b"required certificate"
    required_sha1 = testflight.hashlib.sha1(included_certificate).hexdigest().upper()
    monkeypatch.setattr(
        testflight,
        "installed_profiles",
        lambda _name: [
            (
                Path("/tmp/profile.mobileprovision"),
                {
                    "Name": "iOS Profile",
                    "TeamIdentifier": ["TEAMID1234"],
                    "ExpirationDate": expiration,
                    "DeveloperCertificates": [included_certificate],
                    "Entitlements": {
                        "application-identifier": "TEAMID1234.com.example.App",
                        "com.apple.developer.healthkit": True,
                    },
                },
            )
        ],
    )

    failures = testflight.validate_profile(
        "iOS Profile",
        bundle_id="com.example.App",
        team_id="TEAMID1234",
        require_healthkit=True,
        signing_certificate_sha1=required_sha1,
    )

    assert failures == []


def test_codesign_preflight_returns_identity_fingerprint(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))

    class Completed:
        returncode = 0
        stdout = (
            "  1) 99EAB1BF5E2B37C62C465831AFC05427936039D2 "
            '"Apple Distribution: Eric Feunekes (TVKR339CEB)"\n'
            "     1 valid identities found\n"
        )
        stderr = ""

    def fake_run(
        args: list[str],
        *,
        capture_output: bool,
        text: bool,
        check: bool,
        timeout: int,
    ) -> Completed:
        del args, capture_output, text, check, timeout
        return Completed()

    monkeypatch.setattr(testflight.subprocess, "run", fake_run)
    monkeypatch.setattr(testflight, "codesign_dryrun_failure", lambda _config, _sha1: None)

    failures, fingerprint = testflight.codesign_preflight(config)

    assert failures == []
    assert fingerprint == "99EAB1BF5E2B37C62C465831AFC05427936039D2"


def test_codesign_preflight_rejects_identity_without_noninteractive_key_access(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))

    class Completed:
        returncode = 0
        stdout = (
            "  1) 99EAB1BF5E2B37C62C465831AFC05427936039D2 "
            '"Apple Distribution: Eric Feunekes (TVKR339CEB)"\n'
            "     1 valid identities found\n"
        )
        stderr = ""

    def fake_run(
        args: list[str],
        *,
        capture_output: bool,
        text: bool,
        check: bool,
        timeout: int,
    ) -> Completed:
        del args, capture_output, text, check, timeout
        return Completed()

    monkeypatch.setattr(testflight.subprocess, "run", fake_run)
    monkeypatch.setattr(
        testflight,
        "codesign_dryrun_failure",
        lambda _config, _sha1: "signing identity cannot codesign noninteractively: denied",
    )

    failures, fingerprint = testflight.codesign_preflight(config)

    assert failures == ["signing identity cannot codesign noninteractively: denied"]
    assert fingerprint is None


def test_codesign_dryrun_uses_fingerprint_and_configured_keychain(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))
    calls: list[list[str]] = []

    class Completed:
        returncode = 0
        stderr = ""
        stdout = ""

    def fake_run(
        args: list[str],
        *,
        capture_output: bool,
        text: bool,
        check: bool,
        timeout: int,
    ) -> Completed:
        del capture_output, text, check, timeout
        calls.append(args)
        return Completed()

    monkeypatch.setattr(testflight.subprocess, "run", fake_run)

    failure = testflight.codesign_dryrun_failure(config, "ABCDEF1234")

    assert failure is None
    assert len(calls) == 1
    assert calls[0][:6] == [
        "/usr/bin/codesign",
        "--force",
        "--dryrun",
        "--timestamp=none",
        "--sign",
        "ABCDEF1234",
    ]
    assert calls[0][6] == "--keychain"
    assert calls[0][7] == str(testflight.logical_keychain_path(config.keychain_path))


def test_codesign_preflight_distinguishes_matching_but_invalid_identity(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = testflight.ReleaseConfig.from_env(valid_env(tmp_path))

    class Completed:
        returncode = 0
        stderr = ""

        def __init__(self, stdout: str) -> None:
            self.stdout = stdout

    calls: list[list[str]] = []

    def fake_run(
        args: list[str],
        *,
        capture_output: bool,
        text: bool,
        check: bool,
        timeout: int,
    ) -> Completed:
        del capture_output, text, check, timeout
        calls.append(args)
        if "-v" in args:
            return Completed("     0 valid identities found\n")
        return Completed(
            "  1) 99EAB1BF5E2B37C62C465831AFC05427936039D2 "
            '"Apple Distribution: Eric Feunekes (TVKR339CEB)"\n'
            "     1 identities found\n"
        )

    monkeypatch.setattr(testflight.subprocess, "run", fake_run)

    failures, fingerprint = testflight.codesign_preflight(config)

    assert failures == [
        "signing identity is present but not valid for code signing: Apple Distribution"
    ]
    assert fingerprint is None
    assert len(calls) == 2


def test_mobileprovision_decode_falls_back_to_openssl(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    profile = tmp_path / "profile.mobileprovision"
    profile.write_bytes(b"signed profile")
    payload = {
        "Name": "Setmark iOS App Store",
        "TeamIdentifier": ["TEAMID1234"],
        "ExpirationDate": testflight.dt.datetime.now(testflight.dt.UTC)
        + testflight.dt.timedelta(days=30),
        "Entitlements": {
            "application-identifier": "TEAMID1234.com.example.App",
            "com.apple.developer.healthkit": True,
        },
    }
    calls: list[list[str]] = []

    class Completed:
        def __init__(self, returncode: int, stdout: bytes = b"", stderr: bytes = b"") -> None:
            self.returncode = returncode
            self.stdout = stdout
            self.stderr = stderr

    def fake_run(
        args: list[str],
        *,
        check: bool,
        capture_output: bool,
        text: bool,
        timeout: int,
    ) -> Completed:
        del check, capture_output, text, timeout
        calls.append(args)
        if args[0] == "security":
            return Completed(1, stderr=b"security cms failed")
        return Completed(0, stdout=testflight.plistlib.dumps(payload))

    monkeypatch.setattr(testflight.subprocess, "run", fake_run)

    decoded = testflight.decode_mobileprovision(profile)

    assert decoded is not None
    assert decoded["Name"] == "Setmark iOS App Store"
    assert calls[0][:3] == ["security", "cms", "-D"]
    assert calls[1][:5] == ["openssl", "smime", "-verify", "-inform", "DER"]
