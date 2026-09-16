#!/usr/bin/env python3
"""Verify real exported app/resources and a disposable ad-hoc runtime copy.

This does not assert Developer ID/notarization. It must never publish its copy.
"""
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
from updates.common import BUNDLE_ID, FEED_URL, version_info

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    if sys.platform != "darwin":
        raise ValueError("Run the packaging regression on macOS")
    version, public = sys.argv[1:3]
    expected = version_info(version)
    output = ROOT / "dist/unsigned"
    app = output / "RetroLife.app"
    data = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    for key, value in {"CFBundleIdentifier": BUNDLE_ID, "RLReleaseVersion": version,
                       "CFBundleVersion": expected["bundleVersion"], "SUPublicEDKey": public,
                       "SUFeedURL": FEED_URL, "SUVerifyUpdateBeforeExtraction": True}.items():
        if data.get(key) != value:
            raise ValueError("Incorrect packaged setting: " + key)
    if any(k.startswith("RLTest") for k in data):
        raise ValueError("Test-only trust configuration leaked into a release bundle")
    for component in ("Sparkle.framework/Sparkle", "libretrolife_updater.dylib", "libretrolife_godot.dylib", "bsnes-jg_libretro.dylib"):
        binary = app / "Contents/Frameworks" / component
        subprocess.run(["lipo", str(binary), "-verify_arch", "arm64"], check=True)
    for notice in ("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md", "Sparkle-LICENSE", "retro-cartridge-models/LICENSE", "retro-cartridge-models/provenance.json"):
        if not (app / "Contents/Resources/licenses" / notice).is_file():
            raise ValueError("Missing packaged notice: " + notice)
    for name in ("retrolife-source.tar.gz", "retrolife-rust-dependencies.tar.gz", "bsnes-jg.tar.gz"):
        with tarfile.open(output / name) as archive:
            if not archive.getmembers():
                raise ValueError("An empty corresponding-source archive cannot be released")
            if name == "retrolife-source.tar.gz":
                if "retrolife/.github/workflows/auto-release.yml" not in archive.getnames():
                    raise ValueError("Corresponding source must include release workflows")
    with tempfile.TemporaryDirectory(prefix="retrolife-package-test-") as temporary:
        copy = Path(temporary) / "RetroLife.app"
        # Explicitly test-only signing. The production artifact is not changed.
        subprocess.run(["ditto", str(app), str(copy)], check=True)
        subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(copy)], check=True, capture_output=True)
        marker = "RETROLIFE_UPDATE_RELEASE_CHECK "
        process = subprocess.run([str(copy / "Contents/MacOS/RetroLife"), "--headless", "--", "--verify-updater-release"],
                                 capture_output=True, text=True, timeout=45)
        if "SCRIPT ERROR" in process.stderr or "Parse Error" in process.stderr:
            raise ValueError("Exported Godot release probe has a script error")
        lines = [line[len(marker):] for line in process.stdout.splitlines() if line.startswith(marker)]
        if process.returncode != 2 or len(lines) != 1:
            raise ValueError("The actual exported app did not execute the release probe correctly")
        state = json.loads(lines[0])
        if state.get("available") is not False or state.get("currentVersion") != version:
            raise ValueError("Headless app must report its real version without enabling unsigned updates")
    print("Release packaging passed: arm64 components, notices, corresponding source and actual packaged Godot probe.")
    print("The ad-hoc/headless test remains update-disabled. No signed release acceptance is claimed.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit("Release packaging regression failed: " + str(error))
