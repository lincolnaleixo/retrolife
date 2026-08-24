#!/usr/bin/env python3
"""Generate the provisional M2.2 NTSC-U SNES front-shell package.

The geometry is original RetroLife work released under CC0-1.0. It reads the
M2.1 reference manifest and does not import or adapt the rejected alpha mesh.
Final dimensional approval still requires physical cartridge calibration.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import tempfile
from dataclasses import dataclass, field
from pathlib import Path


ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v1"
LICENSE = "CC0-1.0"
SOURCE = "original-parametric-clean-rebuild"


@dataclass
class Mesh:
    vertices: list[tuple[float, float, float]] = field(default_factory=list)
    faces: list[tuple[int, int, int]] = field(default_factory=list)
    uvs: list[tuple[float, float]] = field(default_factory=list)
    face_uvs: list[tuple[int, int, int]] = field(default_factory=list)

    def add(self, other: "Mesh") -> None:
        vertex_offset = len(self.vertices)
        uv_offset = len(self.uvs)
        self.vertices.extend(other.vertices)
        self.faces.extend(
            tuple(index + vertex_offset for index in face) for face in other.faces
        )
        self.uvs.extend(other.uvs)
        self.face_uvs.extend(
            tuple(index + uv_offset for index in face) for face in other.face_uvs
        )

    @property
    def triangles(self) -> int:
        return len(self.faces)


def ensure_ccw(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    area = sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    )
    return points if area > 0 else list(reversed(points))


def rounded_rectangle_points(
    width_mm: float,
    height_mm: float,
    radius_mm: float,
    center_x_mm: float,
    bottom_y_mm: float,
    segments: int = 12,
) -> list[tuple[float, float]]:
    radius_mm = min(radius_mm, width_mm * 0.5, height_mm * 0.5)
    center_y = bottom_y_mm + height_mm * 0.5
    corners = [
        (
            center_x_mm + width_mm * 0.5 - radius_mm,
            center_y + height_mm * 0.5 - radius_mm,
            0.0,
            90.0,
        ),
        (
            center_x_mm - width_mm * 0.5 + radius_mm,
            center_y + height_mm * 0.5 - radius_mm,
            90.0,
            180.0,
        ),
        (
            center_x_mm - width_mm * 0.5 + radius_mm,
            center_y - height_mm * 0.5 + radius_mm,
            180.0,
            270.0,
        ),
        (
            center_x_mm + width_mm * 0.5 - radius_mm,
            center_y - height_mm * 0.5 + radius_mm,
            270.0,
            360.0,
        ),
    ]
    points: list[tuple[float, float]] = []
    for corner_index, (center_x, corner_y, start, end) in enumerate(corners):
        for index in range(segments + 1):
            if corner_index and index == 0:
                continue
            angle = math.radians(start + (end - start) * index / segments)
            points.append(
                (
                    center_x + radius_mm * math.cos(angle),
                    corner_y + radius_mm * math.sin(angle),
                )
            )
    return ensure_ccw(points)


def scale_inset(
    points: list[tuple[float, float]], inset_mm: float
) -> list[tuple[float, float]]:
    center_x = sum(point[0] for point in points) / len(points)
    center_y = sum(point[1] for point in points) / len(points)
    extent_x = max(abs(point[0] - center_x) for point in points)
    extent_y = max(abs(point[1] - center_y) for point in points)
    scale_x = max(0.88, (extent_x - inset_mm) / extent_x)
    scale_y = max(0.88, (extent_y - inset_mm) / extent_y)
    return [
        (
            center_x + (x - center_x) * scale_x,
            center_y + (y - center_y) * scale_y,
        )
        for x, y in points
    ]


def extruded_polygon(
    points_mm: list[tuple[float, float]],
    z_back_mm: float,
    z_front_mm: float,
    bevel_mm: float = 0.45,
) -> Mesh:
    points_mm = ensure_ccw(points_mm)
    inner = scale_inset(points_mm, bevel_mm)
    loops = [
        (inner, z_back_mm),
        (points_mm, z_back_mm + bevel_mm),
        (points_mm, z_front_mm - bevel_mm),
        (inner, z_front_mm),
    ]
    mesh = Mesh()
    count = len(points_mm)
    for loop, z_value in loops:
        mesh.vertices.extend(
            (x / 1000.0, y / 1000.0, z_value / 1000.0) for x, y in loop
        )
    for layer in range(3):
        lower = layer * count
        upper = (layer + 1) * count
        for index in range(count):
            following = (index + 1) % count
            mesh.faces.extend(
                (
                    (lower + index, lower + following, upper + following),
                    (lower + index, upper + following, upper + index),
                )
            )
    center_x = sum(x for x, _ in points_mm) / count
    center_y = sum(y for _, y in points_mm) / count
    back_center = len(mesh.vertices)
    mesh.vertices.append((center_x / 1000.0, center_y / 1000.0, z_back_mm / 1000.0))
    front_center = len(mesh.vertices)
    mesh.vertices.append((center_x / 1000.0, center_y / 1000.0, z_front_mm / 1000.0))
    front_offset = 3 * count
    for index in range(count):
        following = (index + 1) % count
        mesh.faces.append((back_center, following, index))
        mesh.faces.append((front_center, front_offset + index, front_offset + following))
    return mesh


def rounded_prism(
    width_mm: float,
    height_mm: float,
    depth_mm: float,
    radius_mm: float,
    center_x_mm: float,
    bottom_y_mm: float,
    z_center_mm: float,
    segments: int = 12,
    bevel_mm: float = 0.12,
) -> Mesh:
    points = rounded_rectangle_points(
        width_mm,
        height_mm,
        radius_mm,
        center_x_mm,
        bottom_y_mm,
        segments,
    )
    return extruded_polygon(
        points,
        z_center_mm - depth_mm * 0.5,
        z_center_mm + depth_mm * 0.5,
        min(bevel_mm, depth_mm * 0.3),
    )


def cylinder(
    radius_mm: float,
    depth_mm: float,
    center_mm: tuple[float, float, float],
    segments: int = 40,
) -> Mesh:
    center_x, center_y, center_z = center_mm
    mesh = Mesh()
    for z_value in (center_z - depth_mm * 0.5, center_z + depth_mm * 0.5):
        for index in range(segments):
            angle = math.tau * index / segments
            mesh.vertices.append(
                (
                    (center_x + radius_mm * math.cos(angle)) / 1000.0,
                    (center_y + radius_mm * math.sin(angle)) / 1000.0,
                    z_value / 1000.0,
                )
            )
    back_center = len(mesh.vertices)
    mesh.vertices.append(
        (center_x / 1000.0, center_y / 1000.0, (center_z - depth_mm * 0.5) / 1000.0)
    )
    front_center = len(mesh.vertices)
    mesh.vertices.append(
        (center_x / 1000.0, center_y / 1000.0, (center_z + depth_mm * 0.5) / 1000.0)
    )
    for index in range(segments):
        following = (index + 1) % segments
        mesh.faces.extend(
            (
                (index, following, segments + following),
                (index, segments + following, segments + index),
                (back_center, following, index),
                (front_center, segments + index, segments + following),
            )
        )
    return mesh


def outer_outline(
    width_mm: float, height_mm: float, central_width_mm: float, top_drop_mm: float
) -> list[tuple[float, float]]:
    half_width = width_mm * 0.5
    center_half = central_width_mm * 0.5
    wing_top = height_mm - top_drop_mm
    return ensure_ccw(
        [
            (-half_width + 4.0, 0.0),
            (half_width - 4.0, 0.0),
            (half_width - 1.5, 1.2),
            (half_width, 4.2),
            (half_width, wing_top - 4.0),
            (half_width - 1.2, wing_top - 1.4),
            (half_width - 4.0, wing_top),
            (center_half + 2.5, wing_top),
            (center_half + 0.9, wing_top + 1.4),
            (center_half + 0.9, height_mm - 2.2),
            (center_half - 1.0, height_mm),
            (-center_half + 1.0, height_mm),
            (-center_half - 0.9, height_mm - 2.2),
            (-center_half - 0.9, wing_top + 1.4),
            (-center_half - 2.5, wing_top),
            (-half_width + 4.0, wing_top),
            (-half_width + 1.2, wing_top - 1.4),
            (-half_width, wing_top - 4.0),
            (-half_width, 4.2),
            (-half_width + 1.5, 1.2),
        ]
    )


def value(entry: dict) -> float:
    return float(entry["value"])


def build(reference: dict) -> tuple[dict[str, Mesh], dict]:
    envelope = reference["envelope"]
    landmarks = reference["provisionalLandmarks"]
    width = value(envelope["width"])
    height = value(envelope["height"])
    depth = value(envelope["depth"])
    central_width = value(landmarks["centralUpperBodyWidth"])
    wing_width = value(landmarks["sideWingWidthEach"])
    top_drop = value(landmarks["sideWingTopDrop"])
    front_depth = depth * 0.52
    front_z = front_depth

    shell = extruded_polygon(
        outer_outline(width, height, central_width, top_drop),
        0.0,
        front_depth,
        0.62,
    )
    features = Mesh()
    grooves = Mesh()
    screw_wells = Mesh()

    grip = landmarks["sideGripGrooves"]
    groove_centers = [float(center) for center in grip["centerY"]]
    groove_height = value(grip["grooveHeight"])
    band_bounds = [4.5] + groove_centers + [height - top_drop - 0.9]
    for side in (-1.0, 1.0):
        center_x = side * (central_width * 0.5 + wing_width * 0.5)
        for index in range(len(band_bounds) - 1):
            lower = band_bounds[index] + (groove_height * 0.55 if index else 0.0)
            upper = band_bounds[index + 1] - groove_height * 0.55
            features.add(
                rounded_prism(
                    wing_width - 2.0,
                    max(1.0, upper - lower),
                    0.48,
                    1.0,
                    center_x,
                    lower,
                    front_z + 0.14,
                    8,
                    0.08,
                )
            )
        for center_y in groove_centers:
            grooves.add(
                rounded_prism(
                    wing_width - 1.2,
                    groove_height,
                    0.24,
                    0.42,
                    center_x,
                    center_y - groove_height * 0.5,
                    front_z + 0.39,
                    8,
                    0.04,
                )
            )

    label = landmarks["labelRecess"]
    label_width = value(label["width"])
    label_height = value(label["height"])
    label_bottom = value(label["bottomY"])
    label_radius = value(label["cornerRadius"])
    features.add(
        rounded_prism(
            label_width + 2.2,
            label_height + 2.2,
            0.58,
            label_radius + 0.9,
            0.0,
            label_bottom - 1.1,
            front_z + 0.17,
            18,
            0.08,
        )
    )
    label_surface = rounded_prism(
        label_width,
        label_height,
        0.18,
        label_radius,
        0.0,
        label_bottom,
        front_z + 0.35,
        20,
        0.03,
    )
    label_surface.uvs = [
        (
            min(1.0, max(0.0, (x * 1000.0 + label_width * 0.5) / label_width)),
            min(1.0, max(0.0, (y * 1000.0 - label_bottom) / label_height)),
        )
        for x, y, _ in label_surface.vertices
    ]
    label_surface.face_uvs = list(label_surface.faces)

    lower = landmarks["lowerFrontGripField"]
    lower_width = value(lower["width"])
    lower_height = value(lower["height"])
    lower_bottom = value(lower["bottomY"])
    rail_width = 2.4
    features.add(
        rounded_prism(
            lower_width,
            2.4,
            0.54,
            1.1,
            0.0,
            lower_bottom + lower_height - 2.4,
            front_z + 0.16,
            14,
            0.08,
        )
    )
    for x_position in (
        -lower_width * 0.5 + rail_width * 0.5,
        lower_width * 0.5 - rail_width * 0.5,
    ):
        features.add(
            rounded_prism(
                rail_width,
                lower_height - 1.0,
                0.50,
                0.85,
                x_position,
                lower_bottom,
                front_z + 0.15,
                12,
                0.07,
            )
        )
    channel_width = lower_width - 13.0
    channel_height = 5.2
    channel_bottom = lower_bottom + lower_height - 14.2
    grooves.add(
        rounded_prism(
            channel_width,
            channel_height,
            0.26,
            2.6,
            0.0,
            channel_bottom,
            front_z + 0.40,
            20,
            0.04,
        )
    )
    features.add(
        rounded_prism(
            1.2,
            max(7.0, channel_bottom - lower_bottom - 0.7),
            0.32,
            0.45,
            0.0,
            lower_bottom + 0.5,
            front_z + 0.19,
            10,
            0.04,
        )
    )

    screws = landmarks["securityScrewCenters"]
    screw_x = value(screws["xAbsolute"])
    screw_y = value(screws["y"])
    screw_radius = value(screws["wellDiameter"]) * 0.5
    for x_position in (-screw_x, screw_x):
        screw_wells.add(
            cylinder(
                screw_radius,
                0.50,
                (x_position, screw_y, front_z + 0.21),
                48,
            )
        )
        grooves.add(
            cylinder(
                screw_radius * 0.34,
                0.18,
                (x_position, screw_y, front_z + 0.52),
                36,
            )
        )

    features.add(
        rounded_prism(
            central_width + 2.0,
            2.0,
            0.34,
            0.8,
            0.0,
            height - 2.25,
            front_z + 0.11,
            12,
            0.05,
        )
    )
    for x_position in (-width * 0.5 + 8.0, width * 0.5 - 8.0):
        features.add(
            rounded_prism(
                11.0,
                3.2,
                0.42,
                1.1,
                x_position,
                0.0,
                front_z + 0.13,
                12,
                0.06,
            )
        )

    meshes = {
        "front_shell": shell,
        "front_features": features,
        "front_grooves": grooves,
        "label_surface": label_surface,
        "screw_wells": screw_wells,
    }
    manifest = {
        "schemaVersion": 1,
        "assetId": ASSET_ID,
        "license": LICENSE,
        "source": SOURCE,
        "status": "provisional-front-shell-blockout",
        "referenceId": reference["referenceId"],
        "physicalCalibrationComplete": bool(
            reference["physicalCalibration"]["completed"]
        ),
        "alphaGeometryReused": False,
        "systemId": "snes",
        "region": "NTSC-U/C",
        "shellPart": "front",
        "physicalEnvelopeMm": [width, height, depth],
        "frontHalfDepthMm": front_depth,
        "centralUpperBodyWidthMm": central_width,
        "sideWingWidthEachMm": wing_width,
        "sideGripGrooveCountEach": len(groove_centers),
        "labelRecessMm": [label_width, label_height, label_bottom],
        "lowerFrontGripFieldMm": [lower_width, lower_height, lower_bottom],
        "rootPivot": "bottom connector center",
        "consoleVisible": False,
        "m3TextureSlot": "snes-front-label",
        "labelUvBounds": [[0.0, 0.0], [1.0, 1.0]],
        "mayApproveFinalGeometry": bool(
            reference["modelingGate"]["mayApproveFinalM2_2Geometry"]
        ),
        "mayStartM2_3Blockout": True,
        "mayStartM3": False,
        "components": {
            name: {
                "vertices": len(mesh.vertices),
                "triangles": mesh.triangles,
            }
            for name, mesh in meshes.items()
        },
    }
    return meshes, manifest


def obj_text(mesh: Mesh, object_name: str) -> str:
    lines = [
        f"# {object_name}",
        "# SPDX-License-Identifier: CC0-1.0",
        f"o {object_name}",
    ]
    lines.extend(f"v {x:.9f} {y:.9f} {z:.9f}" for x, y, z in mesh.vertices)
    if mesh.uvs:
        lines.extend(f"vt {u:.9f} {v:.9f}" for u, v in mesh.uvs)
    for index, face in enumerate(mesh.faces):
        if mesh.uvs:
            uv_face = mesh.face_uvs[index]
            lines.append(
                "f "
                + " ".join(
                    f"{vertex + 1}/{uv + 1}"
                    for vertex, uv in zip(face, uv_face)
                )
            )
        else:
            lines.append("f " + " ".join(str(vertex + 1) for vertex in face))
    return "\n".join(lines) + "\n"


def material_text(name: str, color: str, roughness: float) -> str:
    red, green, blue = [int(color[index : index + 2], 16) / 255.0 for index in (1, 3, 5)]
    return (
        '[gd_resource type="StandardMaterial3D" format=3]\n\n'
        "[resource]\n"
        f'resource_name = "{name}"\n'
        f"albedo_color = Color({red:.6f}, {green:.6f}, {blue:.6f}, 1)\n"
        "metallic = 0.0\n"
        f"roughness = {roughness:.3f}\n"
    )


def scene_text(manifest: dict) -> str:
    components = [
        ("front_shell", "FrontShell", "shell"),
        ("front_features", "FrontFeatures", "shell"),
        ("front_grooves", "FrontGrooves", "detail"),
        ("label_surface", "LabelSurface", "label"),
        ("screw_wells", "ScrewWells", "detail"),
    ]
    lines = ['[gd_scene load_steps=9 format=3]', ""]
    for index, (component, _, _) in enumerate(components, 1):
        lines.append(
            f'[ext_resource type="ArrayMesh" path="res://assets/snes/m2_2/snes_ntsc_u_{component}.obj" id="{index}_mesh"]'
        )
    lines.extend(
        [
            '[ext_resource type="Material" path="res://assets/snes/m2_2/materials/snes_m2_2_shell_clay.tres" id="6_shell"]',
            '[ext_resource type="Material" path="res://assets/snes/m2_2/materials/snes_m2_2_detail_clay.tres" id="7_detail"]',
            '[ext_resource type="Material" path="res://assets/snes/m2_2/materials/snes_m2_2_label_placeholder.tres" id="8_label"]',
            "",
            '[node name="SnesNaCartridgeFrontM2_2" type="Node3D"]',
            f'metadata/asset_id = "{manifest["assetId"]}"',
            'metadata/system_id = "snes"',
            'metadata/region = "NTSC-U/C"',
            'metadata/license = "CC0-1.0"',
            'metadata/source = "original-parametric-clean-rebuild"',
            'metadata/status = "provisional-front-shell-blockout"',
            "metadata/console_visible = false",
            "metadata/physical_calibration_complete = false",
            "metadata/may_approve_final_geometry = false",
            "metadata/may_start_m2_3_blockout = true",
            "metadata/may_start_m3 = false",
            "",
            '[node name="VisualRoot" type="Node3D" parent="."]',
        ]
    )
    material_ids = {"shell": "6_shell", "detail": "7_detail", "label": "8_label"}
    for index, (component, node_name, material) in enumerate(components, 1):
        lines.extend(
            [
                "",
                f'[node name="{node_name}" type="MeshInstance3D" parent="VisualRoot"]',
                f'mesh = ExtResource("{index}_mesh")',
                f'material_override = ExtResource("{material_ids[material]}")',
                f'metadata/triangle_count = {manifest["components"][component]["triangles"]}',
            ]
        )
        if node_name == "LabelSurface":
            lines.append('metadata/m3_texture_slot = "snes-front-label"')
    lines.extend(
        [
            "",
            '[node name="DockPivot" type="Marker3D" parent="."]',
            "position = Vector3(0, 0, 0)",
            "",
            '[node name="CenterOfMass" type="Marker3D" parent="."]',
            "position = Vector3(0, 0.044, 0.0052)",
            "",
            '[node name="LabelAnchor" type="Marker3D" parent="."]',
            "position = Vector3(0, 0.06625, 0.01062)",
            "",
            '[node name="ConnectorAnchor" type="Marker3D" parent="."]',
            "position = Vector3(0, 0, 0)",
            "",
            '[node name="BrowseFocusedAnchor" type="Marker3D" parent="."]',
            "rotation_degrees = Vector3(-5, -9, 0)",
            "",
            '[node name="DockApproachAnchor" type="Marker3D" parent="."]',
            "rotation_degrees = Vector3(-2, -2, 0)",
            "",
        ]
    )
    return "\n".join(lines)


def smoke_test_text() -> str:
    return '''extends SceneTree

const FRONT := preload("res://scenes/SnesNaCartridgeFrontM2_2.tscn")


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var asset := FRONT.instantiate()
    root.add_child(asset)
    await process_frame
    await process_frame

    _require(str(asset.get_meta("asset_id", "")) == "retrolife.snes.na-cartridge.m2.2.front.v1", "asset id")
    _require(str(asset.get_meta("license", "")) == "CC0-1.0", "license")
    _require(str(asset.get_meta("source", "")) == "original-parametric-clean-rebuild", "source")
    _require(not bool(asset.get_meta("console_visible", true)), "console exclusion")
    _require(not bool(asset.get_meta("physical_calibration_complete", true)), "calibration honesty")
    _require(not bool(asset.get_meta("may_approve_final_geometry", true)), "approval gate")
    _require(bool(asset.get_meta("may_start_m2_3_blockout", false)), "M2.3 blockout gate")
    _require(not bool(asset.get_meta("may_start_m3", true)), "M3 gate")
    _require(asset.find_child("Console", true, false) == null, "no console node")

    for node_name in ["FrontShell", "FrontFeatures", "FrontGrooves", "LabelSurface", "ScrewWells"]:
        var instance := asset.find_child(node_name, true, false) as MeshInstance3D
        _require(instance != null and instance.mesh != null, "mesh %s" % node_name)
        _require(int(instance.get_meta("triangle_count", 0)) > 0, "triangles %s" % node_name)

    var shell := asset.find_child("FrontShell", true, false) as MeshInstance3D
    var shell_size := shell.get_aabb().size
    _require(absf(shell_size.x - 0.136) <= 0.0011, "width")
    _require(absf(shell_size.y - 0.088) <= 0.0011, "height")
    _require(absf(shell_size.z - 0.0104) <= 0.0008, "front depth")

    var label := asset.find_child("LabelSurface", true, false) as MeshInstance3D
    var arrays := label.mesh.surface_get_arrays(0)
    var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
    _require(not uvs.is_empty(), "label UVs")
    var minimum_uv := Vector2(100.0, 100.0)
    var maximum_uv := Vector2(-100.0, -100.0)
    for uv in uvs:
        minimum_uv = minimum_uv.min(uv)
        maximum_uv = maximum_uv.max(uv)
    _require(minimum_uv.x <= 0.001 and minimum_uv.y <= 0.001, "UV minimum")
    _require(maximum_uv.x >= 0.999 and maximum_uv.y >= 0.999, "UV maximum")
    _require(str(label.get_meta("m3_texture_slot", "")) == "snes-front-label", "M3 texture slot")

    for anchor_name in ["DockPivot", "CenterOfMass", "LabelAnchor", "ConnectorAnchor", "BrowseFocusedAnchor", "DockApproachAnchor"]:
        _require(asset.find_child(anchor_name, true, false) != null, "anchor %s" % anchor_name)

    print("RETROLIFE_M2_2_FRONT_GODOT_OK asset=true meshes=5 grooves=5 uv=true pivot=true console=false physical_calibrated=false final_approval=false m3=false")
    quit(0)


func _require(condition: bool, label_name: String) -> void:
    if condition:
        return
    push_error("RETROLIFE_M2_2_FRONT_GODOT_FAILED: %s" % label_name)
    quit(1)
'''


def svg_start(title: str, subtitle: str, width: int = 1600, height: int = 900) -> list[str]:
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        f"<title>{title}</title>",
        '<rect width="100%" height="100%" fill="#080a0f"/>',
        f'<text x="80" y="66" fill="#f4f6fb" font-family="system-ui" font-size="34" font-weight="700">{title}</text>',
        f'<text x="80" y="98" fill="#98a2b5" font-family="system-ui" font-size="17">{subtitle}</text>',
    ]


def cartridge_front_group(x: float, y: float, scale: float, identifier: str) -> str:
    outline = "M -64 0 L 64 0 L 66.5 1.2 L 68 4.2 L 68 77.5 L 66.8 80 L 44 81.5 L 42.4 83 L 42.4 85.8 L 40.5 88 L -40.5 88 L -42.4 85.8 L -42.4 83 L -44 81.5 L -66.8 80 L -68 77.5 L -68 4.2 L -66.5 1.2 Z"
    grooves = []
    for center in (17.5, 31.5, 45.5, 59.5, 73.5):
        for side in (-1, 1):
            grooves.append(
                f'<rect x="{side * 54.75 - 11.8:.2f}" y="{center - 0.7:.2f}" width="23.6" height="1.4" rx=".6" fill="#737987"/>'
            )
    return (
        f'<g id="{identifier}" transform="translate({x} {y}) scale({scale} {-scale})">'
        f'<path d="{outline}" fill="#aeb2bb" stroke="#d8dbe2" stroke-width=".7"/>'
        '<rect x="-42.6" y="45.9" width="85.2" height="40.7" rx="5" fill="#c3c6cd"/>'
        '<rect x="-41.5" y="47" width="83" height="38.5" rx="4.2" fill="#9298a5"/>'
        '<path d="M -41.5 41 H 41.5 V 38.6 H 39.1 V 4 H 41.5 V 41 Z M -41.5 38.6 H -39.1 V 4 H -41.5 Z" fill="#c1c4cb"/>'
        '<rect x="-35" y="26.8" width="70" height="5.2" rx="2.6" fill="#7f8693"/>'
        '<rect x="-.6" y="13.8" width="1.2" height="13" rx=".5" fill="#c1c4cb"/>'
        + "".join(grooves)
        + '<circle cx="-54.5" cy="10" r="3.1" fill="#707784"/><circle cx="54.5" cy="10" r="3.1" fill="#707784"/>'
        + "</g>"
    )


def clay_svg() -> str:
    parts = svg_start(
        "M2.2 front clay review",
        "Provisional clean rebuild, neutral clay, no label art, no console",
    )
    parts.extend(
        [
            '<rect x="60" y="135" width="1480" height="700" rx="28" fill="#11151e" stroke="#242b38"/>',
            cartridge_front_group(420, 720, 5.6, "front-clay"),
            '<text x="420" y="790" text-anchor="middle" fill="#f4f6fb" font-family="system-ui" font-size="24" font-weight="650">Front orthographic</text>',
            '<g transform="translate(1130 710) skewY(-7) scale(.96 1)">',
            cartridge_front_group(0, 0, 5.5, "three-quarter-clay"),
            '</g>',
            '<path d="M 1488 215 L 1530 244 L 1530 704 L 1488 720 Z" fill="#777e8b" opacity=".8"/>',
            '<text x="1130" y="790" text-anchor="middle" fill="#f4f6fb" font-family="system-ui" font-size="24" font-weight="650">Front three-quarter mass check</text>',
            '<text x="800" y="855" text-anchor="middle" fill="#a8b1c2" font-family="system-ui" font-size="16">Stepped top, broad side wings, five grooves, shallow label recess, lower grip field, screw wells</text>',
            "</svg>\n",
        ]
    )
    return "".join(parts)


def overlay_svg() -> str:
    parts = svg_start(
        "M2.2 front orthographic overlay",
        "Generated silhouette against the provisional M2.1 136 x 88 mm reference",
    )
    parts.extend(
        [
            '<rect x="170" y="140" width="1260" height="675" rx="24" fill="#10141c" stroke="#252d3a"/>',
            cartridge_front_group(800, 745, 6.2, "generated-overlay"),
            '<rect x="378.4" y="199.4" width="843.2" height="545.6" fill="none" stroke="#dc5df5" stroke-width="3" stroke-dasharray="14 10"/>',
            '<line x1="378" y1="775" x2="1222" y2="775" stroke="#4de0d2" stroke-width="2"/><text x="800" y="805" text-anchor="middle" fill="#4de0d2" font-family="system-ui" font-size="18">136.0 mm</text>',
            '<line x1="1330" y1="199" x2="1330" y2="745" stroke="#4de0d2" stroke-width="2"/><text x="1362" y="485" fill="#4de0d2" font-family="system-ui" font-size="18" transform="rotate(90 1362 485)">88.0 mm</text>',
            '<text x="200" y="860" fill="#dc5df5" font-family="system-ui" font-size="16">Dashed: provisional envelope</text><text x="510" y="860" fill="#d8dbe2" font-family="system-ui" font-size="16">Clay: generated front shell</text>',
            "</svg>\n",
        ]
    )
    return "".join(parts)


def top_side_overlay_svg() -> str:
    parts = svg_start(
        "M2.2 front top and side overlay",
        "Front-half depth and stepped shoulder continuity, provisional until caliper calibration",
    )
    parts.extend(
        [
            '<rect x="80" y="145" width="1440" height="665" rx="26" fill="#10141c" stroke="#252d3a"/>',
            '<text x="150" y="205" fill="#f4f6fb" font-family="system-ui" font-size="22" font-weight="650">Top profile</text>',
            '<path d="M 190 300 L 360 300 L 380 282 L 1220 282 L 1240 300 L 1410 300 L 1410 365 L 190 365 Z" fill="#aeb2bb" stroke="#d8dbe2" stroke-width="2"/>',
            '<rect x="190" y="300" width="1220" height="65" fill="none" stroke="#dc5df5" stroke-width="2" stroke-dasharray="12 8"/>',
            '<text x="800" y="400" text-anchor="middle" fill="#4de0d2" font-family="system-ui" font-size="18">136.0 mm width, stepped center and shoulders</text>',
            '<text x="150" y="505" fill="#f4f6fb" font-family="system-ui" font-size="22" font-weight="650">Side profile</text>',
            '<path d="M 650 740 L 650 555 Q 652 535 670 530 L 735 530 Q 748 538 754 555 L 754 740 Z" fill="#aeb2bb" stroke="#d8dbe2" stroke-width="2"/>',
            '<rect x="650" y="530" width="200" height="210" fill="none" stroke="#dc5df5" stroke-width="2" stroke-dasharray="12 8"/>',
            '<text x="800" y="770" text-anchor="middle" fill="#4de0d2" font-family="system-ui" font-size="18">10.4 mm front half of the provisional 20.0 mm shell depth</text>',
            "</svg>\n",
        ]
    )
    return "".join(parts)


def alpha_comparison_svg() -> str:
    parts = svg_start(
        "M2.2 silhouette comparison",
        "Rejected alpha characteristics at left, clean NTSC-U front rebuild at right",
    )
    parts.extend(
        [
            '<rect x="70" y="140" width="700" height="680" rx="26" fill="#15131a" stroke="#3a263d"/>',
            '<rect x="230" y="225" width="380" height="500" rx="32" fill="#787681" stroke="#d05b7c" stroke-width="3"/>',
            '<rect x="290" y="310" width="260" height="138" rx="16" fill="#56545d" stroke="#d05b7c" stroke-width="6"/>',
            '<g stroke="#d05b7c" stroke-width="8">' + ''.join(f'<line x1="250" y1="{480+i*28}" x2="300" y2="{480+i*28}"/><line x1="540" y1="{480+i*28}" x2="590" y2="{480+i*28}"/>' for i in range(6)) + '</g>',
            '<text x="420" y="775" text-anchor="middle" fill="#f49ab3" font-family="system-ui" font-size="22" font-weight="650">Rejected alpha</text>',
            '<text x="420" y="805" text-anchor="middle" fill="#bca6af" font-family="system-ui" font-size="15">Rounded slab, narrow ribs, heavy label frame</text>',
            '<rect x="830" y="140" width="700" height="680" rx="26" fill="#11171a" stroke="#24403d"/>',
            cartridge_front_group(1180, 735, 5.7, "clean-rebuild-comparison"),
            '<text x="1180" y="775" text-anchor="middle" fill="#7ce8d8" font-family="system-ui" font-size="22" font-weight="650">M2.2 clean rebuild</text>',
            '<text x="1180" y="805" text-anchor="middle" fill="#a8c0bc" font-family="system-ui" font-size="15">Stepped top, broad wings, five full-width grooves</text>',
            "</svg>\n",
        ]
    )
    return "".join(parts)


def m1_poses_svg() -> str:
    parts = svg_start(
        "M2.2 front shell in M1 poses",
        "Focused, dock approach and docked composition using the locked bottom-dock contract",
    )
    cards = [
        (310, 620, 3.8, "focused", False, -5, -9),
        (800, 665, 3.25, "dock approach", True, -2, -2),
        (1290, 710, 2.9, "docked", True, -1, 0),
    ]
    for x_position, y_position, scale, caption, dock, rotation_x, rotation_y in cards:
        parts.append(
            f'<rect x="{x_position-220}" y="145" width="440" height="660" rx="24" fill="#10141c" stroke="#252d3a"/>'
        )
        parts.append(cartridge_front_group(x_position, y_position, scale, caption.replace(" ", "-")))
        if dock:
            parts.append(
                f'<rect x="{x_position-170}" y="{y_position+8}" width="340" height="90" rx="24" fill="#252c39" stroke="#3a4558" stroke-width="3"/><rect x="{x_position-70}" y="{y_position-4}" width="140" height="24" rx="10" fill="#080a0f"/>'
            )
        parts.append(
            f'<text x="{x_position}" y="760" text-anchor="middle" fill="#f4f6fb" font-family="system-ui" font-size="22" font-weight="650">{caption}</text><text x="{x_position}" y="790" text-anchor="middle" fill="#9ea8b9" font-family="system-ui" font-size="15">rotation x {rotation_x}, y {rotation_y} degrees</text>'
        )
    parts.append("</svg>\n")
    return "".join(parts)


def contract_text(manifest: dict) -> str:
    triangles = sum(component["triangles"] for component in manifest["components"].values())
    return f'''# M2.2 provisional NTSC-U SNES front shell

## Status

This package implements the clean M2.2 front-shell blockout. It is generated from the committed M2.1 provisional reference package and does not reuse the rejected alpha geometry.

It is not final dimensional approval. M2.1 physical calibration and explicit owner approval remain required before the geometry can be finalized.

## Generated contract

- Asset ID: `{manifest["assetId"]}`
- License: `CC0-1.0`
- Source: `original-parametric-clean-rebuild`
- Provisional envelope: `136 x 88 x 20 mm`
- Front-half depth: `{manifest["frontHalfDepthMm"]:.1f} mm`
- Generated triangles: `{triangles}`
- Root pivot: bottom connector center
- Side grip grooves: five per wing
- Label surface: separate planar mesh with stable `0..1` UVs
- Console, branding, legal text, game artwork, ROMs and third-party meshes: excluded

## Godot interface

`SnesNaCartridgeFrontM2_2.tscn` exposes five mesh nodes and the named `DockPivot`, `CenterOfMass`, `LabelAnchor`, `ConnectorAnchor`, `BrowseFocusedAnchor` and `DockApproachAnchor` markers.

The scene is an independent M2.2 source asset. M2.5 owns replacement of the active alpha runtime scene.

## Remaining gates

- Measure one authentic early NTSC-U/C `SNS-006` cartridge with digital calipers.
- Reconcile the M2.1 B and C confidence dimensions.
- Rerun generation, overlays and platform smoke tests after calibration.
- Obtain explicit owner approval of the corrected front clay and M1 poses.
- Keep M3 blocked until the complete M2 gate closes.
'''


def asset_readme(manifest: dict) -> str:
    return f'''# RetroLife M2.2 SNES front shell

Original deterministic CC0 front-shell geometry for the M2.2 milestone.

The package contains only the provisional front half of the early NTSC-U/C wide-shell cartridge. Rear shell, connector cavity, final materials, LODs and runtime replacement belong to M2.3 through M2.5.

Asset: `{manifest["assetId"]}`
Reference: `{manifest["referenceId"]}`
Status: `{manifest["status"]}`
'''


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


GENERATED_PATHS = [
    "frontend/design/m2-2-snes-front-shell.md",
    "frontend/design/m2-2-snes-front-manifest.json",
    "frontend/design/m2-2-snes-front-clay.svg",
    "frontend/design/m2-2-snes-front-overlay.svg",
    "frontend/design/m2-2-snes-front-top-side-overlay.svg",
    "frontend/design/m2-2-snes-alpha-comparison.svg",
    "frontend/design/m2-2-snes-m1-poses.svg",
    "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_front_shell.obj",
    "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_front_features.obj",
    "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_front_grooves.obj",
    "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_label_surface.obj",
    "frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_screw_wells.obj",
    "frontend/godot-ui/assets/snes/m2_2/materials/snes_m2_2_shell_clay.tres",
    "frontend/godot-ui/assets/snes/m2_2/materials/snes_m2_2_detail_clay.tres",
    "frontend/godot-ui/assets/snes/m2_2/materials/snes_m2_2_label_placeholder.tres",
    "frontend/godot-ui/assets/snes/m2_2/LICENSE-CC0.md",
    "frontend/godot-ui/assets/snes/m2_2/PROVENANCE.md",
    "frontend/godot-ui/assets/snes/m2_2/README.md",
    "frontend/godot-ui/scenes/SnesNaCartridgeFrontM2_2.tscn",
    "frontend/godot-ui/scripts/m2_2_snes_front_smoke_test.gd",
]


def write(root: Path) -> None:
    design = root / "frontend/design"
    asset = root / "frontend/godot-ui/assets/snes/m2_2"
    materials = asset / "materials"
    scene = root / "frontend/godot-ui/scenes"
    scripts = root / "frontend/godot-ui/scripts"
    for directory in (design, asset, materials, scene, scripts):
        directory.mkdir(parents=True, exist_ok=True)

    reference = json.loads((design / "m2-snes-reference-manifest.json").read_text())
    meshes, manifest = build(reference)
    mesh_names = {
        "front_shell": "snes_ntsc_u_front_shell.obj",
        "front_features": "snes_ntsc_u_front_features.obj",
        "front_grooves": "snes_ntsc_u_front_grooves.obj",
        "label_surface": "snes_ntsc_u_label_surface.obj",
        "screw_wells": "snes_ntsc_u_screw_wells.obj",
    }
    for component, mesh in meshes.items():
        (asset / mesh_names[component]).write_text(obj_text(mesh, component))

    (materials / "snes_m2_2_shell_clay.tres").write_text(
        material_text("M2.2 shell clay", "#afb3bc", 0.72)
    )
    (materials / "snes_m2_2_detail_clay.tres").write_text(
        material_text("M2.2 molded detail clay", "#737986", 0.78)
    )
    (materials / "snes_m2_2_label_placeholder.tres").write_text(
        material_text("M2.2 label calibration placeholder", "#9298a5", 0.68)
    )
    (asset / "LICENSE-CC0.md").write_text(
        "# CC0 1.0 Universal\n\n"
        "The original RetroLife M2.2 generator, geometry, neutral materials and review diagrams are dedicated to the public domain under CC0 1.0 Universal.\n\n"
        "https://creativecommons.org/publicdomain/zero/1.0/\n"
    )
    (asset / "PROVENANCE.md").write_text(
        "# M2.2 provenance\n\n"
        "This package is original parametric RetroLife geometry generated from the M2.1 measurement manifest by `scripts/generate-m2-2-snes-front.py`. It is released under CC0-1.0.\n\n"
        "No third-party mesh, embedded photograph, trademark, game artwork, ROM or console geometry is included. The rejected alpha geometry is not copied or imported.\n\n"
        "Patent drawings and open reference photography recorded by M2.1 inform proportions only. Physical cartridge calibration is still required.\n"
    )
    (asset / "README.md").write_text(asset_readme(manifest))
    (scene / "SnesNaCartridgeFrontM2_2.tscn").write_text(scene_text(manifest))
    (scripts / "m2_2_snes_front_smoke_test.gd").write_text(smoke_test_text())
    (design / "m2-2-snes-front-shell.md").write_text(contract_text(manifest))
    (design / "m2-2-snes-front-clay.svg").write_text(clay_svg())
    (design / "m2-2-snes-front-overlay.svg").write_text(overlay_svg())
    (design / "m2-2-snes-front-top-side-overlay.svg").write_text(top_side_overlay_svg())
    (design / "m2-2-snes-alpha-comparison.svg").write_text(alpha_comparison_svg())
    (design / "m2-2-snes-m1-poses.svg").write_text(m1_poses_svg())

    generated_for_hash = [path for path in GENERATED_PATHS if not path.endswith("manifest.json")]
    manifest["generatedFiles"] = {
        relative: sha256(root / relative) for relative in generated_for_hash
    }
    (design / "m2-2-snes-front-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )
    total_triangles = sum(mesh.triangles for mesh in meshes.values())
    print(
        "RETROLIFE_M2_2_FRONT_GENERATED "
        f"asset={ASSET_ID} triangles={total_triangles} grooves=5 uv=true "
        "alpha_reused=false physical_calibrated=false final_approval=false m3=false"
    )


def compare(expected_root: Path, actual_root: Path) -> list[str]:
    different: list[str] = []
    for relative in GENERATED_PATHS:
        expected = expected_root / relative
        actual = actual_root / relative
        if not actual.is_file() or expected.read_bytes() != actual.read_bytes():
            different.append(relative)
    return different


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    if arguments.check:
        with tempfile.TemporaryDirectory() as temporary:
            expected_root = Path(temporary)
            reference_source = root / "frontend/design/m2-snes-reference-manifest.json"
            reference_target = expected_root / "frontend/design/m2-snes-reference-manifest.json"
            reference_target.parent.mkdir(parents=True, exist_ok=True)
            reference_target.write_bytes(reference_source.read_bytes())
            write(expected_root)
            differences = compare(expected_root, root)
            if differences:
                raise SystemExit("Generated M2.2 files are stale:\n" + "\n".join(differences))
        print("RETROLIFE_M2_2_FRONT_GENERATION_CHECK_OK")
        return
    write(root)


if __name__ == "__main__":
    main()
