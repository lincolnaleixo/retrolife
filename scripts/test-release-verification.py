#!/usr/bin/env python3
"""Offline fail-closed and diagnostic coverage for notarization verification."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "signing", Path(__file__).with_name("ci-sign-macos-release.py"))
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class TicketValidationTests(unittest.TestCase):
    def check_results(self, results, succeeds):
        output = io.StringIO()
        with patch.object(signing.subprocess, "run", side_effect=results) as command, \
                patch.object(signing.time, "sleep") as sleep, \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            if succeeds:
                signing.verify_notarization_ticket(Path("/private/example/RetroLife.app"), {})
            else:
                with self.assertRaisesRegex(RuntimeError, "release remains unpublished"):
                    signing.verify_notarization_ticket(Path("/private/example/RetroLife.app"), {})
        self.assertNotIn("private/example", output.getvalue())
        self.assertNotIn("sensitive tool output", output.getvalue())
        for call in command.call_args_list:
            self.assertEqual(call.args[0][:3], ["xcrun", "stapler", "validate"])
            self.assertEqual(call.kwargs["timeout"], 30)
        return command.call_count, sleep.call_count, output.getvalue()

    def test_first_success_does_not_retry(self):
        count, sleeps, _ = self.check_results([subprocess.CompletedProcess([], 0)], True)
        self.assertEqual((count, sleeps), (1, 0))

    def test_transient_failure_can_recover_without_modifying_artifact(self):
        count, sleeps, output = self.check_results([
            subprocess.CompletedProcess([], 65, stderr="sensitive tool output"),
            subprocess.CompletedProcess([], 0)], True)
        self.assertEqual((count, sleeps), (2, 1))
        self.assertIn("exit 65", output)

    def test_invalid_ticket_still_blocks_release(self):
        count, sleeps, _ = self.check_results([
            subprocess.CompletedProcess([], 65, stderr="sensitive tool output")] * 3, False)
        self.assertEqual((count, sleeps), (3, 2))

    def test_timeout_is_bounded_and_does_not_leak_diagnostics(self):
        count, sleeps, output = self.check_results([
            subprocess.TimeoutExpired("stapler", 30, output="sensitive tool output")] * 3, False)
        self.assertEqual((count, sleeps), (3, 2))
        self.assertIn("timeout after 30 seconds", output)


if __name__ == "__main__":
    unittest.main()
