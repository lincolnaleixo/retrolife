#!/usr/bin/env python3
"""Explicit local MP4-to-OGV conversion for a RetroLife presentation pack."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

MAX_VIDEO = 128 * 1024 * 1024


def convert(metadata_path: Path, ffmpeg: str) -> Path:
    """Keep the MP4, verify its optional checksum and atomically select an OGV."""
    metadata_path = metadata_path.resolve(strict=True)
    if metadata_path.stat().st_size > 256 * 1024:
        raise ValueError("The metadata document is too large.")
    original = metadata_path.read_bytes()
    document = json.loads(original)
    if not isinstance(document, dict) or document.get("schemaVersion") != 1:
        raise ValueError("Expected a version 1 RetroLife presentation pack.")
    entry = document.get("media", {}).get("video", {})
    name = entry.get("path", "") if isinstance(entry, dict) else ""
    if not isinstance(name, str) or not name or Path(name).name != name or ".." in name or ":" in name or "\\" in name or not name.lower().endswith(".mp4"):
        raise ValueError("Select a presentation pack with a local MP4 basename.")
    source = metadata_path.parent / name
    if source.is_symlink() or not source.is_file() or not 0 < source.stat().st_size <= MAX_VIDEO:
        raise ValueError("The source video is missing, linked or larger than 128 MB.")
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    if entry.get("sha256") and entry["sha256"] != source_hash:
        raise ValueError("The source video does not match its recorded checksum.")
    executable = shutil.which(ffmpeg)
    if executable is None:
        raise ValueError("Install ffmpeg or supply its executable path with --ffmpeg.")
    try:
        encoders = subprocess.run([executable, "-hide_banner", "-encoders"], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ValueError("The ffmpeg encoder list could not be checked.") from exc
    if encoders.returncode or "libtheora" not in encoders.stdout.split():
        raise ValueError("This ffmpeg has no libtheora encoder. Use a Theora-enabled ffmpeg; the existing MP4 still opens in your video player.")
    with tempfile.TemporaryDirectory(prefix=".video-convert-", dir=metadata_path.parent) as temporary:
        output = Path(temporary) / "preview.ogv"
        command = [executable, "-nostdin", "-hide_banner", "-loglevel", "error", "-protocol_whitelist", "file,pipe", "-f", "mov", "-i", str(source), "-map", "0:v:0", "-an", "-t", "120", "-vf", r"scale=min(1280\,iw):-2", "-c:v", "libtheora", "-q:v", "7", "-f", "ogg", str(output)]
        try:
            completed = subprocess.run(command, capture_output=True, check=False, timeout=180)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ValueError("Local video conversion could not finish. The original pack was retained.") from exc
        if completed.returncode or not output.is_file() or not 0 < output.stat().st_size <= MAX_VIDEO:
            raise ValueError("ffmpeg could not create a supported preview. The original pack was retained.")
        data = output.read_bytes()
        if not data.startswith(b"OggS"):
            raise ValueError("ffmpeg did not produce an Ogg video.")
        if metadata_path.read_bytes() != original or hashlib.sha256(source.read_bytes()).hexdigest() != source_hash:
            raise ValueError("The pack changed during conversion. It was not overwritten.")
        digest = hashlib.sha256(data).hexdigest()
        target = metadata_path.parent / ("video-" + digest[:20] + ".ogv")
        if target.exists():
            if target.is_symlink() or hashlib.sha256(target.read_bytes()).hexdigest() != digest:
                raise ValueError("The destination name is already occupied by different media.")
        else:
            os.replace(output, target)
        document["media"]["video"] = {"path": target.name, "sha256": digest, "source": str(entry.get("source", "Local video"))[:120] + " · local Theora preview"}
        pending = Path(temporary) / "metadata.json"
        pending.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
        os.replace(pending, metadata_path)
        return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("metadata", type=Path, help="Local presentation/metadata.json")
    parser.add_argument("--ffmpeg", default="ffmpeg", help="ffmpeg executable name or path")
    options = parser.parse_args()
    try:
        output = convert(options.metadata, options.ffmpeg)
    except (ValueError, OSError, TypeError, KeyError, AttributeError) as exc:
        # External command output and remote URLs are intentionally never printed.
        print("Conversion stopped: " + (str(exc) if isinstance(exc, ValueError) else "Invalid or unreadable local pack."))
        return 1
    print("Inline preview ready: " + str(output))
    print("The original MP4 is retained. Reopen this game's collection to refresh.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
