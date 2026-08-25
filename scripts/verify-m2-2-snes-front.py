#!/usr/bin/env python3
"""Deterministic verification for the provisional M2.2 SNES front shell v2."""
from __future__ import annotations

import collections
import hashlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "frontend/design"
ASSET = ROOT / "frontend/godot-ui/assets/snes/m2_2"
SCENE = ROOT / "frontend/godot-ui/scenes/SnesNaCartridgeFrontM2_2.tscn"
RUNTIME = ROOT / "frontend/godot-ui/scripts/snes_na_cartridge_m2_2_v2.gd"
WORKFLOW = ROOT / ".github/workflows/m2-2-snes-front.yml"
ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v2"
PRIOR_ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v1"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"RETROLIFE_M2_2_FRONT_FAILED: {message}")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounds(vertices: list[tuple[float, float, float]]) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    return (
        tuple(min(vertex[index] for vertex in vertices) for index in range(3)),
        tuple(max(vertex[index] for vertex in vertices) for index in range(3)),
    )


def near(value: float, expected: float, tolerance: float) -> bool:
    return abs(value - expected) <= tolerance


def verify_watertight_and_connected(vertices: list[tuple[float, float, float]], faces: list[tuple[int, int, int]]) -> None:
    edge_counts: collections.Counter[tuple[int, int]] = collections.Counter()
    adjacency: list[set[int]] = [set() for _ in vertices]
    used: set[int] = set()
    for face in faces:
        for vertex in face:
            used.add(vertex)
        for a, b in ((face[0], face[1]), (face[1], face[2]), (face[2], face[0])):
            edge_counts[tuple(sorted((a, b)))] += 1
            adjacency[a].add(b)
            adjacency[b].add(a)
    bad_edges = [edge for edge, count in edge_counts.items() if count != 2]
    require(not bad_edges, f"continuous shell is not watertight; {len(bad_edges)} boundary/non-manifold edges")
    start = next(iter(used))
    visited = {start}
    stack = [start]
    while stack:
        current = stack.pop()
        for neighbor in adjacency[current]:
            if neighbor in used and neighbor not in visited:
                visited.add(neighbor)
                stack.append(neighbor)
    require(visited == used, f"continuous shell has {len(used - visited)} disconnected used vertices")


