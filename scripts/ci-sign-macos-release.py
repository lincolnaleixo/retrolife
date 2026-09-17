#!/usr/bin/env python3
"""Sign already-tested binaries with protected CI credentials.

Hosted mode imports temporary certificate and Sparkle material; local-keychain
mode uses only the trusted Mac's existing Keychain. In both modes the
persistent Sparkle key must match the public key baked into the unsigned app.
Nothing secret is logged.
"""
from __future__ import annotations
import base64
import binascii
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
from release_automation import (ALL_PROTECTED_SECRETS, API_KEY_NOTARY_SECRETS,
                                LOCAL_KEYCHAIN_SECRETS, PASSWORD_NOTARY_SECRETS,
                                SIGNING_SECRETS, assert_release_context)
from updates.common import BUNDLE_ID, FEED_URL, decode_key, version_info

ROOT = Path(__file__).resolve().parent.parent


def run(arguments: list[str], env: dict | None = None) -> str:
    process = subprocess.run(arguments, cwd=ROOT, env=env or public_environment(), capture_output=True, text=True)
    if process.returncode:
        # Error messages intentionally do not contain command arguments or output.
        raise RuntimeError(Path(arguments[0]).name + " failed; release remains unpublished")
    return process.stdout.strip()


def public_environment() -> dict:
    return {k: v for k, v in os.environ.items() if k not in ALL_PROTECTED_SECRETS and k not in {"GH_TOKEN", "GITHUB_TOKEN"}}


def unlock_keychain(path: Path, env: dict) -> None:
    """Unlock a self-hosted runner keychain without placing its password in argv."""
    script = r'''
set timeout 30
log_user 0
spawn /usr/bin/security unlock-keychain [lindex $argv 0]
expect {
    -re {(?i)password.*:} { send -- "$env(MACOS_KEYCHAIN_PASSWORD)\r"; exp_continue }
    eof {}
    timeout { exit 2 }
}
set result [wait]
exit [lindex $result 3]
'''
    process = subprocess.run(["/usr/bin/expect", "-c", script, str(path)], env=env,
                             capture_output=True, text=True)
    if process.returncode:
        raise RuntimeError("The local signing Keychain could not be unlocked")


def verify_bundle(app: Path, version: str, public_key: str, team: str, env: dict) -> None:
    info = version_info(version)
    plist = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected = {"CFBundleIdentifier": BUNDLE_ID, "RLReleaseVersion": version,
                "CFBundleVersion": info["bundleVersion"], "SUFeedURL": FEED_URL,
                "SUPublicEDKey": public_key, "SUVerifyUpdateBeforeExtraction": True}
    if any(plist.get(k) != v for k, v in expected.items()) or any(k.startswith("RLTest") for k in plist):
        raise ValueError("Packaged updater identity or trust configuration is invalid")
    for name in ("Sparkle.framework/Sparkle", "libretrolife_updater.dylib", "libretrolife_godot.dylib", "bsnes-jg_libretro.dylib"):
        if not (app / "Contents/Frameworks" / name).is_file():
            raise ValueError("Packaged updater or emulation component is missing")
    run(["codesign", "--verify", "--deep", "--strict", str(app)], env)
    details = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)], capture_output=True, text=True, env=env)
    if details.returncode or f"TeamIdentifier={team}\n" not in details.stderr or "Authority=Developer ID Application:" not in details.stderr:
        raise ValueError("The application is not signed by the configured Developer ID team")
    run(["xcrun", "stapler", "validate", str(app)], env)
    run(["spctl", "--assess", "--type", "execute", str(app)], env)
    roots = [str(ROOT).encode(), str(Path.home()).encode()]
    for path in app.rglob("*"):
        if path.is_symlink():
            if not path.resolve().is_relative_to(app.resolve()):
                raise ValueError("Application has a symlink outside its bundle")
            continue
        if path.is_file():
            # Only return the relative file name; never disclose matched values.
            with path.open("rb") as stream:
                previous = b""
                while chunk := stream.read(1024 * 1024):
                    data = previous + chunk
                    if any(needle in data for needle in roots):
                        raise ValueError("Private build path found in " + str(path.relative_to(app)))
                    previous = data[-4096:]


def verify_probe(app: Path, version: str, env: dict) -> None:
    result = subprocess.run([str(app / "Contents/MacOS/RetroLife"), "--audio-driver", "Dummy",
                             "--rendering-method", "gl_compatibility", "--", "--verify-updater-release"],
                            env=env, capture_output=True, text=True, timeout=45)
    marker = "RETROLIFE_UPDATE_RELEASE_CHECK "
    lines = [line[len(marker):] for line in result.stdout.splitlines() if line.startswith(marker)]
    if result.returncode or len(lines) != 1:
        raise ValueError("The packaged Godot application failed its updater-availability check")
    state = json.loads(lines[0])
    if state.get("available") is not True or state.get("currentVersion") != version:
        raise ValueError("Refusing release: the installed app still reports updater unavailable")
    print("Installed Godot application reports the expected version and an available updater.")


