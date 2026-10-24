#!/usr/bin/env python3
"""Exercise model staging with tiny original fixtures, without downloading assets."""
from __future__ import annotations
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
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

    def test_release_stage_rejects_owner_staged_labels(self) -> None:
        archive, lock = self.package()
        destination = self.root / "stage"
        assets.stage(archive, lock, destination)
        labels = destination / "labels" / "snes-super-mario-world"
        labels.mkdir(parents=True)
        (labels / "front.png").write_bytes(b"owner-only")
        with self.assertRaisesRegex(ValueError, "Owner-only"):
            assets.verify_stage(lock, destination)

    def test_platform_models_keep_separate_files_and_notices(self) -> None:
        for model_id in ("mega-drive", "playstation-1", "nintendo-64", "nes"):
            self.files = {model_id + ".glb": glb(), "LICENSE": model_id.encode(),
                          "CREDITS.md": b"Independent source", "NOTICE.md": b"Neutral model"}
            archive, lock = self.package()
            lock["id"] = model_id
            destination = self.root / "stage" / model_id
            assets.stage(archive, lock, destination)
            assets.verify_stage(lock, destination)
        for model_id in ("mega-drive", "playstation-1", "nintendo-64", "nes"):
            self.assertEqual((self.root / "stage" / model_id / "LICENSE").read_text(), model_id)
            self.assertTrue((self.root / "stage" / model_id / (model_id + ".glb")).is_file())


class PublicReleaseAssetsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.project = self.root / "frontend/godot-ui"
        (self.project / "assets/brand").mkdir(parents=True)
        (self.project / "assets/brand/icon.svg").write_text("<svg/>")
        self.tracked = {"assets/brand/icon.svg", "project.godot"}
        (self.project / "project.godot").write_text("config_version=5\n")

    def tearDown(self) -> None:
        self.directory.cleanup()

    def test_public_mode_is_offline_and_declares_no_private_models(self) -> None:
        manifest = self.root / "release-assets.json"
        with patch.object(assets, "ROOT", self.root), patch.object(assets, "public_project_files", return_value=self.tracked), patch.object(sys, "argv", ["prepare", "--mode", "public-neutral", "--release-project", "--manifest", str(manifest)]), patch.object(assets.urllib.request, "urlopen", side_effect=AssertionError("Public builds must be offline")):
            assets.main()
        self.assertEqual(json.loads(manifest.read_text()), assets.PUBLIC_MANIFEST)
        self.assertFalse((self.root / ".cache").exists())

    def test_public_mode_rejects_private_geometry_without_deleting_it(self) -> None:
        private = self.project / "assets/cartridges/snes.glb"
        private.parent.mkdir()
        private.write_bytes(glb())
        with self.assertRaisesRegex(ValueError, "Private cartridge assets"):
            assets.verify_public_project(self.project, self.tracked, True)
        self.assertEqual(private.read_bytes(), glb())

    def test_private_art_in_another_folder_cannot_bypass_the_guard(self) -> None:
        private = self.project / "assets/owner.png"
        private.write_bytes(b"private")
        with self.assertRaisesRegex(ValueError, "Unreviewed resource"):
            assets.verify_public_project(self.project, self.tracked, True)
        private.unlink()
        (self.project / "hidden-art.glb").write_bytes(glb())
        with self.assertRaisesRegex(ValueError, "Unreviewed resource"):
            assets.verify_public_project(self.project, self.tracked, True)

    def test_symlinks_cannot_supply_owner_art(self) -> None:
        (self.project / "assets/owner").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            assets.verify_public_project(self.project, self.tracked, True)

    def test_only_import_metadata_for_reviewed_resources_is_allowed(self) -> None:
        imported = self.project / "assets/brand/icon.svg.import"
        imported.write_text("original resource import")
        assets.verify_public_project(self.project, self.tracked, True)
        (self.project / "assets/owner.png.import").write_text("private cached import")
        with self.assertRaisesRegex(ValueError, "Unreviewed resource"):
            assets.verify_public_project(self.project, self.tracked, True)

    def test_native_build_outputs_are_allowed_but_extra_pack_is_rejected(self) -> None:
        (self.project / "bin").mkdir()
        (self.project / "bin/libretrolife_godot.dylib").write_bytes(b"native fixture")
        assets.verify_public_project(self.project, self.tracked, True)
        (self.project / "bin/owner.pck").write_bytes(b"private pack")
        with self.assertRaisesRegex(ValueError, "Unreviewed resource"):
            assets.verify_public_project(self.project, self.tracked, True)

    def test_owner_mode_cannot_create_a_public_release_manifest(self) -> None:
        with patch.object(sys, "argv", ["prepare", "--mode", "owner", "--release-project"]), self.assertRaises(SystemExit):
            assets.main()


