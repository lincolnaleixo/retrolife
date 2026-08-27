#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
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
CI_WORKFLOW = ROOT / ".github/workflows/ci.yml"
MANIFEST = DESIGN / "m2-2-snes-front-manifest.json"
ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v4"
PRIOR_ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v3"
REFERENCE_ID = "retrolife.m2.1.snes-ntsc-u.reference.v2"
SOURCE = "original-cadquery-opencascade-brep-rebuild"
SURFACE_MODEL = "cadquery-opencascade-brep-with-drafted-booleans"


def fail(message: str) -> None:
    raise SystemExit(f"RETROLIFE_M2_2_FRONT_FAILED: {message}")


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-regeneration", action="store_true")
    return parser.parse_args()


def parse_binary_stl(path: Path) -> tuple[int, list[tuple[float, float, float]]]:
    data = path.read_bytes()
    require(len(data) >= 84, "STL is truncated")
    count = struct.unpack_from("<I", data, 80)[0]
    require(len(data) == 84 + count * 50, "STL size does not match triangle count")
    vertices: list[tuple[float, float, float]] = []
    offset = 84
    for _ in range(count):
        values = struct.unpack_from("<12fH", data, offset)
        vertices.extend(
            [
                (values[3], values[4], values[5]),
                (values[6], values[7], values[8]),
                (values[9], values[10], values[11]),
            ]
        )
        offset += 50
    return count, vertices


