#!/usr/bin/env python3
"""Fixture tests; no real video, network or credentials required."""
import hashlib
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("convert_presentation", Path(__file__).with_name("convert-presentation-video.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ConversionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="retrolife-video-test-")
        self.root = Path(self.directory.name)
        self.video = self.root / "video.mp4"
        self.video.write_bytes(b"fixture-mp4")
        self.document = {"schemaVersion": 1, "game": {"system": "snes", "slug": "example-game", "title": "Example"}, "media": {"video": {"path": "video.mp4", "sha256": hashlib.sha256(self.video.read_bytes()).hexdigest(), "source": "Fixture"}}}
        self.metadata = self.root / "metadata.json"
        self.save()

    def tearDown(self):
        self.directory.cleanup()

    def save(self):
        self.metadata.write_text(json.dumps(self.document))

    def fake_run(self, command, **_kwargs):
        if "-encoders" in command:
            return SimpleNamespace(returncode=0, stdout=" V....D libtheora Theora video")
        self.assertEqual(command[command.index("-protocol_whitelist") + 1], "file,pipe")
        self.assertEqual(command[command.index("-t") + 1], "120")
        self.assertIn("-nostdin", command)
        self.assertIn("-an", command)
        Path(command[-1]).write_bytes(b"OggSfixture-theora")
        return SimpleNamespace(returncode=0)

    def test_converts_atomically_and_retains_source(self):
        with patch.object(module.shutil, "which", return_value="/fixture/ffmpeg"), patch.object(module.subprocess, "run", side_effect=self.fake_run):
            output = module.convert(self.metadata, "ffmpeg")
        result = json.loads(self.metadata.read_text())
        self.assertTrue(self.video.exists())
        self.assertEqual(result["media"]["video"]["path"], output.name)
        self.assertEqual(result["media"]["video"]["sha256"], hashlib.sha256(output.read_bytes()).hexdigest())
        self.assertEqual(result["game"], self.document["game"])

    def test_rejects_checksum_mismatch_without_modification(self):
        self.document["media"]["video"]["sha256"] = "0" * 64
        self.save()
        original = self.metadata.read_bytes()
        with self.assertRaises(ValueError):
            module.convert(self.metadata, "ffmpeg")
        self.assertEqual(self.metadata.read_bytes(), original)

    def test_rejects_path_traversal(self):
        self.document["media"]["video"]["path"] = "../video.mp4"
        self.save()
        with self.assertRaises(ValueError):
            module.convert(self.metadata, "ffmpeg")

    def test_preserves_new_edit_during_conversion(self):
        def concurrent_edit(command, **kwargs):
            response = self.fake_run(command, **kwargs)
            if "-encoders" in command:
                return response
            self.document["description"] = "Concurrent edit must survive"
            self.save()
            return response
        with patch.object(module.shutil, "which", return_value="/fixture/ffmpeg"), patch.object(module.subprocess, "run", side_effect=concurrent_edit):
            with self.assertRaises(ValueError):
                module.convert(self.metadata, "ffmpeg")
        self.assertEqual(json.loads(self.metadata.read_text())["description"], "Concurrent edit must survive")
        self.assertEqual(json.loads(self.metadata.read_text())["media"]["video"]["path"], "video.mp4")

    def test_failed_transcode_preserves_pack(self):
        original = self.metadata.read_bytes()
        with patch.object(module.shutil, "which", return_value="/fixture/ffmpeg"), patch.object(module.subprocess, "run", return_value=SimpleNamespace(returncode=1)):
            with self.assertRaises(ValueError):
                module.convert(self.metadata, "ffmpeg")
        self.assertEqual(self.metadata.read_bytes(), original)

    def test_missing_theora_has_clear_error_and_preserves_pack(self):
        original = self.metadata.read_bytes()
        with patch.object(module.shutil, "which", return_value="/fixture/ffmpeg"), patch.object(module.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout="libx264")):
            with self.assertRaisesRegex(ValueError, "no libtheora encoder"):
                module.convert(self.metadata, "ffmpeg")
        self.assertEqual(self.metadata.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
