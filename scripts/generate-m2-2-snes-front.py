#!/usr/bin/env python3
"""Generate the provisional M2.2 v3 NTSC-U SNES front-shell package.

The v3 asset is an original RetroLife multi-section loft rebuilt only from the
committed public M2.1 dimensional contract. External photographs and a public
3D scan are listed as visual comparison references; no external vertices,
textures or photographs are copied into the generated CC0 asset package.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import tempfile
import zlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence

ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v3"
PRIOR_ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v2"
REJECTED_ASSET_IDS = ["retrolife.snes.na-cartridge.m2.2.front.v1", PRIOR_ASSET_ID]
LICENSE = "CC0-1.0"
SOURCE = "original-parametric-multi-section-loft-rebuild"
SURFACE_MODEL = "multi-section-loft-with-molded-front-patch"
WIDTH_MM = 136.0
HEIGHT_MM = 88.0
DEPTH_MM = 20.0
FRONT_DEPTH_MM = 10.4
CENTRAL_WIDTH_MM = 83.0
TOP_DROP_MM = 6.5
LABEL_WIDTH_MM = 83.0
LABEL_HEIGHT_MM = 38.5
LABEL_BOTTOM_MM = 47.0
LABEL_RADIUS_MM = 4.0
SCREW_X_MM = 54.5
SCREW_Y_MM = 10.0
SCREW_WELL_RADIUS_MM = 3.25
GROOVE_CENTERS_MM = [17.5, 31.5, 45.5, 59.5, 73.5]
GROOVE_HEIGHT_MM = 1.25
GRID_COLUMNS = 96
ROW_STEP_MM = 1.0
SECTION_DEPTHS_MM = [0.0, 0.55, 2.0, 4.6, 7.4]

@dataclass
class Mesh:
    vertices: list[tuple[float, float, float]] = field(default_factory=list)
    faces: list[tuple[int, int, int]] = field(default_factory=list)
    uvs: list[tuple[float, float]] = field(default_factory=list)
    face_uvs: list[tuple[int, int, int]] = field(default_factory=list)
    def add_vertex(self, value: tuple[float, float, float]) -> int:
        self.vertices.append(value)
        return len(self.vertices) - 1
    def add_face(self, a: int, b: int, c: int) -> None:
        self.faces.append((a, b, c))
    @property
    def triangles(self) -> int:
        return len(self.faces)

@dataclass(frozen=True)
class Geometry:
    shell: Mesh
    label: Mesh
    rows: tuple[tuple[float, float], ...]
    columns: int

def clamp(value: float, minimum: float, maximum: float) -> float:
    return min(maximum, max(minimum, value))

def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if math.isclose(edge0, edge1):
        return 1.0 if value >= edge1 else 0.0
    t = clamp((value - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

def recess_weight(distance: float, feather: float) -> float:
    return 1.0 - smoothstep(-feather, feather, distance)

def rounded_box_sdf(x: float, y: float, center_x: float, center_y: float, half_width: float, half_height: float, radius: float) -> float:
    qx = abs(x - center_x) - (half_width - radius)
    qy = abs(y - center_y) - (half_height - radius)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return outside + inside - radius

def interpolate_controls(controls: Sequence[tuple[float, float]], step_mm: float) -> list[tuple[float, float]]:
    rows: list[tuple[float, float]] = []
    for index in range(len(controls) - 1):
        start_y, start_width = controls[index]
        end_y, end_width = controls[index + 1]
        if math.isclose(start_y, end_y):
            if not rows or rows[-1] != (start_y, start_width):
                rows.append((start_y, start_width))
            rows.append((end_y, end_width))
            continue
        steps = max(1, math.ceil((end_y - start_y) / step_mm))
        for current in range(steps):
            t = current / steps
            row = (start_y + (end_y - start_y) * t, start_width + (end_width - start_width) * t)
            if not rows or row != rows[-1]:
                rows.append(row)
    rows.append(controls[-1])
    return rows

def shell_rows() -> list[tuple[float, float]]:
    wing_top = HEIGHT_MM - TOP_DROP_MM
    controls = [
        (0.0, 64.0), (0.7, 65.8), (2.1, 67.2), (4.4, 68.0),
        (wing_top - 5.0, 68.0), (wing_top - 2.2, 67.4),
        (wing_top - 0.5, 65.0), (wing_top, 64.0),
        (wing_top, 44.0), (wing_top + 0.8, 42.8),
        (wing_top + 2.2, 42.1), (HEIGHT_MM - 2.0, 41.4),
        (HEIGHT_MM - 0.7, 40.4), (HEIGHT_MM, 39.4),
    ]
    return interpolate_controls(controls, ROW_STEP_MM)

def column_parameter(index: int) -> float:
    linear = -1.0 + 2.0 * index / GRID_COLUMNS
    return math.sin(linear * math.pi * 0.5)

def wing_groove_weight(x: float, y: float) -> float:
    if abs(x) < CENTRAL_WIDTH_MM * 0.5 + 1.0:
        return 0.0
    result = 0.0
    for center_y in GROOVE_CENTERS_MM:
        distance = rounded_box_sdf(
            x, y,
            math.copysign((CENTRAL_WIDTH_MM * 0.5 + WIDTH_MM * 0.5) * 0.5, x),
            center_y,
            (WIDTH_MM * 0.5 - CENTRAL_WIDTH_MM * 0.5 - 2.0) * 0.5,
            GROOVE_HEIGHT_MM * 0.5,
            GROOVE_HEIGHT_MM * 0.42,
        )
        result = max(result, recess_weight(distance, 0.38))
    return result

def base_front_depth(x: float, y: float, half_width: float) -> float:
    nx = clamp(abs(x) / max(half_width, 1.0), 0.0, 1.0)
    center_y = HEIGHT_MM * 0.48
    ny = clamp(abs(y - center_y) / (HEIGHT_MM * 0.52), 0.0, 1.0)
    side_roll = 1.34 * pow(nx, 3.4)
    vertical_roll = 0.32 * pow(ny, 2.5)
    crown = 0.18 * (1.0 - nx * nx) * (1.0 - ny * ny)
    wing_setback = 0.16 * smoothstep(CENTRAL_WIDTH_MM * 0.5, 49.0, abs(x))
    return FRONT_DEPTH_MM - side_roll - vertical_roll + crown - wing_setback

def molded_front_depth(x: float, y: float, half_width: float) -> float:
    depth = base_front_depth(x, y, half_width)
    label_distance = rounded_box_sdf(x, y, 0.0, LABEL_BOTTOM_MM + LABEL_HEIGHT_MM * 0.5, LABEL_WIDTH_MM * 0.5, LABEL_HEIGHT_MM * 0.5, LABEL_RADIUS_MM)
    label_weight = recess_weight(label_distance, 1.35)
    depth = depth * (1.0 - label_weight) + 9.43 * label_weight
    field_distance = rounded_box_sdf(x, y, 0.0, 22.8, 41.5, 18.2, 3.0)
    depth -= 0.13 * recess_weight(field_distance, 1.65)
    channel_distance = rounded_box_sdf(x, y, 0.0, 28.0, 35.0, 2.85, 2.85)
    depth -= 0.82 * recess_weight(channel_distance, 0.82)
    depth -= 0.48 * wing_groove_weight(x, y)
    for screw_x in (-SCREW_X_MM, SCREW_X_MM):
        radial = math.hypot(x - screw_x, y - SCREW_Y_MM)
        outer = 1.0 - smoothstep(SCREW_WELL_RADIUS_MM - 0.75, SCREW_WELL_RADIUS_MM + 0.7, radial)
        center = 1.0 - smoothstep(0.75, 1.45, radial)
        depth -= 0.92 * outer + 0.34 * center
    return max(7.6, depth)

def front_grid(rows: Sequence[tuple[float, float]]) -> tuple[Mesh, list[list[int]]]:
    mesh = Mesh()
    indices: list[list[int]] = []
    for y, half_width in rows:
        row_indices: list[int] = []
        for column in range(GRID_COLUMNS + 1):
            parameter = column_parameter(column)
            x = half_width * parameter
            z = molded_front_depth(x, y, half_width)
            row_indices.append(mesh.add_vertex((x / 1000.0, y / 1000.0, z / 1000.0)))
        indices.append(row_indices)
    for row_index in range(len(rows) - 1):
        for column in range(GRID_COLUMNS):
            a = indices[row_index][column]
            b = indices[row_index][column + 1]
            c = indices[row_index + 1][column]
            d = indices[row_index + 1][column + 1]
            mesh.add_face(a, c, d)
            mesh.add_face(a, d, b)
    return mesh, indices

def perimeter_indices(grid: Sequence[Sequence[int]]) -> list[int]:
    rows = len(grid)
    columns = len(grid[0])
    result: list[int] = []
    result.extend(grid[0])
    for row in range(1, rows):
        result.append(grid[row][columns - 1])
    for column in range(columns - 2, -1, -1):
        result.append(grid[rows - 1][column])
    for row in range(rows - 2, 0, -1):
        result.append(grid[row][0])
    return result

def boundary_section_point(front: tuple[float, float, float], section_depth_mm: float, section_index: int) -> tuple[float, float, float]:
    x = front[0] * 1000.0
    y = front[1] * 1000.0
    front_z = front[2] * 1000.0
    progress = section_index / max(1, len(SECTION_DEPTHS_MM) - 1)
    x_scale = 1.0 - 0.010 * progress
    vertical_inset = 0.22 * progress
    if y < HEIGHT_MM * 0.5:
        y_value = y + vertical_inset * (1.0 - y / (HEIGHT_MM * 0.5))
    else:
        y_value = y - vertical_inset * ((y - HEIGHT_MM * 0.5) / (HEIGHT_MM * 0.5))
    groove = wing_groove_weight(x, y)
    side_sign = -1.0 if x < 0.0 else 1.0
    x_value = x * x_scale - side_sign * groove * (0.38 + 0.16 * progress)
    z_value = section_depth_mm - groove * (0.14 + 0.12 * (1.0 - progress))
    if section_index == len(SECTION_DEPTHS_MM) - 1:
        z_value = min(front_z - 0.72, section_depth_mm)
    return (x_value / 1000.0, y_value / 1000.0, z_value / 1000.0)

def build_shell() -> tuple[Mesh, tuple[tuple[float, float], ...]]:
    rows = shell_rows()
    shell, grid = front_grid(rows)
    perimeter = perimeter_indices(grid)
    previous = perimeter
    for reverse_index, section_depth in enumerate(reversed(SECTION_DEPTHS_MM)):
        section_index = len(SECTION_DEPTHS_MM) - 1 - reverse_index
        current: list[int] = []
        for front_index in perimeter:
            current.append(shell.add_vertex(boundary_section_point(shell.vertices[front_index], section_depth, section_index)))
        for index in range(len(perimeter)):
            following = (index + 1) % len(perimeter)
            a, b = previous[index], previous[following]
            c, d = current[index], current[following]
            shell.add_face(a, b, d)
            shell.add_face(a, d, c)
        previous = current
    center = shell.add_vertex((0.0, HEIGHT_MM * 0.5 / 1000.0, 0.0))
    for index in range(len(previous)):
        following = (index + 1) % len(previous)
        shell.add_face(center, previous[following], previous[index])
    return shell, tuple(rows)

def rounded_rectangle_points(width_mm: float, height_mm: float, radius_mm: float, bottom_y_mm: float, segments: int = 14) -> list[tuple[float, float]]:
    radius_mm = min(radius_mm, width_mm * 0.5, height_mm * 0.5)
    center_y = bottom_y_mm + height_mm * 0.5
    corners = [
        (width_mm * 0.5 - radius_mm, center_y + height_mm * 0.5 - radius_mm, 0.0, 90.0),
        (-width_mm * 0.5 + radius_mm, center_y + height_mm * 0.5 - radius_mm, 90.0, 180.0),
        (-width_mm * 0.5 + radius_mm, center_y - height_mm * 0.5 + radius_mm, 180.0, 270.0),
        (width_mm * 0.5 - radius_mm, center_y - height_mm * 0.5 + radius_mm, 270.0, 360.0),
    ]
    points: list[tuple[float, float]] = []
    for corner_index, (cx, cy, start, end) in enumerate(corners):
        for index in range(segments + 1):
            if corner_index and index == 0:
                continue
            angle = math.radians(start + (end - start) * index / segments)
            points.append((cx + radius_mm * math.cos(angle), cy + radius_mm * math.sin(angle)))
    return points

def build_label() -> Mesh:
    mesh = Mesh()
    outline = rounded_rectangle_points(LABEL_WIDTH_MM, LABEL_HEIGHT_MM, LABEL_RADIUS_MM, LABEL_BOTTOM_MM)
    z = 9.455 / 1000.0
    center = mesh.add_vertex((0.0, (LABEL_BOTTOM_MM + LABEL_HEIGHT_MM * 0.5) / 1000.0, z))
    mesh.uvs.append((0.5, 0.5))
    outline_indices: list[int] = []
    for x, y in outline:
        outline_indices.append(mesh.add_vertex((x / 1000.0, y / 1000.0, z)))
        mesh.uvs.append(((x + LABEL_WIDTH_MM * 0.5) / LABEL_WIDTH_MM, (y - LABEL_BOTTOM_MM) / LABEL_HEIGHT_MM))
    for index in range(len(outline_indices)):
        following = (index + 1) % len(outline_indices)
        mesh.add_face(center, outline_indices[index], outline_indices[following])
        mesh.face_uvs.append((center, outline_indices[index], outline_indices[following]))
    return mesh

def build_geometry() -> Geometry:
    shell, rows = build_shell()
    return Geometry(shell=shell, label=build_label(), rows=rows, columns=GRID_COLUMNS + 1)

def obj_text(mesh: Mesh, name: str) -> str:
    lines = [f"# {name}", "# SPDX-License-Identifier: CC0-1.0", f"o {name}"]
    lines.extend(f"v {x:.9f} {y:.9f} {z:.9f}" for x, y, z in mesh.vertices)
    if mesh.uvs:
        lines.extend(f"vt {u:.9f} {v:.9f}" for u, v in mesh.uvs)
    for face_index, face in enumerate(mesh.faces):
        if mesh.uvs:
            uv_face = mesh.face_uvs[face_index]
            lines.append("f " + " ".join(f"{vertex + 1}/{uv + 1}" for vertex, uv in zip(face, uv_face)))
        else:
            lines.append("f " + " ".join(str(vertex + 1) for vertex in face))
    return "\n".join(lines) + "\n"

def material_text(name: str, color: str, roughness: float) -> str:
    red, green, blue = [int(color[index:index + 2], 16) / 255.0 for index in (1, 3, 5)]
    return ('[gd_resource type="StandardMaterial3D" format=3]\n\n[resource]\n' + f'resource_name = "{name}"\n' + f"albedo_color = Color({red:.6f}, {green:.6f}, {blue:.6f}, 1)\nmetallic = 0.0\nroughness = {roughness:.3f}\n")

def scene_text(manifest: dict) -> str:
    return f'''[gd_scene load_steps=5 format=3]

[ext_resource type="ArrayMesh" path="res://assets/snes/m2_2/snes_ntsc_u_front_shell_v3.obj" id="1_shell"]
[ext_resource type="ArrayMesh" path="res://assets/snes/m2_2/snes_ntsc_u_label_surface_v3.obj" id="2_label"]
[ext_resource type="Material" path="res://assets/snes/m2_2/materials/snes_m2_2_v3_shell_clay.tres" id="3_shell_material"]
[ext_resource type="Material" path="res://assets/snes/m2_2/materials/snes_m2_2_v3_label_placeholder.tres" id="4_label_material"]

[node name="SnesNaCartridgeFrontM2_2" type="Node3D"]
metadata/asset_id = "{ASSET_ID}"
metadata/prior_asset_id = "{PRIOR_ASSET_ID}"
metadata/source = "{SOURCE}"
metadata/license = "CC0-1.0"
metadata/status = "provisional-multi-section-loft-rebuild"
metadata/surface_model = "{SURFACE_MODEL}"
metadata/height_field_only = false
metadata/console_visible = false
metadata/physical_calibration_complete = false
metadata/external_geometry_copied = false
metadata/prior_geometry_accepted = false
metadata/may_approve_final_geometry = false
metadata/may_start_m2_3_blockout = false
metadata/may_start_m3 = false

[node name="VisualRoot" type="Node3D" parent="."]
[node name="ContinuousShell" type="MeshInstance3D" parent="VisualRoot"]
mesh = ExtResource("1_shell")
material_override = ExtResource("3_shell_material")
metadata/surface_topology = "single-connected-watertight-shell"
metadata/surface_model = "{SURFACE_MODEL}"
metadata/triangle_count = {manifest['components']['continuous_shell']['triangles']}
[node name="LabelSurface" type="MeshInstance3D" parent="VisualRoot"]
mesh = ExtResource("2_label")
material_override = ExtResource("4_label_material")
metadata/m3_texture_slot = "snes-front-label"
[node name="DockPivot" type="Marker3D" parent="."]
position = Vector3(0, 0, 0)
[node name="CenterOfMass" type="Marker3D" parent="."]
position = Vector3(0, 0.044, 0.0052)
[node name="LabelAnchor" type="Marker3D" parent="."]
position = Vector3(0, 0.06625, 0.009455)
[node name="ConnectorAnchor" type="Marker3D" parent="."]
position = Vector3(0, 0, 0)
[node name="BrowseFocusedAnchor" type="Marker3D" parent="."]
rotation_degrees = Vector3(-5, -9, 0)
[node name="DockApproachAnchor" type="Marker3D" parent="."]
rotation_degrees = Vector3(-2, -2, 0)
'''

def smoke_test_text() -> str:
    return f'''extends SceneTree

const FRONT := preload("res://scenes/SnesNaCartridgeFrontM2_2.tscn")
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var asset := FRONT.instantiate()
    root.add_child(asset)
    await process_frame
    await process_frame
    _require(str(asset.get_meta("asset_id", "")) == "{ASSET_ID}", "asset id")
    _require(str(asset.get_meta("prior_asset_id", "")) == "{PRIOR_ASSET_ID}", "prior asset id")
    _require(str(asset.get_meta("source", "")) == "{SOURCE}", "source")
    _require(str(asset.get_meta("surface_model", "")) == "{SURFACE_MODEL}", "surface model")
    _require(not bool(asset.get_meta("height_field_only", true)), "not height-field-only")
    _require(not bool(asset.get_meta("console_visible", true)), "console exclusion")
    _require(not bool(asset.get_meta("physical_calibration_complete", true)), "calibration honesty")
    _require(not bool(asset.get_meta("external_geometry_copied", true)), "external geometry boundary")
    _require(not bool(asset.get_meta("prior_geometry_accepted", true)), "prior geometry rejection")
    _require(not bool(asset.get_meta("may_approve_final_geometry", true)), "approval gate")
    _require(not bool(asset.get_meta("may_start_m2_3_blockout", true)), "M2.3 gate")
    _require(not bool(asset.get_meta("may_start_m3", true)), "M3 gate")
    var shell := asset.find_child("ContinuousShell", true, false) as MeshInstance3D
    _require(shell != null and shell.mesh != null, "continuous shell")
    _require(str(shell.get_meta("surface_topology", "")) == "single-connected-watertight-shell", "watertight metadata")
    _require(int(shell.get_meta("triangle_count", 0)) > 10000, "triangle budget")
    var shell_size := shell.get_aabb().size
    _require(absf(shell_size.x - 0.136) <= 0.0012, "width")
    _require(absf(shell_size.y - 0.088) <= 0.0012, "height")
    _require(absf(shell_size.z - 0.0104) <= 0.0010, "front depth")
    var label := asset.find_child("LabelSurface", true, false) as MeshInstance3D
    _require(label != null and label.mesh != null, "label surface")
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
    print("RETROLIFE_M2_2_FRONT_GODOT_OK asset=v3 loft=true height_field_only=false watertight=true uv=true console=false physical_calibrated=false final_approval=false m2_3=false m3=false")
    quit(0)
func _require(condition: bool, label_name: String) -> void:
    if condition:
        return
    push_error("RETROLIFE_M2_2_FRONT_GODOT_FAILED: %s" % label_name)
    quit(1)
'''

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

class Canvas:
    def __init__(self, width: int, height: int, color: tuple[int, int, int]) -> None:
        self.width = width
        self.height = height
        self.pixels = bytearray(color * (width * height))
        self.depth = [float("inf")] * (width * height)
    def clear_depth(self) -> None:
        self.depth = [float("inf")] * (self.width * self.height)
    def set_pixel(self, x: int, y: int, color: tuple[int, int, int]) -> None:
        if 0 <= x < self.width and 0 <= y < self.height:
            offset = (y * self.width + x) * 3
            self.pixels[offset:offset + 3] = bytes(color)
    def fill_rect(self, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
        left, right = max(0, x0), min(self.width, x1)
        if right <= left:
            return
        for y in range(max(0, y0), min(self.height, y1)):
            start, end = (y * self.width + left) * 3, (y * self.width + right) * 3
            self.pixels[start:end] = bytes(color) * (right - left)
    def line(self, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int], width: int = 1) -> None:
        dx, sx = abs(x1 - x0), 1 if x0 < x1 else -1
        dy, sy = -abs(y1 - y0), 1 if y0 < y1 else -1
        error = dx + dy
        while True:
            radius = max(0, width // 2)
            self.fill_rect(x0 - radius, y0 - radius, x0 + radius + 1, y0 + radius + 1, color)
            if x0 == x1 and y0 == y1:
                break
            twice = 2 * error
            if twice >= dy:
                error += dy
                x0 += sx
            if twice <= dx:
                error += dx
                y0 += sy
    def triangle(self, points: Sequence[tuple[float, float, float]], color: tuple[int, int, int], offset_x: int, offset_y: int, panel_width: int, panel_height: int) -> None:
        xs, ys = [p[0] for p in points], [p[1] for p in points]
        min_x, max_x = max(offset_x, int(math.floor(min(xs)))), min(offset_x + panel_width - 1, int(math.ceil(max(xs))))
        min_y, max_y = max(offset_y, int(math.floor(min(ys)))), min(offset_y + panel_height - 1, int(math.ceil(max(ys))))
        if min_x > max_x or min_y > max_y:
            return
        x0, y0, z0 = points[0]
        x1, y1, z1 = points[1]
        x2, y2, z2 = points[2]
        denominator = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(denominator) < 1e-7:
            return
        for y in range(min_y, max_y + 1):
            py = y + 0.5
            for x in range(min_x, max_x + 1):
                px = x + 0.5
                a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / denominator
                b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / denominator
                c = 1.0 - a - b
                if a < -1e-5 or b < -1e-5 or c < -1e-5:
                    continue
                depth = a * z0 + b * z1 + c * z2
                index = y * self.width + x
                if depth < self.depth[index]:
                    self.depth[index] = depth
                    self.set_pixel(x, y, color)
    def save_png(self, path: Path) -> None:
        raw = bytearray()
        stride = self.width * 3
        for row in range(self.height):
            raw.append(0)
            raw.extend(self.pixels[row * stride:(row + 1) * stride])
        def chunk(kind: bytes, data: bytes) -> bytes:
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
        path.write_bytes(png)

FONT = {
"A":["01110","10001","10001","11111","10001","10001","10001"],"B":["11110","10001","10001","11110","10001","10001","11110"],"C":["01111","10000","10000","10000","10000","10000","01111"],"D":["11110","10001","10001","10001","10001","10001","11110"],"E":["11111","10000","10000","11110","10000","10000","11111"],"F":["11111","10000","10000","11110","10000","10000","10000"],"G":["01111","10000","10000","10111","10001","10001","01111"],"H":["10001","10001","10001","11111","10001","10001","10001"],"I":["11111","00100","00100","00100","00100","00100","11111"],"J":["00111","00010","00010","00010","10010","10010","01100"],"K":["10001","10010","10100","11000","10100","10010","10001"],"L":["10000","10000","10000","10000","10000","10000","11111"],"M":["10001","11011","10101","10101","10001","10001","10001"],"N":["10001","11001","10101","10011","10001","10001","10001"],"O":["01110","10001","10001","10001","10001","10001","01110"],"P":["11110","10001","10001","11110","10000","10000","10000"],"Q":["01110","10001","10001","10001","10101","10010","01101"],"R":["11110","10001","10001","11110","10100","10010","10001"],"S":["01111","10000","10000","01110","00001","00001","11110"],"T":["11111","00100","00100","00100","00100","00100","00100"],"U":["10001","10001","10001","10001","10001","10001","01110"],"V":["10001","10001","10001","10001","10001","01010","00100"],"W":["10001","10001","10001","10101","10101","10101","01010"],"X":["10001","10001","01010","00100","01010","10001","10001"],"Y":["10001","10001","01010","00100","00100","00100","00100"],"Z":["11111","00001","00010","00100","01000","10000","11111"],"0":["01110","10001","10011","10101","11001","10001","01110"],"1":["00100","01100","00100","00100","00100","00100","01110"],"2":["01110","10001","00001","00010","00100","01000","11111"],"3":["11110","00001","00001","01110","00001","00001","11110"],"4":["00010","00110","01010","10010","11111","00010","00010"],"5":["11111","10000","10000","11110","00001","00001","11110"],"6":["01110","10000","10000","11110","10001","10001","01110"],"7":["11111","00001","00010","00100","01000","01000","01000"],"8":["01110","10001","10001","01110","10001","10001","01110"],"9":["01110","10001","10001","01111","00001","00001","01110"],".":["00000","00000","00000","00000","00000","00110","00110"],":":["00000","00110","00110","00000","00110","00110","00000"],"-":["00000","00000","00000","11111","00000","00000","00000"],"/":["00001","00010","00010","00100","01000","01000","10000"]," ":["00000"]*7}

def draw_text(canvas: Canvas, x: int, y: int, text: str, color: tuple[int, int, int], scale: int = 3) -> None:
    cursor = x
    for character in text.upper():
        glyph = FONT.get(character, FONT[" "])
        for row, pattern in enumerate(glyph):
            for column, value in enumerate(pattern):
                if value == "1":
                    canvas.fill_rect(cursor + column * scale, y + row * scale, cursor + (column + 1) * scale, y + (row + 1) * scale, color)
        cursor += 6 * scale

def rotation_matrix(yaw: float, pitch: float, roll: float = 0.0) -> tuple[tuple[float, float, float], ...]:
    cy, sy, cp, sp, cr, sr = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch), math.cos(roll), math.sin(roll)
    return ((cy * cr + sy * sp * sr, -cy * sr + sy * sp * cr, sy * cp),(cp * sr, cp * cr, -sp),(-sy * cr + cy * sp * sr, sy * sr + cy * sp * cr, cy * cp))

def transform_vertex(vertex: tuple[float, float, float], matrix: tuple[tuple[float, float, float], ...]) -> tuple[float, float, float]:
    x, y, z = vertex[0], vertex[1] - HEIGHT_MM * 0.5 / 1000.0, vertex[2] - FRONT_DEPTH_MM * 0.5 / 1000.0
    return (matrix[0][0]*x+matrix[0][1]*y+matrix[0][2]*z,matrix[1][0]*x+matrix[1][1]*y+matrix[1][2]*z,matrix[2][0]*x+matrix[2][1]*y+matrix[2][2]*z)

def render_mesh(canvas: Canvas, mesh: Mesh, panel: tuple[int, int, int, int], yaw_degrees: float, pitch_degrees: float) -> None:
    x0, y0, width, height = panel
    matrix = rotation_matrix(math.radians(yaw_degrees), math.radians(pitch_degrees))
    transformed = [transform_vertex(vertex, matrix) for vertex in mesh.vertices]
    minimum_x, maximum_x = min(v[0] for v in transformed), max(v[0] for v in transformed)
    minimum_y, maximum_y = min(v[1] for v in transformed), max(v[1] for v in transformed)
    scale = min((width - 48) / max(maximum_x - minimum_x, 1e-6), (height - 48) / max(maximum_y - minimum_y, 1e-6))
    center_x, center_y = (minimum_x + maximum_x) * 0.5, (minimum_y + maximum_y) * 0.5
    projected = [(x0 + width * 0.5 + (v[0] - center_x) * scale, y0 + height * 0.5 - (v[1] - center_y) * scale, v[2]) for v in transformed]
    canvas.clear_depth()
    light = (-0.35, 0.55, -0.76)
    for face in mesh.faces:
        a, b, c = transformed[face[0]], transformed[face[1]], transformed[face[2]]
        ux, uy, uz = b[0]-a[0], b[1]-a[1], b[2]-a[2]
        vx, vy, vz = c[0]-a[0], c[1]-a[1], c[2]-a[2]
        nx, ny, nz = uy*vz-uz*vy, uz*vx-ux*vz, ux*vy-uy*vx
        length = math.sqrt(nx*nx+ny*ny+nz*nz)
        if length < 1e-12:
            continue
        nx, ny, nz = nx/length, ny/length, nz/length
        if nz >= 0.02:
            continue
        diffuse = max(0.0, nx*light[0]+ny*light[1]+nz*light[2])
        value = int(clamp(145 + 84 * diffuse, 0, 255))
        canvas.triangle([projected[index] for index in face], (value, min(255, value+6), min(255, value+12)), x0, y0, width, height)

def review_pngs(root: Path, geometry: Geometry) -> None:
    mobile = root / "frontend/design/mobile"
    mobile.mkdir(parents=True, exist_ok=True)
    background, panel_color, border, text, muted = (7,9,14),(17,21,31),(42,50,65),(240,243,249),(157,168,187)
    views = [("FRONT ORTHOGRAPHIC",0.0,0.0),("FRONT THREE QUARTER",-24.0,-8.0),("SIDE PROFILE",-90.0,0.0),("TOP PROFILE",0.0,-90.0)]
    names = ["m2-2-snes-v3-front.png","m2-2-snes-v3-three-quarter.png","m2-2-snes-v3-side.png","m2-2-snes-v3-top.png"]
    for (label,yaw,pitch), filename in zip(views,names):
        canvas = Canvas(1080,760,background)
        canvas.fill_rect(32,96,1048,690,panel_color)
        canvas.line(32,96,1047,96,border,2); canvas.line(32,689,1047,689,border,2); canvas.line(32,96,32,689,border,2); canvas.line(1047,96,1047,689,border,2)
        draw_text(canvas,44,30,"RETROLIFE M2.2 V3",text,4); draw_text(canvas,44,66,label,muted,2)
        render_mesh(canvas,geometry.shell,(54,116,972,540),yaw,pitch)
        canvas.save_png(mobile/filename)
    sheet = Canvas(1080,2680,background)
    draw_text(sheet,46,34,"RETROLIFE M2.2 V3",text,5); draw_text(sheet,46,82,"MULTI SECTION LOFT REVIEW",muted,3); draw_text(sheet,46,112,"PROVISIONAL - PHYSICAL CALIBRATION OPEN",muted,2)
    panel_y=158
    for label,yaw,pitch in views:
        sheet.fill_rect(32,panel_y,1048,panel_y+570,panel_color)
        sheet.line(32,panel_y,1047,panel_y,border,2); sheet.line(32,panel_y+569,1047,panel_y+569,border,2); sheet.line(32,panel_y,32,panel_y+569,border,2); sheet.line(1047,panel_y,1047,panel_y+569,border,2)
        draw_text(sheet,56,panel_y+20,label,text,3); render_mesh(sheet,geometry.shell,(48,panel_y+62,984,474),yaw,pitch); panel_y += 606
    draw_text(sheet,46,2594,"ASSET V3 - NO EXTERNAL GEOMETRY COPIED",muted,2)
    sheet.save_png(mobile/"m2-2-snes-v3-mobile-review.png")

def projection_svg(title: str, subtitle: str, geometry: Geometry, view: str) -> str:
    lines=[f'<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900" viewBox="0 0 1600 900"><title>{title}</title><rect width="100%" height="100%" fill="#080a0f"/><text x="80" y="66" fill="#f4f6fb" font-family="system-ui" font-size="34" font-weight="700">{title}</text><text x="80" y="98" fill="#98a2b5" font-family="system-ui" font-size="17">{subtitle}</text><rect x="60" y="135" width="1480" height="700" rx="28" fill="#11151e" stroke="#242b38"/>']
    if view == "front":
        points=[(800+w*4.7,750-y*6.4) for y,w in geometry.rows]
        right=" ".join(f"{x:.1f},{y:.1f}" for x,y in points); left=" ".join(f"{1600-x:.1f},{y:.1f}" for x,y in reversed(points))
        lines.append(f'<polygon points="{right} {left}" fill="#aeb2bb" stroke="#e0e3e9" stroke-width="3"/><rect x="605" y="205" width="390" height="246" rx="24" fill="#8f96a3" stroke="#d3d7df" stroke-width="3"/>')
        for center_y in GROOVE_CENTERS_MM:
            y=750-center_y*6.4
            lines.append(f'<line x1="486" y1="{y:.1f}" x2="588" y2="{y:.1f}" stroke="#737b89" stroke-width="7" stroke-linecap="round"/><line x1="1012" y1="{y:.1f}" x2="1114" y2="{y:.1f}" stroke="#737b89" stroke-width="7" stroke-linecap="round"/>')
        lines.append('<rect x="636" y="548" width="328" height="34" rx="17" fill="#727a88"/><circle cx="544" cy="686" r="16" fill="#697180"/><circle cx="1056" cy="686" r="16" fill="#697180"/>')
    else:
        lines.append('<path d="M 655 730 C 646 690 646 232 660 188 C 720 154 846 150 924 178 C 950 224 956 666 940 724 C 852 760 733 760 655 730 Z" fill="#aeb2bb" stroke="#e0e3e9" stroke-width="3"/><path d="M 680 714 C 674 650 675 254 690 210 C 752 188 842 186 900 204" fill="none" stroke="#717988" stroke-width="5"/><line x1="654" y1="720" x2="944" y2="720" stroke="#5ad0dd" stroke-width="2" stroke-dasharray="8 7"/><text x="800" y="790" text-anchor="middle" fill="#5ad0dd" font-family="system-ui" font-size="17">10.4 mm molded front half, multi-section taper</text>')
    lines.append('</svg>\n')
    return "".join(lines)

def contract_text(manifest: dict) -> str:
    return f'''# M2.2 v3 provisional NTSC-U SNES front shell

## Decision

The v1 plate stack and v2 height-field-only presentation are rejected as production geometry. This v3 source replaces them with an original multi-section loft and an integrated molded front patch.

The geometry remains provisional. It does not claim physical calibration or final owner approval.

## Generated contract

- Asset ID: `{ASSET_ID}`
- Prior asset ID: `{PRIOR_ASSET_ID}`
- License: `CC0-1.0`
- Source: `{SOURCE}`
- Surface model: `{SURFACE_MODEL}`
- Envelope: `136 x 88 x 20 mm`
- Front-half depth: `10.4 mm`
- Connected shell vertices: `{manifest['components']['continuous_shell']['vertices']}`
- Connected shell triangles: `{manifest['components']['continuous_shell']['triangles']}`
- Loft sections: `{len(SECTION_DEPTHS_MM)}` plus the molded face
- Label surface: separate rounded planar mesh with stable `0..1` UVs
- Root pivot: bottom connector center
- Console, branding, legal text, game artwork, ROMs and external mesh data: excluded

## Physical comparison boundary

The visual comparison record links an authentic-cartridge scan, public-domain cartridge photography, bottom photography and the design patent. Those sources are used only to challenge silhouette, shoulder roll, label recess, side taper and molded-detail relationships. No third-party vertices, textures or photographs are embedded in this CC0 package.

## Remaining gates

- Measure one authentic early NTSC-U/C `SNS-006` cartridge with digital calipers.
- Reconcile the provisional M2.1 B and C dimensions.
- Review the mobile PNG sheet against the physical specimen.
- Obtain explicit owner visual approval.
- Keep M2.3 and M3 blocked until those gates close.
'''

def physical_comparison_text() -> str:
    return '''# M2.2 v3 physical comparison record

## Purpose

This record documents external visual checks without importing third-party media or geometry. The generated asset remains original RetroLife CC0 work.

## External visual references

1. Laser Design, `Super Mario World Game Cartridge`, Artec Space Spider scan, Sketchfab. The scan is visual validation only. No vertices, textures or topology are copied.
   https://sketchfab.com/3d-models/super-mario-world-game-cartridge-a102d3e7fe5c4770912a56e69b04898a
2. Evan-Amos cartridge photography, Wikimedia Commons, public-domain reference photography.
   https://commons.wikimedia.org/wiki/File:SNES-SFAM-Cartridges.jpg
3. North American SNES cartridge bottom photography, Wikimedia Commons.
   https://commons.wikimedia.org/wiki/File:North_American_SNES_cartridge_bottom.jpg
4. Nintendo design patent USD343833S, orthographic and perspective shell relationships.
   https://patents.google.com/patent/USD343833S/en

## Corrections made from the comparison

- Replaced the front-only closed height field with a multi-section side-wall loft.
- Added continuous side roll and seam taper rather than a flat extruded slab.
- Reduced the visual dominance of the label recess and added a broad draft transition.
- Made the lower field a shallow molded flattening instead of a separate plate.
- Made the grip one continuous rounded channel.
- Continued the five wing grooves into the loft boundary.
- Replaced flat screw depressions with blended bowl-shaped wells.
- Smoothed the central-top shoulders while preserving the public 136 x 88 mm envelope.

## Honesty gates

The scan and photographs are not dimensional substitutes for a caliper session. Physical calibration and owner approval remain false in the manifest. M2.3 and M3 remain blocked.
'''

def asset_readme() -> str:
    return f'''# RetroLife M2.2 v3 SNES front shell

Original deterministic CC0 geometry for the provisional NTSC-U/C front shell.

Asset: `{ASSET_ID}`
Source: `{SOURCE}`
Surface model: `{SURFACE_MODEL}`

The package contains the front half only. Physical calibration, rear-shell work, final materials, LODs and active-runtime replacement remain separate gates.
'''

GENERATED_PATHS=[
"frontend/design/m2-2-snes-front-shell.md","frontend/design/m2-2-snes-v3-physical-comparison.md","frontend/design/m2-2-snes-front-manifest.json","frontend/design/m2-2-snes-front-clay.svg","frontend/design/m2-2-snes-front-overlay.svg","frontend/design/m2-2-snes-front-top-side-overlay.svg","frontend/design/m2-2-snes-alpha-comparison.svg","frontend/design/m2-2-snes-m1-poses.svg","frontend/design/mobile/m2-2-snes-v3-front.png","frontend/design/mobile/m2-2-snes-v3-three-quarter.png","frontend/design/mobile/m2-2-snes-v3-side.png","frontend/design/mobile/m2-2-snes-v3-top.png","frontend/design/mobile/m2-2-snes-v3-mobile-review.png","frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_front_shell_v3.obj","frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_label_surface_v3.obj","frontend/godot-ui/assets/snes/m2_2/materials/snes_m2_2_v3_shell_clay.tres","frontend/godot-ui/assets/snes/m2_2/materials/snes_m2_2_v3_label_placeholder.tres","frontend/godot-ui/assets/snes/m2_2/LICENSE-CC0.md","frontend/godot-ui/assets/snes/m2_2/PROVENANCE.md","frontend/godot-ui/assets/snes/m2_2/README.md","frontend/godot-ui/scenes/SnesNaCartridgeFrontM2_2.tscn","frontend/godot-ui/scripts/m2_2_snes_front_smoke_test.gd"]

def write(root: Path) -> None:
    design=root/"frontend/design"; mobile=design/"mobile"; asset=root/"frontend/godot-ui/assets/snes/m2_2"; materials=asset/"materials"; scenes=root/"frontend/godot-ui/scenes"; scripts=root/"frontend/godot-ui/scripts"
    for directory in (design,mobile,asset,materials,scenes,scripts): directory.mkdir(parents=True,exist_ok=True)
    reference=json.loads((design/"m2-snes-reference-manifest.json").read_text()); geometry=build_geometry()
    for stale in [asset/"snes_ntsc_u_front_shell.obj",asset/"snes_ntsc_u_front_features.obj",asset/"snes_ntsc_u_front_grooves.obj",asset/"snes_ntsc_u_label_surface.obj",asset/"snes_ntsc_u_screw_wells.obj",materials/"snes_m2_2_shell_clay.tres",materials/"snes_m2_2_detail_clay.tres",materials/"snes_m2_2_label_placeholder.tres",scripts/"snes_na_cartridge_m2_2_v2.gd"]:
        if stale.exists(): stale.unlink()
    (asset/"snes_ntsc_u_front_shell_v3.obj").write_text(obj_text(geometry.shell,"snes_ntsc_u_front_shell_v3")); (asset/"snes_ntsc_u_label_surface_v3.obj").write_text(obj_text(geometry.label,"snes_ntsc_u_label_surface_v3"))
    (materials/"snes_m2_2_v3_shell_clay.tres").write_text(material_text("M2.2 v3 shell clay","#aeb3bd",0.74)); (materials/"snes_m2_2_v3_label_placeholder.tres").write_text(material_text("M2.2 v3 label placeholder","#8f96a3",0.70))
    manifest={"schemaVersion":3,"assetId":ASSET_ID,"priorAssetId":PRIOR_ASSET_ID,"rejectedAssetIds":REJECTED_ASSET_IDS,"license":LICENSE,"source":SOURCE,"status":"provisional-multi-section-loft-rebuild","referenceId":reference.get("referenceId","retrolife.m2.1.snes-ntsc-u.reference.v1"),"physicalCalibrationComplete":bool(reference.get("physicalCalibration",{}).get("completed",False)),"externalGeometryCopied":False,"externalMediaEmbedded":False,"physicalVisualComparisonRecorded":True,"surfaceModel":SURFACE_MODEL,"heightFieldOnly":False,"surfaceTopology":"single-connected-watertight-shell","systemId":"snes","region":"NTSC-U/C","shellPart":"front","physicalEnvelopeMm":[WIDTH_MM,HEIGHT_MM,DEPTH_MM],"frontHalfDepthMm":FRONT_DEPTH_MM,"centralUpperBodyWidthMm":CENTRAL_WIDTH_MM,"sideGripGrooveCountEach":len(GROOVE_CENTERS_MM),"labelRecessMm":[LABEL_WIDTH_MM,LABEL_HEIGHT_MM,LABEL_BOTTOM_MM],"rootPivot":"bottom connector center","consoleVisible":False,"m3TextureSlot":"snes-front-label","labelUvBounds":[[0.0,0.0],[1.0,1.0]],"loftSectionDepthsMm":SECTION_DEPTHS_MM,"frontGrid":{"rows":len(geometry.rows),"columns":geometry.columns},"mayApproveFinalGeometry":False,"mayStartM2_3Blockout":False,"mayStartM3":False,"components":{"continuous_shell":{"vertices":len(geometry.shell.vertices),"triangles":geometry.shell.triangles,"path":"frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_front_shell_v3.obj"},"label_surface":{"vertices":len(geometry.label.vertices),"triangles":geometry.label.triangles,"path":"frontend/godot-ui/assets/snes/m2_2/snes_ntsc_u_label_surface_v3.obj"}},"externalVisualReferences":[{"kind":"physical-scan-visual-check","url":"https://sketchfab.com/3d-models/super-mario-world-game-cartridge-a102d3e7fe5c4770912a56e69b04898a","geometryCopied":False},{"kind":"public-domain-cartridge-photography","url":"https://commons.wikimedia.org/wiki/File:SNES-SFAM-Cartridges.jpg","mediaEmbedded":False},{"kind":"bottom-photography","url":"https://commons.wikimedia.org/wiki/File:North_American_SNES_cartridge_bottom.jpg","mediaEmbedded":False},{"kind":"design-patent-orthographic","url":"https://patents.google.com/patent/USD343833S/en","mediaEmbedded":False}]}
    (scenes/"SnesNaCartridgeFrontM2_2.tscn").write_text(scene_text(manifest)); (scripts/"m2_2_snes_front_smoke_test.gd").write_text(smoke_test_text()); (design/"m2-2-snes-front-shell.md").write_text(contract_text(manifest)); (design/"m2-2-snes-v3-physical-comparison.md").write_text(physical_comparison_text())
    (design/"m2-2-snes-front-clay.svg").write_text(projection_svg("M2.2 v3 physical-shape clay review","Original multi-section loft, neutral clay, no label art, no console",geometry,"front")); (design/"m2-2-snes-front-overlay.svg").write_text(projection_svg("M2.2 v3 orthographic envelope overlay","Generated silhouette normalized to the public 136 x 88 mm contract",geometry,"front")); (design/"m2-2-snes-front-top-side-overlay.svg").write_text(projection_svg("M2.2 v3 top and side profile","Multi-section taper and molded edge roll, provisional until caliper validation",geometry,"side")); (design/"m2-2-snes-alpha-comparison.svg").write_text(projection_svg("M2.2 v3 rejection comparison","v1 plates and v2 height-field-only source rejected; v3 multi-section loft active",geometry,"front")); (design/"m2-2-snes-m1-poses.svg").write_text(projection_svg("M2.2 v3 shell in locked M1 poses","Front asset remains independent from active runtime replacement",geometry,"front")); review_pngs(root,geometry)
    (asset/"LICENSE-CC0.md").write_text("# CC0 1.0 Universal\n\nThe original RetroLife M2.2 v3 generator, geometry, neutral materials and review diagrams are dedicated to the public domain under CC0 1.0 Universal.\n\nhttps://creativecommons.org/publicdomain/zero/1.0/\n"); (asset/"PROVENANCE.md").write_text("# M2.2 v3 provenance\n\nThis package is original parametric RetroLife geometry generated only from the committed public M2.1 dimensional contract.\n\nExternal scans, photographs and patent figures are linked for visual challenge only. No third-party vertex, texture, photograph, game art, ROM, console geometry or private repository data is copied or embedded.\n\nPhysical cartridge calibration and explicit owner approval are still required.\n"); (asset/"README.md").write_text(asset_readme())
    generated_for_hash=[path for path in GENERATED_PATHS if not path.endswith("manifest.json")]; manifest["generatedFiles"]={relative:sha256(root/relative) for relative in generated_for_hash}; (design/"m2-2-snes-front-manifest.json").write_text(json.dumps(manifest,indent=2,sort_keys=True)+"\n")
    print("RETROLIFE_M2_2_FRONT_GENERATED "+f"asset={ASSET_ID} shell_triangles={geometry.shell.triangles} shell_vertices={len(geometry.shell.vertices)} loft_sections={len(SECTION_DEPTHS_MM)} "+"height_field_only=false watertight=true external_geometry_copied=false physical_calibrated=false final_approval=false m2_3=false m3=false")

def compare(expected_root: Path, actual_root: Path) -> list[str]:
    return [relative for relative in GENERATED_PATHS if not (actual_root/relative).is_file() or (expected_root/relative).read_bytes()!=(actual_root/relative).read_bytes()]

def main() -> None:
    parser=argparse.ArgumentParser(); parser.add_argument("--root",type=Path,default=Path(__file__).resolve().parents[1]); parser.add_argument("--check",action="store_true"); arguments=parser.parse_args(); root=arguments.root.resolve()
    if arguments.check:
        with tempfile.TemporaryDirectory() as temporary:
            expected_root=Path(temporary); source=root/"frontend/design/m2-snes-reference-manifest.json"; target=expected_root/"frontend/design/m2-snes-reference-manifest.json"; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(source.read_bytes()); write(expected_root); differences=compare(expected_root,root)
            if differences: raise SystemExit("Generated M2.2 v3 files are stale:\n"+"\n".join(differences))
        print("RETROLIFE_M2_2_FRONT_GENERATION_CHECK_OK"); return
    write(root)
if __name__=="__main__": main()
