#!/usr/bin/env python3
"""Verify a pinned neutral model and stage unchanged build inputs, never game art.

Use --archive for an offline build, --verify-only to audit an existing stage.
The model's independent license and notices travel with the unchanged GLB.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import struct
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
LOCK = ROOT / "assets/cartridges.lock.json"
DEST = ROOT / "frontend/godot-ui/assets/cartridges"
MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_EXPANDED_BYTES = 128 * 1024 * 1024


def verify(path: Path, expected: dict) -> None:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Missing or unsafe asset: {path.name}")
    if path.stat().st_size != expected["bytes"]:
        raise ValueError(f"Size mismatch: {path.name}")
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != expected["sha256"]:
        raise ValueError(f"Checksum mismatch: {path.name}")


def validate_glb(path: Path) -> dict:
    with path.open("rb") as stream:
        header = stream.read(20)
        if len(header) != 20:
            raise ValueError("Truncated GLB header")
        magic, version, length, chunk_length, chunk_type = struct.unpack("<4sIIII", header)
        if (magic != b"glTF" or version != 2 or length != path.stat().st_size
                or chunk_type != 0x4E4F534A or chunk_length > 4 * 1024 * 1024):
            raise ValueError("Invalid GLB structure")
        document = json.loads(stream.read(chunk_length))
    for entry in document.get("images", []) + document.get("buffers", []):
        if "uri" in entry:
            raise ValueError("Only embedded GLB resources are allowed")
    if document.get("cameras") or document.get("extensions", {}).get("KHR_lights_punctual"):
        raise ValueError("Cartridges must not import cameras or lights")
    return {
        "meshes": [mesh.get("name", "") for mesh in document.get("meshes", [])],
        "materials": [material.get("name", "") for material in document.get("materials", [])],
        "embeddedImages": len(document.get("images", [])),
    }


def stage(archive: Path, lock: dict, destination: Path) -> None:
    verify(archive, lock["archive"])
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cartridges-", dir=destination.parent) as temporary:
        work = Path(temporary)
        with zipfile.ZipFile(archive) as package:
            members: dict[str, zipfile.ZipInfo] = {}
            expanded = 0
            for member in package.infolist():
                name = PurePosixPath(member.filename)
                mode = member.external_attr >> 16
                if (name.is_absolute() or ".." in name.parts or "\\" in member.filename
                        or stat.S_ISLNK(mode) or member.flag_bits & 1):
                    raise ValueError("Unsafe archive member")
                expanded += member.file_size
                if expanded > MAX_EXPANDED_BYTES:
                    raise ValueError("Expanded archive exceeds the size budget")
                if member.is_dir():
                    continue
                # Some model packages have a versioned top-level folder.
                if name.name in lock["files"]:
                    if name.name in members:
                        raise ValueError("Duplicate selected archive member")
                    members[name.name] = member
            for name, expected in lock["files"].items():
                member = members.get(name)
                if member is None or member.file_size != expected["bytes"]:
                    raise ValueError(f"Missing or wrong-sized package member: {name}")
                with package.open(member) as source, (work / name).open("wb") as target:
                    shutil.copyfileobj(source, target, 1024 * 1024)
                verify(work / name, expected)
        summary = validate_glb(work / "snes-ntsc-u.glb")
        (work / "model-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        (work / "provenance.json").write_text(json.dumps(lock, indent=2) + "\n")
        # Validate everything before replacing any previous verified inputs.
        destination.mkdir(parents=True, exist_ok=True)
        for item in work.iterdir():
            target = destination / item.name
            if target.is_file() and target.read_bytes() == item.read_bytes():
                continue
            os.replace(item, target)
    print(f"Staged {lock['id']} {lock['version']}: {len(summary['meshes'])} meshes")
    print("Cartridge material slots: " + ", ".join(summary["materials"]))


def verify_stage(lock: dict, destination: Path) -> None:
    for name, expected in lock["files"].items():
        verify(destination / name, expected)
    if json.loads((destination / "provenance.json").read_text()) != lock:
        raise ValueError("Staged provenance does not match the asset lock")
    validate_glb(destination / "snes-ntsc-u.glb")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Use this verified archive without network access")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text())
    if args.verify_only:
        verify_stage(lock, DEST)
        print("Pinned cartridge assets and notices verified")
        return
    if args.archive is None:
        try:
            verify_stage(lock, DEST)
            print("Pinned cartridge assets already verified")
            return
        except (ValueError, OSError, json.JSONDecodeError):
            pass
    archive = args.archive or ROOT / ".cache/cartridges" / lock["archive"]["name"]
    if not archive.exists():
        if args.archive:
            raise ValueError("The supplied offline archive does not exist")
        archive.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(dir=archive.parent, suffix=".download")
        try:
            with os.fdopen(descriptor, "wb") as target:
                request = urllib.request.Request(lock["archive"]["url"], headers={"User-Agent": "RetroLife-asset-builder"})
                with urllib.request.urlopen(request, timeout=60) as response:
                    total = 0
                    while block := response.read(1024 * 1024):
                        total += len(block)
                        if total > MAX_ARCHIVE_BYTES:
                            raise ValueError("Archive download exceeds the size budget")
                        target.write(block)
            verify(Path(temporary), lock["archive"])
            os.replace(temporary, archive)
        finally:
            Path(temporary).unlink(missing_ok=True)
    stage(archive, lock, DEST)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        raise SystemExit(f"Cartridge preparation failed: {error}") from error
