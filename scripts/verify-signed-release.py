#!/usr/bin/env python3
"""Verify a signed release on a disposable hosted macOS runner."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    if len(sys.argv) != 4:
        raise ValueError("verify-signed-release expects version, public key and team")
    version, public_key, team = sys.argv[1:]
    archive = ROOT / "dist/release/RetroLife-macos-arm64.zip"
    if not archive.is_file() or archive.is_symlink():
        raise ValueError("signed updater archive is missing")
    spec = importlib.util.spec_from_file_location("ci_sign_verify", ROOT / "scripts/ci-sign-macos-release.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix="retrolife-verify-") as temporary:
        subprocess.run(["ditto", "-x", "-k", str(archive), temporary], check=True)
        app = Path(temporary) / "RetroLife.app"
        environment = module.public_environment()
        module.verify_bundle(app, version, public_key, team, environment)
        module.verify_probe(app, version, environment)
    print("Signed application and updater probe passed on the disposable hosted runner.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("Signed release verification failed: " + str(error), file=sys.stderr)
        sys.exit(1)
