#!/usr/bin/env python3
"""Fail-closed release planning, asset audit and immutable GitHub publication."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.request
from updates.common import FEED_URL, BUNDLE_ID, decode_key, sha256, validate_metadata, version_info, write_json

ROOT = Path(__file__).resolve().parent.parent
REPO = "lincolnaleixo/retrolife"
SIGNING_SECRETS = (
    "MACOS_CERTIFICATE_P12_BASE64", "MACOS_CERTIFICATE_PASSWORD", "SPARKLE_PRIVATE_KEY",
)
PASSWORD_NOTARY_SECRETS = ("APPLE_ID", "APPLE_APP_PASSWORD")
API_KEY_NOTARY_SECRETS = (
    "APPLE_API_KEY_ID", "APPLE_API_ISSUER_ID", "APPLE_API_KEY_P8_BASE64",
)
LOCAL_KEYCHAIN_SECRETS = ("MACOS_KEYCHAIN_PASSWORD",)
LOCAL_SPARKLE_SECRETS = ("SPARKLE_PRIVATE_KEY",)
# Kept as the legacy password-based set for callers that need the historical
# names.  A release may use either the password pair or the API-key trio.
REQUIRED_SECRETS = (*SIGNING_SECRETS, *PASSWORD_NOTARY_SECRETS)
ALL_PROTECTED_SECRETS = (*SIGNING_SECRETS, *PASSWORD_NOTARY_SECRETS, *API_KEY_NOTARY_SECRETS, *LOCAL_KEYCHAIN_SECRETS)
PAYLOAD_FILES = (
    "RetroLife-macos-arm64.zip", "RetroLife-macos-arm64.dmg", "retrolife-update.json",
    "retrolife-source.tar.gz", "retrolife-rust-dependencies.tar.gz", "bsnes-jg.tar.gz",
    "retrolife-cartridge-assets.lock.json", "LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md",
    "release-notes.md", "release-build.json",
)
ASSETS = (*PAYLOAD_FILES, "SHA256SUMS")
SHA = re.compile(r"[0-9a-f]{40}\Z")
DELTA_ASSET = re.compile(r"RetroLife-macos-arm64-from-[0-9]+\.[0-9]+\.[0-9]+(?:[ab]|fc)[0-9]+\.delta\Z")


def delta_assets(directory: Path) -> tuple[str, ...]:
    return tuple(sorted(p.name for p in directory.iterdir() if DELTA_ASSET.fullmatch(p.name)))


def next_version(base: str, tags: list[str]) -> str:
    minimum = version_info(base)
    if minimum["channel"] != "stable":
        raise ValueError("The automatic release base must be a stable semantic version")
    known = []
    for tag in tags:
        try:
            known.append(version_info(tag))
        except ValueError:
            if re.match(r"v?\d+\.\d+\.\d+", tag):
                raise ValueError("Unsupported existing release tag: " + tag) from None
    latest = max(known, key=lambda x: x["sort"]) if known else None
    components = minimum["sort"][:3]
    sequence = 1
    if latest and latest["sort"][:3] >= components:
        components = latest["sort"][:3]
        stage, previous = latest["sort"][3:]
        if stage == 0:
            sequence = 1  # A beta is newer than every alpha in the same series.
        elif stage == 1 and previous < 255:
            sequence = previous + 1
        else:
            major, minor, patch = components
            patch += 1
            if patch > 99:
                minor, patch = minor + 1, 0
            if minor > 99:
                major, minor = major + 1, 0
            components = (major, minor, patch)
    candidate = ".".join(map(str, components)) + f"-beta.{sequence}"
    return version_info(candidate)["version"]


def configuration_errors(env: dict) -> list[str]:
    local_mode = env.get("SIGNING_MODE") == "local-keychain"
    if local_mode:
        missing = [name for name in (*LOCAL_KEYCHAIN_SECRETS, *LOCAL_SPARKLE_SECRETS)
                   if env.get("HAS_" + name) != "true"]
        if not env.get("LOCAL_KEYCHAIN_PATH"):
            missing.append("LOCAL_KEYCHAIN_PATH (environment variable, local runner path)")
        if not env.get("NOTARY_PROFILE"):
            missing.append("NOTARY_PROFILE (environment variable, local Keychain profile)")
    else:
        missing = [name for name in SIGNING_SECRETS if env.get("HAS_" + name) != "true"]
        password_missing = [name for name in PASSWORD_NOTARY_SECRETS if env.get("HAS_" + name) != "true"]
        api_missing = [name for name in API_KEY_NOTARY_SECRETS if env.get("HAS_" + name) != "true"]
        password_ready = not password_missing
        api_ready = not api_missing
        if not password_ready and not api_ready:
            missing.append("APPLE_ID + APPLE_APP_PASSWORD or " + ", ".join(API_KEY_NOTARY_SECRETS))
    if not re.fullmatch(r"[A-Z0-9]{10}", env.get("APPLE_TEAM_ID", "")):
        missing.append("APPLE_TEAM_ID (environment variable, 10 characters)")
    try:
        decode_key(env.get("SPARKLE_PUBLIC_KEY", ""), 32)
    except ValueError:
        missing.append("SPARKLE_PUBLIC_KEY (environment variable, exported public key)")
    return missing


def assert_release_context(env: dict) -> None:
    if env.get("GITHUB_REPOSITORY") != REPO or env.get("GITHUB_REF") != "refs/heads/main":
        raise ValueError("Production releases are restricted to this repository's main branch")
    if env.get("GITHUB_EVENT_NAME") not in {"push", "workflow_dispatch"}:
        raise ValueError("Pull requests and tag events must never publish production releases")
    if not SHA.fullmatch(env.get("GITHUB_SHA", "")):
        raise ValueError("The release requires an exact source commit")


def gh(*args: str) -> object:
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode:
        # Do not reflect command arguments, server text or credentials into public logs.
        raise RuntimeError("GitHub release request failed; no published assets were overwritten")
    return json.loads(result.stdout) if result.stdout.strip() else None


def all_releases() -> list[dict]:
    releases = []
    for page in range(1, 101):
        batch = gh("api", f"repos/{REPO}/releases?per_page=100&page={page}")
        if not isinstance(batch, list):
            raise ValueError("Invalid GitHub release response")
        releases.extend(batch)
        if len(batch) < 100:
            return releases
    raise ValueError("Release history exceeds the configured pagination limit")


def output_values(**values) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as stream:
            for key, value in values.items():
                if "\n" in str(value) or "\r" in str(value):
                    raise ValueError("Invalid workflow output")
                stream.write(f"{key}={value}\n")


def plan() -> None:
    assert_release_context(os.environ)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if head != os.environ["GITHUB_SHA"]:
        raise ValueError("Checkout does not match the triggering commit")
    releases = all_releases()
    for release in releases:
        if not release.get("draft") and SHA.fullmatch(release.get("target_commitish", "")) and {a.get("name") for a in release.get("assets", [])} >= set(ASSETS):
            published_source = release["target_commitish"]
            ancestry = subprocess.run(["git", "merge-base", "--is-ancestor", published_source, head], capture_output=True)
            if ancestry.returncode:
                raise ValueError("A newer or divergent source already has a release; refusing to publish a stale queued commit")
        if release.get("draft") or release.get("target_commitish") != head:
            continue
        names = {a["name"] for a in release.get("assets", []) if a.get("state") == "uploaded"}
        if set(ASSETS) <= names:
            info = version_info(release["tag_name"])
            output_values(version=info["version"], tag=info["tag"], published="true")
            print("This exact source commit already has a complete release; only the feed will be refreshed.")
            return
    tags = subprocess.check_output(["git", "tag", "--list", "v*"], text=True).splitlines()
    tags += [r["tag_name"] for r in releases]
    base = json.loads((ROOT / "assets/release-policy.json").read_text())["baseVersion"]
    version = next_version(base, tags)
    output_values(version=version, tag="v" + version, published="false")
    print("Next unused release: v" + version)


def write_manifest(directory: Path, version: str, commit: str, run_url: str) -> dict:
    if not SHA.fullmatch(commit):
        raise ValueError("A full source SHA is required")
    info = version_info(version)
    if not re.fullmatch(r"https://github.com/lincolnaleixo/retrolife/actions/runs/\d+", run_url):
        raise ValueError("Invalid build evidence URL")
    metadata = json.loads((directory / "retrolife-update.json").read_text())
    validate_metadata(metadata)
    if metadata["version"] != info["version"]:
        raise ValueError("Update metadata does not match the planned release")
    archive = directory / "RetroLife-macos-arm64.zip"
    if metadata["length"] != archive.stat().st_size or metadata["sha256"] != sha256(archive):
        raise ValueError("Signed updater ZIP differs from its metadata")
    entries = {}
    for name in PAYLOAD_FILES:
        if name == "release-build.json":
            continue
        path = directory / name
        if not path.is_file() or path.is_symlink() or not path.stat().st_size:
            raise ValueError("Missing or unsafe release asset: " + name)
        entries[name] = {"bytes": path.stat().st_size, "sha256": sha256(path)}
    manifest = {"schemaVersion": 1, "repository": REPO, "sourceCommit": commit,
                "version": info["version"], "tag": info["tag"], "workflowRun": run_url,
                "files": entries}
    write_json(directory / "release-build.json", manifest)
    sums = "".join(f"{sha256(directory / name)}  {name}\n" for name in PAYLOAD_FILES)
    (directory / "SHA256SUMS").write_text(sums, encoding="utf-8")
    return manifest


def audit_assets(directory: Path, version: str, commit: str) -> dict:
    deltas = delta_assets(directory)
    expected = set(ASSETS) | set(deltas)
    if {p.name for p in directory.iterdir()} != expected:
        raise ValueError("Release directory must contain exactly the approved public assets")
    manifest = json.loads((directory / "release-build.json").read_text())
    if (manifest.get("schemaVersion"), manifest.get("repository"), manifest.get("sourceCommit"), manifest.get("version")) != (1, REPO, commit, version):
        raise ValueError("Release provenance does not match source/version")
    if set(manifest.get("files", {})) != set(PAYLOAD_FILES) - {"release-build.json"}:
        raise ValueError("Incomplete release manifest")
    for name in (*ASSETS, *deltas):
        path = directory / name
        if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
            raise ValueError("Unsafe release asset: " + name)
        if name in manifest["files"] and manifest["files"][name] != {"bytes": path.stat().st_size, "sha256": sha256(path)}:
            raise ValueError("Release asset checksum changed: " + name)
    expected_sums = "".join(f"{sha256(directory / name)}  {name}\n" for name in (*PAYLOAD_FILES, *deltas))
    if (directory / "SHA256SUMS").read_text() != expected_sums:
        raise ValueError("Release SHA256SUMS does not cover the complete payload")
    metadata = json.loads((directory / "retrolife-update.json").read_text())
    validate_metadata(metadata)
    if metadata["version"] != version or metadata["sha256"] != sha256(directory / metadata["asset"]) or metadata["length"] != (directory / metadata["asset"]).stat().st_size:
        raise ValueError("Update metadata does not match the audited payload")
    if {entry["asset"] for entry in metadata.get("deltas", [])} != set(deltas):
        raise ValueError("Delta update metadata does not match the audited payload")
    for entry in metadata.get("deltas", []):
        path = directory / entry["asset"]
        if path.stat().st_size != entry["length"] or sha256(path) != entry["sha256"]:
            raise ValueError("Delta update metadata does not match its file")
    return manifest


def verify_remote(release: dict, directory: Path) -> None:
    local = {p.name for p in directory.iterdir()}
    assets = release.get("assets", [])
    if len(assets) != len(local) or {a["name"] for a in assets} != local:
        raise ValueError("GitHub has an incomplete or unexpected release asset set")
    for asset in assets:
        path = directory / asset["name"]
        if (asset.get("state"), asset.get("size"), asset.get("digest")) != ("uploaded", path.stat().st_size, "sha256:" + sha256(path)):
            raise ValueError("GitHub asset digest/size verification failed: " + asset["name"])


def publish(directory: Path, version: str) -> None:
    assert_release_context(os.environ)
    commit = os.environ["GITHUB_SHA"]
    audit_assets(directory, version, commit)
    info = version_info(version)
    if any(r["tag_name"] == info["tag"] for r in all_releases()):
        raise ValueError("Release tag already belongs to a draft or published release; never overwrite it")
    # Atomic ref creation refuses collisions, unlike a force-push or upload --clobber.
    gh("api", "--method", "POST", f"repos/{REPO}/git/refs", "-f", "ref=refs/tags/" + info["tag"], "-f", "sha=" + commit)
    release = gh("api", "--method", "POST", f"repos/{REPO}/releases",
                 "-f", "tag_name=" + info["tag"], "-f", "target_commitish=" + commit,
                 "-f", "name=RetroLife " + info["tag"], "-F", "draft=true", "-F", "prerelease=true",
                 "-f", "body=" + (directory / "release-notes.md").read_text())
    deltas = delta_assets(directory)
    upload_names = (*ASSETS, *deltas)
    result = subprocess.run(["gh", "release", "upload", info["tag"], *[str(directory / n) for n in upload_names], "--repo", REPO], capture_output=True)
    if result.returncode:
        raise RuntimeError("Asset upload failed. The release remains a draft; no update was advertised")
    # GitHub asset digests may become available shortly after upload.
    for attempt in range(6):
        remote = gh("api", f"repos/{REPO}/releases/{release['id']}")
        try:
            verify_remote(remote, directory)
            break
        except ValueError:
            if attempt == 5:
                raise
            time.sleep(5)
    gh("api", "--method", "PATCH", f"repos/{REPO}/releases/{release['id']}", "-F", "draft=false", "-F", "prerelease=true", "-f", "make_latest=false")
    print("Published " + info["tag"] + " with verified assets.")


def feed() -> None:
    assert_release_context(os.environ)
    spec = importlib.util.spec_from_file_location("release_feed", ROOT / "scripts/publish-update-feed.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # This explicit call is required: releases created by GITHUB_TOKEN do not
    # themselves trigger the release-event workflow.
    client = module.GitHub(os.environ.get("GH_TOKEN", ""))
    for attempt in range(5):
        try:
            content = module.render(client.items())
            client.publish(content)
            for retry in range(30):
                try:
                    with urllib.request.urlopen(FEED_URL + "?verify=" + str(time.time_ns()), timeout=30) as response:
                        published = response.read(len(content) + 1)
                    if published == content:
                        print("Public HTTPS updater feed matches the published release metadata.")
                        return
                except OSError:
                    pass
                time.sleep(5)
            raise ValueError("Public update feed is not readable yet; retry the feed job")
        except (OSError, ValueError, RuntimeError):
            if attempt == 4:
                raise
            time.sleep(5)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["preflight", "plan", "manifest", "audit", "publish", "feed", "notes"])
    parser.add_argument("--directory", type=Path, default=ROOT / "dist/release")
    parser.add_argument("--version", default="")
    args = parser.parse_args()
    if args.command == "preflight":
        assert_release_context(os.environ)
        missing = configuration_errors(os.environ)
        if missing:
            report = "Release signing is not configured. Missing in the macos-release environment:\n" + "\n".join("- " + m for m in missing) + "\nSee docs/automatic-releases.md. No unsigned replacement will be published.\n"
            if os.environ.get("GITHUB_STEP_SUMMARY"):
                Path(os.environ["GITHUB_STEP_SUMMARY"]).write_text(report)
            raise ValueError(report)
        output_values(public_key=os.environ["SPARKLE_PUBLIC_KEY"])
        print("Release configuration is present; private material was not read or printed.")
    elif args.command == "plan":
        plan()
    elif args.command == "feed":
        feed()
    elif args.command == "notes":
        version_info(args.version)
        notes = f"# RetroLife {args.version}\n\nAutomated testing prerelease for macOS 13+ / Apple Silicon.\n\nSource commit: {os.environ['GITHUB_SHA']}\nBuild evidence: https://github.com/{REPO}/actions/runs/{os.environ['GITHUB_RUN_ID']}\nDate: {datetime.now(timezone.utc).date()}\n\nInstall the signed DMG once to enable future in-app updates. This release includes the 3D cartridge library and Sparkle updater. Games, BIOS, labels and personal saves are not bundled.\n\nThis pipeline requires native automated tests, updater availability in the packaged app, Developer ID signing, notarization, stapling and Gatekeeper checks before publication. A prerelease is not hands-on acceptance: physical controllers, audible sound, sustained gameplay, real-user saves and signed-to-signed in-app upgrades still need target-Mac verification.\n\n## Source changelog\n\n" + (ROOT / "CHANGELOG.md").read_text()
        args.directory.mkdir(parents=True, exist_ok=True)
        (args.directory / "release-notes.md").write_text(notes)
    elif args.command == "manifest":
        write_manifest(args.directory, args.version, os.environ["GITHUB_SHA"], f"https://github.com/{REPO}/actions/runs/{os.environ['GITHUB_RUN_ID']}")
    elif args.command == "audit":
        audit_assets(args.directory, args.version, os.environ["GITHUB_SHA"])
    else:
        publish(args.directory, args.version)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError, subprocess.SubprocessError) as exc:
        print("Release automation failed: " + str(exc), file=sys.stderr)
        sys.exit(1)