class PreviewNoticeTests(unittest.TestCase):
    def test_preview_preserves_notices_from_current_and_legacy_source_layouts(self) -> None:
        script = Path(__file__).with_name("prepare-media-preview.py")
        consoles = {"snes-ntsc-u": "snes", "mega-drive": "mega-drive", "playstation-1": "playstation-1", "nintendo-64": "nintendo-64", "nes": "nes"}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for layout in ("current", "legacy"):
                with self.subTest(layout=layout):
                    source = root / layout
                    models = source / "dist/development"
                    expected = {}
                    for model_id, console in consoles.items():
                        model = models / model_id / f"{model_id}.glb"
                        model.parent.mkdir(parents=True)
                        model.write_bytes(glb({"asset": {"version": "2.0"}, "meshes": [{"name": "FrontLabel"}]}))
                        legacy = source / "assets" / model_id
                        legacy.mkdir(parents=True)
                        folder = source / "assets/templates" / console if layout == "current" else legacy
                        folder.mkdir(parents=True, exist_ok=True)
                        for name in ("LICENSE", "NOTICE.md", "CREDITS.md"):
                            # Canonical notices must win if both layouts exist.
                            (legacy / name).write_text("Legacy fixture notice\n")
                            content = f"{layout} {model_id} {name}\n"
                            (folder / name).write_text(content)
                            expected[(model_id, name)] = content
                    output = root / f"preview-{layout}"
                    subprocess.run(
                        [sys.executable, str(script), "--models-root", str(source),
                         "--owner-examples", str(models), "--output", str(output)],
                        check=True, capture_output=True, text=True,
                    )
                    notices = output / "assets/cartridges/source-notices"
                    for (model_id, name), content in expected.items():
                        self.assertEqual((notices / model_id / name).read_text(), content)
                    marker = json.loads((output / "owner-artwork-preview.json").read_text())
                    self.assertEqual(set(marker["ownerExampleIds"]), set(consoles) - {"snes-ntsc-u"})

    def test_missing_owner_example_does_not_bypass_neutral_checksum(self) -> None:
        script = Path(__file__).with_name("prepare-media-preview.py")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            models = root / "source/dist/development"
            examples = root / "examples"
            examples.mkdir()
            for model_id in ("snes-ntsc-u", "mega-drive"):
                model = models / model_id / f"{model_id}.glb"
                model.parent.mkdir(parents=True)
                model.write_bytes(glb({"asset": {"version": "2.0"}, "meshes": [{"name": "FrontLabel"}]}))
            result = subprocess.run(
                [sys.executable, str(script), "--models-root", str(root / "source"),
                 "--owner-examples", str(examples), "--output", str(root / "preview")],
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Size mismatch: mega-drive.glb", result.stderr)
            self.assertFalse((root / "preview").exists())


class CollectionLabelIndexTest(unittest.TestCase):
    """The committed app-side label metadata must match the pinned lock."""

    def test_label_index_is_included_in_exports(self) -> None:
        root = Path(__file__).resolve().parent.parent
        text = (root / "frontend/godot-ui/export_presets.cfg").read_text()
        include_lines = [line for line in text.splitlines() if line.startswith("include_filter=")]
        self.assertEqual(len(include_lines), 2)
        for line in include_lines:
            self.assertIn("scripts/library/collection_labels.json", line)

    def test_each_neutral_model_license_is_included_in_exports(self) -> None:
        root = Path(__file__).resolve().parent.parent
        models = json.loads((root / "assets/media-models.lock.json").read_text())["models"]
        include_lines = [line for line in (root / "frontend/godot-ui/export_presets.cfg").read_text().splitlines() if line.startswith("include_filter=")]
        for line in include_lines:
            self.assertIn("assets/cartridges/LICENSE", line)
            for model in models:
                self.assertIn(f"assets/cartridges/{model['id']}/LICENSE", line)

    def test_index_matches_lock(self) -> None:
        root = Path(__file__).resolve().parent.parent
        lock = json.loads((root / "assets/cartridges.lock.json").read_text())
        index = json.loads(
            (root / "frontend/godot-ui/scripts/library/collection_labels.json").read_text()
        )
        recorded = {
            entry["title"]: entry for entry in index["labels"]
        }
        expected = {
            entry["title"]: entry for entry in lock.get("labels", [])
        }
        self.assertEqual(set(recorded), set(expected))
        host = "https://raw.githubusercontent.com/lincolnaleixo/retro-3d-library/"
        for title, entry in recorded.items():
            source = expected[title]
            for side in ("front", "rear"):
                local = entry[side]
                lock_side = source[side]
                self.assertEqual(local["sha256"], lock_side["sha256"])
                self.assertEqual(local["bytes"], lock_side["bytes"])
                self.assertEqual(local["url"], host + source["tag"] + "/" + lock_side["path"])
                self.assertNotIn("/main/", local["url"])
                self.assertRegex(local["sha256"], r"^[a-f0-9]{64}$")
                self.assertRegex(local["path"], rf"^res://assets/cartridges/labels/.+{side}\.png$")


if __name__ == "__main__":
    unittest.main()
