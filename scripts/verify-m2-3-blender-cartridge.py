#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "frontend/design/m2-3-snes-blender-manifest.json"
ASSET_ID = "retrolife.snes.ntsc-u.cartridge.m2.3.blender.v1"
RENDER_KEYS = {"front", "front-clay", "three-quarter", "rear", "rear-three-quarter", "side", "top", "bottom"}


def fail(message: str) -> None:
    raise SystemExit(f"RETROLIFE_M2_3_BLENDER_FAILED: {message}")


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked(entry: dict[str, object]) -> Path:
    path = ROOT / str(entry["path"])
    require(path.is_file(), f"missing {path.relative_to(ROOT)}")
    require(sha256(path) == entry["sha256"], f"hash {path.relative_to(ROOT)}")
    require(path.stat().st_size == int(entry["bytes"]), f"size {path.relative_to(ROOT)}")
    return path


def png_dimensions(path: Path) -> list[int]:
    data = path.read_bytes()[:24]
    require(data.startswith(b"\x89PNG\r\n\x1a\n") and data[12:16] == b"IHDR", f"PNG {path.name}")
    return list(struct.unpack(">II", data[16:24]))


def nonblank(path: Path) -> None:
    try:
        from PIL import Image
    except ImportError:
        require(path.stat().st_size > 20_000, f"small render {path.name}")
        return
    extrema = Image.open(path).convert("RGB").resize((64, 64)).getextrema()
    require(any(high - low > 20 for low, high in extrema), f"blank render {path.name}")


def glb_document(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    require(len(data) > 100_000, "GLB size")
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    require(magic == b"glTF" and version == 2 and length == len(data), "GLB header")
    chunk_length, chunk_type = struct.unpack_from("<II", data, 12)
    require(chunk_type == 0x4E4F534A, "GLB JSON chunk")
    return json.loads(data[20 : 20 + chunk_length].rstrip(b" \x00").decode("utf-8"))


def main() -> None:
    require(MANIFEST.is_file(), "manifest missing")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    require(manifest.get("schemaVersion") == 1, "manifest schema")
    require(manifest.get("assetId") == ASSET_ID, "asset ID")
    require(manifest.get("status") == "provisional-attributed-reference-normalized-in-blender", "status")
    require(manifest.get("physicalEnvelopeMm") == [136.0, 88.0, 20.0], "physical envelope")
    require(manifest.get("rootPivot") == "bottom-connector-center", "root pivot")
    require(str(manifest.get("blenderVersion", "")).startswith("5.2"), "Blender version")
    for key, expected in {
        "reviewLabelArtOriginal": True,
        "commercialLabelArtEmbedded": False,
        "romsEmbedded": False,
        "privateRepositoryMaterialUsed": False,
        "physicalCalibrationComplete": False,
        "ownerVisualApproval": False,
        "mayMerge": False,
    }.items():
        require(manifest.get(key) is expected, key)

    source = checked(manifest["sourceMesh"])
    require(source.suffix.lower() in {".stl", ".obj", ".ply"}, "source format")
    require(manifest["sourceMesh"].get("creator") == "neebick", "source creator")
    require(manifest["sourceMesh"].get("publicUrl") == "https://www.thingiverse.com/thing:6364945", "source URL")
    license_name = str(manifest["sourceMesh"].get("license", "")).lower()
    require("cc by" in license_name or "attribution" in license_name or "cc0" in license_name, "source license")
    for forbidden in ["noncommercial", "non-commercial", "sharealike", "share-alike", "no derivatives"]:
        require(forbidden not in license_name, f"unsupported license restriction {forbidden}")
    for key in ["licensePath", "provenancePath"]:
        require((ROOT / manifest["sourceMesh"][key]).is_file(), key)

    blend = checked(manifest["runtime"]["blend"])
    glb = checked(manifest["runtime"]["glb"])
    require(blend.read_bytes()[:7] == b"BLENDER", "Blend header")
    document = glb_document(glb)
    names = {node.get("name", "") for node in document.get("nodes", [])}
    require("CartridgeShell" in names, "GLB shell")
    require("Label" in names, "GLB label")

    require(set(manifest.get("renders", {})) == RENDER_KEYS, "render keys")
    for key, entry in manifest["renders"].items():
        path = checked(entry)
        require(png_dimensions(path) == [1400, 1000], f"render dimensions {key}")
        require(entry["dimensionsPx"] == [1400, 1000], f"manifest render dimensions {key}")
        nonblank(path)
    sheet = checked(manifest["reviewSheet"])
    require(png_dimensions(sheet) == manifest["reviewSheet"]["dimensionsPx"], "review sheet dimensions")
    require(manifest["reviewSheet"]["dimensionsPx"][0] == 1400, "review sheet width")
    nonblank(sheet)

    generator = (ROOT / "scripts/blender/build_m2_3_cartridge.py").read_text(encoding="utf-8")
    for marker in ["bpy.ops.wm.stl_import", "export_scene.gltf", "RETROLIFE_M2_3_BLENDER_OK"]:
        require(marker in generator, f"generator marker {marker}")
    workflow = (ROOT / ".github/workflows/m2-3-blender.yml").read_text(encoding="utf-8")
    for marker in ["blender-5.2.1-linux-x64.tar.xz", "--background", "xvfb-run", "permissions:\n  contents: read"]:
        require(marker in workflow, f"workflow marker {marker}")
    scene = (ROOT / "frontend/godot-ui/scenes/SnesNaCartridgeM2_3.tscn").read_text(encoding="utf-8")
    smoke = (ROOT / "frontend/godot-ui/scripts/m2_3_snes_blender_smoke_test.gd").read_text(encoding="utf-8")
    require(ASSET_ID in scene, "scene asset")
    require("RETROLIFE_M2_3_BLENDER_GODOT_OK" in smoke, "smoke marker")
    for path in [ROOT / ".codex-blender-source", ROOT / ".codex-payload"]:
        require(not path.exists(), f"temporary path {path.name}")
    require(not list((ROOT / ".github/workflows").glob("codex-*.yml")), "temporary workflows")

    print(
        "RETROLIFE_M2_3_BLENDER_OK "
        f"asset={ASSET_ID} blender={manifest['blenderVersion']} "
        f"vertices={manifest['vertices']} polygons={manifest['polygons']} "
        "commercial_label=false private_material=false calibration=false approval=false merge=false"
    )


if __name__ == "__main__":
    main()
