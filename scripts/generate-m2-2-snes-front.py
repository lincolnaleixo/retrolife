#!/usr/bin/env python3
"""Generate the public M2.2 v4 CadQuery front-shell package.

The v4 asset is an original Open CASCADE B-rep rebuilt from the committed
public reference contract. External photographs, patent drawings and a public
scan are comparison references only. Their geometry and media are not copied.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import struct
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

import cadquery as cq
import numpy as np
from cadquery import exporters
from PIL import Image, ImageDraw, ImageFont

ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v4"
PRIOR_ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v3"
REJECTED_ASSET_IDS = [
    "retrolife.snes.na-cartridge.m2.2.front.v1",
    "retrolife.snes.na-cartridge.m2.2.front.v2",
    PRIOR_ASSET_ID,
]
REFERENCE_ID = "retrolife.m2.1.snes-ntsc-u.reference.v2"
LICENSE = "CC0-1.0"
SOURCE = "original-cadquery-opencascade-brep-rebuild"
SURFACE_MODEL = "cadquery-opencascade-brep-with-drafted-booleans"
CAD_TOOL = "CadQuery 2.8.0"
CAD_KERNEL = "Open CASCADE 7.9"

STEP_REL = "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_front_shell_v4.step"
STL_REL = "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_front_shell_v4.stl"
OBJ_REL = "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_front_shell_v4.obj"
LABEL_OBJ_REL = "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_label_surface_v4.obj"
SHELL_MATERIAL_REL = "frontend/godot-ui/assets/snes/m2_2/materials/snes_m2_2_v4_shell_clay.tres"
LABEL_MATERIAL_REL = "frontend/godot-ui/assets/snes/m2_2/materials/snes_m2_2_v4_label_placeholder.tres"
SCENE_REL = "frontend/godot-ui/scenes/SnesNaCartridgeFrontM2_2.tscn"
SMOKE_REL = "frontend/godot-ui/scripts/m2_2_snes_front_smoke_test.gd"
DOC_REL = "frontend/design/m2-2-snes-front-shell.md"
COMPARISON_REL = "frontend/design/m2-2-snes-v4-physical-comparison.md"
MANIFEST_REL = "frontend/design/m2-2-snes-front-manifest.json"
PROVENANCE_REL = "frontend/godot-ui/assets/snes/m2_2/PROVENANCE.md"
ASSET_README_REL = "frontend/godot-ui/assets/snes/m2_2/README.md"
ASSET_LICENSE_REL = "frontend/godot-ui/assets/snes/m2_2/LICENSE-CC0.md"

RENDER_RELATIVE = {
    "front": "frontend/design/mobile/m2-2-snes-v4-front.png",
    "threeQuarter": "frontend/design/mobile/m2-2-snes-v4-three-quarter.png",
    "side": "frontend/design/mobile/m2-2-snes-v4-side.png",
    "top": "frontend/design/mobile/m2-2-snes-v4-top.png",
    "dimensions": "frontend/design/mobile/m2-2-snes-v4-dimensions.png",
    "mobileReview": "frontend/design/mobile/m2-2-snes-v4-mobile-review.png",
}

GENERATED_RELATIVE = [
    STEP_REL,
    STL_REL,
    OBJ_REL,
    LABEL_OBJ_REL,
    SHELL_MATERIAL_REL,
    LABEL_MATERIAL_REL,
    SCENE_REL,
    SMOKE_REL,
    DOC_REL,
    COMPARISON_REL,
    MANIFEST_REL,
    PROVENANCE_REL,
    ASSET_README_REL,
    ASSET_LICENSE_REL,
    *RENDER_RELATIVE.values(),
]

STALE_RELATIVE = [
    "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_front_shell_v3.obj",
    "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_label_surface_v3.obj",
    "frontend/godot-ui/assets/snes/m2_2/materials/snes_m2_2_v3_shell_clay.tres",
    "frontend/godot-ui/assets/snes/m2_2/materials/snes_m2_2_v3_label_placeholder.tres",
    "frontend/design/mobile/m2-2-snes-v3-front.png",
    "frontend/design/mobile/m2-2-snes-v3-three-quarter.png",
    "frontend/design/mobile/m2-2-snes-v3-side.png",
    "frontend/design/mobile/m2-2-snes-v3-top.png",
    "frontend/design/mobile/m2-2-snes-v3-mobile-review.png",
    "frontend/design/m2-2-snes-v3-physical-comparison.md",
    "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_front_shell_v3.obj.import",
    "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_label_surface_v3.obj.import",
    "frontend/design/m2-2-snes-front-clay.svg",
    "frontend/design/m2-2-snes-front-overlay.svg",
    "frontend/design/m2-2-snes-front-top-side-overlay.svg",
    "frontend/design/m2-2-snes-alpha-comparison.svg",
    "frontend/design/m2-2-snes-m1-poses.svg",
]


@dataclass(frozen=True)
class Dimensions:
    width: float
    height: float
    depth: float
    front_half_depth: float
    central_body_width: float
    central_top_width: float
    wing_top: float
    label_width: float
    label_height: float
    label_bottom: float
    label_radius: float
    label_depth: float
    channel_width: float
    channel_height: float
    channel_center_y: float
    channel_depth: float
    screw_x: float
    screw_y: float
    screw_well_diameter: float
    band_divisions_y: tuple[float, ...]


@dataclass(frozen=True)
class MeshData:
    vertices_mm: np.ndarray
    faces: np.ndarray


@dataclass(frozen=True)
class BuildResult:
    solid: cq.Solid
    mesh: MeshData
    dimensions: Dimensions
    volume_mm3: float
    face_count: int
    edge_count: int


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def value(entry: object) -> float:
    if isinstance(entry, dict):
        return float(entry["value"])
    return float(entry)


def load_dimensions(root: Path) -> Dimensions:
    path = root / "frontend/design/m2-snes-reference-manifest.json"
    reference = json.loads(path.read_text(encoding="utf-8"))
    require(reference.get("referenceId") == REFERENCE_ID, "M2.1 reference ID is not v2")
    envelope = reference["envelope"]
    landmarks = reference["provisionalLandmarks"]
    label = landmarks["labelRecess"]
    channel = landmarks["lowerFrontGripChannel"]
    screws = landmarks["securityScrewCenters"]
    bands = landmarks["sideMouldedBands"]
    return Dimensions(
        width=value(envelope["width"]),
        height=value(envelope["height"]),
        depth=value(envelope["depth"]),
        front_half_depth=value(landmarks["frontShellDepth"]),
        central_body_width=value(landmarks["centralUpperBodyWidth"]),
        central_top_width=value(landmarks["centralTopWidth"]),
        wing_top=value(landmarks["sideWingTopY"]),
        label_width=value(label["width"]),
        label_height=value(label["height"]),
        label_bottom=value(label["bottomY"]),
        label_radius=value(label["cornerRadius"]),
        label_depth=value(label["depth"]),
        channel_width=value(channel["width"]),
        channel_height=value(channel["height"]),
        channel_center_y=value(channel["centerY"]),
        channel_depth=value(channel["depth"]),
        screw_x=value(screws["xAbsolute"]),
        screw_y=value(screws["y"]),
        screw_well_diameter=value(screws["wellDiameter"]),
        band_divisions_y=tuple(float(item) for item in bands["divisionCenterY"]),
    )


def arc_points(
    center_x: float,
    center_y: float,
    radius: float,
    start_degrees: float,
    end_degrees: float,
    segments: int,
    include_start: bool = True,
) -> list[tuple[float, float]]:
    result: list[tuple[float, float]] = []
    for index in range(segments + 1):
        if index == 0 and not include_start:
            continue
        angle = math.radians(start_degrees + (end_degrees - start_degrees) * index / segments)
        result.append((center_x + radius * math.cos(angle), center_y + radius * math.sin(angle)))
    return result


def bezier_points(
    point0: tuple[float, float],
    point1: tuple[float, float],
    point2: tuple[float, float],
    point3: tuple[float, float],
    segments: int,
    include_start: bool = True,
) -> list[tuple[float, float]]:
    result: list[tuple[float, float]] = []
    for index in range(segments + 1):
        if index == 0 and not include_start:
            continue
        t = index / segments
        u = 1.0 - t
        result.append(
            (
                u**3 * point0[0]
                + 3 * u * u * t * point1[0]
                + 3 * u * t * t * point2[0]
                + t**3 * point3[0],
                u**3 * point0[1]
                + 3 * u * u * t * point1[1]
                + 3 * u * t * t * point2[1]
                + t**3 * point3[1],
            )
        )
    return result


def clean_points(points: Iterable[tuple[float, float]]) -> list[tuple[float, float]]:
    result: list[tuple[float, float]] = []
    for point in points:
        if not result or math.hypot(point[0] - result[-1][0], point[1] - result[-1][1]) > 1e-7:
            result.append(point)
    if len(result) > 1 and math.hypot(result[0][0] - result[-1][0], result[0][1] - result[-1][1]) < 1e-7:
        result.pop()
    return result


def outer_profile(
    dimensions: Dimensions,
    outer_half: float,
    wing_top: float,
    central_top_half: float,
    central_top: float,
    bottom_y: float,
) -> list[tuple[float, float]]:
    bottom_radius = 3.4
    outer_top_radius = 2.8
    side_top = wing_top - outer_top_radius
    shoulder_x = dimensions.central_body_width * 0.5
    points: list[tuple[float, float]] = [(-outer_half + bottom_radius, bottom_y)]
    points.extend(
        arc_points(
            -outer_half + bottom_radius,
            bottom_y + bottom_radius,
            bottom_radius,
            -90,
            -180,
            8,
            False,
        )
    )
    points.append((-outer_half, side_top))
    points.extend(
        arc_points(
            -outer_half + outer_top_radius,
            side_top,
            outer_top_radius,
            180,
            90,
            8,
            False,
        )
    )
    points.append((-shoulder_x - 2.0, wing_top))
    points.extend(
        bezier_points(
            (-shoulder_x - 2.0, wing_top),
            (-shoulder_x - 0.6, wing_top + 0.1),
            (-central_top_half - 1.4, central_top - 1.8),
            (-central_top_half, central_top),
            10,
            False,
        )
    )
    points.append((central_top_half, central_top))
    points.extend(
        bezier_points(
            (central_top_half, central_top),
            (central_top_half + 1.4, central_top - 1.8),
            (shoulder_x + 0.6, wing_top + 0.1),
            (shoulder_x + 2.0, wing_top),
            10,
            False,
        )
    )
    points.append((outer_half - outer_top_radius, wing_top))
    points.extend(
        arc_points(
            outer_half - outer_top_radius,
            side_top,
            outer_top_radius,
            90,
            0,
            8,
            False,
        )
    )
    points.append((outer_half, bottom_y + bottom_radius))
    points.extend(
        arc_points(
            outer_half - bottom_radius,
            bottom_y + bottom_radius,
            bottom_radius,
            0,
            -90,
            8,
            False,
        )
    )
    return clean_points(points)


def central_profile(
    dimensions: Dimensions,
    width: float,
    wing_top: float,
    central_top_width: float,
    central_top: float,
    bottom_y: float,
) -> list[tuple[float, float]]:
    half_width = width * 0.5
    top_half_width = central_top_width * 0.5
    bottom_radius = 1.6
    points: list[tuple[float, float]] = [(-half_width + bottom_radius, bottom_y)]
    points.extend(
        arc_points(
            -half_width + bottom_radius,
            bottom_y + bottom_radius,
            bottom_radius,
            -90,
            -180,
            6,
            False,
        )
    )
    points.append((-half_width, wing_top - 1.2))
    points.extend(
        bezier_points(
            (-half_width, wing_top - 1.2),
            (-half_width, wing_top),
            (-top_half_width - 1.0, central_top - 1.3),
            (-top_half_width, central_top),
            10,
            False,
        )
    )
    points.append((top_half_width, central_top))
    points.extend(
        bezier_points(
            (top_half_width, central_top),
            (top_half_width + 1.0, central_top - 1.3),
            (half_width, wing_top),
            (half_width, wing_top - 1.2),
            10,
            False,
        )
    )
    points.append((half_width, bottom_y + bottom_radius))
    points.extend(
        arc_points(
            half_width - bottom_radius,
            bottom_y + bottom_radius,
            bottom_radius,
            0,
            -90,
            6,
            False,
        )
    )
    return clean_points(points)


def rounded_rectangle_points(
    width: float,
    height: float,
    radius: float,
    center_x: float,
    center_y: float,
    segments: int = 10,
) -> list[tuple[float, float]]:
    radius = min(radius, width * 0.5 - 1e-4, height * 0.5 - 1e-4)
    points: list[tuple[float, float]] = [
        (center_x - width * 0.5 + radius, center_y - height * 0.5),
        (center_x + width * 0.5 - radius, center_y - height * 0.5),
    ]
    points.extend(
        arc_points(
            center_x + width * 0.5 - radius,
            center_y - height * 0.5 + radius,
            radius,
            -90,
            0,
            segments,
            False,
        )
    )
    points.append((center_x + width * 0.5, center_y + height * 0.5 - radius))
    points.extend(
        arc_points(
            center_x + width * 0.5 - radius,
            center_y + height * 0.5 - radius,
            radius,
            0,
            90,
            segments,
            False,
        )
    )
    points.append((center_x - width * 0.5 + radius, center_y + height * 0.5))
    points.extend(
        arc_points(
            center_x - width * 0.5 + radius,
            center_y + height * 0.5 - radius,
            radius,
            90,
            180,
            segments,
            False,
        )
    )
    points.append((center_x - width * 0.5, center_y - height * 0.5 + radius))
    points.extend(
        arc_points(
            center_x - width * 0.5 + radius,
            center_y - height * 0.5 + radius,
            radius,
            180,
            270,
            segments,
            False,
        )
    )
    return clean_points(points)


def wire(points: Sequence[tuple[float, float]], z: float) -> cq.Wire:
    return cq.Workplane("XY").workplane(offset=z).polyline(list(points)).close().val()


def loft_solid(profiles: Sequence[tuple[float, Sequence[tuple[float, float]]]]) -> cq.Solid:
    return cq.Solid.makeLoft([wire(points, z) for z, points in profiles], False)


def tapered_pocket(
    top_width: float,
    top_height: float,
    top_radius: float,
    bottom_width: float,
    bottom_height: float,
    bottom_radius: float,
    center_x: float,
    center_y: float,
    z_bottom: float,
    z_top: float,
) -> cq.Solid:
    return loft_solid(
        [
            (
                z_bottom,
                rounded_rectangle_points(
                    bottom_width,
                    bottom_height,
                    bottom_radius,
                    center_x,
                    center_y,
                ),
            ),
            (
                z_top,
                rounded_rectangle_points(
                    top_width,
                    top_height,
                    top_radius,
                    center_x,
                    center_y,
                ),
            ),
        ]
    )



def weld_mesh(vertices: np.ndarray, faces: np.ndarray, decimals: int = 6) -> MeshData:
    mapping: dict[tuple[float, float, float], int] = {}
    unique: list[tuple[float, float, float]] = []
    remap = np.empty(len(vertices), dtype=np.int64)
    for index, vertex in enumerate(vertices):
        key = tuple(round(float(value), decimals) for value in vertex)
        target = mapping.get(key)
        if target is None:
            target = len(unique)
            mapping[key] = target
            unique.append(key)
        remap[index] = target
    clean_faces: list[tuple[int, int, int]] = []
    seen: set[tuple[int, int, int]] = set()
    for face in faces:
        mapped = tuple(int(remap[int(index)]) for index in face)
        if len(set(mapped)) != 3:
            continue
        duplicate_key = tuple(sorted(mapped))
        if duplicate_key in seen:
            continue
        seen.add(duplicate_key)
        clean_faces.append(mapped)
    return MeshData(
        vertices_mm=np.asarray(unique, dtype=np.float64),
        faces=np.asarray(clean_faces, dtype=np.int64),
    )

def build_cad(dimensions: Dimensions) -> BuildResult:
    half_width = dimensions.width * 0.5
    central_top_half = dimensions.central_top_width * 0.5
    outer_sections = [
        (
            0.0,
            outer_profile(
                dimensions,
                half_width - 1.7,
                dimensions.wing_top - 0.8,
                central_top_half - 1.0,
                dimensions.height - 0.9,
                0.6,
            ),
        ),
        (
            0.75,
            outer_profile(
                dimensions,
                half_width - 0.9,
                dimensions.wing_top - 0.3,
                central_top_half - 0.5,
                dimensions.height - 0.3,
                0.2,
            ),
        ),
        (
            2.2,
            outer_profile(
                dimensions,
                half_width - 0.2,
                dimensions.wing_top,
                central_top_half,
                dimensions.height,
                0.0,
            ),
        ),
        (
            7.6,
            outer_profile(
                dimensions,
                half_width,
                dimensions.wing_top,
                central_top_half,
                dimensions.height,
                0.0,
            ),
        ),
        (
            9.0,
            outer_profile(
                dimensions,
                half_width - 0.4,
                dimensions.wing_top - 0.2,
                central_top_half - 0.3,
                dimensions.height - 0.2,
                0.18,
            ),
        ),
        (
            dimensions.front_half_depth - 0.85,
            outer_profile(
                dimensions,
                half_width - 1.0,
                dimensions.wing_top - 0.5,
                central_top_half - 0.7,
                dimensions.height - 0.55,
                0.45,
            ),
        ),
    ]
    solid = loft_solid(outer_sections)

    central_sections = [
        (
            dimensions.front_half_depth - 1.4,
            central_profile(
                dimensions,
                dimensions.central_body_width,
                dimensions.wing_top - 0.1,
                dimensions.central_top_width,
                dimensions.height - 0.15,
                0.45,
            ),
        ),
        (
            dimensions.front_half_depth - 0.65,
            central_profile(
                dimensions,
                dimensions.central_body_width - 0.3,
                dimensions.wing_top - 0.2,
                dimensions.central_top_width - 0.3,
                dimensions.height - 0.3,
                0.55,
            ),
        ),
        (
            dimensions.front_half_depth,
            central_profile(
                dimensions,
                dimensions.central_body_width - 0.9,
                dimensions.wing_top - 0.5,
                dimensions.central_top_width - 0.9,
                dimensions.height - 0.65,
                0.75,
            ),
        ),
    ]
    solid = solid.fuse(loft_solid(central_sections)).clean()

    label_center_y = dimensions.label_bottom + dimensions.label_height * 0.5
    solid = solid.cut(
        tapered_pocket(
            dimensions.label_width + 0.8,
            dimensions.label_height + 0.8,
            dimensions.label_radius + 0.45,
            dimensions.label_width,
            dimensions.label_height,
            dimensions.label_radius,
            0.0,
            label_center_y,
            dimensions.front_half_depth - dimensions.label_depth,
            dimensions.front_half_depth + 0.7,
        )
    )

    channel_radius = dimensions.channel_height * 0.5
    channel_floor_z = dimensions.front_half_depth - dimensions.channel_depth
    solid = solid.cut(
        tapered_pocket(
            dimensions.channel_width + 0.8,
            dimensions.channel_height + 0.8,
            channel_radius + 0.2,
            dimensions.channel_width,
            dimensions.channel_height,
            channel_radius,
            0.0,
            dimensions.channel_center_y,
            channel_floor_z,
            dimensions.front_half_depth + 0.7,
        )
    )

    center_key_height = 10.8
    center_key_center_y = dimensions.channel_center_y - dimensions.channel_height * 0.5 - center_key_height * 0.5 + 0.15
    solid = solid.cut(
        tapered_pocket(
            1.05,
            center_key_height + 0.45,
            0.45,
            0.72,
            center_key_height,
            0.32,
            0.0,
            center_key_center_y,
            dimensions.front_half_depth - 0.34,
            dimensions.front_half_depth + 0.7,
        )
    )

    groove_center_x = dimensions.width * 0.5 - 10.0
    for center_y in dimensions.band_divisions_y:
        for center_x in (-groove_center_x, groove_center_x):
            solid = solid.cut(
                tapered_pocket(
                    21.0,
                    1.5,
                    0.7,
                    20.2,
                    0.95,
                    0.44,
                    center_x,
                    center_y,
                    dimensions.front_half_depth - 1.48,
                    dimensions.front_half_depth + 0.35,
                )
            )

    through_radius = 1.45
    countersink_radius = dimensions.screw_well_diameter * 0.5
    for center_x in (-dimensions.screw_x, dimensions.screw_x):
        countersink = cq.Solid.makeCone(
            through_radius,
            countersink_radius,
            1.45,
            cq.Vector(center_x, dimensions.screw_y, dimensions.front_half_depth - 1.75),
            cq.Vector(0, 0, 1),
        )
        through = cq.Solid.makeCylinder(
            through_radius,
            dimensions.front_half_depth + 0.5,
            cq.Vector(center_x, dimensions.screw_y, 0),
            cq.Vector(0, 0, 1),
        )
        solid = solid.cut(countersink).cut(through)

    inner_sections = [
        (
            0.0,
            outer_profile(
                dimensions,
                half_width - 4.2,
                dimensions.wing_top - 2.8,
                central_top_half - 3.0,
                dimensions.height - 3.3,
                2.3,
            ),
        ),
        (
            dimensions.front_half_depth - 2.6,
            outer_profile(
                dimensions,
                half_width - 2.9,
                dimensions.wing_top - 2.1,
                central_top_half - 2.3,
                dimensions.height - 2.6,
                1.8,
            ),
        ),
    ]
    solid = solid.cut(loft_solid(inner_sections)).clean()
    envelope_clip = (
        cq.Workplane("XY")
        .box(
            dimensions.width,
            dimensions.height,
            dimensions.front_half_depth,
            centered=(True, False, False),
        )
        .val()
    )
    solid = solid.intersect(envelope_clip).clean()
    require(solid.isValid(), "CadQuery produced an invalid B-rep solid")

    vertices, triangles = solid.tessellate(0.05, 0.12)
    vertex_array = np.asarray([[vertex.x, vertex.y, vertex.z] for vertex in vertices], dtype=np.float64)
    # Open CASCADE triangulation can extend a few tenths beyond spline end sections.
    # The Godot review mesh is clipped to the locked public envelope while STEP
    # remains the authoritative B-rep export. Topology and face order are kept.
    vertex_array[:, 0] = np.clip(vertex_array[:, 0], -dimensions.width * 0.5, dimensions.width * 0.5)
    vertex_array[:, 1] = np.clip(vertex_array[:, 1], 0.0, dimensions.height)
    vertex_array[:, 2] = np.clip(vertex_array[:, 2], 0.0, dimensions.front_half_depth)
    face_array = np.asarray(triangles, dtype=np.int64)
    welded = weld_mesh(vertex_array, face_array)
    require(len(welded.vertices_mm) > 1000 and len(welded.faces) > 2000, "CAD tessellation is unexpectedly small")
    return BuildResult(
        solid=solid,
        mesh=welded,
        dimensions=dimensions,
        volume_mm3=float(solid.Volume()),
        face_count=len(solid.Faces()),
        edge_count=len(solid.Edges()),
    )


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def canonicalize_step(path: Path) -> None:
    content = path.read_text(encoding="utf-8")
    content = re.sub(
        r"FILE_NAME\('Open CASCADE Shape Model','[^']*',\('Author'\),\(\s*'Open CASCADE'\),'Open CASCADE STEP processor 7\.9','Open CASCADE 7\.9'\s*,'Unknown'\);",
        "FILE_NAME('RetroLife M2.2 v4 front shell','2000-01-01T00:00:00',('RetroLife public generator'),('RetroLife'),'CadQuery 2.8.0 / Open CASCADE 7.9','Open CASCADE 7.9','CC0-1.0');",
        content,
        flags=re.MULTILINE,
    )
    content = content.replace(
        "PRODUCT('Open CASCADE STEP translator 7.9 1','Open CASCADE STEP translator 7.9 1','',(#8));",
        "PRODUCT('RetroLife M2.2 v4 front shell','RetroLife M2.2 v4 front shell','',(#8));",
    )
    path.write_text(content.replace("\r\n", "\n"), encoding="utf-8", newline="\n")


def triangle_normal(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> np.ndarray:
    normal = np.cross(b - a, c - a)
    length = float(np.linalg.norm(normal))
    if length < 1e-12:
        return np.zeros(3, dtype=np.float64)
    return normal / length


def write_binary_stl(path: Path, mesh: MeshData) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    header = b"RetroLife M2.2 v4 CadQuery front shell CC0-1.0"
    header = header[:80].ljust(80, b" ")
    with path.open("wb") as stream:
        stream.write(header)
        stream.write(struct.pack("<I", len(mesh.faces)))
        for face in mesh.faces:
            a, b, c = (mesh.vertices_mm[int(index)] for index in face)
            normal = triangle_normal(a, b, c)
            values = [*normal, *a, *b, *c]
            stream.write(struct.pack("<12fH", *[float(item) for item in values], 0))


def vertex_normals(mesh: MeshData) -> np.ndarray:
    normals = np.zeros_like(mesh.vertices_mm)
    for face in mesh.faces:
        a, b, c = (mesh.vertices_mm[int(index)] for index in face)
        weighted = np.cross(b - a, c - a)
        for index in face:
            normals[int(index)] += weighted
    lengths = np.linalg.norm(normals, axis=1)
    lengths[lengths < 1e-12] = 1.0
    return normals / lengths[:, None]


def write_obj(path: Path, mesh: MeshData) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    normals = vertex_normals(mesh)
    lines = ["# RetroLife M2.2 v4 CadQuery front shell", "# SPDX-License-Identifier: CC0-1.0", "o front_shell_v4"]
    for vertex in mesh.vertices_mm:
        lines.append(f"v {vertex[0] / 1000.0:.9f} {vertex[1] / 1000.0:.9f} {vertex[2] / 1000.0:.9f}")
    for normal in normals:
        lines.append(f"vn {normal[0]:.9f} {normal[1]:.9f} {normal[2]:.9f}")
    for face in mesh.faces:
        one_based = [int(index) + 1 for index in face]
        lines.append("f " + " ".join(f"{index}//{index}" for index in one_based))
    write_text(path, "\n".join(lines) + "\n")


def label_mesh(dimensions: Dimensions) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    center_y = dimensions.label_bottom + dimensions.label_height * 0.5
    perimeter = rounded_rectangle_points(
        dimensions.label_width,
        dimensions.label_height,
        dimensions.label_radius,
        0.0,
        center_y,
        14,
    )
    z = dimensions.front_half_depth - dimensions.label_depth + 0.018
    vertices = [[0.0, center_y, z], *[[x, y, z] for x, y in perimeter]]
    uvs = [[0.5, 0.5]]
    for x, y in perimeter:
        uvs.append(
            [
                (x + dimensions.label_width * 0.5) / dimensions.label_width,
                (y - dimensions.label_bottom) / dimensions.label_height,
            ]
        )
    faces = []
    for index in range(len(perimeter)):
        faces.append([0, index + 1, ((index + 1) % len(perimeter)) + 1])
    return np.asarray(vertices, dtype=np.float64), np.asarray(faces, dtype=np.int64), np.asarray(uvs, dtype=np.float64)


def write_label_obj(path: Path, dimensions: Dimensions) -> tuple[np.ndarray, np.ndarray]:
    vertices, faces, uvs = label_mesh(dimensions)
    lines = ["# RetroLife M2.2 v4 label surface", "# SPDX-License-Identifier: CC0-1.0", "o label_surface_v4"]
    for vertex in vertices:
        lines.append(f"v {vertex[0] / 1000.0:.9f} {vertex[1] / 1000.0:.9f} {vertex[2] / 1000.0:.9f}")
    for uv in uvs:
        lines.append(f"vt {uv[0]:.9f} {uv[1]:.9f}")
    lines.append("vn 0.000000000 0.000000000 1.000000000")
    for face in faces:
        one_based = [int(index) + 1 for index in face]
        lines.append("f " + " ".join(f"{index}/{index}/1" for index in one_based))
    write_text(path, "\n".join(lines) + "\n")
    return vertices, faces


def vtk_label_polydata(dimensions: Dimensions):
    import vtk

    center_y = dimensions.label_bottom + dimensions.label_height * 0.5
    z = dimensions.front_half_depth - dimensions.label_depth + 0.018
    perimeter = rounded_rectangle_points(
        dimensions.label_width,
        dimensions.label_height,
        dimensions.label_radius,
        0.0,
        center_y,
        20,
    )
    points = vtk.vtkPoints()
    for x, y in perimeter:
        points.InsertNextPoint(x, y, z)
    polygon = vtk.vtkPolygon()
    polygon.GetPointIds().SetNumberOfIds(len(perimeter))
    for index in range(len(perimeter)):
        polygon.GetPointIds().SetId(index, index)
    cells = vtk.vtkCellArray()
    cells.InsertNextCell(polygon)
    data = vtk.vtkPolyData()
    data.SetPoints(points)
    data.SetPolys(cells)
    triangles = vtk.vtkTriangleFilter()
    triangles.SetInputData(data)
    triangles.Update()
    return triangles.GetOutput()


def make_actor(polydata, color: tuple[float, float, float], ambient: float, diffuse: float, specular: float):
    import vtk

    mapper = vtk.vtkPolyDataMapper()
    mapper.SetInputData(polydata)
    actor = vtk.vtkActor()
    actor.SetMapper(mapper)
    prop = actor.GetProperty()
    prop.SetColor(*color)
    prop.SetInterpolationToPhong()
    prop.SetAmbient(ambient)
    prop.SetDiffuse(diffuse)
    prop.SetSpecular(specular)
    prop.SetSpecularPower(30.0)
    return actor


def render_view(
    path: Path,
    stl_path: Path,
    dimensions: Dimensions,
    camera_position: tuple[float, float, float],
    focal_point: tuple[float, float, float],
    view_up: tuple[float, float, float],
    parallel_scale: float | None,
    size: tuple[int, int],
) -> None:
    import vtk

    reader = vtk.vtkSTLReader()
    reader.SetFileName(str(stl_path))
    reader.Update()

    renderer = vtk.vtkRenderer()
    renderer.SetBackground(0.035, 0.045, 0.065)
    shell_actor = make_actor(reader.GetOutput(), (0.44, 0.43, 0.49), 0.34, 0.63, 0.20)
    label_actor = make_actor(vtk_label_polydata(dimensions), (0.22, 0.25, 0.31), 0.52, 0.42, 0.08)
    renderer.AddActor(shell_actor)
    renderer.AddActor(label_actor)

    headlight = vtk.vtkLight()
    headlight.SetLightTypeToHeadlight()
    headlight.SetIntensity(0.82)
    renderer.AddLight(headlight)
    for position, intensity in [((-110.0, 155.0, 205.0), 0.72), ((145.0, 82.0, 105.0), 0.30)]:
        light = vtk.vtkLight()
        light.SetLightTypeToSceneLight()
        light.SetPosition(*position)
        light.SetFocalPoint(*focal_point)
        light.SetIntensity(intensity)
        renderer.AddLight(light)

    camera = vtk.vtkCamera()
    camera.SetPosition(*camera_position)
    camera.SetFocalPoint(*focal_point)
    camera.SetViewUp(*view_up)
    if parallel_scale is not None:
        camera.ParallelProjectionOn()
        camera.SetParallelScale(parallel_scale)
    else:
        camera.SetViewAngle(28.0)
    renderer.SetActiveCamera(camera)
    renderer.ResetCameraClippingRange()

    window = vtk.vtkRenderWindow()
    window.SetOffScreenRendering(1)
    window.SetSize(*size)
    window.AddRenderer(renderer)
    window.Render()

    capture = vtk.vtkWindowToImageFilter()
    capture.SetInput(window)
    capture.SetInputBufferTypeToRGB()
    capture.ReadFrontBufferOff()
    capture.Update()
    path.parent.mkdir(parents=True, exist_ok=True)
    writer = vtk.vtkPNGWriter()
    writer.SetFileName(str(path))
    writer.SetInputConnection(capture.GetOutputPort())
    writer.Write()

def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).is_file():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def render_dimensions(path: Path, dimensions: Dimensions) -> None:
    canvas = Image.new("RGB", (1600, 1000), "#0b0f17")
    draw = ImageDraw.Draw(canvas)
    draw.text((64, 42), "RetroLife M2.2 v4 CAD dimensions", font=font(42, True), fill="#f4f6fb")
    draw.text((64, 98), "Provisional visual fit. Physical caliper calibration is still required.", font=font(23), fill="#9aa6b8")
    scale = 8.0
    origin_x = 800
    origin_y = 850
    outline = outer_profile(
        dimensions,
        dimensions.width * 0.5,
        dimensions.wing_top,
        dimensions.central_top_width * 0.5,
        dimensions.height,
        0.0,
    )
    points = [(origin_x + x * scale, origin_y - y * scale) for x, y in outline]
    draw.polygon(points, fill="#4c4b58", outline="#d8dce6")
    label_box = (
        origin_x - dimensions.label_width * scale * 0.5,
        origin_y - (dimensions.label_bottom + dimensions.label_height) * scale,
        origin_x + dimensions.label_width * scale * 0.5,
        origin_y - dimensions.label_bottom * scale,
    )
    draw.rounded_rectangle(label_box, radius=int(dimensions.label_radius * scale), fill="#161a22", outline="#c3c8d3", width=3)
    channel_box = (
        origin_x - dimensions.channel_width * scale * 0.5,
        origin_y - (dimensions.channel_center_y + dimensions.channel_height * 0.5) * scale,
        origin_x + dimensions.channel_width * scale * 0.5,
        origin_y - (dimensions.channel_center_y - dimensions.channel_height * 0.5) * scale,
    )
    draw.rounded_rectangle(channel_box, radius=int(dimensions.channel_height * scale * 0.5), outline="#b4bac7", width=3)
    for x in (-dimensions.screw_x, dimensions.screw_x):
        cx = origin_x + x * scale
        cy = origin_y - dimensions.screw_y * scale
        radius = dimensions.screw_well_diameter * scale * 0.5
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill="#10141b", outline="#c6ccd8", width=2)
    for y in dimensions.band_divisions_y:
        py = origin_y - y * scale
        draw.line((origin_x - dimensions.width * scale * 0.5 + 14, py, origin_x - dimensions.central_body_width * scale * 0.5 - 8, py), fill="#c6ccd8", width=3)
        draw.line((origin_x + dimensions.central_body_width * scale * 0.5 + 8, py, origin_x + dimensions.width * scale * 0.5 - 14, py), fill="#c6ccd8", width=3)

    dimension_color = "#7ce2d4"
    draw.line((origin_x - dimensions.width * scale * 0.5, 930, origin_x + dimensions.width * scale * 0.5, 930), fill=dimension_color, width=2)
    draw.text((origin_x - 74, 938), f"{dimensions.width:.1f} mm", font=font(22, True), fill=dimension_color)
    draw.line((140, origin_y, 140, origin_y - dimensions.height * scale), fill=dimension_color, width=2)
    draw.text((58, 470), f"{dimensions.height:.1f} mm", font=font(22, True), fill=dimension_color)
    draw.text((1110, 230), f"Label: {dimensions.label_width:.1f} x {dimensions.label_height:.1f} mm", font=font(22), fill="#d4d8e2")
    draw.text((1110, 276), f"Grip channel: {dimensions.channel_width:.1f} x {dimensions.channel_height:.1f} mm", font=font(22), fill="#d4d8e2")
    draw.text((1110, 322), "Four divisions create five broad side bands", font=font(22), fill="#d4d8e2")
    draw.text((1110, 368), f"Front shell depth: {dimensions.front_half_depth:.1f} mm", font=font(22), fill="#d4d8e2")
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path, optimize=False, compress_level=9)


def mobile_review(path: Path, render_paths: dict[str, Path]) -> None:
    canvas = Image.new("RGB", (1400, 3300), "#090d15")
    draw = ImageDraw.Draw(canvas)
    draw.text((66, 52), "RetroLife M2.2 v4", font=font(48, True), fill="#f4f6fb")
    draw.text((66, 116), "Open CASCADE B-rep review", font=font(30), fill="#a9b3c4")
    draw.text((66, 166), "Actual CAD render. No SVG geometry and no external mesh data.", font=font(22), fill="#808b9d")
    sections = [
        ("front", "FRONT ORTHOGRAPHIC"),
        ("threeQuarter", "FRONT THREE-QUARTER"),
        ("side", "SIDE PROFILE, FRONT HALF ONLY"),
        ("top", "TOP PROFILE"),
    ]
    top = 230
    for key, title in sections:
        image = Image.open(render_paths[key]).convert("RGB")
        image.thumbnail((1260, 650), Image.Resampling.LANCZOS)
        card = (44, top, 1356, top + 710)
        draw.rounded_rectangle(card, radius=26, fill="#111722", outline="#2a3445", width=3)
        x = 700 - image.width // 2
        y = top + 22 + (630 - image.height) // 2
        canvas.paste(image, (x, y))
        draw.text((70, top + 660), title, font=font(24, True), fill="#e9ecf2")
        top += 740
    draw.text((66, 3210), "Physical calibration and owner approval remain open.", font=font(22), fill="#98a3b4")
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path, optimize=False, compress_level=9)


def write_support_files(root: Path, result: BuildResult, file_hashes: dict[str, str]) -> None:
    dimensions = result.dimensions
    mesh_min = result.mesh.vertices_mm.min(axis=0)
    mesh_max = result.mesh.vertices_mm.max(axis=0)
    mesh_size = mesh_max - mesh_min
    center_of_mass = result.solid.Center()
    material_shell = """[gd_resource type=\"StandardMaterial3D\" format=3]\n\n[resource]\nresource_name = \"M2.2 v4 shell clay\"\nalbedo_color = Color(0.43, 0.42, 0.49, 1)\nmetallic = 0.0\nroughness = 0.78\n"""
    material_label = """[gd_resource type=\"StandardMaterial3D\" format=3]\n\n[resource]\nresource_name = \"M2.2 v4 label placeholder\"\nalbedo_color = Color(0.22, 0.25, 0.31, 1)\nmetallic = 0.0\nroughness = 0.68\n"""
    write_text(root / SHELL_MATERIAL_REL, material_shell)
    write_text(root / LABEL_MATERIAL_REL, material_label)

    scene = f"""[gd_scene load_steps=5 format=3]\n\n[ext_resource type=\"ArrayMesh\" path=\"res://assets/snes/m2_2/snes_ntsc_u_front_shell_v4.obj\" id=\"1_shell\"]\n[ext_resource type=\"ArrayMesh\" path=\"res://assets/snes/m2_2/snes_ntsc_u_label_surface_v4.obj\" id=\"2_label\"]\n[ext_resource type=\"Material\" path=\"res://assets/snes/m2_2/materials/snes_m2_2_v4_shell_clay.tres\" id=\"3_shell_material\"]\n[ext_resource type=\"Material\" path=\"res://assets/snes/m2_2/materials/snes_m2_2_v4_label_placeholder.tres\" id=\"4_label_material\"]\n\n[node name=\"SnesNaCartridgeFrontM2_2\" type=\"Node3D\"]\nmetadata/asset_id = \"{ASSET_ID}\"\nmetadata/prior_asset_id = \"{PRIOR_ASSET_ID}\"\nmetadata/source = \"{SOURCE}\"\nmetadata/license = \"{LICENSE}\"\nmetadata/status = \"provisional-cad-brep-rebuild\"\nmetadata/surface_model = \"{SURFACE_MODEL}\"\nmetadata/cad_tool = \"{CAD_TOOL}\"\nmetadata/cad_kernel = \"{CAD_KERNEL}\"\nmetadata/step_exported = true\nmetadata/height_field_only = false\nmetadata/multi_section_loft_only = false\nmetadata/console_visible = false\nmetadata/physical_calibration_complete = false\nmetadata/external_geometry_copied = false\nmetadata/external_media_embedded = false\nmetadata/prior_geometry_accepted = false\nmetadata/may_approve_final_geometry = false\nmetadata/may_start_m2_3_blockout = false\nmetadata/may_start_m3 = false\n\n[node name=\"VisualRoot\" type=\"Node3D\" parent=\".\"]\n[node name=\"CadShell\" type=\"MeshInstance3D\" parent=\"VisualRoot\"]\nmesh = ExtResource(\"1_shell\")\nmaterial_override = ExtResource(\"3_shell_material\")\nmetadata/surface_topology = \"single-connected-watertight-cad-shell\"\nmetadata/surface_model = \"{SURFACE_MODEL}\"\nmetadata/triangle_count = {len(result.mesh.faces)}\n[node name=\"LabelSurface\" type=\"MeshInstance3D\" parent=\"VisualRoot\"]\nmesh = ExtResource(\"2_label\")\nmaterial_override = ExtResource(\"4_label_material\")\nmetadata/m3_texture_slot = \"snes-front-label\"\n[node name=\"DockPivot\" type=\"Marker3D\" parent=\".\"]\nposition = Vector3(0, 0, 0)\n[node name=\"CenterOfMass\" type=\"Marker3D\" parent=\".\"]\nposition = Vector3({center_of_mass.x / 1000.0:.6f}, {center_of_mass.y / 1000.0:.6f}, {center_of_mass.z / 1000.0:.6f})\n[node name=\"LabelAnchor\" type=\"Marker3D\" parent=\".\"]\nposition = Vector3(0, {(dimensions.label_bottom + dimensions.label_height * 0.5) / 1000.0:.6f}, {(dimensions.front_half_depth - dimensions.label_depth + 0.018) / 1000.0:.6f})\n[node name=\"ConnectorAnchor\" type=\"Marker3D\" parent=\".\"]\nposition = Vector3(0, 0, 0)\n[node name=\"BrowseFocusedAnchor\" type=\"Marker3D\" parent=\".\"]\nrotation_degrees = Vector3(-5, -9, 0)\n[node name=\"DockApproachAnchor\" type=\"Marker3D\" parent=\".\"]\nrotation_degrees = Vector3(-2, -2, 0)\n"""
    write_text(root / SCENE_REL, scene)

    smoke = f"""extends SceneTree\n\nconst SCENE := preload(\"res://scenes/SnesNaCartridgeFrontM2_2.tscn\")\nconst EXPECTED_ASSET := \"{ASSET_ID}\"\n\nfunc _initialize() -> void:\n    var instance := SCENE.instantiate()\n    root.add_child(instance)\n    await process_frame\n    var failures: Array[String] = []\n    _require(instance.get_meta(\"asset_id\", \"\") == EXPECTED_ASSET, \"asset id\", failures)\n    _require(instance.get_meta(\"source\", \"\") == \"{SOURCE}\", \"source\", failures)\n    _require(instance.get_meta(\"step_exported\", false), \"STEP export\", failures)\n    _require(not instance.get_meta(\"height_field_only\", true), \"height field rejected\", failures)\n    _require(not instance.get_meta(\"multi_section_loft_only\", true), \"loft-only rejected\", failures)\n    _require(not instance.get_meta(\"external_geometry_copied\", true), \"external geometry boundary\", failures)\n    _require(not instance.get_meta(\"external_media_embedded\", true), \"external media boundary\", failures)\n    _require(not instance.get_meta(\"physical_calibration_complete\", true), \"calibration honesty\", failures)\n    _require(not instance.get_meta(\"may_approve_final_geometry\", true), \"approval gate\", failures)\n    _require(not instance.get_meta(\"may_start_m2_3_blockout\", true), \"M2.3 gate\", failures)\n    _require(not instance.get_meta(\"may_start_m3\", true), \"M3 gate\", failures)\n    var shell := instance.get_node_or_null(\"VisualRoot/CadShell\") as MeshInstance3D\n    var label := instance.get_node_or_null(\"VisualRoot/LabelSurface\") as MeshInstance3D\n    _require(shell != null and shell.mesh != null, \"CAD shell mesh\", failures)\n    _require(label != null and label.mesh != null, \"label mesh\", failures)\n    for marker_name in [\"DockPivot\", \"CenterOfMass\", \"LabelAnchor\", \"ConnectorAnchor\", \"BrowseFocusedAnchor\", \"DockApproachAnchor\"]:\n        _require(instance.get_node_or_null(marker_name) != null, marker_name, failures)\n    if failures.is_empty():\n        print(\"RETROLIFE_M2_2_FRONT_GODOT_OK asset=v4 cad=opencascade step=true\")\n        quit(0)\n        return\n    for failure in failures:\n        push_error(\"RETROLIFE_M2_2_FRONT_GODOT_FAILED: \" + failure)\n    quit(1)\n\nfunc _require(condition: bool, label: String, failures: Array[String]) -> void:\n    if not condition:\n        failures.append(label)\n"""
    write_text(root / SMOKE_REL, smoke)

    documentation = f"""# M2.2 v4 provisional NTSC-U SNES front shell\n\n## Decision\n\nThe v1 plate stack, v2 height field and v3 loft-only presentation are rejected. The v4 package is rebuilt as a real CadQuery/Open CASCADE boundary-representation solid with drafted boolean features. SVG is no longer the primary geometry or review medium.\n\nThe geometry remains provisional. It does not claim physical caliper calibration or final owner approval.\n\n## Generated contract\n\n- Asset ID: `{ASSET_ID}`\n- Prior asset ID: `{PRIOR_ASSET_ID}`\n- License: `{LICENSE}`\n- CAD source: `{SOURCE}`\n- CAD tool: `{CAD_TOOL}`\n- Kernel: `{CAD_KERNEL}`\n- Surface model: `{SURFACE_MODEL}`\n- Envelope: `{dimensions.width:.1f} x {dimensions.height:.1f} x {dimensions.depth:.1f} mm`\n- Front-shell depth: `{dimensions.front_half_depth:.1f} mm`\n- B-rep volume: `{result.volume_mm3:.1f} mm3`\n- B-rep faces: `{result.face_count}`\n- B-rep edges: `{result.edge_count}`\n- Tessellated triangles: `{len(result.mesh.faces)}`\n- Primary engineering artifact: `snes_ntsc_u_front_shell_v4.step`\n- Godot artifact: `snes_ntsc_u_front_shell_v4.obj`\n- Review artifacts: deterministic PNG renders from the tessellated CAD solid\n- Label surface: separate rounded mesh with stable `0..1` UVs\n- Root pivot: bottom connector center\n- Console, branding, legal text, commercial artwork, ROMs and external mesh data: excluded\n\n## Molded features\n\n- A real side-wall roll is formed by the B-rep section stack.\n- The front body is a fused solid, not a stack of visible feature plates.\n- Label recess and grip channel are drafted boolean pockets.\n- Four recessed side divisions create five broad molded bands per wing.\n- Screw wells use conical countersinks and through openings.\n- The back is opened by an internal cavity cut, so the artifact is a front-shell body rather than a solid billet.\n\n## Physical comparison boundary\n\nThe comparison record links authentic cartridge photography, the cartridge bottom, the USD343833S design patent and a public physical scan. No vertices, textures or photographs from those references are embedded in the CC0 asset.\n\n## Remaining gates\n\n- Measure one authentic early NTSC-U/C `SNS-006` cartridge with digital calipers.\n- Reconcile all provisional B and C dimensions in M2.1.\n- Compare the v4 PNG sheet and STEP file against the physical specimen.\n- Obtain explicit owner visual approval.\n- Keep M2.3 and M3 blocked until those gates close.\n"""
    write_text(root / DOC_REL, documentation)

    comparison = """# M2.2 v4 physical comparison record\n\nThe v4 CAD source was challenged against the following public external references. They are used for visual comparison only.\n\n- Authentic NTSC-U/C Super Mario World cartridge photography: https://www.ebay.com/itm/155342209898\n- Wikimedia Commons public-domain SNES and Super Famicom cartridge photography by Evan-Amos: https://commons.wikimedia.org/wiki/File:SNES-SFAM-Cartridges.jpg\n- North American cartridge bottom photograph: https://commons.wikimedia.org/wiki/File:North_American_SNES_cartridge_bottom.jpg\n- Nintendo USD343833S design patent: https://patents.google.com/patent/USD343833S/en\n- Laser Design physical scan listing: https://sketchfab.com/3d-models/super-mario-world-game-cartridge-a102d3e7fe5c4770912a56e69b04898a\n\nNo vertices, texture pixels, label artwork or photograph pixels are copied into the generated asset. The visual review changed only original RetroLife CAD parameters and boolean features.\n\nThe four active PNG views are direct renders of the committed v4 CAD tessellation. They are the primary mobile review medium.\n"""
    write_text(root / COMPARISON_REL, comparison)

    provenance = f"""# Provenance\n\nAsset `{ASSET_ID}` is generated by `scripts/generate-m2-2-snes-front.py` from the public M2.1 dimensional contract.\n\nThe source builds a CadQuery/Open CASCADE B-rep and exports canonical STEP, deterministic STL and OBJ files. The mobile PNGs are rendered from the generated tessellation.\n\nExternal references are comparison-only. No third-party vertices, textures, game artwork, photographs, ROMs or console geometry are embedded.\n\nPhysical caliper calibration and final owner approval remain incomplete.\n"""
    write_text(root / PROVENANCE_REL, provenance)

    asset_readme = f"""# RetroLife M2.2 v4 front shell\n\nThis directory contains the original procedural `{ASSET_ID}` package.\n\n- `snes_ntsc_u_front_shell_v4.step`: canonical CAD B-rep export\n- `snes_ntsc_u_front_shell_v4.stl`: deterministic tessellation in millimetres\n- `snes_ntsc_u_front_shell_v4.obj`: Godot mesh in metres\n- `snes_ntsc_u_label_surface_v4.obj`: separate label surface with stable UVs\n- `materials/`: neutral review materials\n\nThe geometry is provisional and requires physical calibration.\n"""
    write_text(root / ASSET_README_REL, asset_readme)
    write_text(
        root / ASSET_LICENSE_REL,
        "# CC0 notice\n\nThe original procedural geometry and generated review assets in this M2.2 v4 package are dedicated to the public domain under CC0 1.0.\n",
    )

    manifest = {
        "schemaVersion": 4,
        "assetId": ASSET_ID,
        "priorAssetId": PRIOR_ASSET_ID,
        "rejectedAssetIds": REJECTED_ASSET_IDS,
        "referenceId": REFERENCE_ID,
        "status": "provisional-cad-brep-rebuild",
        "systemId": "snes",
        "region": "NTSC-U/C",
        "shellPart": "front",
        "license": LICENSE,
        "source": SOURCE,
        "surfaceModel": SURFACE_MODEL,
        "surfaceTopology": "single-connected-watertight-cad-shell",
        "cadTool": CAD_TOOL,
        "cadKernel": CAD_KERNEL,
        "stepExported": True,
        "heightFieldOnly": False,
        "multiSectionLoftOnly": False,
        "physicalCalibrationComplete": False,
        "mayApproveFinalGeometry": False,
        "mayStartM2_3Blockout": False,
        "mayStartM3": False,
        "consoleVisible": False,
        "externalGeometryCopied": False,
        "externalMediaEmbedded": False,
        "physicalVisualComparisonRecorded": True,
        "physicalEnvelopeMm": [dimensions.width, dimensions.height, dimensions.depth],
        "frontShellDepthMm": dimensions.front_half_depth,
        "actualCadBoundsMm": [round(float(mesh_size[0]), 6), round(float(mesh_size[1]), 6), round(float(mesh_size[2]), 6)],
        "actualCadExtentsMm": [[round(float(mesh_min[index]), 6), round(float(mesh_max[index]), 6)] for index in range(3)],
        "cadVolumeMm3": round(result.volume_mm3, 6),
        "brepFaces": result.face_count,
        "brepEdges": result.edge_count,
        "components": {
            "cadStep": {"path": STEP_REL, "sha256": file_hashes[STEP_REL]},
            "cadStl": {"path": STL_REL, "sha256": file_hashes[STL_REL], "triangles": len(result.mesh.faces), "vertices": len(result.mesh.vertices_mm)},
            "godotMesh": {"path": OBJ_REL, "sha256": file_hashes[OBJ_REL], "triangles": len(result.mesh.faces), "vertices": len(result.mesh.vertices_mm)},
            "labelSurface": {"path": LABEL_OBJ_REL, "sha256": file_hashes[LABEL_OBJ_REL]},
        },
        "labelRecessMm": [dimensions.label_width, dimensions.label_height, dimensions.label_bottom, dimensions.label_depth],
        "lowerGripChannelMm": [dimensions.channel_width, dimensions.channel_height, dimensions.channel_center_y, dimensions.channel_depth],
        "frontBandDivisionCountEach": len(dimensions.band_divisions_y),
        "frontMouldedBandCountEach": len(dimensions.band_divisions_y) + 1,
        "frontBandDivisionCenterYmm": list(dimensions.band_divisions_y),
        "screwWellCentersMm": [[-dimensions.screw_x, dimensions.screw_y], [dimensions.screw_x, dimensions.screw_y]],
        "labelUvBounds": [[0.0, 0.0], [1.0, 1.0]],
        "rootPivot": "bottom connector center",
        "externalVisualReferences": [
            {"kind": "authentic-cartridge-photography", "url": "https://www.ebay.com/itm/155342209898", "geometryCopied": False, "mediaEmbedded": False},
            {"kind": "public-domain-cartridge-photography", "url": "https://commons.wikimedia.org/wiki/File:SNES-SFAM-Cartridges.jpg", "geometryCopied": False, "mediaEmbedded": False},
            {"kind": "bottom-photography", "url": "https://commons.wikimedia.org/wiki/File:North_American_SNES_cartridge_bottom.jpg", "geometryCopied": False, "mediaEmbedded": False},
            {"kind": "design-patent", "url": "https://patents.google.com/patent/USD343833S/en", "geometryCopied": False, "mediaEmbedded": False},
            {"kind": "physical-scan-visual-check", "url": "https://sketchfab.com/3d-models/super-mario-world-game-cartridge-a102d3e7fe5c4770912a56e69b04898a", "geometryCopied": False, "mediaEmbedded": False},
        ],
        "reviewRenders": {key: {"path": relative, "sha256": file_hashes[relative]} for key, relative in RENDER_RELATIVE.items()},
        "generatedFiles": {relative: file_hashes[relative] for relative in sorted(file_hashes)},
    }
    write_text(root / MANIFEST_REL, json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def generate(root: Path, render: bool, copy_renders_from: Path | None = None) -> None:
    dimensions = load_dimensions(root)
    result = build_cad(dimensions)

    step_path = root / STEP_REL
    step_path.parent.mkdir(parents=True, exist_ok=True)
    exporters.export(cq.Workplane(obj=result.solid), str(step_path))
    canonicalize_step(step_path)
    write_binary_stl(root / STL_REL, result.mesh)
    write_obj(root / OBJ_REL, result.mesh)
    write_label_obj(root / LABEL_OBJ_REL, dimensions)

    render_paths = {key: root / relative for key, relative in RENDER_RELATIVE.items()}
    if render:
        size = (1400, 1000)
        focal = (0.0, dimensions.height * 0.5, dimensions.front_half_depth * 0.5)
        render_view(render_paths["front"], root / STL_REL, dimensions, (0.0, dimensions.height * 0.5, 260.0), focal, (0.0, 1.0, 0.0), 55.0, size)
        render_view(render_paths["threeQuarter"], root / STL_REL, dimensions, (172.0, 132.0, 188.0), focal, (0.0, 1.0, 0.0), None, size)
        render_view(render_paths["side"], root / STL_REL, dimensions, (245.0, dimensions.height * 0.5, 4.5), focal, (0.0, 1.0, 0.0), 54.0, size)
        render_view(render_paths["top"], root / STL_REL, dimensions, (0.0, 225.0, 4.5), focal, (0.0, 0.0, -1.0), 78.0, size)
        render_dimensions(render_paths["dimensions"], dimensions)
        mobile_review(render_paths["mobileReview"], render_paths)
    elif copy_renders_from is not None:
        for relative in RENDER_RELATIVE.values():
            source = copy_renders_from / relative
            require(source.is_file(), f"missing committed render {relative}")
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
    else:
        raise RuntimeError("render generation or committed render copy is required")

    preliminary_files = [
        STEP_REL,
        STL_REL,
        OBJ_REL,
        LABEL_OBJ_REL,
        *RENDER_RELATIVE.values(),
    ]
    preliminary_hashes = {relative: sha256(root / relative) for relative in preliminary_files}
    write_support_files(root, result, preliminary_hashes)

    hash_candidates = [relative for relative in GENERATED_RELATIVE if relative != MANIFEST_REL]
    all_hashes = {relative: sha256(root / relative) for relative in hash_candidates}
    write_support_files(root, result, all_hashes)

    for stale in STALE_RELATIVE:
        path = root / stale
        if path.exists():
            path.unlink()

    print(
        "RETROLIFE_M2_2_CAD_GENERATED "
        f"asset={ASSET_ID} cad=opencascade brep_faces={result.face_count} "
        f"triangles={len(result.mesh.faces)} step=true height_field=false loft_only=false"
    )


def compare_generated(actual_root: Path, generated_root: Path) -> None:
    failures: list[str] = []
    for relative in GENERATED_RELATIVE:
        actual = actual_root / relative
        generated = generated_root / relative
        if not actual.is_file():
            failures.append(f"missing {relative}")
            continue
        if not generated.is_file():
            failures.append(f"generator omitted {relative}")
            continue
        if actual.read_bytes() != generated.read_bytes():
            failures.append(f"differs {relative}")
    for stale in STALE_RELATIVE:
        if (actual_root / stale).exists():
            failures.append(f"stale active asset {stale}")
    if failures:
        raise SystemExit("RETROLIFE_M2_2_CAD_GENERATION_CHECK_FAILED: " + "; ".join(failures))
    print("RETROLIFE_M2_2_CAD_GENERATION_CHECK_OK")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--skip-renders", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = args.root.resolve()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="retrolife-m2-2-v4-") as directory:
            generated_root = Path(directory)
            # Copy the public source required by the generator.
            source_reference = root / "frontend/design/m2-snes-reference-manifest.json"
            destination_reference = generated_root / "frontend/design/m2-snes-reference-manifest.json"
            destination_reference.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source_reference, destination_reference)
            generate(generated_root, render=not args.skip_renders, copy_renders_from=root if args.skip_renders else None)
            compare_generated(root, generated_root)
        return
    generate(root, render=not args.skip_renders, copy_renders_from=root if args.skip_renders else None)


if __name__ == "__main__":
    main()
