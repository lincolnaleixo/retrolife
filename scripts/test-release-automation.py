#!/usr/bin/env python3
"""Offline contracts for automatic prereleases; no private keys or network use."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import release_automation as release
from updates.common import ASSET_NAME, BUNDLE_ID, MINIMUM_OS, sha256, version_info

KEY = base64.b64encode(bytes(range(32))).decode()
COMMIT = "1" * 40
RUN = "https://github.com/lincolnaleixo/retrolife/actions/runs/123"
ENV = {"GITHUB_REPOSITORY": release.REPO, "GITHUB_REF": "refs/heads/main", "GITHUB_SHA": COMMIT, "GITHUB_EVENT_NAME": "push"}


class Versions(unittest.TestCase):
    def test_first_existing_betas_and_numeric_order(self):
        self.assertEqual(release.next_version("0.1.0", []), "0.1.0-beta.1")
        self.assertEqual(release.next_version("0.1.0", ["v0.1.0-beta.1", "v0.1.0-beta.2"]), "0.1.0-beta.3")
        self.assertEqual(release.next_version("0.1.0", ["v0.1.0-beta.9", "v0.1.0-beta.10"]), "0.1.0-beta.11")

    def test_alpha_rc_stable_and_future_series(self):
        for tags, expected in [(["v0.1.0-alpha.255"], "0.1.0-beta.1"), (["v0.1.0-rc.1"], "0.1.1-beta.1"),
                               (["v0.1.0"], "0.1.1-beta.1"), (["v0.2.0-beta.4"], "0.2.0-beta.5")]:
            self.assertEqual(release.next_version("0.1.0", tags), expected)
        self.assertEqual(release.next_version("0.3.0", ["v0.2.0"]), "0.3.0-beta.1")

    def test_apple_suffix_rollover(self):
        for base, tag, expected in [("0.1.0", "v0.1.0-beta.255", "0.1.1-beta.1"),
                                    ("0.1.0", "v0.1.99-beta.255", "0.2.0-beta.1"),
                                    ("0.1.0", "v0.99.99", "1.0.0-beta.1")]:
            self.assertEqual(release.next_version(base, [tag]), expected)
        with self.assertRaises(ValueError):
            release.next_version("9999.99.99", ["v9999.99.99"])

    def test_refuse_unsupported_version_tags_and_bases(self):
        for tag in ["v0.1.0-beta.256", "v0.1.0-local.2", "v0.1.0;touch X"]:
            with self.assertRaises(ValueError):
                release.next_version("0.1.0", [tag])
        with self.assertRaises(ValueError):
            release.next_version("0.1.0-beta.3", [])
        self.assertEqual(release.next_version("0.1.0", ["unrelated"]), "0.1.0-beta.1")


class Configuration(unittest.TestCase):
    def test_only_report_names_not_private_values(self):
        env = {"HAS_" + key: "true" for key in release.REQUIRED_SECRETS}
        env.update(APPLE_TEAM_ID="ABCDEF1234", SPARKLE_PUBLIC_KEY=KEY)
        self.assertEqual(release.configuration_errors(env), [])
        env["HAS_SPARKLE_PRIVATE_KEY"] = "false"
        self.assertEqual(release.configuration_errors(env), ["SPARKLE_PRIVATE_KEY"])
        api_env = {"HAS_" + key: "true" for key in release.SIGNING_SECRETS + release.API_KEY_NOTARY_SECRETS}
        api_env.update(APPLE_TEAM_ID="ABCDEF1234", SPARKLE_PUBLIC_KEY=KEY)
        self.assertEqual(release.configuration_errors(api_env), [])
        local_env = {"SIGNING_MODE": "local-keychain", "HAS_MACOS_KEYCHAIN_PASSWORD": "true",
                     "HAS_SPARKLE_PRIVATE_KEY": "true",
                     "LOCAL_KEYCHAIN_PATH": "/test-fixture/signing.keychain-db",
                     "NOTARY_PROFILE": "retrolife-openemu", "APPLE_TEAM_ID": "ABCDEF1234",
                     "SPARKLE_PUBLIC_KEY": KEY}
        self.assertEqual(release.configuration_errors(local_env), [])
        self.assertGreaterEqual(len(release.configuration_errors({})), 6)

    def test_disallow_pr_tag_fork_and_ambiguous_sources(self):
        release.assert_release_context(ENV)
        release.assert_release_context({**ENV, "GITHUB_EVENT_NAME": "workflow_dispatch"})
        for key, val in [("GITHUB_REF", "refs/pull/12/merge"), ("GITHUB_REF", "refs/tags/v0.1.0"),
                         ("GITHUB_EVENT_NAME", "pull_request"), ("GITHUB_EVENT_NAME", "pull_request_target"),
                         ("GITHUB_REPOSITORY", "someone/retrolife"), ("GITHUB_SHA", "main")]:
            with self.assertRaises(ValueError):
                release.assert_release_context({**ENV, key: val})

    def test_production_child_environment_excludes_private_values(self):
        spec = importlib.util.spec_from_file_location("ci_sign", Path(__file__).with_name("ci-sign-macos-release.py"))
        signer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(signer)
        env = {key: "sensitive-fixture" for key in (*release.ALL_PROTECTED_SECRETS, "GH_TOKEN", "GITHUB_TOKEN")}
        with patch.dict(os.environ, {**env, "SPARKLE_PUBLIC_KEY": KEY}, clear=True):
            self.assertEqual(signer.public_environment(), {"SPARKLE_PUBLIC_KEY": KEY})


class Assets(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        for name in release.PAYLOAD_FILES:
            if name != "release-build.json":
                (self.directory / name).write_bytes(b"public-test-fixture\n")
        info = version_info("0.1.0-beta.3")
        metadata = {"schemaVersion": 1, **{key: info[key] for key in ("version", "tag", "bundleVersion", "channel")},
                    "bundleId": BUNDLE_ID, "platform": "macos", "architecture": "arm64", "minimumSystemVersion": MINIMUM_OS,
                    "asset": ASSET_NAME, "length": (self.directory / ASSET_NAME).stat().st_size,
                    "sha256": sha256(self.directory / ASSET_NAME), "edSignature": base64.b64encode(bytes(range(64))).decode(), "notes": "Fixture only"}
        (self.directory / "retrolife-update.json").write_text(json.dumps(metadata))
        release.write_manifest(self.directory, info["version"], COMMIT, RUN)

    def test_complete_payload_has_all_sources_notices_and_checksums(self):
        manifest = release.audit_assets(self.directory, "0.1.0-beta.3", COMMIT)
        self.assertEqual(manifest["sourceCommit"], COMMIT)
        self.assertIn("bsnes-jg.tar.gz", manifest["files"])
        self.assertEqual(len(manifest["files"]), len(release.PAYLOAD_FILES) - 1)

    def test_extra_file_is_never_uploaded(self):
        (self.directory / "unexpected-secret").write_text("nonsecret fixture")
        with self.assertRaises(ValueError):
            release.audit_assets(self.directory, "0.1.0-beta.3", COMMIT)

    def test_missing_notice_and_modified_archive_are_rejected(self):
        (self.directory / "NOTICE").unlink()
        with self.assertRaises(ValueError):
            release.audit_assets(self.directory, "0.1.0-beta.3", COMMIT)
        (self.directory / "NOTICE").write_text("different")
        with self.assertRaises(ValueError):
            release.audit_assets(self.directory, "0.1.0-beta.3", COMMIT)

    def test_symlink_empty_and_mismatched_source_are_rejected(self):
        with self.assertRaises(ValueError):
            release.audit_assets(self.directory, "0.1.0-beta.3", "2" * 40)
        source = self.directory / "NOTICE"
        source.unlink()
        source.symlink_to(self.directory / "LICENSE")
        with self.assertRaises(ValueError):
            release.audit_assets(self.directory, "0.1.0-beta.3", COMMIT)
        source.unlink()
        source.touch()
        with self.assertRaises(ValueError):
            release.write_manifest(self.directory, "0.1.0-beta.3", COMMIT, RUN)

    def test_metadata_size_signature_and_version_are_validated(self):
        path = self.directory / "retrolife-update.json"
        original = json.loads(path.read_text())
        for field, value in [("length", 12345), ("edSignature", "invalid"), ("version", "0.1.0-beta.4")]:
            path.write_text(json.dumps({**original, field: value}))
            with self.assertRaises(ValueError):
                release.write_manifest(self.directory, "0.1.0-beta.3", COMMIT, RUN)

    def test_remote_size_and_digest_must_match(self):
        remote = {"assets": [{"name": n, "state": "uploaded", "size": (self.directory / n).stat().st_size,
                              "digest": "sha256:" + sha256(self.directory / n)} for n in release.ASSETS]}
        release.verify_remote(remote, self.directory)
        remote["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaises(ValueError):
            release.verify_remote(remote, self.directory)

    def test_publication_never_overwrites_existing_tags(self):
        with patch.dict(os.environ, ENV), patch.object(release, "all_releases", return_value=[{"tag_name": "v0.1.0-beta.3"}]), patch.object(release, "gh") as client:
            with self.assertRaises(ValueError):
                release.publish(self.directory, "0.1.0-beta.3")
            client.assert_not_called()

    def test_failed_upload_keeps_a_draft_without_advertising(self):
        with patch.dict(os.environ, ENV), patch.object(release, "all_releases", return_value=[]), patch.object(release, "gh", side_effect=[{}, {"id": 55}]) as client, patch.object(release.subprocess, "run") as upload:
            upload.return_value.returncode = 1
            with self.assertRaises(RuntimeError):
                release.publish(self.directory, "0.1.0-beta.3")
            self.assertEqual(client.call_count, 2)
            self.assertIn("draft=true", client.call_args.args)


class WorkflowBoundary(unittest.TestCase):
    def test_pinned_actions_and_exact_main_only_release(self):
        workflow = (release.ROOT / ".github/workflows/auto-release.yml").read_text()
        self.assertNotIn("pull_request", workflow)
        self.assertNotIn("self-hosted", workflow)
        self.assertIn("branches: [main]", workflow)
        self.assertIn("queue: max", workflow)
        self.assertNotIn("cancel-in-progress: true", workflow)
        import re
        for ref in re.findall(r"uses: ([^\n]+)", workflow):
            self.assertRegex(ref, r"^actions/[a-z-]+@[0-9a-f]{40}$")
        build = workflow.split("  build:\n", 1)[1].split("  sign:\n", 1)[0]
        self.assertNotIn("secrets.", build)
        self.assertIn("runs-on: retrolife", workflow)
        self.assertIn("RETROLIFE_SIGNING_MODE", workflow)
        self.assertIn("/usr/local/libexec/retrolife-sign-release", workflow)
        self.assertNotIn("scripts/ci-sign-macos-release.py", workflow)
        self.assertNotIn("RETROLIFE_SIGNING_RUNNER", workflow)
        publish = workflow.split("  publish:\n", 1)[1]
        self.assertNotIn("secrets.", publish)
        self.assertIn("release_automation.py feed", workflow)

    def test_pr_validation_has_no_production_secret_or_publication(self):
        workflow = (release.ROOT / ".github/workflows/release-automation-checks.yml").read_text()
        for forbidden in ["secrets.", "contents: write", "environment:", "self-hosted", "ci-sign-macos-release"]:
            self.assertNotIn(forbidden, workflow)
        self.assertIn("test-release-packaging.py", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
