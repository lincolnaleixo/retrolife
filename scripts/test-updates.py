#!/usr/bin/env python3
"""Offline updater contracts: versions, trust inputs and publication boundaries."""
import base64
from copy import deepcopy
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import sys
import tarfile
import tempfile
import unittest
import xml.etree.ElementTree as ET
from updates.common import ASSET_NAME, BUNDLE_ID, FEED_URL, MINIMUM_OS, decode_key, validate_metadata, version_info
from updates.feed import SPARKLE, download_url, release_item, render

ROOT = Path(__file__).resolve().parent.parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sdk = load("prepare_sparkle", "prepare-sparkle.py")
config = load("configure_updater", "configure-updater-bundle.py")
publisher = load("publish_feed", "publish-update-feed.py")


def metadata(version="0.1.0-beta.10"):
    info = version_info(version)
    return {"schemaVersion": 1, **{k: info[k] for k in ("version", "tag", "bundleVersion", "channel")},
            "bundleId": BUNDLE_ID, "platform": "macos", "architecture": "arm64", "minimumSystemVersion": MINIMUM_OS,
            "asset": ASSET_NAME, "length": 1234, "sha256": "a" * 64,
            "edSignature": base64.b64encode(bytes(range(64))).decode(), "notes": "Notes <script>alert(1)</script> & details"}


def release(data):
    return {"tag_name": data["tag"], "draft": False, "prerelease": data["channel"] == "beta", "published_at": "2026-09-15T12:00:00Z",
            "assets": [{"name": ASSET_NAME, "size": data["length"], "state": "uploaded",
                        "browser_download_url": download_url(data["tag"], ASSET_NAME), "digest": "sha256:" + data["sha256"]}]}