def main() -> None:
    assert_release_context(os.environ)
    if sys.platform != "darwin" or run(["uname", "-m"]) != "arm64":
        raise ValueError("A hosted Apple Silicon macOS runner is required")
    local_mode = os.environ.get("RETROLIFE_SIGNING_MODE") == "local-keychain"
    if local_mode:
        for name in LOCAL_KEYCHAIN_SECRETS:
            if not os.environ.get(name):
                raise ValueError("Missing protected release secret: " + name)
        local_keychain_value = os.environ.get("RETROLIFE_KEYCHAIN_PATH", "")
        profile = os.environ.get("RETROLIFE_NOTARY_PROFILE", "")
        if not local_keychain_value or not profile:
            raise ValueError("Missing local signing Keychain configuration")
        password_ready = api_ready = False
    else:
        for name in SIGNING_SECRETS:
            if not os.environ.get(name):
                raise ValueError("Missing protected release secret: " + name)
        password_ready = all(os.environ.get(name) for name in PASSWORD_NOTARY_SECRETS)
        api_ready = all(os.environ.get(name) for name in API_KEY_NOTARY_SECRETS)
        if not password_ready and not api_ready:
            raise ValueError("Missing protected notarization credentials")
    version = sys.argv[1]
    version_info(version)
    public = os.environ["SPARKLE_PUBLIC_KEY"]
    decode_key(public, 32)
    team = os.environ["APPLE_TEAM_ID"]
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("Invalid Apple team identifier")
    app = ROOT / "dist/unsigned/RetroLife.app"
    if plistlib.loads((app / "Contents/Info.plist").read_bytes()).get("SUPublicEDKey") != public:
        raise ValueError("Unsigned app public key does not match release configuration")
    clean_env = public_environment()
    sdk = Path(run(["python3", "scripts/prepare-sparkle.py"], clean_env))
    original_default = run(["security", "default-keychain", "-d", "user"], clean_env).strip('" ')
    original_list = re.findall(r'"([^"\n]+)"', run(["security", "list-keychains", "-d", "user"], clean_env))
    private_dir = None
    keychain = None
    local_keychain = None
    try:
        if local_mode:
            local_keychain = Path(local_keychain_value).expanduser()
            if not local_keychain.is_file():
                raise ValueError("The configured local signing Keychain does not exist")
            unlock_env = {**clean_env, "MACOS_KEYCHAIN_PASSWORD": os.environ["MACOS_KEYCHAIN_PASSWORD"]}
            unlock_keychain(local_keychain, unlock_env)
            run(["security", "list-keychains", "-d", "user", "-s", str(local_keychain), *original_list], clean_env)
            run(["security", "default-keychain", "-d", "user", "-s", str(local_keychain)], clean_env)
            identities = run(["security", "find-identity", "-v", "-p", "codesigning", str(local_keychain)], clean_env)
        else:
            private_dir = Path(tempfile.mkdtemp(prefix="retrolife-signing-", dir=os.environ["RUNNER_TEMP"]))
            keychain = private_dir / "release.keychain-db"
            password = secrets.token_urlsafe(36)
            certificate = private_dir / "certificate.p12"
            certificate.write_bytes(base64.b64decode(os.environ["MACOS_CERTIFICATE_P12_BASE64"], validate=True))
            certificate.chmod(0o600)
            sparkle_key = private_dir / "sparkle-secret"
            sparkle_key.write_text(os.environ["SPARKLE_PRIVATE_KEY"].strip() + "\n")
            sparkle_key.chmod(0o600)
            run(["security", "create-keychain", "-p", password, str(keychain)], clean_env)
            run(["security", "set-keychain-settings", "-lut", "21600", str(keychain)], clean_env)
            run(["security", "unlock-keychain", "-p", password, str(keychain)], clean_env)
            run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *original_list], clean_env)
            run(["security", "default-keychain", "-d", "user", "-s", str(keychain)], clean_env)
            run(["security", "import", str(certificate), "-k", str(keychain), "-P", os.environ["MACOS_CERTIFICATE_PASSWORD"], "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"], clean_env)
            run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, str(keychain)], clean_env)
            identities = run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)], clean_env)
        matching = re.findall(r'([0-9A-F]{40}) "Developer ID Application: [^"\n]+ \(' + team + r'\)"', identities)
        if len(matching) != 1:
            raise ValueError("The certificate must contain exactly one matching Developer ID Application identity")
        account = "io.github.lincolnaleixo.retrolife.sparkle"
        if local_mode:
            if run([str(sdk / "bin/generate_keys"), "--account", account, "-p"]) != public:
                raise ValueError("Persistent Sparkle signing key does not match the app's public key")
        else:
            run([str(sdk / "bin/generate_keys"), "--account", account, "-f", str(sparkle_key)], clean_env)
            if run([str(sdk / "bin/generate_keys"), "--account", account, "-p"], clean_env) != public:
                raise ValueError("Imported Sparkle signing key does not match the app's public key")
            profile = "retrolife-ci-notary"
            if api_ready:
                notary_key = private_dir / "app-store-connect-api-key.p8"
                try:
                    key_bytes = base64.b64decode(os.environ["APPLE_API_KEY_P8_BASE64"], validate=True)
                except (ValueError, binascii.Error) as error:
                    raise ValueError("Invalid App Store Connect API key encoding") from error
                if not key_bytes or len(key_bytes) > 16384:
                    raise ValueError("App Store Connect API key is empty or unexpectedly large")
                notary_key.write_bytes(key_bytes)
                notary_key.chmod(0o600)
                run(["xcrun", "notarytool", "store-credentials", profile, "--key", str(notary_key),
                     "--key-id", os.environ["APPLE_API_KEY_ID"], "--issuer", os.environ["APPLE_API_ISSUER_ID"],
                     "--keychain", str(keychain)], clean_env)
            else:
                run(["xcrun", "notarytool", "store-credentials", profile, "--apple-id", os.environ["APPLE_ID"],
                     "--team-id", team, "--password", os.environ["APPLE_APP_PASSWORD"], "--keychain", str(keychain)], clean_env)
        signing_env = {**clean_env, "SIGNING_IDENTITY": matching[0], "NOTARY_PROFILE": profile}
        run(["bash", "scripts/sign-macos.sh", str(app)], signing_env)
        run(["python3", "scripts/prepare-update-metadata.py", str(app), str(app.parent / "RetroLife-macos-arm64.zip"), "--account", account], signing_env)
        run(["bash", "scripts/package-macos-dmg.sh", str(app), str(ROOT / "dist/dmg")], signing_env)
        print("Developer ID signing, notarization, stapling, DMG and ZIP signature checks passed.")
    finally:
        # Always restore the runner's configuration, including after failure.
        cleanup_errors = []
        for arguments in (
            ["security", "default-keychain", "-d", "user", "-s", original_default],
            ["security", "list-keychains", "-d", "user", "-s", *original_list],
        ):
            result = subprocess.run(arguments, capture_output=True, env=clean_env)
            if result.returncode:
                cleanup_errors.append(arguments[1])
        if local_mode:
            if local_keychain is not None:
                result = subprocess.run(["security", "lock-keychain", str(local_keychain)], capture_output=True, env=clean_env)
                if result.returncode:
                    cleanup_errors.append("lock-keychain")
        else:
            if keychain is not None:
                result = subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True, env=clean_env)
                if result.returncode:
                    cleanup_errors.append("delete-keychain")
            if private_dir is not None:
                shutil.rmtree(private_dir)
        if cleanup_errors:
            raise RuntimeError("Signing environment cleanup failed; release remains unpublished")
    for name in ALL_PROTECTED_SECRETS:
        os.environ.pop(name, None)
    # Private signing material is gone before executing the signed application.
    verify_bundle(app, version, public, team, clean_env)
    with tempfile.TemporaryDirectory(prefix="retrolife-installed-", dir=os.environ["RUNNER_TEMP"]) as installed:
        run(["ditto", "-x", "-k", str(app.parent / "RetroLife-macos-arm64.zip"), installed], clean_env)
        restored = Path(installed) / "RetroLife.app"
        verify_bundle(restored, version, public, team, clean_env)
        verify_probe(restored, version, clean_env)
    release = ROOT / "dist/release"
    release.mkdir()
    for name in ("RetroLife-macos-arm64.zip", "retrolife-update.json", "retrolife-source.tar.gz", "retrolife-rust-dependencies.tar.gz", "bsnes-jg.tar.gz", "retrolife-cartridge-assets.lock.json", "LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md"):
        shutil.copy2(app.parent / name, release / name)
    shutil.copy2(ROOT / "dist/dmg/RetroLife-macos-arm64.dmg", release)
    run(["python3", "scripts/release_automation.py", "notes", "--version", version], clean_env)
    run(["python3", "scripts/release_automation.py", "manifest", "--version", version], clean_env)
    run(["python3", "scripts/release_automation.py", "audit", "--version", version], clean_env)
    print("Complete signed release payload verified; ready for publication.")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Never echo subprocess arguments, raw plist content, tokens or key material.
        print("Signed release failed. No unsigned app was published. Verify the protected environment, certificate, notarization credentials and persistent Sparkle key.", file=sys.stderr)
        sys.exit(1)
