@tool
extends Node3D

## RetroLife M2 North American SNES-style cartridge.
## Original parametric geometry released under CC0-1.0.
## No console, logo, game art, ROM, or third-party mesh is included.

const ASSET_ID := "retrolife.snes.na-cartridge.m2.v1"
const LICENSE := "CC0-1.0"
const SYSTEM_ID := "snes"
const MEDIA_FAMILY := "snes-na-cartridge"
const WIDTH := 0.135
const HEIGHT := 0.0864
const DEPTH := 0.0202
const FRONT := DEPTH * 0.5

@export_range(0, 1, 1) var lod_level := 0:
    set(value):
        lod_level = clampi(value, 0, 1)
        if is_inside_tree():
            call_deferred("_rebuild")

var _generated_root: Node3D


func _ready() -> void:
    _rebuild()


func m2_manifest() -> Dictionary:
    return {
        "schemaVersion": 1,
        "assetId": ASSET_ID,
        "license": LICENSE,
        "source": "original-parametric",
        "systemId": SYSTEM_ID,
        "mediaFamily": MEDIA_FAMILY,
        "lod": lod_level,
        "physicalEnvelopeMeters": Vector3(WIDTH, HEIGHT, DEPTH),
        "rootPivot": "bottom connector center",
        "consoleVisible": false,
        "labelUvMinimum": Vector2.ZERO,
        "labelUvMaximum": Vector2.ONE,
	"realArtworkOwner": "M3",
    }


func _rebuild() -> void:
    if _generated_root != null and is_instance_valid(_generated_root):
        _generated_root.free()

    _generated_root = Node3D.new()
    _generated_root.name = "M2GeneratedGeometry"
    _generated_root.set_meta("m2_generated", true)
    add_child(_generated_root)

    set_meta("asset_id", ASSET_ID)
    set_meta("license", LICENSE)
    set_meta("source", "original-parametric")
    set_meta("system_id", SYSTEM_ID)
    set_meta("media_family", MEDIA_FAMILY)
    set_meta("lod", lod_level)
    set_meta("console_visible", false)

    var shell_geometry := _geometry()
    var detail_geometry := _geometry()
    var screw_geometry := _geometry()
    var contact_geometry := _geometry()

    if lod_level == 0:
        _build_lod0(shell_geometry, detail_geometry, screw_geometry, contact_geometry)
    else:
        _build_lod1(shell_geometry, detail_geometry)

    _generated_root.add_child(_mesh_instance(
        "Shell",
        _commit(shell_geometry),
        _material("SNES shell", Color("a9acb4"), 0.66)
    ))
    _generated_root.add_child(_mesh_instance(
        "Details",
        _commit(detail_geometry),
        _material("SNES shell details", Color("50545e"), 0.78)
    ))

    var label := _mesh_instance(
        "LabelSurface",
        _commit(_label_geometry()),
        _material("M2 neutral label placeholder", Color("5966b9"), 0.62)
    )
    label.set_meta("m3_texture_slot", "snes-front-label")
    label.set_meta("uv_minimum", Vector2.ZERO)
    label.set_meta("uv_maximum", Vector2.ONE)
    _generated_root.add_child(label)

    if lod_level == 0:
        _generated_root.add_child(_mesh_instance(
            "Screws",
            _commit(screw_geometry),
            _material("Security screws", Color("707782"), 0.28, 0.72)
        ))
        _generated_root.add_child(_mesh_instance(
            "Contacts",
            _commit(contact_geometry),
            _material("Connector contacts", Color("c79a36"), 0.30, 0.68)
        ))

    _add_anchor("DockPivot", Vector3.ZERO)
    _add_anchor("CenterOfMass", Vector3(0.0, HEIGHT * 0.5, 0.0))
    _add_anchor("LabelAnchor", Vector3(0.0, 0.060, FRONT + 0.0015))
    _add_anchor("ConnectorAnchor", Vector3(0.0, 0.0019, 0.0))


