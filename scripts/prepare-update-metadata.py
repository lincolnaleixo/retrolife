#!/usr/bin/env python3
"""Sign the final notarized ZIP with the maintainer's existing Sparkle key."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import zipfile
from updates.common import ASSET_NAME, BUNDLE_ID, MINIMUM_OS, METADATA_NAME, decode_key, sha256, validate_metadata, version_info, write_json

ROOT = Path(__file__).resolve().parent.parent


def prepare(app: Path, archive: Path, account: str, notes: str) -> Path:
    if archive.name != ASSET_NAME:
        raise ValueError("Unexpected update ZIP name")
    data = plistlib.loads((app / "Contents" / "Info.plist").read_bytes())
    info = version_info(data.get("RLReleaseVersion", ""))
    if data.get("CFBundleVersion") != info["bundleVersion"]:
        raise ValueError("Application build identity does not match the release")
    with zipfile.ZipFile(archive) as bundle:
        embedded = plistlib.loads(bundle.read("RetroLife.app/Contents/Info.plist"))
        if embedded != data:
            raise ValueError("Update ZIP contains different app metadata; recreate it after signing/stapling")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "execute", str(app)], check=True)
    sdk = ROOT / ".cache" / "sparkle" / "2.10.0"
    public = subprocess.check_output([str(sdk / "bin/generate_keys"), "--account", account, "-p"], text=True).strip()
    decode_key(public, 32)
    if public != data.get("SUPublicEDKey"):
        raise ValueError("The app's pinned public key does not match the release signing account")
    signature = subprocess.check_output([str(sdk / "bin/sign_update"), "--account", account, "-p", str(archive)], text=True).strip()
    decode_key(signature, 64)
    subprocess.run([str(sdk / "bin/sign_update"), "--account", account, "--verify", str(archive), signature], check=True)
    metadata = {"schemaVersion": 1, **{k: info[k] for k in ("version", "tag", "bundleVersion", "channel")},
                "bundleId": BUNDLE_ID, "platform": "macos", "architecture": "arm64", "minimumSystemVersion": MINIMUM_OS,
                "asset": ASSET_NAME, "length": archive.stat().st_size, "sha256": sha256(archive), "edSignature": signature, "notes": notes}
    validate_metadata(metadata)
    output = archive.parent / METADATA_NAME
    write_json(output, metadata)
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--account", default="io.github.lincolnaleixo.retrolife.sparkle")
    parser.add_argument("--notes", type=Path)
    args = parser.parse_args()
    try:
        notes = args.notes.read_text(encoding="utf-8") if args.notes else "A signed RetroLife update. See GitHub Releases for the complete changelog."
        print(prepare(args.app, args.archive, args.account, notes))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Update metadata failed: {error}\n")
