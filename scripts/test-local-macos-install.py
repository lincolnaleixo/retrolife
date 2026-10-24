#!/usr/bin/env python3
"""Portable installer safety tests. No Keychain, signing key or TCC access."""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("local_install", Path(__file__).with_name("install-local-macos.py"))
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)
IDENTITY = "A" * 40
DEVELOPMENT = f'  1) {IDENTITY} "Apple Development: Local Test (TEST123456)"\n'
REQUIREMENT = 'identifier "io.github.lincolnaleixo.retrolife" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: Local Test (TEST123456)"'
PIN = {"bundleId": installer.BUNDLE_ID, "identity": IDENTITY, "requirement": REQUIREMENT}


def app(path: Path, marker: str = "old") -> Path:
    (path / "Contents/MacOS").mkdir(parents=True)
    (path / "Contents/Frameworks").mkdir()
    (path / "Contents/Resources").mkdir()
    (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": installer.BUNDLE_ID,
        "RLBuildChannel": "local-development", "CFBundleExecutable": "RetroLife"}))
    (path / "Contents/MacOS/RetroLife").write_bytes(b"\xcf\xfa\xed\xfe" + marker.encode())
    (path / "Contents/Frameworks/core.dylib").write_bytes(b"\xcf\xfa\xed\xfe" + marker.encode())
    (path / "Contents/Resources/marker").write_text(marker)
    return path


class IdentityTests(unittest.TestCase):
    def test_first_setup_requires_explicit_development_identity(self):
        for selected, listing in [(None, DEVELOPMENT), ("-", DEVELOPMENT),
                                  (IDENTITY, DEVELOPMENT.replace("Apple Development:", "Developer ID Application:"))]:
            with self.subTest(selected=selected, listing=listing), self.assertRaises(ValueError):
                installer.select_identity(selected, None, listing)
        self.assertEqual(installer.select_identity(IDENTITY.lower(), None, DEVELOPMENT), IDENTITY)

    def test_existing_pin_is_reused_and_cannot_change(self):
        self.assertEqual(installer.select_identity(None, PIN, DEVELOPMENT), IDENTITY)
        with self.assertRaises(ValueError):
            installer.select_identity("B" * 40, PIN, DEVELOPMENT)
        with self.assertRaises(ValueError):
            installer.select_identity(None, PIN, "0 valid identities found")
        with self.assertRaises(ValueError):
            installer.select_identity(None, {**PIN, "bundleId": "other.app"}, DEVELOPMENT)

    def test_pin_write_is_atomic_and_private(self):
        with tempfile.TemporaryDirectory() as temporary:
            pin = Path(temporary) / "settings/local-signing.json"
            installer.write_pin(pin, PIN)
            self.assertEqual(json.loads(pin.read_text()), PIN)
            self.assertEqual(pin.stat().st_mode & 0o777, 0o600)
            with patch.object(installer.os, "replace", side_effect=OSError("full disk")):
                with self.assertRaises(OSError):
                    installer.write_pin(pin, {**PIN, "identity": "B" * 40})
            self.assertEqual(json.loads(pin.read_text()), PIN)
            self.assertEqual(list(pin.parent.iterdir()), [pin])