func _build_lod0(shell: Dictionary, detail: Dictionary, screws: Dictionary, contacts: Dictionary) -> void:
    _append(shell, _rounded_prism(WIDTH, HEIGHT, DEPTH, 0.0045, 0.0, 0.0, 12, 0.00135))
    _append(shell, _rounded_prism(0.088, 0.0102, DEPTH + 0.0010, 0.0020, HEIGHT - 0.0098, 0.0, 7, 0.00045))

    for x_value in [-0.0575, 0.0575]:
        _append(shell, _rounded_prism(0.0082, 0.072, DEPTH + 0.00075, 0.0017, 0.0070, 0.0, 6, 0.00038), Vector3(x_value, 0.0, 0.0))

    for x_value in [-0.0605, 0.0605]:
        for y_value in [0.0180, 0.0285, 0.0390, 0.0495, 0.0600]:
            _append(shell, _rounded_prism(0.0135, 0.0036, 0.00120, 0.0015, y_value - 0.0018, FRONT + 0.00048, 5, 0.00018), Vector3(x_value, 0.0, 0.0))
            _append(shell, _rounded_prism(0.0135, 0.0036, 0.00110, 0.0015, y_value - 0.0018, -FRONT - 0.00042, 5, 0.00018), Vector3(x_value, 0.0, 0.0))

    _append(shell, _rounded_prism(0.091, 0.043, 0.00135, 0.0040, 0.0385, FRONT + 0.00047, 10, 0.00022))
    _append(detail, _rounded_prism(0.085, 0.037, 0.00072, 0.0032, 0.0415, FRONT + 0.00072, 10, 0.00012))
    _append(detail, _rounded_prism(0.069, 0.0180, 0.00068, 0.0030, 0.0180, FRONT + 0.00072, 8, 0.00012))
    _append(shell, _rounded_prism(0.058, 0.0072, 0.00115, 0.0027, 0.0242, FRONT + 0.00100, 8, 0.00020))

    for x_value in [-0.0335, 0.0335]:
        _append(shell, _rounded_prism(0.0042, 0.0300, 0.00115, 0.0013, 0.0110, FRONT + 0.00092, 5, 0.00018), Vector3(x_value, 0.0, 0.0))

    _append(detail, _rounded_prism(0.092, 0.053, 0.00066, 0.0033, 0.0210, -FRONT - 0.00066, 10, 0.00012))
    _append(shell, _rounded_prism(0.087, 0.048, 0.00072, 0.0028, 0.0235, -FRONT - 0.00103, 9, 0.00012))

    for index in range(13):
        _append(detail, _box_geometry(Vector3(0.081, 0.00045, 0.00038), Vector3(0.0, 0.029 + index * 0.00245, -FRONT - 0.00148)))

    _append(shell, _rounded_prism(0.033, 0.0080, 0.00065, 0.0020, 0.0655, -FRONT - 0.00142, 7, 0.00011))
    _append(detail, _rounded_prism(WIDTH + 0.00045, HEIGHT + 0.00045, 0.00072, 0.0047, -0.000225, 0.0, 12, 0.00016))
    _append(detail, _box_geometry(Vector3(0.086, 0.0054, 0.0160), Vector3(0.0, 0.0027, 0.0)))

    for x_value in [-0.046, 0.046]:
        _append(detail, _box_geometry(Vector3(0.0080, 0.0030, 0.0042), Vector3(x_value, HEIGHT - 0.0014, 0.0)))
    for x_value in [-0.058, 0.058]:
        _append(shell, _rounded_prism(0.015, 0.0045, DEPTH + 0.0010, 0.0014, 0.0, 0.0, 5, 0.00022), Vector3(x_value, 0.0, 0.0))

    for z_value in [FRONT + 0.00105, -FRONT - 0.00105]:
        for x_value in [-0.055, 0.055]:
            _append(screws, _cylinder_geometry(0.00235, 0.00105, Vector3(x_value, 0.0105, z_value), 28))

    var pitch := 0.00245
    var start_x := -pitch * 31.0 * 0.5
    for index in range(32):
        _append(contacts, _box_geometry(Vector3(0.00142, 0.0032, 0.00052), Vector3(start_x + index * pitch, 0.0019, 0.0)))


func _build_lod1(shell: Dictionary, detail: Dictionary) -> void:
    _append(shell, _rounded_prism(WIDTH, HEIGHT, DEPTH, 0.0045, 0.0, 0.0, 5, 0.00135))
    _append(shell, _rounded_prism(0.088, 0.0102, DEPTH + 0.0008, 0.0020, HEIGHT - 0.0098, 0.0, 4, 0.00042))
    for x_value in [-0.0605, 0.0605]:
        for y_value in [0.022, 0.040, 0.058]:
            _append(shell, _rounded_prism(0.0135, 0.0038, 0.0010, 0.0014, y_value - 0.0019, FRONT + 0.00042, 3, 0.00016), Vector3(x_value, 0.0, 0.0))
    _append(detail, _rounded_prism(0.085, 0.037, 0.00065, 0.0032, 0.0415, FRONT + 0.00066, 6, 0.00010))
    _append(detail, _rounded_prism(0.069, 0.018, 0.00060, 0.0030, 0.0180, FRONT + 0.00066, 5, 0.00010))


