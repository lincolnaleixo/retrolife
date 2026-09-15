#!/usr/bin/env python3
"""Rebuild the isolated updates branch using metadata from published releases.

Run only from reviewed main-branch code with contents:write. No signing key or
release executable is used here. Sparkle verifies each archive on the client.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import urllib.error
import urllib.request
from updates.common import METADATA_NAME, REPOSITORY
from updates.feed import download_url, release_item, render


class GitHub:
    def __init__(self, token: str):
        self.token = token

    def api(self, path: str, data=None, method="GET", missing=False):
        url = "https://api.github.com/repos/" + REPOSITORY + "/" + path
        headers = {"Accept": "application/vnd.github+json", "User-Agent": "RetroLife-release-feed", "X-GitHub-Api-Version": "2022-11-28"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        body = json.dumps(data).encode() if data is not None else None
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = response.read(8 * 1024 * 1024 + 1)
        except urllib.error.HTTPError as error:
            if missing and error.code == 404:
                return None
            raise RuntimeError(f"GitHub request failed with HTTP {error.code}") from None
        if len(payload) > 8 * 1024 * 1024:
            raise ValueError("GitHub response exceeds size limit")
        return json.loads(payload)

    def items(self):
        items = []
        for page in range(1, 11):
            releases = self.api(f"releases?per_page=100&page={page}")
            for release in releases:
                if release.get("draft"):
                    continue
                metadata_assets = [a for a in release.get("assets", []) if a.get("name") == METADATA_NAME]
                if not metadata_assets:
                    continue  # Old pre-updater beta releases are not update candidates.
                if len(metadata_assets) != 1:
                    raise ValueError("Duplicate release update metadata")
                asset = metadata_assets[0]
                # Never interpolate unchecked release tags into a download URL.
                from updates.common import version_info
                tag = version_info(release["tag_name"])["tag"]
                expected = download_url(tag, METADATA_NAME)
                if asset.get("browser_download_url") != expected or not 0 < asset.get("size", 0) <= 65536:
                    raise ValueError("Unexpected update metadata asset")
                # Public asset downloads never receive the GitHub API token.
                with urllib.request.urlopen(expected, timeout=60) as response:
                    payload = response.read(65537)
                if len(payload) > 65536:
                    raise ValueError("Update metadata exceeds size limit")
                items.append(release_item(release, json.loads(payload)))
            if len(releases) < 100:
                return items
        raise ValueError("Too many releases to safely rebuild the complete feed")

    def publish(self, content: bytes) -> bool:
        current = self.api("git/ref/heads/updates", missing=True)
        parents = [current["object"]["sha"]] if current else []
        if current:
            previous = self.api("contents/appcast.xml?ref=updates", missing=True)
            if previous and base64.b64decode(previous.get("content", "")) == content:
                return False
        blob = self.api("git/blobs", {"content": content.decode(), "encoding": "utf-8"}, "POST")
        tree = self.api("git/trees", {"tree": [{"path": "appcast.xml", "mode": "100644", "type": "blob", "sha": blob["sha"]}]}, "POST")
        commit = self.api("git/commits", {"message": "chore: publish signed release update feed", "tree": tree["sha"], "parents": parents}, "POST")
        if current:
            self.api("git/refs/heads/updates", {"sha": commit["sha"], "force": False}, "PATCH")
        else:
            self.api("git/refs", {"ref": "refs/heads/updates", "sha": commit["sha"]}, "POST")
        return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", action="store_true")
    parser.add_argument("--output", type=Path, default=Path("dist/appcast.xml"))
    args = parser.parse_args()
    try:
        token = os.environ.get("GH_TOKEN", "")
        if args.publish and not token:
            raise ValueError("Publishing requires a scoped GH_TOKEN")
        client = GitHub(token)
        content = render(client.items())
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(content)
        if args.publish:
            print("Update feed published" if client.publish(content) else "Update feed is unchanged")
        else:
            print("Update feed prepared without publishing")
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        parser.exit(1, f"Update feed failed: {error}\n")