class LayoutTests(unittest.TestCase):
    def test_only_expected_local_app_and_native_components(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = app(Path(temporary) / "RetroLife.app")
            main, libraries = installer.app_layout(bundle)
            self.assertEqual(main.name, "RetroLife")
            self.assertEqual([p.name for p in libraries], ["core.dylib"])
            info_path = bundle / "Contents/Info.plist"
            info = plistlib.loads(info_path.read_bytes())
            for key, value in [("RLBuildChannel", "release"), ("CFBundleIdentifier", "other.app"),
                               ("CFBundleExecutable", "../../other")]:
                with self.subTest(key=key):
                    info_path.write_bytes(plistlib.dumps({**info, key: value}))
                    with self.assertRaises(ValueError):
                        installer.app_layout(bundle)

    def test_unknown_code_and_symlinks_are_rejected_before_signing(self):
        for relative, kind in [("Contents/Frameworks/Sparkle.framework", "directory"),
                               ("Contents/Resources/helper", "native"),
                               ("Contents/Frameworks/outside.dylib", "symlink"),
                               ("Contents/Frameworks/fake.dylib", "text")]:
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as temporary:
                bundle = app(Path(temporary) / "RetroLife.app")
                extra = bundle / relative
                if kind == "directory":
                    extra.mkdir()
                elif kind == "native":
                    extra.write_bytes(b"\xcf\xfa\xed\xfe")
                elif kind == "symlink":
                    extra.symlink_to("/outside/binary")
                else:
                    extra.write_text("not native code")
                with self.assertRaises(ValueError):
                    installer.app_layout(bundle)

    def test_running_app_blocks_replacement(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destination = app(root / "RetroLife.app")
            preview_alias = root / "RetroLife Preview.app"
            preview_alias.symlink_to(destination, target_is_directory=True)
            distinct_preview = app(root / "Independent Preview.app")
            for bundle, blocked in [(destination, True), (preview_alias, True), (distinct_preview, False)]:
                process = "345 " + str(bundle / "Contents/MacOS/RetroLife")
                with self.subTest(bundle=bundle.name), patch.object(installer, "run", return_value=subprocess.CompletedProcess([], 0, process)):
                    if blocked:
                        with self.assertRaises(ValueError):
                            installer.refuse_running(destination)
                    else:
                        installer.refuse_running(destination)


class ContinuityTests(unittest.TestCase):
    def test_requirement_check_uses_inline_source_not_a_filename(self):
        bundle = Path("/Applications/RetroLife.app")
        with patch.object(installer, "run") as run:
            installer.verify_requirement(bundle, REQUIREMENT)
        run.assert_called_once_with("/usr/bin/codesign", "--verify", "--strict", "--all-architectures",
                                    "-R", "=" + REQUIREMENT, str(bundle))

    def test_certificate_updates_check_both_directions_and_saved_pin(self):
        with tempfile.TemporaryDirectory() as temporary:
            old = Path(temporary) / "old.app"
            old.mkdir()
            new = Path(temporary) / "new.app"
            with patch.object(installer, "designated_requirement", return_value=REQUIREMENT), \
                 patch.object(installer, "verify") as verify, \
                 patch.object(installer, "verify_requirement") as matches, \
                 patch.object(installer, "run", return_value=subprocess.CompletedProcess([], 0, "", "Signature size=100")):
                self.assertEqual(installer.verify_continuity(new, old, PIN), (REQUIREMENT, False))
                verify.assert_called_once_with(old)
                self.assertEqual(matches.call_args_list, [unittest.mock.call(new, REQUIREMENT),
                                                        unittest.mock.call(new, REQUIREMENT),
                                                        unittest.mock.call(old, REQUIREMENT)])

    def test_ad_hoc_migration_does_not_pin_old_cdhash(self):
        with tempfile.TemporaryDirectory() as temporary:
            old = Path(temporary) / "old.app"
            old.mkdir()
            new = Path(temporary) / "new.app"
            with patch.object(installer, "designated_requirement", side_effect=[REQUIREMENT, 'cdhash H"1234"']), \
                 patch.object(installer, "verify"), patch.object(installer, "verify_requirement") as matches, \
                 patch.object(installer, "run", return_value=subprocess.CompletedProcess([], 0, "", "Signature=adhoc\n")):
                self.assertEqual(installer.verify_continuity(new, old, None), (REQUIREMENT, True))
                matches.assert_not_called()

    def test_candidate_identity_drift_and_ad_hoc_output_are_rejected(self):
        for requirement in ['cdhash H"1234"', REQUIREMENT + " and true"]:
            with self.subTest(requirement=requirement), \
                 patch.object(installer, "designated_requirement", return_value=requirement), \
                 patch.object(installer, "verify_requirement"), self.assertRaises(ValueError):
                installer.verify_continuity(Path("new.app"), None, PIN)


class TransactionTests(unittest.TestCase):
    def test_success_preserves_root_and_old_contents(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            old = app(root / "RetroLife.app")
            candidate = app(root / "Candidate.app", "new")
            inode = old.stat().st_ino
            backup = root / "backups/one"
            verified = []
            saved = []
            installer.replace_contents(candidate, old, backup, lambda p: verified.append(p), lambda: saved.append(True))
            self.assertEqual(old.stat().st_ino, inode)
            self.assertEqual((old / "Contents/Resources/marker").read_text(), "new")
            self.assertEqual((backup / "Contents/Resources/marker").read_text(), "old")
            self.assertEqual(verified, [old])
            self.assertEqual(saved, [True])

    def test_verification_and_pin_failure_restore_original_app(self):
        for failure in ("verify", "pin"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                old = app(root / "RetroLife.app")
                candidate = app(root / "Candidate.app", "new")
                inode = old.stat().st_ino
                def reject(*_):
                    raise OSError("failure after swap")
                with self.assertRaises(OSError):
                    installer.replace_contents(candidate, old, root / "backups/one",
                                               reject if failure == "verify" else lambda _: None,
                                               reject if failure == "pin" else lambda: None)
                self.assertEqual(old.stat().st_ino, inode)
                self.assertEqual((old / "Contents/Resources/marker").read_text(), "old")
                self.assertEqual((candidate / "Contents/Resources/marker").read_text(), "new")

    def test_first_install_failure_leaves_no_partial_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destination = root / "RetroLife.app"
            candidate = app(root / "Candidate.app", "new")
            with self.assertRaises(OSError):
                installer.replace_contents(candidate, destination, root / "backups/one", lambda _: None,
                                           lambda: (_ for _ in ()).throw(OSError("cannot save pin")))
            self.assertFalse(destination.exists())
            self.assertEqual((candidate / "Contents/Resources/marker").read_text(), "new")

    def test_failed_second_rename_restores_old_contents(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            old = app(root / "RetroLife.app")
            candidate = app(root / "Candidate.app", "new")
            original_rename = Path.rename
            def fail_candidate(path, target):
                if path == candidate / "Contents":
                    raise OSError("rename failed")
                return original_rename(path, target)
            with patch.object(Path, "rename", fail_candidate), self.assertRaises(OSError):
                installer.replace_contents(candidate, old, root / "backups/one", lambda _: None, lambda: None)
            self.assertEqual((old / "Contents/Resources/marker").read_text(), "old")
            self.assertEqual((candidate / "Contents/Resources/marker").read_text(), "new")


if __name__ == "__main__":
    unittest.main()
