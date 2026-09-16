#!/usr/bin/env python3
"""Sign already-tested binaries with temporary, environment-scoped CI credentials.

No private key is generated here. A persistent Sparkle key must be provided and
must match the public key baked into the unsigned app. Nothing secret is logged.
"""
from __future__ import annotations
import base64
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
from release_automation import REQUIRED_SECRETS, assert_release_context
from updates.common import BUNDLE_ID, FEED_URL, decode_key, version_info

ROOT = Path(__file__).resolve().parent.parent


def run(arguments: list[str], env: dict | None = None) -> str:
    process = subprocess.run(arguments, cwd=ROOT, env=env, capture_output=True, text=True)
    if process.returncode:
        # Error messages intentionally do not contain command arguments or output.
        raise RuntimeError(Path(arguments[0]).name + " failed; release remains unpublished")
    return process.stdout.strip()


def public_environment() -> dict:
    return {k: v for k, v in os.environ.items() if k not in REQUIRED_SECRETS and k not in {"GH_TOKEN", "GITHUB_TOKEN"}}


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
    for name in REQUIRED_SECRETS:
        if not os.environ.get(name):
            raise ValueError("Missing protected release secret: " + name)
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
    sdk = Path(run(["python3", "scripts/prepare-sparkle.py"], public_environment()))
    clean_env = public_environment()
    original_default = run(["security", "default-keychain", "-d", "user"]).strip('" ')
    original_list = re.findall(r'"([^"\n]+)"', run(["security", "list-keychains", "-d", "user"]))
    private_dir = Path(tempfile.mkdtemp(prefix="retrolife-signing-", dir=os.environ["RUNNER_TEMP"]))
    keychain = private_dir / "release.keychain-db"
    try:
        password = secrets.token_urlsafe(36)
        certificate = private_dir / "certificate.p12"
        certificate.write_bytes(base64.b64decode(os.environ["MACOS_CERTIFICATE_P12_BASE64"], validate=True))
        certificate.chmod(0o600)
        sparkle_key = private_dir / "sparkle-secret"
        sparkle_key.write_text(os.environ["SPARKLE_PRIVATE_KEY"].strip() + "\n")
        sparkle_key.chmod(0o600)
        run(["security", "create-keychain", "-p", password, str(keychain)])
        run(["security", "set-keychain-settings", "-lut", "21600", str(keychain)])
        run(["security", "unlock-keychain", "-p", password, str(keychain)])
        run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *original_list])
        run(["security", "default-keychain", "-d", "user", "-s", str(keychain)])
        run(["security", "import", str(certificate), "-k", str(keychain), "-P", os.environ["MACOS_CERTIFICATE_PASSWORD"], "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"])
        run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, str(keychain)])
        identities = run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)])
        matching = re.findall(r'([0-9A-F]{40}) "Developer ID Application: [^"\n]+ \(' + team + r'\)"', identities)
        if len(matching) != 1:
            raise ValueError("The certificate must contain exactly one matching Developer ID Application identity")
        account = "io.github.lincolnaleixo.retrolife.sparkle"
        run([str(sdk / "bin/generate_keys"), "--account", account, "-f", str(sparkle_key)])
        if run([str(sdk / "bin/generate_keys"), "--account", account, "-p"]) != public:
            raise ValueError("Persistent Sparkle signing key does not match the app's public key")
        profile = "retrolife-ci-notary"
        run(["xcrun", "notarytool", "store-credentials", profile, "--apple-id", os.environ["APPLE_ID"],
             "--team-id", team, "--password", os.environ["APPLE_APP_PASSWORD"], "--keychain", str(keychain)])
        signing_env = {**clean_env, "SIGNING_IDENTITY": matching[0], "NOTARY_PROFILE": profile}
        run(["bash", "scripts/sign-macos.sh", str(app)], signing_env)
        run(["python3", "scripts/prepare-update-metadata.py", str(app), str(app.parent / "RetroLife-macos-arm64.zip"), "--account", account], signing_env)
        run(["bash", "scripts/package-macos-dmg.sh", str(app), str(ROOT / "dist/dmg")], signing_env)
        print("Developer ID signing, notarization, stapling, DMG and ZIP signature checks passed.")
    finally:
        # Always restore the runner's configuration, including after failure.
        subprocess.run(["security", "default-keychain", "-d", "user", "-s", original_default], capture_output=True)
        subprocess.run(["security", "list-keychains", "-d", "user", "-s", *original_list], capture_output=True)
        subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True)
        shutil.rmtree(private_dir)
    for name in REQUIRED_SECRETS:
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
