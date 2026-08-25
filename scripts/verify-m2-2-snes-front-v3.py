#!/usr/bin/env python3
"""Deterministic verification for the M2.2 v3 SNES front-shell rebuild."""
from __future__ import annotations

import hashlib
import json
import struct
import subprocess
import sys
from collections import Counter, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "frontend/design"
ASSET = ROOT / "frontend/godot-ui/assets/snes/m2_2"
SCENE = ROOT / "frontend/godot-ui/scenes/SnesNaCartridgeFrontM2_2.tscn"
WORKFLOW = ROOT / ".github/workflows/m2-2-snes-front.yml"
ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v3"
PRIOR_ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v2"
SOURCE = "original-parametric-multi-section-loft-rebuild"
SURFACE_MODEL = "multi-section-loft-with-molded-front-patch"

def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"RETROLIFE_M2_2_FRONT_FAILED: {message}")

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def parse_obj(path: Path) -> tuple[list[tuple[float, float, float]], list[tuple[float, float]], list[tuple[int, int, int]]]:
    vertices: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    faces: list[tuple[int, int, int]] = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if line.startswith("v "):
            _, x, y, z = line.split()
            vertices.append((float(x), float(y), float(z)))
        elif line.startswith("vt "):
            _, u, v = line.split()
            uvs.append((float(u), float(v)))
        elif line.startswith("f "):
            parts = line.split()[1:]
            require(len(parts) == 3, f"non-triangle face in {path.name}")
            face = tuple(int(part.split("/")[0]) - 1 for part in parts)
            require(all(0 <= index < len(vertices) for index in face), f"face index in {path.name}")
            faces.append(face)  # type: ignore[arg-type]
    require(vertices, f"no vertices in {path.name}")
    require(faces, f"no faces in {path.name}")
    return vertices, uvs, faces

def bounds(vertices: list[tuple[float, float, float]]) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    minimum = tuple(min(vertex[index] for vertex in vertices) for index in range(3))
    maximum = tuple(max(vertex[index] for vertex in vertices) for index in range(3))
    return minimum, maximum

def near(value: float, expected: float, tolerance: float) -> bool:
    return abs(value - expected) <= tolerance

def manifold_and_components(vertex_count: int, faces: list[tuple[int, int, int]]) -> tuple[bool, int]:
    edges: Counter[tuple[int, int]] = Counter()
    adjacency: list[set[int]] = [set() for _ in range(vertex_count)]
    used: set[int] = set()
    for a, b, c in faces:
        used.update((a, b, c))
        for left, right in ((a, b), (b, c), (c, a)):
            edge = (left, right) if left < right else (right, left)
            edges[edge] += 1
            adjacency[left].add(right)
            adjacency[right].add(left)
    manifold = bool(edges) and all(count == 2 for count in edges.values())
    components = 0
    remaining = set(used)
    while remaining:
        components += 1
        start = remaining.pop()
        queue = deque([start])
        while queue:
            current = queue.popleft()
            for neighbour in adjacency[current]:
                if neighbour in remaining:
                    remaining.remove(neighbour)
                    queue.append(neighbour)
    return manifold, components

def png_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), f"PNG signature {path.name}")
    require(data[12:16] == b"IHDR", f"PNG IHDR {path.name}")
    return struct.unpack(">II", data[16:24])