def load_generator():
    source = ROOT / "scripts/generate-m2-2-snes-front.py"
    spec = importlib.util.spec_from_file_location("retrolife_m2_2_generator", source)
    require(spec is not None and spec.loader is not None, "cannot load generator module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> None:
    subprocess.run(
        [sys.executable, str(ROOT / "scripts/generate-m2-2-snes-front.py"), "--root", str(ROOT), "--check"],
        check=True,
    )

    reference = json.loads((DESIGN / "m2-snes-reference-manifest.json").read_text())
    manifest = json.loads((DESIGN / "m2-2-snes-front-manifest.json").read_text())
    require(manifest["schemaVersion"] == 2, "schema version")
    require(manifest["assetId"] == ASSET_ID, "asset id")
    require(manifest["priorAssetId"] == PRIOR_ASSET_ID, "prior asset id")
    require(manifest["priorGeometryAccepted"] is False, "prior geometry rejection")
    require(manifest["license"] == "CC0-1.0", "license")
    require(manifest["source"] == "original-parametric-continuous-surface-rebuild", "source")
    require(manifest["runtimeRepresentation"] == "deterministic-godot-generated-mesh", "runtime representation")
    require(manifest["status"] == "provisional-continuous-surface-rebuild", "status")
    require(manifest["referenceId"] == reference["referenceId"], "reference linkage")
    require(manifest["alphaGeometryReused"] is False, "alpha/v1 reuse")
    require(manifest["consoleVisible"] is False, "console exclusion")
    require(manifest["physicalCalibrationComplete"] is False, "calibration honesty")
    require(manifest["mayApproveFinalGeometry"] is False, "final approval gate")
    require(manifest["mayStartM2_3Blockout"] is False, "M2.3 gate")
    require(manifest["mayStartM3"] is False, "M3 gate")
    require(manifest["surfaceTopology"] == "single-connected-watertight-shell", "surface topology")
    require(manifest["physicalEnvelopeMm"] == [136.0, 88.0, 20.0], "envelope")
    require(manifest["labelUvBounds"] == [[0.0, 0.0], [1.0, 1.0]], "label UV contract")
    require(manifest["referenceLandmarks"]["sideGripGrooveCountEach"] == 5, "five wing grooves")

    generator = load_generator()
    shell, label, _metadata = generator.build_shell(reference)
    verify_watertight_and_connected(shell.vertices, shell.faces)
    minimum, maximum = bounds(shell.vertices)
    size = tuple(maximum[index] - minimum[index] for index in range(3))
    require(near(size[0], 0.136, 0.0011), f"shell width {size[0]}")
    require(near(size[1], 0.088, 0.0011), f"shell height {size[1]}")
    require(0.0090 <= size[2] <= 0.0106, f"front depth {size[2]}")
    require(near(minimum[2], 0.0, 0.00001), "seam plane origin")
    require(10_000 <= shell.triangles <= 35_000, f"LOD0 triangle budget {shell.triangles}")
    require(manifest["components"]["continuous_shell"] == {"vertices": len(shell.vertices), "triangles": shell.triangles}, "shell manifest counts")
    require(manifest["components"]["label_surface"] == {"vertices": len(label.vertices), "triangles": label.triangles}, "label manifest counts")
    require(label.uvs == [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)], "label UVs")

    for obsolete in [
        "snes_ntsc_u_front_shell.obj",
        "snes_ntsc_u_front_features.obj",
        "snes_ntsc_u_front_grooves.obj",
        "snes_ntsc_u_label_surface.obj",
        "snes_ntsc_u_screw_wells.obj",
        "materials/snes_m2_2_shell_clay.tres",
        "materials/snes_m2_2_detail_clay.tres",
        "materials/snes_m2_2_label_placeholder.tres",
    ]:
        require(not (ASSET / obsolete).exists(), f"obsolete v1 output remains: {obsolete}")

    generated = manifest.get("generatedFiles", {})
    require(len(generated) == 9, f"generated file count {len(generated)}")
    for relative, expected_hash in generated.items():
        path = ROOT / relative
        require(path.is_file(), f"missing generated file {relative}")
        require(sha256(path) == expected_hash, f"generated hash {relative}")

    scene = SCENE.read_text()
    require('res://scripts/snes_na_cartridge_m2_2_v2.gd' in scene, "runtime generator scene link")
    require("ArrayMesh" not in scene, "scene must not embed plate meshes")
    runtime = RUNTIME.read_text()
    for marker in [
        f'const ASSET_ID := "{ASSET_ID}"',
        f'const PRIOR_ASSET_ID := "{PRIOR_ASSET_ID}"',
        "single-connected-watertight-shell",
        f"const EXPECTED_SHELL_TRIANGLES := {shell.triangles}",
        "_front_surface_z",
        "_rounded_box_sdf",
        "_build_label_mesh",
        'set_meta("may_start_m2_3_blockout", false)',
        'set_meta("may_start_m3", false)',
    ]:
        require(marker in runtime, f"runtime generator missing marker: {marker}")
    for rejected in ["FrontFeatures", "FrontGrooves", "ScrewWells", "snes_ntsc_u_front_features.obj"]:
        require(rejected not in runtime, f"runtime reintroduced v1 plate form: {rejected}")

    source = (ROOT / "scripts/generate-m2-2-snes-front.py").read_text()
    require("continuous-surface rebuild" in source.lower(), "continuous rebuild marker")
    require(PRIOR_ASSET_ID in source, "prior rejection marker")
    require("CC0-1.0" in source, "source license")
    require("BoxMesh" not in source, "generic BoxMesh")

    docs = (DESIGN / "m2-2-snes-front-shell.md").read_text()
    require("rejected as plate-stacked production geometry" in docs, "v1 rejection documentation")
    require("one connected watertight surface" in docs, "continuous topology documentation")
    require("physical calibration" in docs.lower(), "physical calibration documentation")
    require("M2.3 and M3" in docs and "blocked" in docs.lower(), "later milestone gates")
    require("rather than committing a multi-megabyte intermediate OBJ" in docs, "compact runtime representation documentation")

    for name in [
        "m2-2-snes-front-clay.svg",
        "m2-2-snes-front-overlay.svg",
        "m2-2-snes-front-top-side-overlay.svg",
        "m2-2-snes-alpha-comparison.svg",
        "m2-2-snes-m1-poses.svg",
    ]:
        content = (DESIGN / name).read_text()
        require(content.startswith("<svg"), f"invalid SVG {name}")
        require("M2.2" in content, f"review identity {name}")

    require("CC0 1.0 Universal" in (ASSET / "LICENSE-CC0.md").read_text(), "CC0 record")
    provenance = (ASSET / "PROVENANCE.md").read_text()
    require("not imported, copied, or used as a modeling source" in provenance, "v1 provenance boundary")
    require("Physical cartridge calibration is still required" in provenance, "calibration provenance")

    smoke = (ROOT / "frontend/godot-ui/scripts/m2_2_snes_front_smoke_test.gd").read_text()
    require("RETROLIFE_M2_2_FRONT_GODOT_OK" in smoke, "Godot marker")
    require("continuous=true" in smoke, "Godot topology marker")
    require("m2_3=false" in smoke, "Godot M2.3 gate marker")

    workflow = WORKFLOW.read_text()
    require("runs-on: ubuntu-24.04" in workflow, "hosted Linux runner")
    require("runs-on: macos-15" in workflow, "hosted macOS runner")
    require("scripts/verify-m2-2-snes-front.py" in workflow, "source validator in workflow")
    require("m2_2_snes_front_smoke_test.gd" in workflow, "Godot smoke in workflow")
    require("permissions:\n  contents: read" in workflow, "read-only workflow")

    print(
        "RETROLIFE_M2_2_FRONT_OK "
        f"asset={ASSET_ID} envelope=136x88 shell_triangles={shell.triangles} "
        "continuous=true watertight=true runtime=godot uv=true prior_rejected=true "
        "physical_calibrated=false final_approval=false m2_3=false m3=false"
    )

if __name__ == "__main__":
    main()