func _label_geometry() -> Dictionary:
    var geometry := _rounded_prism(
        0.0795,
        0.031,
        0.00048 if lod_level == 0 else 0.00042,
        0.0026,
        0.0445,
        FRONT + (0.00123 if lod_level == 0 else 0.00112),
        12 if lod_level == 0 else 6,
        0.00008
    )
    geometry["has_uv"] = true
    var vertices: PackedVector3Array = geometry["vertices"]
    var uvs := PackedVector2Array()
    for vertex in vertices:
        uvs.append(Vector2(
            clampf((vertex.x + 0.03975) / 0.0795, 0.0, 1.0),
            clampf((vertex.y - 0.0445) / 0.0310, 0.0, 1.0)
        ))
    geometry["uvs"] = uvs
    return geometry


func _geometry() -> Dictionary:
    return {
        "vertices": PackedVector3Array(),
        "faces": [],
        "uvs": PackedVector2Array(),
        "has_uv": false,
    }


func _append(target: Dictionary, source: Dictionary, translation := Vector3.ZERO) -> void:
    var target_vertices: PackedVector3Array = target["vertices"]
    var source_vertices: PackedVector3Array = source["vertices"]
    var offset := target_vertices.size()
    for vertex in source_vertices:
        target_vertices.append(vertex + translation)
    target["vertices"] = target_vertices

    var target_faces: Array = target["faces"]
    for face: PackedInt32Array in source["faces"]:
        target_faces.append(PackedInt32Array([face[0] + offset, face[1] + offset, face[2] + offset]))
    target["faces"] = target_faces

    var target_uvs: PackedVector2Array = target["uvs"]
    var source_uvs: PackedVector2Array = source["uvs"]
    if bool(source["has_uv"]):
        target["has_uv"] = true
        for uv in source_uvs:
            target_uvs.append(uv)
    else:
        for _vertex in source_vertices:
            target_uvs.append(Vector2.ZERO)
    target["uvs"] = target_uvs


func _commit(geometry: Dictionary) -> ArrayMesh:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var vertices: PackedVector3Array = geometry["vertices"]
    var uvs: PackedVector2Array = geometry["uvs"]
    for face: PackedInt32Array in geometry["faces"]:
        var a := vertices[face[0]]
        var b := vertices[face[1]]
        var c := vertices[face[2]]
        var normal := (b - a).cross(c - a).normalized()
        for index in face:
            surface.set_normal(normal)
            if bool(geometry["has_uv"]):
                surface.set_uv(uvs[index])
            surface.add_vertex(vertices[index])
    return surface.commit()


func _rounded_points(width: float, height: float, radius: float, y_min: float, segments: int) -> PackedVector2Array:
    var points := PackedVector2Array()
    var center_y := y_min + height * 0.5
    var corners := [
        [width * 0.5 - radius, center_y + height * 0.5 - radius, 0.0, 90.0],
        [-width * 0.5 + radius, center_y + height * 0.5 - radius, 90.0, 180.0],
        [-width * 0.5 + radius, center_y - height * 0.5 + radius, 180.0, 270.0],
        [width * 0.5 - radius, center_y - height * 0.5 + radius, 270.0, 360.0],
    ]
    for corner_index in range(corners.size()):
        var corner: Array = corners[corner_index]
        for index in range(segments + 1):
            if corner_index > 0 and index == 0:
                continue
            var angle := deg_to_rad(lerpf(float(corner[2]), float(corner[3]), float(index) / float(segments)))
            points.append(Vector2(
                float(corner[0]) + cos(angle) * radius,
                float(corner[1]) + sin(angle) * radius
            ))
    return points


