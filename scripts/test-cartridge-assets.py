#!/usr/bin/env python3
"""Exercise model staging with tiny original fixtures, without downloading assets."""
from __future__ import annotations
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("assets", Path(__file__).with_name("prepare-cartridge-assets.py"))
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)


def description(data: bytes) -> dict:
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def glb(document: dict | None = None) -> bytes:
    data = json.dumps(document or {"asset": {"version": "2.0"}, "meshes": [], "materials": []}).encode()
    data += b" " * ((-len(data)) % 4)
    return struct.pack("<4sIIII", b"glTF", 2, 20 + len(data), len(data), 0x4E4F534A) + data


class StagingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.files = {"snes-ntsc-u.glb": glb(), "LICENSE": b"Fixture license\n", "CREDITS.md": b"Original fixture\n", "NOTICE.md": b"No third-party artwork\n"}

    def tearDown(self) -> None:
        self.directory.cleanup()

    def package(self, extras: dict | None = None, prefix: str = "") -> tuple[Path, dict]:
        archive = self.root / "fixture.zip"
        with zipfile.ZipFile(archive, "w") as package:
            for name, data in (self.files | (extras or {})).items():
                package.writestr(prefix + name, data)
        lock = {"id": "fixture", "version": "0.0.0", "archive": description(archive.read_bytes()), "files": {name: description(data) for name, data in self.files.items()}}
        return archive, lock

    def test_verified_stage_and_offline_reverification(self) -> None:
        archive, lock = self.package(prefix="model-0.0.0/")
        destination = self.root / "stage"
        assets.stage(archive, lock, destination)
        assets.verify_stage(lock, destination)
        self.assertEqual((destination / "snes-ntsc-u.glb").read_bytes(), self.files["snes-ntsc-u.glb"])
        self.assertEqual(len(list(destination.iterdir())), 6)

    def test_wrong_archive_checksum(self) -> None:
        archive, lock = self.package()
        lock["archive"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            assets.stage(archive, lock, self.root / "stage")

    def test_wrong_member_checksum(self) -> None:
        archive, lock = self.package()
        lock["files"]["LICENSE"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            assets.stage(archive, lock, self.root / "stage")
        self.assertFalse((self.root / "stage").exists())

    def test_path_traversal(self) -> None:
        archive, lock = self.package({"../escape": b"unsafe"})
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            assets.stage(archive, lock, self.root / "stage")
        self.assertFalse((self.root / "escape").exists())

    def test_duplicate_selected_basename(self) -> None:
        archive, lock = self.package({"other/LICENSE": self.files["LICENSE"]})
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            assets.stage(archive, lock, self.root / "stage")

    def test_external_glb_resource(self) -> None:
        self.files["snes-ntsc-u.glb"] = glb({"asset": {"version": "2.0"}, "images": [{"uri": "https://example.invalid/texture.png"}]})
        archive, lock = self.package()
        with self.assertRaisesRegex(ValueError, "embedded"):
            assets.stage(archive, lock, self.root / "stage")

    def test_missing_member(self) -> None:
        archive, lock = self.package()
        lock["files"]["missing"] = description(b"no")
        with self.assertRaisesRegex(ValueError, "Missing"):
            assets.stage(archive, lock, self.root / "stage")

    def test_modified_stage_rejected(self) -> None:
        archive, lock = self.package()
        destination = self.root / "stage"
        assets.stage(archive, lock, destination)
        (destination / "LICENSE").write_bytes(b"changed")
        with self.assertRaises(ValueError):
            assets.verify_stage(lock, destination)

    def test_staging_is_idempotent(self) -> None:
        archive, lock = self.package()
        destination = self.root / "stage"
        assets.stage(archive, lock, destination)
        before = (destination / "snes-ntsc-u.glb").stat().st_mtime_ns
        assets.stage(archive, lock, destination)
        self.assertEqual(before, (destination / "snes-ntsc-u.glb").stat().st_mtime_ns)


if __name__ == "__main__":
    unittest.main()
