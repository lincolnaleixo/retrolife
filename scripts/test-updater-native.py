#!/usr/bin/env python3
"""Run real Sparkle updates using disposable, ad-hoc-signed test applications.

No release credentials, Keychain entries, application installs or user saves are
used. Only the explicit test executable bypasses Developer ID and HTTPS checks.
"""
from __future__ import annotations

from functools import partial
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import xml.etree.ElementTree as ET
from updates.common import version_info

ROOT = Path(__file__).resolve().parent.parent
SDK = ROOT / ".cache/sparkle/2.10.0"
NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def run(*command, **kwargs):
    return subprocess.run(list(map(str, command)), check=True, **kwargs)


def build_app(path: Path, executable: Path, version: str, key: str, feed: str, mode: str, directory: Path, beta=True):
    contents = path / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Frameworks").mkdir()
    shutil.copy2(executable, contents / "MacOS/RetroLife")
    run("ditto", SDK / "Sparkle.framework", contents / "Frameworks/Sparkle.framework", stdout=subprocess.DEVNULL)
    info = version_info(version)
    data = {"CFBundleExecutable": "RetroLife", "CFBundleName": "RetroLife", "CFBundlePackageType": "APPL",
            "CFBundleIdentifier": "io.github.lincolnaleixo.retrolife.updater-test", "CFBundleVersion": info["bundleVersion"],
            "CFBundleShortVersionString": info["shortVersion"], "RLReleaseVersion": info["version"],
            "LSMinimumSystemVersion": "13.0", "SUFeedURL": feed, "SUPublicEDKey": key,
            "SUEnableAutomaticChecks": False, "SUAutomaticallyUpdate": False, "SUAllowsAutomaticUpdates": True,
            "SUVerifyUpdateBeforeExtraction": True,
            "RLDefaultBetaUpdates": beta, "RLTestMode": mode, "RLTestDirectory": str(directory),
            "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}}
    (contents / "Info.plist").write_bytes(plistlib.dumps(data))
    # Ad-hoc signatures are for disposable tests only, not a release fallback.
    run("codesign", "--force", "--deep", "--sign", "-", path, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def appcast(path: Path, version: str, signature: str, size: int, url: str, minimum="13.0"):
    info = version_info(version)
    root = ET.Element("rss", {"version": "2.0", "xmlns:sparkle": NS})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "RetroLife test updates"
    item = ET.SubElement(channel, "item")
    for key, value in (("sparkle:version", info["bundleVersion"]), ("sparkle:shortVersionString", version), ("sparkle:minimumSystemVersion", minimum)):
        ET.SubElement(item, key).text = value
    if info["channel"] == "beta":
        ET.SubElement(item, "sparkle:channel").text = "beta"
    ET.SubElement(item, "enclosure", {"url": url, "length": str(size), "type": "application/octet-stream", "sparkle:edSignature": signature})
    path.write_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True))


class QuietServer(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def main():
    if os.uname().sysname != "Darwin" or os.uname().machine != "arm64":
        raise RuntimeError("Apple Silicon is required")
    results = []
    (ROOT / ".cache").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="updater-test-", dir=ROOT / ".cache") as temporary:
        folder = Path(temporary)
        binary = folder / "UpdaterTest"
        run("xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=13.0", "-fobjc-arc", "-fblocks",
            "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-DRETROLIFE_UPDATER_TESTING=1",
            "-F", SDK, "-framework", "Cocoa", "-framework", "Security", "-framework", "Sparkle",
            "-Wl,-rpath,@executable_path/../Frameworks", ROOT / "native/macos/updater.m", ROOT / "native/macos/updater_smoke.m", "-o", binary)
        keyfile = folder / "ephemeral-seed"
        key = subprocess.check_output(["xcrun", "swift", str(ROOT / "native/macos/update_test_keys.swift"), str(keyfile)], text=True).strip()
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietServer, directory=str(folder)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        origin = f"http://127.0.0.1:{server.server_port}"
        try:
            for mode in ("policy", "no-update", "downgrade", "stable-only", "incompatible-os", "network-error", "bad-origin", "invalid-signature", "install"):
                case = folder / mode
                case.mkdir()
                installed = case / "installed/RetroLife.app"
                candidate = case / "candidate/RetroLife.app"
                current_version = "0.1.0-beta.2"
                target_version = "0.1.0-beta.10"
                if mode == "no-update":
                    target_version = current_version
                if mode == "downgrade":
                    target_version = "0.1.0-beta.1"
                feed = f"{origin}/{mode}/appcast.xml"
                build_app(installed, binary, current_version, key, feed, mode, case, beta=mode != "stable-only")
                build_app(candidate, binary, target_version, key, feed, "relaunched", case)
                archive = case / "RetroLife-macos-arm64.zip"
                run("ditto", "-c", "-k", "--keepParent", candidate, archive)
                signature = subprocess.check_output([str(SDK / "bin/sign_update"), "--ed-key-file", str(keyfile), "-p", str(archive)], text=True).strip()
                run(SDK / "bin/sign_update", "--ed-key-file", keyfile, "--verify", archive, signature)
                if mode == "invalid-signature":
                    with archive.open("ab") as stream:
                        stream.write(b"tampered after signing")
                url = f"{origin}/{mode}/RetroLife-macos-arm64.zip"
                if mode == "bad-origin":
                    url = "https://example.invalid/RetroLife-macos-arm64.zip"
                appcast(case / "appcast.xml", target_version, signature, archive.stat().st_size, url, "99.0" if mode == "incompatible-os" else "13.0")
                if mode == "network-error":
                    (case / "appcast.xml").unlink()
                # These sentinel files stand for user data and must not be touched.
                saves = case / "user-data/saves"
                saves.mkdir(parents=True)
                (saves / "sentinel.txt").write_text("keep my save")
                with (case / "native.log").open("wb") as log:
                    process = subprocess.Popen([str(installed / "Contents/MacOS/RetroLife")], stdout=log, stderr=log)
                    deadline = time.monotonic() + 110
                    while time.monotonic() < deadline and not (case / "result.json").exists():
                        time.sleep(0.25)
                    if not (case / "result.json").exists():
                        process.kill()
                        print((case / "native.log").read_text(errors="replace")[-18000:])
                        raise RuntimeError(f"Native updater case {mode} timed out")
                    result = json.loads((case / "result.json").read_text())
                    try:
                        process.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                    installed_info = plistlib.loads((installed / "Contents/Info.plist").read_bytes())
                    expected = target_version if mode == "install" else current_version
                    result["bundlePreservedOrUpdated"] = installed_info["RLReleaseVersion"] == expected
                    result["savePreserved"] = (saves / "sentinel.txt").read_text() == "keep my save"
                    result["case"] = mode
                    results.append(result)
                    print(json.dumps(result), flush=True)
                    if not result["passed"] or not result["bundlePreservedOrUpdated"] or not result["savePreserved"]:
                        print((case / "native.log").read_text(errors="replace")[-18000:])
                        raise RuntimeError(f"Native updater case {mode} failed")
        finally:
            server.shutdown()
            server.server_close()
            (ROOT / ".cache/updater-native-results.json").write_text(json.dumps(results, indent=2) + "\n")
            subprocess.run(["defaults", "delete", "io.github.lincolnaleixo.retrolife.updater-test"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("Native Sparkle update tests passed; ephemeral key and bundles removed")


if __name__ == "__main__":
    main()
