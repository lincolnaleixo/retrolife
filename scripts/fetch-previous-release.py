#!/usr/bin/env python3
"""Fetch the newest published release older than a version, for delta updates.

Prints GITHUB_ENV lines for the signing helper's optional delta inputs. Prints
nothing when no older updater release exists, so the release proceeds without
a delta. Only public release assets are read; no token is required.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import urllib.request

from updates.common import ASSET_NAME, METADATA_NAME, REPOSITORY, version_info

API = f"https://api.github.com/repos/{REPOSITORY}/releases?per_page=100"
MAX_API_BYTES = 4 * 1024 * 1024
MAX_ARCHIVE_BYTES = 2 * 1024 * 1024 * 1024


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="the version being released")
    parser.add_argument("destination", type=Path, help="directory for the previous ZIP")
    arguments = parser.parse_args()
    current = version_info(arguments.version)
    request = urllib.request.Request(
        API, headers={"Accept": "application/vnd.github+json", "User-Agent": "RetroLife-release-fetch"}
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = response.read(MAX_API_BYTES + 1)
    if len(payload) > MAX_API_BYTES:
        raise ValueError("Release listing exceeds the size limit")
    candidates = []
    for release in json.loads(payload):
        if release.get("draft"):
            continue
        try:
            info = version_info(release.get("tag_name", ""))
        except ValueError:
            continue
        names = {asset.get("name") for asset in release.get("assets", [])}
        if ASSET_NAME in names and METADATA_NAME in names and info["sort"] < current["sort"]:
            candidates.append((info["sort"], release, info))
    if not candidates:
        print("No older published release with an updater ZIP; publishing without a delta.", file=sys.stderr)
        return
    _, release, info = max(candidates, key=lambda entry: entry[0])
    asset = next(a for a in release["assets"] if a.get("name") == ASSET_NAME)
    url = str(asset.get("browser_download_url", ""))
    prefix = f"https://github.com/{REPOSITORY}/releases/download/{info['tag']}/"
    if (
        not url.startswith(prefix)
        or asset.get("state") != "uploaded"
        or not 0 < int(asset.get("size", 0)) <= MAX_ARCHIVE_BYTES
    ):
        raise ValueError("Previous release ZIP has an unexpected identity")
    arguments.destination.mkdir(parents=True, exist_ok=True)
    archive = arguments.destination / ASSET_NAME
    with urllib.request.urlopen(url, timeout=600) as response, archive.open("wb") as output:
        while block := response.read(1024 * 1024):
            output.write(block)
    if archive.stat().st_size != int(asset["size"]):
        raise ValueError("Previous release ZIP was truncated")
    print(f"RETROLIFE_DELTA_ARCHIVE={archive}")
    print(f"RETROLIFE_DELTA_FROM={info['bundleVersion']}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        sys.exit(f"Previous release fetch failed: {error}\n")