func _rounded_prism(width: float, height: float, depth: float, radius: float, y_min: float, z_center: float, segments: int, bevel: float) -> Dictionary:
    var geometry := _geometry()
    var outer := _rounded_points(width, height, minf(radius, minf(width, height) * 0.5), y_min, segments)
    var inner := _rounded_points(
        maxf(width - bevel * 2.0, width * 0.8),
        maxf(height - bevel * 2.0, height * 0.8),
        maxf(radius - bevel, 0.0001),
        y_min + bevel,
        segments
    )
    var loops := [
        [inner, z_center - depth * 0.5],
        [outer, z_center - depth * 0.5 + bevel],
        [outer, z_center + depth * 0.5 - bevel],
        [inner, z_center + depth * 0.5],
    ]
    var vertices := PackedVector3Array()
    var faces: Array = []
    var count := outer.size()
    for loop: Array in loops:
        var loop_points: PackedVector2Array = loop[0]
        var z_value: float = loop[1]
        for point in loop_points:
            vertices.append(Vector3(point.x, point.y, z_value))
    for layer in range(3):
        var low := layer * count
        var high := (layer + 1) * count
        for index in range(count):
            var next_index := (index + 1) % count
            faces.append(PackedInt32Array([low + index, low + next_index, high + next_index]))
            faces.append(PackedInt32Array([low + index, high + next_index, high + index]))
    var bottom_center := vertices.size()
    vertices.append(Vector3(0.0, y_min + height * 0.5, z_center - depth * 0.5))
    var top_center := vertices.size()
    vertices.append(Vector3(0.0, y_min + height * 0.5, z_center + depth * 0.5))
    var top_offset := 3 * count
    for index in range(count):
        var next_index := (index + 1) % count
        faces.append(PackedInt32Array([bottom_center, next_index, index]))
        faces.append(PackedInt32Array([top_center, top_offset + index, top_offset + next_index]))
    geometry["vertices"] = vertices
    geometry["faces"] = faces
    return geometry


func _box_geometry(extents: Vector3, center: Vector3) -> Dictionary:
    var geometry := _geometry()
    var half := extents * 0.5
    var vertices := PackedVector3Array([
        Vector3(-half.x, -half.y, -half.z) + center,
        Vector3(half.x, -half.y, -half.z) + center,
        Vector3(half.x, half.y, -half.z) + center,
        Vector3(-half.x, half.y, -half.z) + center,
        Vector3(-half.x, -half.y, half.z) + center,
        Vector3(half.x, -half.y, half.z) + center,
        Vector3(half.x, half.y, half.z) + center,
        Vector3(-half.x, half.y, half.z) + center,
    ])
    geometry["vertices"] = vertices
    geometry["faces"] = [
        PackedInt32Array([0, 2, 1]), PackedInt32Array([0, 3, 2]),
        PackedInt32Array([4, 5, 6]), PackedInt32Array([4, 6, 7]),
        PackedInt32Array([0, 1, 5]), PackedInt32Array([0, 5, 4]),
        PackedInt32Array([1, 2, 6]), PackedInt32Array([1, 6, 5]),
        PackedInt32Array([2, 3, 7]), PackedInt32Array([2, 7, 6]),
        PackedInt32Array([3, 0, 4]), PackedInt32Array([3, 4, 7]),
    ]
    return geometry


func _cylinder_geometry(radius: float, depth: float, center: Vector3, segments: int) -> Dictionary:
    var geometry := _geometry()
    var vertices := PackedVector3Array()
    var faces: Array = []
    for z_value in [center.z - depth * 0.5, center.z + depth * 0.5]:
        for index in range(segments):
            var angle := TAU * float(index) / float(segments)
            vertices.append(Vector3(center.x + cos(angle) * radius, center.y + sin(angle) * radius, z_value))
    var bottom_center := vertices.size()
    vertices.append(Vector3(center.x, center.y, center.z - depth * 0.5))
    var top_center := vertices.size()
    vertices.append(Vector3(center.x, center.y, center.z + depth * 0.5))
    for index in range(segments):
        var next_index := (index + 1) % segments
        faces.append(PackedInt32Array([index, next_index, segments + next_index]))
        faces.append(PackedInt32Array([index, segments + next_index, segments + index]))
        faces.append(PackedInt32Array([bottom_center, next_index, index]))
        faces.append(PackedInt32Array([top_center, segments + index, segments + next_index]))
    geometry["vertices"] = vertices
    geometry["faces"] = faces
    return geometry


func _mesh_instance(node_name: String, mesh: ArrayMesh, material: Material) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    instance.set_meta("triangle_count", mesh.get_faces().size() / 3)
    return instance


func _material(resource_name: String, color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.resource_name = resource_name
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _add_anchor(anchor_name: String, position_value: Vector3) -> void:
    var marker := Marker3D.new()
    marker.name = anchor_name
    marker.position = position_value
    _generated_root.add_child(marker)
