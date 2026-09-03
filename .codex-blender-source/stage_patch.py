#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/blender/generate_m2_3_snes_cartridge.py")
source = path.read_text(encoding="utf-8")

replacements = [
    (
        "import bpy\nfrom mathutils import Vector\n",
        "import bmesh\nimport bpy\nfrom mathutils import Vector\n",
    ),
    (
        "    scene.world.color = (0.008, 0.011, 0.017)\n    # Stable output on hosted CPU runners.\n",
        "    scene.world.color = (0.030, 0.034, 0.045)\n"
        "    scene.world.use_nodes = True\n"
        "    world_background = scene.world.node_tree.nodes.get(\"Background\")\n"
        "    if world_background is not None:\n"
        "        world_background.inputs[\"Color\"].default_value = (0.035, 0.040, 0.055, 1.0)\n"
        "        world_background.inputs[\"Strength\"].default_value = 0.32\n"
        "    # Stable output on hosted CPU runners.\n",
    ),
    (
        "    mesh.from_pydata(vertices, [], faces)\n"
        "    mesh.validate(clean_customdata=False)\n"
        "    mesh.update(calc_edges=True)\n"
        "    obj = bpy.data.objects.new(name, mesh)\n",
        "    mesh.from_pydata(vertices, [], faces)\n"
        "    mesh.validate(clean_customdata=False)\n"
        "    mesh.update(calc_edges=True)\n"
        "    normal_mesh = bmesh.new()\n"
        "    normal_mesh.from_mesh(mesh)\n"
        "    bmesh.ops.recalc_face_normals(normal_mesh, faces=list(normal_mesh.faces))\n"
        "    normal_mesh.to_mesh(mesh)\n"
        "    normal_mesh.free()\n"
        "    mesh.update(calc_edges=True)\n"
        "    obj = bpy.data.objects.new(name, mesh)\n",
    ),
    (
        "    else:\n        data.type = \"PERSP\"\n        data.lens = 65.0\n",
        "    else:\n        data.type = \"PERSP\"\n        data.lens = 72.0\n",
    ),
    (
        "    add_area_light(\"Key\", (-145.0, -190.0, 210.0), target, 1150.0, 115.0)\n"
        "    add_area_light(\"Fill\", (165.0, -110.0, 100.0), target, 720.0, 90.0)\n"
        "    add_area_light(\"Rear rim\", (-120.0, 180.0, 155.0), target, 980.0, 85.0)\n"
        "    add_area_light(\"Top softbox\", (0.0, 15.0, 270.0), target, 850.0, 125.0)\n",
        "    add_area_light(\"Key\", (-145.0, -190.0, 210.0), target, 72000.0, 115.0)\n"
        "    add_area_light(\"Fill\", (165.0, -110.0, 100.0), target, 38000.0, 90.0)\n"
        "    add_area_light(\"Rear rim\", (-120.0, 180.0, 155.0), target, 56000.0, 85.0)\n"
        "    add_area_light(\"Top softbox\", (0.0, 15.0, 270.0), target, 46000.0, 125.0)\n",
    ),
    (
        "        \"front\": add_camera(\"FrontCamera\", (0.0, -285.0, 43.0), center, True, 106.0),\n"
        "        \"front_three_quarter\": add_camera(\"FrontThreeQuarterCamera\", (178.0, -235.0, 145.0), center, False),\n"
        "        \"rear\": add_camera(\"RearCamera\", (0.0, 285.0, 43.0), center, True, 106.0),\n"
        "        \"rear_three_quarter\": add_camera(\"RearThreeQuarterCamera\", (-178.0, 235.0, 145.0), center, False),\n"
        "        \"side\": add_camera(\"SideCamera\", (285.0, 0.0, 43.0), center, True, 106.0),\n"
        "        \"top\": add_camera(\"TopCamera\", (0.0, 0.0, 285.0), (0.0, 0.0, 38.0), True, 154.0),\n"
        "        \"bottom\": add_camera(\"BottomCamera\", (0.0, 0.0, -245.0), (0.0, 0.0, 4.0), True, 154.0),\n",
        "        \"front\": add_camera(\"FrontCamera\", (0.0, -285.0, 43.0), center, True, 150.0),\n"
        "        \"front_three_quarter\": add_camera(\"FrontThreeQuarterCamera\", (188.0, -252.0, 142.0), center, False),\n"
        "        \"rear\": add_camera(\"RearCamera\", (0.0, 285.0, 43.0), center, True, 150.0),\n"
        "        \"rear_three_quarter\": add_camera(\"RearThreeQuarterCamera\", (-188.0, 252.0, 142.0), center, False),\n"
        "        \"side\": add_camera(\"SideCamera\", (285.0, 0.0, 43.0), center, True, 124.0),\n"
        "        \"top\": add_camera(\"TopCamera\", (0.0, 0.0, 285.0), (0.0, 0.0, 38.0), True, 150.0),\n"
        "        \"bottom\": add_camera(\"BottomCamera\", (0.0, 0.0, -245.0), (0.0, 0.0, 4.0), True, 150.0),\n",
    ),
]

for old, new in replacements:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one patch target, found {count}: {old[:80]!r}")
    source = source.replace(old, new, 1)

path.write_text(source, encoding="utf-8")
