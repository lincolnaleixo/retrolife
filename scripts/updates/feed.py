"""Build a restrictive Sparkle feed from published RetroLife release assets."""
from __future__ import annotations

from datetime import datetime
from email.utils import format_datetime
import html
import json
import xml.etree.ElementTree as ET
from .common import ASSET_NAME, METADATA_NAME, REPOSITORY, validate_metadata

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def download_url(tag: str, asset: str) -> str:
    return f"https://github.com/{REPOSITORY}/releases/download/{tag}/{asset}"


def release_item(release: dict, metadata: dict) -> dict:
    info = validate_metadata(metadata)
    if release.get("draft") or release.get("tag_name") != info["tag"]:
        raise ValueError("The release identity does not match its updater metadata")
    if type(release.get("prerelease")) is not bool or release["prerelease"] != (info["channel"] == "beta"):
        raise ValueError("The release prerelease flag does not match its updater channel")
    assets = [a for a in release.get("assets", []) if a.get("name") == ASSET_NAME]
    if len(assets) != 1:
        raise ValueError("A release must contain exactly one updater ZIP")
    asset = assets[0]
    expected = download_url(info["tag"], ASSET_NAME)
    if asset.get("browser_download_url") != expected or asset.get("size") != metadata["length"] or asset.get("state") != "uploaded":
        raise ValueError("Release asset URL, size or state does not match updater metadata")
    digest = asset.get("digest")
    if digest is not None and digest != "sha256:" + metadata["sha256"]:
        raise ValueError("GitHub asset digest does not match updater metadata")
    for delta in metadata.get("deltas", []):
        name = delta["asset"]
        matches = [a for a in release.get("assets", []) if a.get("name") == name]
        if len(matches) != 1:
            raise ValueError("A delta update must have exactly one release asset")
        entry = matches[0]
        expected_delta = download_url(info["tag"], name)
        if entry.get("browser_download_url") != expected_delta \
            or entry.get("size") != delta["length"] or entry.get("state") != "uploaded":
            raise ValueError("Delta asset URL, size or state does not match its metadata")
        delta_digest = entry.get("digest")
        if delta_digest is not None and delta_digest != "sha256:" + delta["sha256"]:
            raise ValueError("Delta asset digest does not match its metadata")
    date = datetime.fromisoformat(release["published_at"].replace("Z", "+00:00"))
    if date.tzinfo is None:
        raise ValueError("Release date must include a timezone")
    return {**metadata, "date": format_datetime(date), "url": expected, "sort": info["sort"]}


def render(items: list[dict]) -> bytes:
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "RetroLife for macOS"
    ET.SubElement(channel, "link").text = f"https://github.com/{REPOSITORY}/releases"
    ET.SubElement(channel, "description").text = "Signed RetroLife updates. Stable releases are the default; beta builds are optional."
    seen = set()
    counts = {"stable": 0, "beta": 0}
    for item in sorted(items, key=lambda x: x["sort"], reverse=True):
        if item["bundleVersion"] in seen:
            raise ValueError("Duplicate update bundle version")
        seen.add(item["bundleVersion"])
        if counts[item["channel"]] >= 20:
            continue
        counts[item["channel"]] += 1
        element = ET.SubElement(channel, "item")
        ET.SubElement(element, "title").text = "RetroLife " + item["version"]
        ET.SubElement(element, "pubDate").text = item["date"]
        ET.SubElement(element, f"{{{SPARKLE}}}version").text = item["bundleVersion"]
        ET.SubElement(element, f"{{{SPARKLE}}}shortVersionString").text = item["version"]
        ET.SubElement(element, f"{{{SPARKLE}}}minimumSystemVersion").text = item["minimumSystemVersion"]
        if item["channel"] == "beta":
            ET.SubElement(element, f"{{{SPARKLE}}}channel").text = "beta"
        # Sparkle renders descriptions as HTML. Escape notes before XML escaping.
        ET.SubElement(element, "description").text = "<p>" + html.escape(item.get("notes", "")).replace("\n", "<br>") + "</p>"
        ET.SubElement(element, "enclosure", {
            "url": item["url"], "length": str(item["length"]), "type": "application/octet-stream",
            f"{{{SPARKLE}}}edSignature": item["edSignature"],
        })
        if item.get("deltas"):
            deltas_element = ET.SubElement(element, f"{{{SPARKLE}}}deltas")
            for delta in item["deltas"]:
                ET.SubElement(deltas_element, "enclosure", {
                    "url": download_url(item["tag"], delta["asset"]),
                    "length": str(delta["length"]), "type": "application/octet-stream",
                    f"{{{SPARKLE}}}deltaFrom": delta["deltaFrom"],
                    f"{{{SPARKLE}}}edSignature": delta["edSignature"],
                })
    ET.indent(root)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"