def main() -> None:
    subprocess.run([sys.executable, str(ROOT / "scripts/generate-m2-2-snes-front.py"), "--root", str(ROOT), "--check"], check=True)
    reference = json.loads((DESIGN / "m2-snes-reference-manifest.json").read_text())
    manifest = json.loads((DESIGN / "m2-2-snes-front-manifest.json").read_text())
    require(manifest["schemaVersion"] == 3, "manifest schema")
    require(manifest["assetId"] == ASSET_ID, "asset id")
    require(manifest["priorAssetId"] == PRIOR_ASSET_ID, "prior asset id")
    require(PRIOR_ASSET_ID in manifest["rejectedAssetIds"], "v2 rejection")
    require("retrolife.snes.na-cartridge.m2.2.front.v1" in manifest["rejectedAssetIds"], "v1 rejection")
    require(manifest["license"] == "CC0-1.0", "license")
    require(manifest["source"] == SOURCE, "source")
    require(manifest["surfaceModel"] == SURFACE_MODEL, "surface model")
    require(manifest["heightFieldOnly"] is False, "height-field-only rejection")
    require(manifest["surfaceTopology"] == "single-connected-watertight-shell", "topology contract")
    require(manifest["referenceId"] == reference["referenceId"], "reference linkage")
    require(manifest["physicalCalibrationComplete"] is False, "calibration honesty")
    require(manifest["externalGeometryCopied"] is False, "external geometry boundary")
    require(manifest["externalMediaEmbedded"] is False, "external media boundary")
    require(manifest["physicalVisualComparisonRecorded"] is True, "physical comparison record")
    require(manifest["consoleVisible"] is False, "console exclusion")
    require(manifest["mayApproveFinalGeometry"] is False, "approval gate")
    require(manifest["mayStartM2_3Blockout"] is False, "M2.3 gate")
    require(manifest["mayStartM3"] is False, "M3 gate")
    require(manifest["physicalEnvelopeMm"] == [136.0, 88.0, 20.0], "envelope")
    require(manifest["frontHalfDepthMm"] == 10.4, "front depth")
    require(manifest["sideGripGrooveCountEach"] == 5, "five grooves")
    require(manifest["labelUvBounds"] == [[0.0, 0.0], [1.0, 1.0]], "UV contract")
    require(len(manifest["loftSectionDepthsMm"]) >= 5, "loft sections")
    require(len(manifest["externalVisualReferences"]) >= 4, "external comparison references")
    for entry in manifest["externalVisualReferences"]:
        require(entry.get("geometryCopied", False) is False, "external geometry copied")
        require(entry.get("mediaEmbedded", False) is False, "external media embedded")
        require(str(entry.get("url", "")).startswith("https://"), "reference URL")
    shell_path = ASSET / "snes_ntsc_u_front_shell_v3.obj"
    label_path = ASSET / "snes_ntsc_u_label_surface_v3.obj"
    shell_vertices, shell_uvs, shell_faces = parse_obj(shell_path)
    label_vertices, label_uvs, label_faces = parse_obj(label_path)
    require(not shell_uvs, "shell should not claim texture UVs")
    require(label_uvs, "label UVs")
    shell_component = manifest["components"]["continuous_shell"]
    require(shell_component["vertices"] == len(shell_vertices), "shell vertex manifest")
    require(shell_component["triangles"] == len(shell_faces), "shell triangle manifest")
    require(12000 <= len(shell_faces) <= 80000, f"shell triangle budget {len(shell_faces)}")
    require(6000 <= len(shell_vertices) <= 50000, f"shell vertex budget {len(shell_vertices)}")
    minimum, maximum = bounds(shell_vertices)
    size = tuple(maximum[index] - minimum[index] for index in range(3))
    require(near(size[0], 0.136, 0.0012), f"shell width {size[0]}")
    require(near(size[1], 0.088, 0.0012), f"shell height {size[1]}")
    require(near(size[2], 0.0104, 0.0010), f"shell depth {size[2]}")
    require(near(minimum[2], 0.0, 0.0001), f"seam origin {minimum[2]}")
    require(maximum[2] >= 0.0101, f"front crown {maximum[2]}")
    manifold, components = manifold_and_components(len(shell_vertices), shell_faces)
    require(manifold, "shell is not edge-manifold/watertight")
    require(components == 1, f"shell components {components}")
    min_uv = (min(uv[0] for uv in label_uvs), min(uv[1] for uv in label_uvs))
    max_uv = (max(uv[0] for uv in label_uvs), max(uv[1] for uv in label_uvs))
    require(min_uv[0] <= 0.001 and min_uv[1] <= 0.001, f"UV minimum {min_uv}")
    require(max_uv[0] >= 0.999 and max_uv[1] >= 0.999, f"UV maximum {max_uv}")
    label_min, label_max = bounds(label_vertices)
    label_size = tuple(label_max[index] - label_min[index] for index in range(3))
    require(near(label_size[0], 0.083, 0.0012), f"label width {label_size[0]}")
    require(near(label_size[1], 0.0385, 0.0012), f"label height {label_size[1]}")
    stale_paths = [ASSET / "snes_ntsc_u_front_shell.obj", ASSET / "snes_ntsc_u_front_features.obj", ASSET / "snes_ntsc_u_front_grooves.obj", ASSET / "snes_ntsc_u_label_surface.obj", ASSET / "snes_ntsc_u_screw_wells.obj", ROOT / "frontend/godot-ui/scripts/snes_na_cartridge_m2_2_v2.gd"]
    for path in stale_paths:
        require(not path.exists(), f"stale v1/v2 generated asset {path}")
    source = (ROOT / "scripts/generate-m2-2-snes-front.py").read_text()
    require("SECTION_DEPTHS_MM" in source, "loft sections in source")
    require("boundary_section_point" in source, "loft boundary source")
    require("height_field_only=false" in source, "height-field rejection marker")
    require("external_geometry_copied=false" in source, "external geometry marker")
    require("BoxMesh" not in source, "generic BoxMesh")
    require(PRIOR_ASSET_ID in source, "prior asset rejection in generator")
    generated = manifest.get("generatedFiles", {})
    require(len(generated) >= 20, f"generated file count {len(generated)}")
    for relative, expected_hash in generated.items():
        path = ROOT / relative
        require(path.is_file(), f"missing generated file {relative}")
        require(sha256(path) == expected_hash, f"generated hash {relative}")
    mobile_files = {
        "front": DESIGN / "mobile/m2-2-snes-v3-front.png",
        "three-quarter": DESIGN / "mobile/m2-2-snes-v3-three-quarter.png",
        "side": DESIGN / "mobile/m2-2-snes-v3-side.png",
        "top": DESIGN / "mobile/m2-2-snes-v3-top.png",
        "mobile sheet": DESIGN / "mobile/m2-2-snes-v3-mobile-review.png",
    }
    for name, path in mobile_files.items():
        require(path.is_file(), f"missing {name} PNG")
        width, height = png_dimensions(path)
        require(width >= 1000, f"mobile width {name}")
        require(height >= 700, f"mobile height {name}")
    require(png_dimensions(mobile_files["mobile sheet"])[1] >= 2500, "mobile sheet height")
    docs = (DESIGN / "m2-2-snes-front-shell.md").read_text()
    comparison = (DESIGN / "m2-2-snes-v3-physical-comparison.md").read_text()
    require("multi-section loft" in docs.lower(), "loft documentation")
    require("physical calibration" in docs.lower(), "calibration documentation")
    require("No third-party vertices" in docs, "external boundary documentation")
    require("Sketchfab" in comparison and "Wikimedia" in comparison and "USD343833S" in comparison, "comparison sources")
    require("No vertices" in comparison, "no-copy comparison statement")
    scene = SCENE.read_text()
    for node in ["ContinuousShell", "LabelSurface", "DockPivot", "CenterOfMass", "LabelAnchor", "ConnectorAnchor", "BrowseFocusedAnchor", "DockApproachAnchor"]:
        require(f'name="{node}"' in scene, f"scene node {node}")
    require(ASSET_ID in scene, "scene asset id")
    require("metadata/height_field_only = false" in scene, "scene height-field marker")
    require("metadata/external_geometry_copied = false" in scene, "scene external boundary")
    require("metadata/may_start_m2_3_blockout = false" in scene, "scene M2.3 gate")
    require("metadata/may_start_m3 = false" in scene, "scene M3 gate")
    require("snes_na_cartridge_m2_2_v2.gd" not in scene, "runtime v2 script reference")
    smoke = (ROOT / "frontend/godot-ui/scripts/m2_2_snes_front_smoke_test.gd").read_text()
    require("RETROLIFE_M2_2_FRONT_GODOT_OK" in smoke, "Godot marker")
    require("height_field_only=false" in smoke, "Godot height-field marker")
    workflow = WORKFLOW.read_text()
    require("runs-on: ubuntu-24.04" in workflow, "Linux runner")
    require("runs-on: macos-15" in workflow, "macOS runner")
    require("scripts/verify-m2-2-snes-front.py" in workflow, "validator in workflow")
    require("m2_2_snes_front_smoke_test.gd" in workflow, "smoke in workflow")
    require("permissions:\n  contents: read" in workflow, "read-only workflow")
    print("RETROLIFE_M2_2_FRONT_OK " + f"asset={ASSET_ID} envelope=136x88 front_depth_mm=10.4 shell_vertices={len(shell_vertices)} shell_triangles={len(shell_faces)} loft_sections={len(manifest['loftSectionDepthsMm'])} connected_components={components} " + "height_field_only=false watertight=true physical_comparison=true external_geometry_copied=false physical_calibrated=false final_approval=false m2_3=false m3=false")

if __name__ == "__main__":
    main()
