#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

ASSET_ID = "retrolife.snes.ntsc-u.cartridge.m2.3.blender.v1"
RENDER_KEYS = (
    "front",
    "front-clay",
    "three-quarter",
    "rear",
    "rear-three-quarter",
    "side",
    "top",
    "bottom",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def font(size: int, bold: bool = False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).is_file():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    fitted = ImageOps.contain(image.convert("RGB"), size, Image.Resampling.LANCZOS)
    panel = Image.new("RGB", size, "#07090d")
    panel.paste(fitted, ((size[0] - fitted.width) // 2, (size[1] - fitted.height) // 2))
    return panel


def png_dimensions(path: Path) -> list[int]:
    data = path.read_bytes()[:24]
    if not data.startswith(b"\x89PNG\r\n\x1a\n") or data[12:16] != b"IHDR":
        raise SystemExit(f"invalid PNG: {path}")
    return list(struct.unpack(">II", data[16:24]))


def build_sheet(root: Path, render_paths: dict[str, Path]) -> Path:
    labels = {
        "front": "FRONT WITH ORIGINAL REVIEW LABEL",
        "front-clay": "FRONT CLAY",
        "three-quarter": "FRONT THREE-QUARTER",
        "rear": "REAR",
        "rear-three-quarter": "REAR THREE-QUARTER",
        "side": "SIDE PROFILE",
        "top": "TOP",
        "bottom": "BOTTOM / CONNECTOR",
    }
    panel_width, panel_height = 620, 440
    margin, gap_x, gap_y = 44, 32, 70
    columns = 2
    rows = (len(RENDER_KEYS) + columns - 1) // columns
    width = 1400
    header = 190
    height = header + rows * (panel_height + gap_y) + 100
    canvas = Image.new("RGB", (width, height), "#f7f8fa")
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, 40), "RetroLife M2.3 Blender cartridge review", font=font(46, True), fill="#10141c")
    draw.text((margin, 104), "Headless Blender 5.2.1, attributed public NTSC-U/C reference, 136 × 88 × 20 mm", font=font(25), fill="#4a5362")
    draw.text((margin, 143), "No commercial label art. Physical calibration and owner approval remain open.", font=font(20), fill="#687384")
    for index, key in enumerate(RENDER_KEYS):
        row, column = divmod(index, columns)
        x = margin + column * (panel_width + gap_x)
        y = header + row * (panel_height + gap_y)
        canvas.paste(fit(Image.open(render_paths[key]), (panel_width, panel_height)), (x, y))
        draw.text((x, y + panel_height + 12), labels[key], font=font(23, True), fill="#10141c")
    output = root / "frontend/design/mobile/m2-3-snes-blender-full-review.png"
    canvas.save(output, optimize=False, compress_level=9)
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--source-archive-sha", default="")
    parser.add_argument("--source-license", required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    source = args.source.resolve()
    manifest_path = root / "frontend/design/m2-3-snes-blender-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["assetId"] = ASSET_ID
    manifest["status"] = "provisional-attributed-reference-normalized-in-blender"
    manifest["sourceMesh"] = {
        "path": str(source.relative_to(root)),
        "sha256": sha256(source),
        "bytes": source.stat().st_size,
        "archiveSha256": args.source_archive_sha,
        "publicUrl": "https://www.thingiverse.com/thing:6364945",
        "creator": "neebick",
        "license": args.source_license,
        "licensePath": "frontend/godot-ui/assets/snes/m2_3/source/LICENSE.md",
        "provenancePath": "frontend/godot-ui/assets/snes/m2_3/source/PROVENANCE.md",
    }
    manifest["physicalEnvelopeMm"] = [136.0, 88.0, 20.0]
    manifest["rootPivot"] = "bottom-connector-center"
    manifest["reviewLabelArtOriginal"] = True
    manifest["commercialLabelArtEmbedded"] = False
    manifest["romsEmbedded"] = False
    manifest["privateRepositoryMaterialUsed"] = False
    manifest["physicalCalibrationComplete"] = False
    manifest["ownerVisualApproval"] = False
    manifest["mayMerge"] = False
    asset_dir = root / "frontend/godot-ui/assets/snes/m2_3"
    blend = asset_dir / "snes_ntsc_u_cartridge_m2_3.blend"
    glb = asset_dir / "snes_ntsc_u_cartridge_m2_3.glb"
    manifest["runtime"] = {
        "blend": {"path": str(blend.relative_to(root)), "sha256": sha256(blend), "bytes": blend.stat().st_size},
        "glb": {"path": str(glb.relative_to(root)), "sha256": sha256(glb), "bytes": glb.stat().st_size},
    }
    mobile = root / "frontend/design/mobile"
    render_paths = {key: mobile / f"m2-3-snes-blender-{key}.png" for key in RENDER_KEYS}
    manifest["renders"] = {
        key: {
            "path": str(path.relative_to(root)),
            "sha256": sha256(path),
            "bytes": path.stat().st_size,
            "dimensionsPx": png_dimensions(path),
        }
        for key, path in render_paths.items()
    }
    sheet = build_sheet(root, render_paths)
    manifest["reviewSheet"] = {
        "path": str(sheet.relative_to(root)),
        "sha256": sha256(sheet),
        "bytes": sheet.stat().st_size,
        "dimensionsPx": png_dimensions(sheet),
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"RETROLIFE_M2_3_BLENDER_FINALIZE_OK asset={ASSET_ID} source_license={args.source_license}")


if __name__ == "__main__":
    main()