class Versions(unittest.TestCase):
    def test_apple_bundle_versions(self):
        for version, expected in (("0.1.0-alpha.1", "0.1.0a1"), ("v0.1.0-beta.10", "0.1.0b10"), ("0.1.0-rc.2", "0.1.0fc2"), ("0.1.0", "0.1.0")):
            self.assertEqual(version_info(version)["bundleVersion"], expected)

    def test_semantic_order_not_string_or_release_date(self):
        versions = ["0.1.0-alpha.1", "0.1.0-beta.2", "0.1.0-beta.10", "0.1.0-rc.1", "0.1.0", "0.2.0-beta.1"]
        self.assertEqual(sorted(reversed(versions), key=lambda v: version_info(v)["sort"]), versions)

    def test_reject_malformed_and_out_of_range_versions(self):
        for value in ("1", "0.1", "01.1.0", "0.1.0-beta.0", "0.1.0-beta.256", "0.1.0-beta.01", "0.1.0;echo hi", "0.1.0+build", "10000.0.0", "0.100.0", "0.1.0\n"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                version_info(value)


class Contracts(unittest.TestCase):
    def test_signatures_are_strict_base64(self):
        decode_key(metadata()["edSignature"], 64)
        for value in ("", "a" * 88, "\n" + metadata()["edSignature"], "%%%", base64.b64encode(b"a" * 63).decode()):
            with self.subTest(value=value), self.assertRaises(ValueError):
                decode_key(value, 64)

    def test_metadata_rejects_wrong_platform_identity_or_missing_signature(self):
        for field, value in (("schemaVersion", 2), ("bundleId", "other"), ("platform", "linux"), ("architecture", "x86_64"), ("channel", "stable"), ("tag", "v0.1.0"), ("bundleVersion", "0.1.0b2"), ("length", -1), ("length", True), ("length", 2**40), ("sha256", "not a hash"), ("asset", "file.pkg"), ("edSignature", ""), ("notes", "bad\x00text")):
            data = metadata()
            data[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                validate_metadata(data)

    def test_release_asset_is_exact_not_a_remote_manifest_url(self):
        data = metadata()
        good = release(data)
        release_item(good, data)
        for field, value in (("browser_download_url", "https://evil.invalid/app.zip"), ("size", 1), ("state", "new"), ("digest", "sha256:" + "b" * 64)):
            bad = deepcopy(good)
            bad["assets"][0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                release_item(bad, data)

    def test_drafts_and_inconsistent_channel_are_rejected(self):
        data = metadata()
        for changes in ({"draft": True}, {"prerelease": False}, {"tag_name": "v0.1.0-beta.2"}, {"assets": []}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                release_item({**release(data), **changes}, data)

    def test_feed_preserves_stable_and_beta_and_escapes_html(self):
        items = [release_item(release(metadata(v)), metadata(v)) for v in ("0.1.0-beta.2", "0.1.0-beta.10", "0.1.0")]
        tree = ET.fromstring(render(items))
        elements = tree.findall("./channel/item")
        self.assertEqual([item.find(f"{{{SPARKLE}}}version").text for item in elements], ["0.1.0", "0.1.0b10", "0.1.0b2"])
        self.assertIsNone(elements[0].find(f"{{{SPARKLE}}}channel"))
        self.assertEqual(elements[1].find(f"{{{SPARKLE}}}channel").text, "beta")
        self.assertNotIn("<script>", elements[0].find("description").text)
        self.assertIn("&lt;script&gt;", elements[0].find("description").text)
        self.assertTrue(elements[0].find("enclosure").get(f"{{{SPARKLE}}}edSignature"))

    def test_duplicate_bundle_versions_are_rejected(self):
        data = metadata()
        item = release_item(release(data), data)
        with self.assertRaises(ValueError):
            render([item, item])

    def test_empty_feed_is_valid_but_does_not_invent_a_release(self):
        self.assertEqual(ET.fromstring(render([])).findall("./channel/item"), [])

    def test_stable_not_dropped_by_many_newer_betas(self):
        versions = ["0.1.0"] + [f"0.2.0-beta.{i}" for i in range(1, 35)]
        tree = ET.fromstring(render([release_item(release(metadata(v)), metadata(v)) for v in versions]))
        self.assertEqual(len(tree.findall("./channel/item")), 21)
        self.assertIn("0.1.0", [e.text for e in tree.findall(f"./channel/item/{{{SPARKLE}}}version")])

    def test_feed_publish_fast_forward_is_idempotent(self):
        class Fake(publisher.GitHub):
            def __init__(self):
                self.calls = []
            def api(self, path, data=None, method="GET", missing=False):
                self.calls.append((path, data, method))
                if path == "git/ref/heads/updates": return {"object": {"sha": "existing"}}
                if path.startswith("contents/"): return {"content": base64.b64encode(render([])).decode()}
                raise AssertionError("Unnecessary write")
        fake = Fake()
        self.assertFalse(fake.publish(render([])))
        self.assertTrue(all(call[2] == "GET" for call in fake.calls))


class Bundle(unittest.TestCase):
    def fixture(self, root):
        app = root / "RetroLife.app"
        content = app / "Contents"
        (content / "Frameworks/Sparkle.framework").mkdir(parents=True)
        (content / "Frameworks/Sparkle.framework/Sparkle").write_text("test")
        (content / "Frameworks/libretrolife_updater.dylib").write_text("test")
        (content / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": BUNDLE_ID}))
        return app

    def test_release_bundle_has_identity_key_feed_and_opt_in_install(self):
        with tempfile.TemporaryDirectory() as temp:
            app = self.fixture(Path(temp))
            key = base64.b64encode(b"x" * 32).decode()
            config.configure(app, "0.1.0-beta.10", key)
            data = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            self.assertEqual(data["CFBundleVersion"], "0.1.0b10")
            self.assertEqual(data["SUPublicEDKey"], key)
            self.assertEqual(data["SUFeedURL"], FEED_URL)
            self.assertTrue(data["SUEnableAutomaticChecks"])
            self.assertFalse(data["SUAutomaticallyUpdate"])
            self.assertFalse(data["SUEnableSystemProfiling"])
            self.assertTrue(data["SUVerifyUpdateBeforeExtraction"])

    def test_release_refuses_missing_key_or_framework_or_test_overrides(self):
        with tempfile.TemporaryDirectory() as temp:
            app = self.fixture(Path(temp))
            key = base64.b64encode(b"x" * 32).decode()
            with self.assertRaises(ValueError): config.configure(app, "0.1.0", "")
            plist = app / "Contents/Info.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleIdentifier": BUNDLE_ID, "RLTestMode": "test"}))
            with self.assertRaises(ValueError): config.configure(app, "0.1.0", key)
            plist.write_bytes(plistlib.dumps({"CFBundleIdentifier": BUNDLE_ID}))
            (app / "Contents/Frameworks/libretrolife_updater.dylib").unlink()
            with self.assertRaises(ValueError): config.configure(app, "0.1.0", key)


class Archive(unittest.TestCase):
    def test_sdk_checksum_mismatch_and_offline_missing(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "corrupt.tar.xz"
            archive.write_bytes(b"not the SDK")
            with self.assertRaises(ValueError): sdk.prepare(archive, offline=True)
            with self.assertRaises(ValueError): sdk.prepare(Path(temp) / "missing", offline=True)

    def test_unsafe_paths_links_devices_rejected(self):
        for name, kind, target in (("../escape", tarfile.REGTYPE, ""), ("/absolute", tarfile.REGTYPE, ""), ("link", tarfile.SYMTYPE, "../../escape"), ("link", tarfile.SYMTYPE, "/absolute"), ("device", tarfile.CHRTYPE, ""), ("hardlink", tarfile.LNKTYPE, "target")):
            with self.subTest(name=name, kind=kind), tempfile.TemporaryDirectory() as temp:
                archive = Path(temp) / "bad.tar.xz"
                with tarfile.open(archive, "w:xz") as stream:
                    member = tarfile.TarInfo(name)
                    member.type, member.linkname = kind, target
                    stream.addfile(member)
                destination = Path(temp) / "out"
                destination.mkdir()
                with self.assertRaises((ValueError, tarfile.TarError)):
                    sdk.safe_unpack(archive, destination)


if __name__ == "__main__":
    unittest.main(verbosity=2)
