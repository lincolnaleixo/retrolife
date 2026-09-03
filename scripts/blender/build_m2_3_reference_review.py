#!/usr/bin/env python3
from __future__ import annotations

import argparse
import bpy
import bmesh
import json
import math
import sys
from pathlib import Path
from mathutils import Matrix, Vector

TARGET = Vector((0.136, 0.020, 0.088))


def args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    return parser.parse_args(values)


def apply(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.select_set(False)


def import_mesh(path: Path) -> bpy.types.Object:
    if path.suffix.lower() == ".stl":
        bpy.ops.wm.stl_import(filepath=str(path))
    elif path.suffix.lower() == ".obj":
        bpy.ops.wm.obj_import(filepath=str(path))
    elif path.suffix.lower() == ".ply":
        bpy.ops.wm.ply_import(filepath=str(path))
    else:
        raise RuntimeError(f"unsupported source mesh: {path}")
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("source import produced no mesh")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    return bpy.context.object


def normalize(obj: bpy.types.Object) -> None:
    apply(obj)
    values = [float(value) for value in obj.dimensions]
    order = sorted(range(3), key=lambda index: values[index], reverse=True)
    axes = [None, None, None]
    axes[order[0]] = Vector((1.0, 0.0, 0.0))
    axes[order[1]] = Vector((0.0, 0.0, 1.0))
    axes[order[2]] = Vector((0.0, 1.0, 0.0))
    rotation = Matrix((axes[0], axes[1], axes[2])).transposed()
    if rotation.determinant() < 0.0:
        axes[order[2]] *= -1.0
        rotation = Matrix((axes[0], axes[1], axes[2])).transposed()
    obj.matrix_world = rotation.to_4x4() @ obj.matrix_world
    apply(obj)
    current = Vector(obj.dimensions)
    obj.scale = Vector((TARGET.x / current.x, TARGET.y / current.y, TARGET.z / current.z))
    apply(obj)
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = Vector(tuple(min(value[index] for value in corners) for index in range(3)))
    maximum = Vector(tuple(max(value[index] for value in corners) for index in range(3)))
    obj.location -= Vector(((minimum.x + maximum.x) * 0.5, (minimum.y + maximum.y) * 0.5, minimum.z))
    bpy.context.view_layer.update()


def clean(obj: bpy.types.Object) -> None:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00001)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    bevel = obj.modifiers.new("Moulded edge cleanup", "BEVEL")
    bevel.width = 0.00028
    bevel.segments = 3
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(28.0)


def material(name: str, color: tuple[float, float, float, float], roughness: float) -> bpy.types.Material:
    result = bpy.data.materials.new(name)
    result.diffuse_color = color
    result.use_nodes = True
    node = result.node_tree.nodes.get("Principled BSDF")
    if node is not None:
        node.inputs["Base Color"].default_value = color
        node.inputs["Roughness"].default_value = roughness
    return result


def label_objects() -> list[bpy.types.Object]:
    created = []
    for name, dimensions, location, color in (
        ("Label", (0.088, 0.00034, 0.0385), (0.0, -0.01025, 0.061), (0.018, 0.022, 0.030, 1.0)),
        ("Red rule", (0.081, 0.00016, 0.0018), (0.0, -0.01047, 0.077), (0.92, 0.05, 0.07, 1.0)),
        ("Blue field", (0.046, 0.00017, 0.025), (-0.004, -0.01048, 0.061), (0.04, 0.28, 0.67, 1.0)),
    ):
        bpy.ops.mesh.primitive_cube_add(location=location)
        obj = bpy.context.object
        obj.name = name
        obj.dimensions = dimensions
        apply(obj)
        modifier = obj.modifiers.new(f"{name} radii", "BEVEL")
        modifier.width = 0.0015 if name == "Label" else 0.0005
        modifier.segments = 5
        obj.data.materials.append(material(name, color, 0.52))
        created.append(obj)
    return created


def setup() -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = engine
            break
        except (TypeError, ValueError):
            continue
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.world.color = (0.004, 0.006, 0.010)
    for name, location, energy, size in (
        ("Key", (-0.22, -0.28, 0.30), 850.0, 0.22),
        ("Fill", (0.26, -0.14, 0.17), 420.0, 0.20),
        ("Rim", (0.02, 0.28, 0.25), 760.0, 0.18),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size
        light = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(light)
        light.location = location


def render(folder: Path, name: str, location: tuple[float, float, float], ortho: float | None, labels: list[bpy.types.Object], show_labels: bool) -> None:
    data = bpy.data.cameras.new(name)
    camera = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = location
    camera.rotation_euler = (Vector((0.0, 0.0, 0.044)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    if ortho is not None:
        data.type = "ORTHO"
        data.ortho_scale = ortho
    else:
        data.lens = 58.0
    for obj in labels:
        obj.hide_render = not show_labels
    bpy.context.scene.camera = camera
    bpy.context.scene.render.filepath = str(folder / f"m2-3-snes-blender-{name}.png")
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(camera, do_unlink=True)


def main() -> None:
    values = args()
    root = values.root.resolve()
    output = root / "frontend/design/mobile"
    assets = root / "frontend/godot-ui/assets/snes/m2_3"
    output.mkdir(parents=True, exist_ok=True)
    assets.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup()
    shell = import_mesh(values.source.resolve())
    shell.name = "CartridgeShell"
    normalize(shell)
    clean(shell)
    shell.data.materials.append(material("Neutral SNES shell", (0.46, 0.45, 0.52, 1.0), 0.67))
    labels = label_objects()
    views = (
        ("front", (0.0, -0.31, 0.044), 0.154, True),
        ("front-clay", (0.0, -0.31, 0.044), 0.154, False),
        ("three-quarter", (0.19, -0.25, 0.145), None, True),
        ("rear", (0.0, 0.31, 0.044), 0.154, False),
        ("rear-three-quarter", (-0.19, 0.25, 0.145), None, False),
        ("side", (0.24, 0.0, 0.044), 0.112, False),
        ("top", (0.0, 0.0, 0.25), 0.156, False),
        ("bottom", (0.0, 0.0, -0.19), 0.156, False),
    )
    for name, location, ortho, show_labels in views:
        render(output, name, location, ortho, labels, show_labels)
    bpy.ops.wm.save_as_mainfile(filepath=str(assets / "snes_ntsc_u_cartridge_m2_3.blend"), compress=True)
    bpy.ops.object.select_all(action="DESELECT")
    shell.select_set(True)
    for obj in labels:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = shell
    bpy.ops.export_scene.gltf(filepath=str(assets / "snes_ntsc_u_cartridge_m2_3.glb"), export_format="GLB", use_selection=True, export_apply=True)
    manifest = {
        "schemaVersion": 1,
        "assetId": "retrolife.snes.ntsc-u.cartridge.m2.3.blender.reference.v1",
        "source": "https://www.thingiverse.com/thing:6364945",
        "creator": "neebick",
        "physicalEnvelopeMm": [136.0, 88.0, 20.0],
        "blenderVersion": bpy.app.version_string,
        "vertices": len(shell.data.vertices),
        "polygons": len(shell.data.polygons),
        "commercialLabelArtEmbedded": False,
        "privateRepositoryMaterialUsed": False,
        "physicalCalibrationComplete": False,
        "ownerVisualApproval": False,
    }
    (root / "frontend/design/m2-3-snes-blender-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("RETROLIFE_M2_3_BLENDER_OK asset=reference-v1 physical_calibration=false owner_approval=false")


if __name__ == "__main__":
    main()