def parse_obj(path: Path) -> tuple[list[tuple[float, float, float]], list[tuple[float, float]], list[tuple[int, int, int]]]:
    vertices: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    faces: list[tuple[int, int, int]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("v "):
            parts = line.split()
            vertices.append((float(parts[1]), float(parts[2]), float(parts[3])))
        elif line.startswith("vt "):
            parts = line.split()
            uvs.append((float(parts[1]), float(parts[2])))
        elif line.startswith("f "):
            refs = line.split()[1:]
            require(len(refs) == 3, f"non-triangle OBJ face in {path.name}")
            indices = []
            for ref in refs:
                index = int(ref.split("/")[0])
                require(index > 0, "OBJ must use positive indices")
                indices.append(index - 1)
            faces.append(tuple(indices))
    return vertices, uvs, faces


def bounds(vertices: list[tuple[float, float, float]]) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    require(bool(vertices), "mesh has no vertices")
    minimum = tuple(min(vertex[index] for vertex in vertices) for index in range(3))
    maximum = tuple(max(vertex[index] for vertex in vertices) for index in range(3))
    return minimum, maximum


def near(value: float, expected: float, tolerance: float) -> bool:
    return abs(value - expected) <= tolerance


def topology(vertex_count: int, faces: list[tuple[int, int, int]]) -> tuple[bool, int]:
    edges: Counter[tuple[int, int]] = Counter()
    adjacency: list[set[int]] = [set() for _ in range(vertex_count)]
    used: set[int] = set()
    for face in faces:
        require(len(set(face)) == 3, "degenerate OBJ topology face")
        for index in face:
            require(0 <= index < vertex_count, "OBJ face index out of range")
            used.add(index)
        for left, right in ((face[0], face[1]), (face[1], face[2]), (face[2], face[0])):
            edge = (left, right) if left < right else (right, left)
            edges[edge] += 1
            adjacency[left].add(right)
            adjacency[right].add(left)
    manifold = bool(edges) and all(count == 2 for count in edges.values())
    remaining = set(used)
    components = 0
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


def check_non_black_png(path: Path) -> None:
    try:
        from PIL import Image
    except ImportError:
        require(path.stat().st_size > 12_000, f"render too small {path.name}")
        return
    image = Image.open(path).convert("RGB")
    sample = image.resize((64, 64))
    extrema = sample.getextrema()
    require(any(high - low > 16 for low, high in extrema), f"render appears blank {path.name}")


def main() -> None:
    args = parse_args()
    if not args.skip_regeneration:
        subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts/generate-m2-2-snes-front.py"),
                "--root",
                str(ROOT),
                "--check",
                "--skip-renders",
            ],
            check=True,
        )

    require(MANIFEST.is_file(), "manifest missing")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    require(manifest.get("schemaVersion") == 4, "manifest schema")
    require(manifest.get("assetId") == ASSET_ID, "asset ID")
    require(manifest.get("priorAssetId") == PRIOR_ASSET_ID, "prior asset ID")
    for rejected in [
        "retrolife.snes.na-cartridge.m2.2.front.v1",
        "retrolife.snes.na-cartridge.m2.2.front.v2",
        PRIOR_ASSET_ID,
    ]:
        require(rejected in manifest.get("rejectedAssetIds", []), f"rejected asset {rejected}")
    require(manifest.get("referenceId") == REFERENCE_ID, "M2.1 reference linkage")
    require(manifest.get("source") == SOURCE, "CAD source")
    require(manifest.get("surfaceModel") == SURFACE_MODEL, "CAD surface model")
    require(manifest.get("cadTool") == "CadQuery 2.8.0", "CadQuery version")
    require(manifest.get("cadKernel") == "Open CASCADE 7.9", "CAD kernel")
    require(manifest.get("stepExported") is True, "STEP export flag")
    require(manifest.get("heightFieldOnly") is False, "height field rejection")
    require(manifest.get("multiSectionLoftOnly") is False, "loft-only rejection")
    require(manifest.get("externalGeometryCopied") is False, "external geometry boundary")
    require(manifest.get("externalMediaEmbedded") is False, "external media boundary")
    require(manifest.get("physicalCalibrationComplete") is False, "physical calibration honesty")
    require(manifest.get("mayApproveFinalGeometry") is False, "approval gate")
    require(manifest.get("mayStartM2_3Blockout") is False, "M2.3 gate")
    require(manifest.get("mayStartM3") is False, "M3 gate")
    require(manifest.get("physicalEnvelopeMm") == [136.0, 88.0, 20.0], "physical envelope")
    require(manifest.get("frontShellDepthMm") == 10.4, "nominal front-shell depth")
    require(manifest.get("actualCadBoundsMm") == [136.0, 88.0, 10.4], "actual CAD bounds")
    require(manifest.get("actualCadExtentsMm") == [[-68.0, 68.0], [0.0, 88.0], [0.0, 10.4]], "actual CAD extents")
    require(manifest.get("frontBandDivisionCountEach") == 4, "front band divisions")
    require(manifest.get("frontMouldedBandCountEach") == 5, "front moulded bands")
    require(manifest.get("frontBandDivisionCenterYmm") == [25.8, 42.0, 58.2, 74.4], "band positions")
    require(manifest.get("labelUvBounds") == [[0.0, 0.0], [1.0, 1.0]], "label UV contract")
    require(len(manifest.get("externalVisualReferences", [])) >= 5, "physical comparison references")
    for reference in manifest["externalVisualReferences"]:
        require(reference.get("geometryCopied") is False, "external geometry copied")
        require(reference.get("mediaEmbedded") is False, "external media embedded")
        require(str(reference.get("url", "")).startswith("https://"), "reference URL")

    step_path = ROOT / manifest["components"]["cadStep"]["path"]
    stl_path = ROOT / manifest["components"]["cadStl"]["path"]
    obj_path = ROOT / manifest["components"]["godotMesh"]["path"]
    label_path = ROOT / manifest["components"]["labelSurface"]["path"]
    for path in [step_path, stl_path, obj_path, label_path]:
        require(path.is_file(), f"missing generated component {path.relative_to(ROOT)}")
    require(step_path.stat().st_size > 1_000_000, "STEP file is unexpectedly small")
    step = step_path.read_text(encoding="utf-8")
    for marker in [
        "ISO-10303-21;",
        "FILE_NAME('RetroLife M2.2 v4 front shell','2000-01-01T00:00:00'",
        "ADVANCED_BREP_SHAPE_REPRESENTATION",
        "MANIFOLD_SOLID_BREP",
        "CadQuery 2.8.0 / Open CASCADE 7.9",
    ]:
        require(marker in step, f"STEP marker {marker}")
    require("2026-" not in step.split("ENDSEC;", 1)[0], "STEP header contains a runtime timestamp")

    stl_triangles, stl_vertices = parse_binary_stl(stl_path)
    component = manifest["components"]["cadStl"]
    require(stl_triangles == component["triangles"], "STL triangle manifest")
    require(8_000 <= stl_triangles <= 80_000, f"STL triangle budget {stl_triangles}")
    stl_min, stl_max = bounds(stl_vertices)
    stl_size = tuple(stl_max[index] - stl_min[index] for index in range(3))
    require(near(stl_size[0], 136.0, 0.01), f"STL width {stl_size[0]}")
    require(near(stl_size[1], 88.0, 0.01), f"STL height {stl_size[1]}")
    require(10.0 <= stl_size[2] <= 10.41, f"STL depth {stl_size[2]}")
    require(near(stl_min[0], -68.0, 0.01) and near(stl_max[0], 68.0, 0.01), "STL X origin")
    require(near(stl_min[1], 0.0, 0.001) and near(stl_min[2], 0.0, 0.001), "STL bottom/seam origin")

    obj_vertices, obj_uvs, obj_faces = parse_obj(obj_path)
    require(not obj_uvs, "shell OBJ should not claim label UVs")
    require(len(obj_vertices) == manifest["components"]["godotMesh"]["vertices"], "OBJ vertex manifest")
    require(len(obj_faces) == manifest["components"]["godotMesh"]["triangles"], "OBJ triangle manifest")
    obj_min, obj_max = bounds(obj_vertices)
    obj_size = tuple(obj_max[index] - obj_min[index] for index in range(3))
    require(near(obj_size[0], 0.136, 0.00002), f"OBJ width {obj_size[0]}")
    require(near(obj_size[1], 0.088, 0.00002), f"OBJ height {obj_size[1]}")
    require(0.0100 <= obj_size[2] <= 0.01041, f"OBJ depth {obj_size[2]}")
    require(near(obj_min[1], 0.0, 0.000001) and near(obj_min[2], 0.0, 0.000001), "OBJ bottom/seam origin")
    manifold, components = topology(len(obj_vertices), obj_faces)
    require(manifold, "OBJ topology is not edge-manifold")
    require(components == 1, f"OBJ connected components {components}")

    label_vertices, label_uvs, label_faces = parse_obj(label_path)
    require(label_vertices and label_faces and label_uvs, "label OBJ is incomplete")
    label_min, label_max = bounds(label_vertices)
    label_size = tuple(label_max[index] - label_min[index] for index in range(3))
    require(near(label_size[0], 0.0915, 0.0002), f"label width {label_size[0]}")
    require(near(label_size[1], 0.0390, 0.0002), f"label height {label_size[1]}")
    min_uv = (min(uv[0] for uv in label_uvs), min(uv[1] for uv in label_uvs))
    max_uv = (max(uv[0] for uv in label_uvs), max(uv[1] for uv in label_uvs))
    require(min_uv[0] <= 0.001 and min_uv[1] <= 0.001, f"label UV minimum {min_uv}")
    require(max_uv[0] >= 0.999 and max_uv[1] >= 0.999, f"label UV maximum {max_uv}")

    render_expectations = {
        "front": (1400, 1000),
        "threeQuarter": (1400, 1000),
        "side": (1400, 1000),
        "top": (1400, 1000),
        "dimensions": (1600, 1000),
        "mobileReview": (1400, 3300),
    }
    for key, expected_dimensions in render_expectations.items():
        entry = manifest["reviewRenders"][key]
        path = ROOT / entry["path"]
        require(path.is_file(), f"missing review render {key}")
        require(png_dimensions(path) == expected_dimensions, f"PNG dimensions {key}")
        check_non_black_png(path)
        require(sha256(path) == entry["sha256"], f"render hash {key}")

    generated = manifest.get("generatedFiles", {})
    require(len(generated) >= 18, f"generated file count {len(generated)}")
    for relative, expected_hash in generated.items():
        path = ROOT / relative
        require(path.is_file(), f"missing generated file {relative}")
        require(sha256(path) == expected_hash, f"generated hash {relative}")

    stale_paths = [
        ASSET / "snes_ntsc_u_front_shell_v3.obj",
        ASSET / "snes_ntsc_u_label_surface_v3.obj",
        ASSET / "materials/snes_m2_2_v3_shell_clay.tres",
        ASSET / "materials/snes_m2_2_v3_label_placeholder.tres",
        DESIGN / "m2-2-snes-front-clay.svg",
        DESIGN / "m2-2-snes-front-overlay.svg",
        DESIGN / "m2-2-snes-front-top-side-overlay.svg",
        DESIGN / "m2-2-snes-alpha-comparison.svg",
        DESIGN / "m2-2-snes-m1-poses.svg",
    ]
    for path in stale_paths:
        require(not path.exists(), f"stale active v3/SVG asset {path.relative_to(ROOT)}")

    source = (ROOT / "scripts/generate-m2-2-snes-front.py").read_text(encoding="utf-8")
    for marker in [
        "import cadquery as cq",
        "cq.Solid.makeLoft",
        "tapered_pocket",
        "canonicalize_step",
        "write_binary_stl",
        "vtk.vtkRenderWindow",
        "height_field=false",
        "loft_only=false",
    ]:
        require(marker in source, f"generator marker {marker}")
    require("BoxMesh" not in source, "generic Godot BoxMesh generator")

    documentation = (DESIGN / "m2-2-snes-front-shell.md").read_text(encoding="utf-8")
    comparison = (DESIGN / "m2-2-snes-v4-physical-comparison.md").read_text(encoding="utf-8")
    for marker in ["CadQuery/Open CASCADE", "STEP", "SVG is no longer the primary", "physical caliper"]:
        require(marker in documentation, f"documentation marker {marker}")
    for marker in ["Super Mario World", "Wikimedia", "USD343833S", "No vertices"]:
        require(marker in comparison, f"comparison marker {marker}")

    scene = SCENE.read_text(encoding="utf-8")
    for marker in [ASSET_ID, "CadShell", "LabelSurface", "metadata/step_exported = true", "metadata/height_field_only = false", "metadata/multi_section_loft_only = false"]:
        require(marker in scene, f"scene marker {marker}")
    smoke = (ROOT / "frontend/godot-ui/scripts/m2_2_snes_front_smoke_test.gd").read_text(encoding="utf-8")
    require("RETROLIFE_M2_2_FRONT_GODOT_OK asset=v4" in smoke, "Godot smoke marker")
    require("quit(0)\n        return" in smoke, "Godot smoke success must return before failure path")

    requirements = (ROOT / "scripts/requirements-m2-cad.txt").read_text(encoding="utf-8")
    for marker in ["cadquery==2.8.0", "numpy==2.3.5", "Pillow==12.3.0", "vtk==9.6.2"]:
        require(marker in requirements, f"CAD requirements marker {marker}")
    for workflow in [WORKFLOW, CI_WORKFLOW]:
        text = workflow.read_text(encoding="utf-8")
        require("scripts/verify-m2-2-snes-front.py" in text, f"verifier in {workflow.name}")
        require("permissions:\n  contents: read" in text, f"read-only permissions in {workflow.name}")
    m2_workflow_text = WORKFLOW.read_text(encoding="utf-8")
    require(m2_workflow_text.count("./scripts/build-phase4-launch.sh debug") == 2, "native bridge build in Linux and macOS M2.2 jobs")
    ci_text = CI_WORKFLOW.read_text(encoding="utf-8")
    require("gitleaks" in ci_text.lower() and " git --no-banner --redact ." in ci_text, "Gitleaks history gate")
    require(not (ROOT / ".codex-payload").exists(), "temporary payload directory remains")
    temporary_workflows = sorted(path.name for path in (ROOT / ".github/workflows").glob("codex-*.yml"))
    require(not temporary_workflows, f"temporary workflows remain: {temporary_workflows}")

    print(
        "RETROLIFE_M2_2_FRONT_OK "
        f"asset={ASSET_ID} cad=opencascade step=true brep_faces={manifest['brepFaces']} "
        f"mesh_vertices={len(obj_vertices)} mesh_triangles={len(obj_faces)} "
        "bands=5 divisions=4 height_field=false loft_only=false "
        "external_geometry_copied=false physical_calibrated=false final_approval=false m2_3=false m3=false"
    )


if __name__ == "__main__":
    main()
