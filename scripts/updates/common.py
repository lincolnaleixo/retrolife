"""Release contracts shared by packaging, appcast generation and tests."""
from __future__ import annotations

import base64
import hashlib
import json
import re
from pathlib import Path

REPOSITORY = "lincolnaleixo/retrolife"
BUNDLE_ID = "io.github.lincolnaleixo.retrolife"
FEED_URL = f"https://raw.githubusercontent.com/{REPOSITORY}/updates/appcast.xml"
ASSET_NAME = "RetroLife-macos-arm64.zip"
METADATA_NAME = "retrolife-update.json"
MINIMUM_OS = "13.0"
MAX_ARCHIVE = 1024 * 1024 * 1024
MAX_DELTAS = 3
DELTA_NAME = re.compile(r"RetroLife-macos-arm64-from-([0-9]+\.[0-9]+\.[0-9]+(?:[ab]|fc)[0-9]+)\.delta\Z")
_VERSION = re.compile(r"v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(alpha|beta|rc)\.([1-9][0-9]*))?\Z")
_BUNDLE = re.compile(r"(\d+)\.(\d+)\.(\d+)(?:(a|b|fc)(\d+))?\Z")


def bundle_sort(value: str) -> tuple:
    """Order CFBundleVersion values, including Apple's a/b/fc suffixes."""
    match = _BUNDLE.fullmatch(value)
    if not match:
        raise ValueError("Invalid bundle version")
    major, minor, patch = map(int, match.group(1, 2, 3))
    stage, sequence = match.group(4, 5)
    return (major, minor, patch, {"a": 0, "b": 1, "fc": 2, None: 3}[stage], int(sequence or 0))


def version_info(value: str) -> dict:
    """Use Apple's supported a/b/fc suffixes, not lexicographic tag ordering."""
    match = _VERSION.fullmatch(value)
    if not match:
        raise ValueError("Use a release version such as 0.1.0, 0.1.0-beta.3 or 0.1.0-rc.1")
    major, minor, patch = map(int, match.group(1, 2, 3))
    stage, sequence = match.group(4, 5)
    if major > 9999 or minor > 99 or patch > 99:
        raise ValueError("Version exceeds the supported CFBundleVersion component sizes")
    if sequence and int(sequence) > 255:
        raise ValueError("Apple prerelease build suffixes must be between 1 and 255")
    base = f"{major}.{minor}.{patch}"
    version = base + (f"-{stage}.{sequence}" if stage else "")
    suffix = {"alpha": "a", "beta": "b", "rc": "fc"}.get(stage, "")
    return {
        "version": version, "tag": "v" + version,
        "bundleVersion": base + (suffix + sequence if stage else ""),
        "shortVersion": base, "channel": "beta" if stage else "stable",
        "sort": (major, minor, patch, {"alpha": 0, "beta": 1, "rc": 2, None: 3}[stage], int(sequence or 0)),
    }


def decode_key(value: str, size: int) -> bytes:
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, TypeError) as exc:
        raise ValueError("Invalid base64 signing value") from exc
    if len(decoded) != size or base64.b64encode(decoded).decode() != value:
        raise ValueError(f"Signing value must be canonical base64 for {size} bytes")
    return decoded


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_metadata(data: dict) -> dict:
    if not isinstance(data, dict) or data.get("schemaVersion") != 1:
        raise ValueError("Unsupported update metadata schema")
    info = version_info(data.get("version", ""))
    for field in ("tag", "bundleVersion", "channel"):
        if data.get(field) != info[field]:
            raise ValueError(f"Update metadata {field} disagrees with its version")
    expected = {"bundleId": BUNDLE_ID, "platform": "macos", "architecture": "arm64",
                "minimumSystemVersion": MINIMUM_OS, "asset": ASSET_NAME}
    for field, value in expected.items():
        if data.get(field) != value:
            raise ValueError(f"Unexpected update {field}")
    length = data.get("length")
    if type(length) is not int or not 0 < length <= MAX_ARCHIVE:
        raise ValueError("Invalid update archive size")
    if not re.fullmatch(r"[0-9a-f]{64}", str(data.get("sha256", ""))):
        raise ValueError("Invalid update archive SHA-256")
    decode_key(data.get("edSignature", ""), 64)
    deltas = data.get("deltas", [])
    if not isinstance(deltas, list) or len(deltas) > MAX_DELTAS:
        raise ValueError("Invalid delta update list")
    for delta in deltas:
        if not isinstance(delta, dict):
            raise ValueError("Invalid delta update entry")
        match = DELTA_NAME.fullmatch(str(delta.get("asset", "")))
        if not match or delta.get("deltaFrom") != match.group(1):
            raise ValueError("Invalid delta update asset")
        if delta["deltaFrom"] == info["bundleVersion"]:
            raise ValueError("A delta update must come from a different build")
        delta_length = delta.get("length")
        if type(delta_length) is not int or not 0 < delta_length <= MAX_ARCHIVE:
            raise ValueError("Invalid delta update size")
        if not re.fullmatch(r"[0-9a-f]{64}", str(delta.get("sha256", ""))):
            raise ValueError("Invalid delta update SHA-256")
        decode_key(delta.get("edSignature", ""), 64)
    notes = data.get("notes", "")
    if not isinstance(notes, str) or len(notes) > 16000 or any(ord(c) < 32 and c not in "\n\t\r" for c in notes):
        raise ValueError("Invalid release notes")
    return info


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)
