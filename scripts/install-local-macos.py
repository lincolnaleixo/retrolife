#!/usr/bin/env python3
"""Install a local development app with a persistent Apple Development identity.

This does not notarize or publish an app. It never changes macOS privacy settings.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import uuid

BUNDLE_ID = "io.github.lincolnaleixo.retrolife"
DEFAULT_PIN = Path.home() / "Library/Application Support/RetroLife/local-signing.json"
MACHO_MAGICS = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
                b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
                b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


def run(*arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(arguments, check=True, capture_output=True, text=True)


def select_identity(requested: str | None, pin: dict | None, identities: str) -> str:
    selected = (requested or (pin or {}).get("identity", "")).upper()
    if not re.fullmatch(r"[0-9A-F]{40}", selected):
        raise ValueError("First install requires --identity with an Apple Development certificate SHA-1.")
    if pin and (pin.get("bundleId") != BUNDLE_ID or pin.get("identity") != selected):
        raise ValueError("The saved local signing identity cannot be changed by an app update.")
    available = set(re.findall(r'\b([0-9A-F]{40}) "Apple Development: [^"\n]+"', identities))
    if selected not in available:
        raise ValueError("The pinned Apple Development identity is unavailable or invalid in Keychain.")
    return selected


def app_layout(app: Path) -> tuple[Path, list[Path]]:
    if app.is_symlink() or not app.is_dir():
        raise ValueError("The source must be a real local app directory.")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("RLBuildChannel") != "local-development":
        raise ValueError("Only the RetroLife local-development bundle can use this installer.")
    executable_name = info.get("CFBundleExecutable", "")
    if not executable_name or Path(executable_name).name != executable_name:
        raise ValueError("Invalid application executable name.")
    main = app / "Contents/MacOS" / executable_name
    libraries = []
    for path in app.rglob("*"):
        if path.is_symlink():
            raise ValueError("Symlinks are unsupported in local install inputs.")
        if path.is_dir():
            if path.suffix.lower() in {".app", ".xpc", ".appex", ".framework", ".bundle"}:
                raise ValueError("Embedded executable bundles need an explicit signing implementation.")
            continue
        with path.open("rb") as stream:
            native = stream.read(4) in MACHO_MAGICS
        if native and path != main:
            if path.suffix != ".dylib" or path.parent != app / "Contents/Frameworks":
                raise ValueError("Unsupported embedded executable: " + str(path.relative_to(app)))
            libraries.append(path)
        elif path.suffix == ".dylib" and not native:
            raise ValueError("A bundled dylib is not a Mach-O binary.")
    with main.open("rb") as stream:
        if stream.read(4) not in MACHO_MAGICS:
            raise ValueError("The main executable is not a Mach-O binary.")
    return main, sorted(libraries)


def designated_requirement(app: Path) -> str:
    result = run("/usr/bin/codesign", "-d", "-r-", str(app))
    for line in (result.stdout + "\n" + result.stderr).splitlines():
        if line.startswith("designated => ") or line.startswith("# designated => "):
            return line.split("=>", 1)[1].strip()
    raise ValueError("The application has no designated signing requirement.")


def verify(app: Path) -> None:
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app))


def verify_requirement(app: Path, requirement: str) -> None:
    # codesign treats a bare argument as a file; '=' explicitly selects inline source.
    run("/usr/bin/codesign", "--verify", "--strict", "--all-architectures", "-R", "=" + requirement, str(app))


def verify_continuity(candidate: Path, installed: Path | None, pin: dict | None) -> tuple[str, bool]:
    requirement = designated_requirement(candidate)
    if "cdhash" in requirement or "certificate" not in requirement or "anchor apple" not in requirement:
        raise ValueError("Local app signing must produce an Apple certificate-backed requirement.")
    if pin and pin.get("requirement"):
        verify_requirement(candidate, pin["requirement"])
        if requirement != pin["requirement"]:
            raise ValueError("The pinned designated signing requirement changed.")
    migration = False
    if installed and installed.exists():
        verify(installed)
        old = designated_requirement(installed)
        details = run("/usr/bin/codesign", "-d", "--verbose=4", str(installed))
        migration = "Signature=adhoc" in details.stderr
        if not migration:
            verify_requirement(candidate, old)
            verify_requirement(installed, requirement)
    return requirement, migration


def refuse_running(app: Path) -> None:
    executable_root = app.resolve() / "Contents/MacOS"
    listing = run("/bin/ps", "-axo", "pid=,comm=").stdout
    for line in listing.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2:
            continue
        executable = Path(parts[1])
        if executable.is_absolute() and executable.resolve().is_relative_to(executable_root):
            raise ValueError("Quit RetroLife normally before installing; the running app was preserved.")


def write_pin(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".local-signing-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def replace_contents(candidate: Path, destination: Path, backup: Path, verify_installed, persist_pin) -> None:
    """Both candidate and backup must be on the destination filesystem."""
    existed = destination.exists()
    old_contents = destination / "Contents"
    moved_old = False
    moved_new = False
    if existed and (destination.is_symlink() or not old_contents.is_dir()):
        raise ValueError("The destination is not a replaceable app bundle.")
    backup.mkdir(parents=True, exist_ok=False)
    try:
        if existed:
            old_contents.rename(backup / "Contents")
            moved_old = True
        else:
            destination.mkdir()
        (candidate / "Contents").rename(old_contents)
        moved_new = True
        verify_installed(destination)
        persist_pin()
    except BaseException:
        if moved_new:
            old_contents.rename(candidate / "Contents")
        if moved_old:
            (backup / "Contents").rename(old_contents)
        elif not existed and destination.exists():
            destination.rmdir()
        if not any(backup.iterdir()):
            backup.rmdir()
        raise


def install(source: Path, destination: Path, identity: str | None, pin_path: Path = DEFAULT_PIN) -> dict:
    if sys.platform != "darwin":
        raise ValueError("Local macOS installation requires macOS.")
    source = source.absolute()
    destination = destination.absolute()
    app_layout(source)
    if destination.is_symlink():
        raise ValueError("The destination cannot be a symlink.")
    if destination.exists():
        app_layout(destination)
    refuse_running(destination)
    pin = json.loads(pin_path.read_text()) if pin_path.exists() else None
    identities = run("/usr/bin/security", "find-identity", "-v", "-p", "codesigning").stdout
    selected = select_identity(identity, pin, identities)
    with tempfile.TemporaryDirectory(prefix="retrolife-local-sign-", dir="/private/tmp") as temporary:
        stage = Path(temporary) / "RetroLife.app"
        run("/usr/bin/ditto", str(source), str(stage))
        # Finder/iCloud can attach metadata that code signing explicitly forbids.
        # Preserve every other attribute, including quarantine.
        for attribute in ("com.apple.FinderInfo", "com.apple.ResourceFork"):
            subprocess.run(["/usr/bin/xattr", "-r", "-d", attribute, str(stage)],
                           check=False, capture_output=True, text=True)
        _, libraries = app_layout(stage)
        for library in libraries:
            run("/usr/bin/codesign", "--force", "--timestamp=none", "--sign", selected, str(library))
        run("/usr/bin/codesign", "--force", "--timestamp=none", "--sign", selected, str(stage))
        verify(stage)
        requirement, migration = verify_continuity(stage, destination, pin)
        new_pin = {"bundleId": BUNDLE_ID, "identity": selected, "requirement": requirement}
        destination.parent.mkdir(parents=True, exist_ok=True)
        # The final swap and rollback use rename on the destination filesystem.
        with tempfile.TemporaryDirectory(prefix=".retrolife-install-", dir=destination.parent) as adjacent:
            candidate = Path(adjacent) / "RetroLife.app"
            run("/usr/bin/ditto", str(stage), str(candidate))
            verify(candidate)
            refuse_running(destination)
            backup = destination.parent / ".RetroLife-backups" / (
                datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:8])
            replace_contents(candidate, destination, backup, verify,
                             lambda: write_pin(pin_path, new_pin) if pin != new_pin else None)
    return {"app": str(destination), "backup": str(backup), "signingPin": str(pin_path),
            "designatedRequirement": requirement, "migratedFromAdHoc": migration,
            "privacy": "macOS may ask once after ad-hoc migration; later builds keep this identity."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--destination", type=Path, default=Path("/Applications/RetroLife.app"))
    parser.add_argument("--identity", help="Apple Development certificate SHA-1, required only for first setup")
    args = parser.parse_args()
    print(json.dumps(install(args.source, args.destination, args.identity), indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # Keep Keychain output and certificate details out of shared logs.
        sys.exit("Local installation failed: " + (str(error) if not isinstance(error, subprocess.SubprocessError)
                                                 else "a signing or verification command failed; the previous app was preserved."))
