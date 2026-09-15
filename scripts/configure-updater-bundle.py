#!/usr/bin/env python3
"""Inject updater release identity and trust before signing, never afterwards."""
import argparse
from pathlib import Path
import plistlib
from updates.common import BUNDLE_ID, FEED_URL, decode_key, version_info


def configure(app: Path, version: str, public_key: str) -> dict:
    info = version_info(version)
    decode_key(public_key, 32)
    plist_path = app / "Contents" / "Info.plist"
    data = plistlib.loads(plist_path.read_bytes())
    if data.get("CFBundleIdentifier") != BUNDLE_ID:
        raise ValueError("Unexpected application bundle identifier")
    frameworks = app / "Contents" / "Frameworks"
    if not (frameworks / "Sparkle.framework" / "Sparkle").is_file() or not (frameworks / "libretrolife_updater.dylib").is_file():
        raise ValueError("Embed the updater and Sparkle before configuring the bundle")
    data.update({
        "CFBundleVersion": info["bundleVersion"],
        "CFBundleShortVersionString": info["shortVersion"],
        "RLReleaseVersion": info["version"],
        "RLDefaultBetaUpdates": info["channel"] == "beta",
        "SUFeedURL": FEED_URL, "SUPublicEDKey": public_key,
        "SUEnableAutomaticChecks": True, "SUAutomaticallyUpdate": False,
        "SUAllowsAutomaticUpdates": True, "SUScheduledCheckInterval": 86400,
        "SUEnableSystemProfiling": False,
    })
    # Do not embed test overrides in a release app.
    for key in list(data):
        if key.startswith("RLTest"):
            raise ValueError("Test-only updater configuration cannot be released")
    plist_path.write_bytes(plistlib.dumps(data, sort_keys=True))
    return info


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("version")
    parser.add_argument("public_key")
    args = parser.parse_args()
    try:
        print(configure(args.app, args.version, args.public_key)["version"])
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Updater configuration failed: {error}\n")
