#!/usr/bin/env python3
"""One-time setup, run interactively on the maintainer's trusted Mac.

Private values go to GitHub's encrypted environment secrets over gh's stdin,
never to the repository, terminal output, process arguments or this chat.
"""
from __future__ import annotations
import argparse
import base64
import getpass
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from release_automation import REPO
from updates.common import decode_key

ROOT = Path(__file__).resolve().parent.parent
ENVIRONMENT = "macos-release"


def command(args: list[str], input_value: str | None = None, missing: bool = False) -> str | None:
    result = subprocess.run(args, cwd=ROOT, input=input_value, capture_output=True, text=True)
    if missing and result.returncode and "HTTP 404" in result.stderr:
        return None
    if result.returncode:
        raise RuntimeError("Setup command failed. Check GitHub admin access and the selected Keychain account; no private values were printed.")
    return result.stdout.strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("certificate", type=Path, help="An explicitly exported Developer ID Application .p12 identity")
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--apple-id", help="Apple account for the app-specific-password notarization route")
    parser.add_argument("--apple-api-key-p8", type=Path, help="A local App Store Connect API key .p8 file")
    parser.add_argument("--apple-api-key-id", help="App Store Connect API key ID")
    parser.add_argument("--apple-api-issuer-id", help="App Store Connect API issuer ID")
    parser.add_argument("--sparkle-account", default="io.github.lincolnaleixo.retrolife.sparkle")
    parser.add_argument("--initialize-sparkle-key", action="store_true", help="Create the persistent signing key only when no key exists; existing keys are reused")
    args = parser.parse_args()
    if sys.platform != "darwin" or not sys.stdin.isatty():
        raise ValueError("Run interactively on your trusted Mac, never in PR CI")
    if not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
        raise ValueError("The Apple team identifier must have 10 uppercase letters/digits")
    path = args.certificate.expanduser().resolve(strict=True)
    if path.suffix.lower() != ".p12" or not 0 < path.stat().st_size <= 32000:
        raise ValueError("Choose the exported .p12 identity, not a Keychain archive")
    api_key_path = args.apple_api_key_p8.expanduser().resolve(strict=True) if args.apple_api_key_p8 else None
    api_key_mode = any((api_key_path, args.apple_api_key_id, args.apple_api_issuer_id))
    if api_key_mode:
        if not all((api_key_path, args.apple_api_key_id, args.apple_api_issuer_id)):
            raise ValueError("API-key notarization requires the .p8 file, key ID and issuer ID")
        if api_key_path.suffix.lower() != ".p8" or not 0 < api_key_path.stat().st_size <= 16384:
            raise ValueError("Choose the explicit App Store Connect .p8 file")
        if args.apple_id:
            raise ValueError("Choose either API-key or app-specific-password notarization")
    elif not args.apple_id:
        raise ValueError("Provide --apple-id or the complete App Store Connect API-key options")
    command(["gh", "auth", "status"])
    sdk = Path(command(["python3", "scripts/prepare-sparkle.py"]))
    if args.initialize_sparkle_key:
        command([str(sdk / "bin/generate_keys"), "--account", args.sparkle_account])
    public = command([str(sdk / "bin/generate_keys"), "--account", args.sparkle_account, "-p"])
    decode_key(public, 32)
    certificate_password = getpass.getpass("Password of the exported Developer ID .p12: ")
    if not certificate_password:
        raise ValueError("The P12 password is required")
    app_password = None if api_key_mode else getpass.getpass("Apple app-specific password for notarization: ")
    if not api_key_mode and not app_password:
        raise ValueError("The Apple app-specific password is required")
    endpoint = f"repos/{REPO}/environments/{ENVIRONMENT}"
    current_raw = command(["gh", "api", endpoint], missing=True)
    current = json.loads(current_raw) if current_raw else {}
    policy = current.get("deployment_branch_policy") or {}
    if not policy.get("custom_branch_policies"):
        # Only deployment scope is changed, never reviewer approval requirements.
        command(["gh", "api", "--method", "PUT", endpoint, "--input", "-"],
                json.dumps({"deployment_branch_policy": {"protected_branches": False, "custom_branch_policies": True}}))
    policies = json.loads(command(["gh", "api", endpoint + "/deployment-branch-policies?per_page=100"]))
    entries = policies.get("branch_policies", [])
    if policies.get("total_count", len(entries)) > len(entries) or any(e.get("name") != "main" or e.get("type", "branch") != "branch" for e in entries):
        raise ValueError("Restrict macos-release to the main branch only before storing production keys. Existing rules were not deleted.")
    if not entries:
        command(["gh", "api", "--method", "POST", endpoint + "/deployment-branch-policies", "--input", "-"], json.dumps({"name": "main", "type": "branch"}))
    with tempfile.TemporaryDirectory(prefix="retrolife-key-transfer-") as temporary:
        private = Path(temporary) / "sparkle-export"
        command([str(sdk / "bin/generate_keys"), "--account", args.sparkle_account, "-x", str(private)])
        private.chmod(0o600)
        private_value = private.read_text().strip()
        if not private_value or len(private_value) > 4096:
            raise ValueError("Unexpected Sparkle key export format")
        values = {"MACOS_CERTIFICATE_P12_BASE64": base64.b64encode(path.read_bytes()).decode(),
                  "MACOS_CERTIFICATE_PASSWORD": certificate_password, "SPARKLE_PRIVATE_KEY": private_value}
        if api_key_mode:
            values.update({"APPLE_API_KEY_ID": args.apple_api_key_id,
                           "APPLE_API_ISSUER_ID": args.apple_api_issuer_id,
                           "APPLE_API_KEY_P8_BASE64": base64.b64encode(api_key_path.read_bytes()).decode()})
        else:
            values.update({"APPLE_ID": args.apple_id, "APPLE_APP_PASSWORD": app_password})
        for name, value in values.items():
            command(["gh", "secret", "set", name, "--repo", REPO, "--env", ENVIRONMENT], value)
        values.clear()
    for name, value in {"APPLE_TEAM_ID": args.team_id, "SPARKLE_PUBLIC_KEY": public}.items():
        command(["gh", "variable", "set", name, "--repo", REPO, "--env", ENVIRONMENT], value)
    command(["gh", "workflow", "run", "auto-release.yml", "--repo", REPO, "--ref", "main"])
    print("Protected release configuration saved; automatic release requested for main.")
    print("The Sparkle key remains in your Keychain. Keep a separate secure backup before relying on automatic distribution.")
    print("Check GitHub Actions for the actual release result; this setup alone does not claim a published app.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        sys.exit("Release setup failed: " + str(error))
