#!/usr/bin/env python3
"""Deterministic verification for the provisional M2.2 SNES front shell."""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "frontend/design"
ASSET = ROOT / "frontend/godot-ui/assets/snes/m2_2"
SCENE = ROOT / "frontend/godot-ui/scenes/SnesNaCartridgeFrontM2_2.tscn"
WORKFLOW = ROOT / ".github/workflows/m2-2-snes-front.yml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"RETROLIFE_M2_2_FRONT_FAILED: {message}")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_obj(
    path: Path,
) -> tuple[list[tuple[float, float, float]], list[tuple[float, float]], int]:
    vertices: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    triangles = 0
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
            triangles += 1
    require(vertices, f"no vertices in {path.name}")
    require(triangles > 0, f"no triangles in {path.name}")
    return vertices, uvs, triangles


def bounds(
    vertices: list[tuple[float, float, float]],
) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    minimum = tuple(min(vertex[index] for vertex in vertices) for index in range(3))
    maximum = tuple(max(vertex[index] for vertex in vertices) for index in range(3))
    return minimum, maximum


def near(value: float, expected: float, tolerance: float) -> bool:
    return abs(value - expected) <= tolerance


def main() -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/generate-m2-2-snes-front.py"),
            "--root",
            str(ROOT),
            "--check",
        ],
        check=True,
    )

    reference = json.loads((DESIGN / "m2-snes-reference-manifest.json").read_text())
    manifest = json.loads((DESIGN / "m2-2-snes-front-manifest.json").read_text())

    require(manifest["assetId"] == "retrolife.snes.na-cartridge.m2.2.front.v1", "asset id")
    require(manifest["license"] == "CC0-1.0", "license")
    require(manifest["source"] == "original-parametric-clean-rebuild", "source")
    require(manifest["status"] == "provisional-front-shell-blockout", "status")
    require(manifest["referenceId"] == reference["referenceId"], "reference linkage")
    require(manifest["alphaGeometryReused"] is False, "alpha reuse")
    require(manifest["consoleVisible"] is False, "console exclusion")
    require(manifest["physicalCalibrationComplete"] is False, "calibration honesty")
    require(manifest["mayApproveFinalGeometry"] is False, "final approval gate")
    require(manifest["mayStartM2_3Blockout"] is True, "M2.3 blockout gate")
    require(manifest["mayStartM3"] is False, "M3 gate")
    require(manifest["sideGripGrooveCountEach"] == 5, "five wing grooves")
    require(manifest["physicalEnvelopeMm"] == [136.0, 88.0, 20.0], "envelope")
    require(manifest["labelUvBounds"] == [[0.0, 0.0], [1.0, 1.0]], "label UV contract")

    expected_files = {
        "front_shell": ASSET / "snes_ntsc_u_front_shell.obj",
        "front_features": ASSET / "snes_ntsc_u_front_features.obj",
        "front_grooves": ASSET / "snes_ntsc_u_front_grooves.obj",
        "label_surface": ASSET / "snes_ntsc_u_label_surface.obj",
        "screw_wells": ASSET / "snes_ntsc_u_screw_wells.obj",
    }
    triangle_total = 0
    parsed: dict[str, tuple[list[tuple[float, float, float]], list[tuple[float, float]], int]] = {}
    for name, path in expected_files.items():
        require(path.is_file(), f"missing {path}")
        text = path.read_text()
        require("SPDX-License-Identifier: CC0-1.0" in text, f"license marker {path.name}")
        vertices, uvs, triangles = parse_obj(path)
        triangle_total += triangles
        parsed[name] = (vertices, uvs, triangles)
        component = manifest["components"][name]
        require(component["vertices"] == len(vertices), f"vertex manifest {name}")
        require(component["triangles"] == triangles, f"triangle manifest {name}")

    shell_vertices = parsed["front_shell"][0]
    minimum, maximum = bounds(shell_vertices)
    size = tuple(maximum[index] - minimum[index] for index in range(3))
    require(near(size[0], 0.136, 0.0011), f"shell width {size[0]}")
    require(near(size[1], 0.088, 0.0011), f"shell height {size[1]}")
    require(near(size[2], 0.0104, 0.0008), f"front half depth {size[2]}")
    require(near(minimum[1], 0.0, 0.0002), "bottom connector origin")
    require(near(minimum[2], 0.0, 0.0002), "front shell seam origin")

    label_vertices, label_uvs, _ = parsed["label_surface"]
    require(label_uvs, "label UVs")
    min_uv = (min(uv[0] for uv in label_uvs), min(uv[1] for uv in label_uvs))
    max_uv = (max(uv[0] for uv in label_uvs), max(uv[1] for uv in label_uvs))
    require(min_uv[0] <= 0.001 and min_uv[1] <= 0.001, f"UV minimum {min_uv}")
    require(max_uv[0] >= 0.999 and max_uv[1] >= 0.999, f"UV maximum {max_uv}")
    label_min, label_max = bounds(label_vertices)
    label_size = tuple(label_max[index] - label_min[index] for index in range(3))
    require(near(label_size[0], 0.083, 0.0011), f"label width {label_size[0]}")
    require(near(label_size[1], 0.0385, 0.0011), f"label height {label_size[1]}")
    require(2500 <= triangle_total <= 12000, f"triangle budget {triangle_total}")

    generated = manifest.get("generatedFiles", {})
    require(len(generated) == 19, f"generated file count {len(generated)}")
    for relative, expected_hash in generated.items():
        path = ROOT / relative
        require(path.is_file(), f"missing generated file {relative}")
        require(sha256(path) == expected_hash, f"generated hash {relative}")

    scene = SCENE.read_text()
    for node in [
        "FrontShell",
        "FrontFeatures",
        "FrontGrooves",
        "LabelSurface",
        "ScrewWells",
        "DockPivot",
        "CenterOfMass",
        "LabelAnchor",
        "ConnectorAnchor",
        "BrowseFocusedAnchor",
        "DockApproachAnchor",
    ]:
        require(f'name="{node}"' in scene, f"scene node {node}")
    require("retrolife.snes.na-cartridge.m2.v1" not in scene, "alpha asset reference")
    require("snes_na_cartridge.gd" not in scene, "alpha script reference")
    require("metadata/console_visible = false" in scene, "scene console metadata")
    require("metadata/may_start_m3 = false" in scene, "scene M3 gate")
    require("metadata/may_approve_final_geometry = false" in scene, "scene approval gate")

    source = (ROOT / "scripts/generate-m2-2-snes-front.py").read_text()
    require("original-parametric-clean-rebuild" in source, "clean rebuild marker")
    require("CC0-1.0" in source, "source license")
    require("BoxMesh" not in source, "generic BoxMesh")

    docs = (DESIGN / "m2-2-snes-front-shell.md").read_text()
    require("physical calibration" in docs.lower(), "physical calibration documentation")
    require("rejected alpha" in docs.lower(), "alpha rejection documentation")
    require("M3" in docs and "blocked" in docs.lower(), "M3 block documentation")
    require("M2.5" in docs, "runtime integration boundary")

    review_files = {
        "front clay": DESIGN / "m2-2-snes-front-clay.svg",
        "front overlay": DESIGN / "m2-2-snes-front-overlay.svg",
        "top and side overlay": DESIGN / "m2-2-snes-front-top-side-overlay.svg",
        "alpha comparison": DESIGN / "m2-2-snes-alpha-comparison.svg",
        "M1 pose board": DESIGN / "m2-2-snes-m1-poses.svg",
    }
    for name, path in review_files.items():
        require(path.is_file(), f"missing {name}")
        content = path.read_text()
        require(content.startswith("<svg"), f"invalid SVG {name}")
        require("M2.2" in content and "front" in content.lower(), f"review identity {name}")

    require("CC0 1.0 Universal" in (ASSET / "LICENSE-CC0.md").read_text(), "CC0 record")
    provenance = (ASSET / "PROVENANCE.md").read_text()
    require("No third-party mesh" in provenance, "third-party boundary")
    require("Physical cartridge calibration is still required" in provenance, "calibration provenance")

    smoke = (ROOT / "frontend/godot-ui/scripts/m2_2_snes_front_smoke_test.gd").read_text()
    require("RETROLIFE_M2_2_FRONT_GODOT_OK" in smoke, "Godot marker")
    require("physical_calibrated=false" in smoke, "Godot calibration marker")

    workflow = WORKFLOW.read_text()
    require("runs-on: ubuntu-24.04" in workflow, "hosted Linux runner")
    require("runs-on: macos-15" in workflow, "hosted macOS runner")
    require("scripts/verify-m2-2-snes-front.py" in workflow, "source validator in workflow")
    require("m2_2_snes_front_smoke_test.gd" in workflow, "Godot smoke in workflow")
    require("permissions:\n  contents: read" in workflow, "read-only workflow")

    print(
        "RETROLIFE_M2_2_FRONT_OK "
        f"asset={manifest['assetId']} envelope=136x88 "
        f"front_depth_mm={manifest['frontHalfDepthMm']:.1f} triangles={triangle_total} "
        "grooves=5 uv=true alpha_reused=false physical_calibrated=false "
        "final_approval=false m3=false"
    )


if __name__ == "__main__":
    main()
