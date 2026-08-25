extends Node3D

const ASSET_ID := "retrolife.snes.na-cartridge.m2.2.front.v2"
const PRIOR_ASSET_ID := "retrolife.snes.na-cartridge.m2.2.front.v1"
const SOURCE := "original-parametric-continuous-surface-rebuild"
const WIDTH_MM := 136.000000
const HEIGHT_MM := 88.000000
const DEPTH_MM := 20.000000
const CENTRAL_WIDTH_MM := 83.000000
const TOP_DROP_MM := 6.500000
const FRONT_DEPTH_MM := 10.400000
const LABEL_WIDTH_MM := 83.000000
const LABEL_HEIGHT_MM := 38.500000
const LABEL_BOTTOM_MM := 47.000000
const LABEL_RADIUS_MM := 4.000000
const SCREW_X_MM := 54.500000
const SCREW_Y_MM := 10.000000
const SCREW_RADIUS_MM := 2.600000
const GROOVE_HEIGHT_MM := 1.200000
const GROOVE_CENTERS_MM := [17.500000, 31.500000, 45.500000, 59.500000, 73.500000]
const GRID_COLUMNS := 88
const GRID_STEP_MM := 1.000000
const EXPECTED_SHELL_TRIANGLES := 33460
const EXPECTED_SHELL_VERTICES := 16732

var _shell: MeshInstance3D
var _label: MeshInstance3D

func _ready() -> void:
    _build_asset()

func m2_manifest() -> Dictionary:
    return {
        "assetId": ASSET_ID,
        "priorAssetId": PRIOR_ASSET_ID,
        "source": SOURCE,
        "status": "provisional-continuous-surface-rebuild",
        "surfaceTopology": "single-connected-watertight-shell",
        "shellTriangles": EXPECTED_SHELL_TRIANGLES,
        "shellVertices": EXPECTED_SHELL_VERTICES,
        "physicalCalibrationComplete": false,
        "priorGeometryAccepted": false,
        "mayApproveFinalGeometry": false,
        "mayStartM2_3Blockout": false,
        "mayStartM3": false,
    }

func _build_asset() -> void:
    set_meta("asset_id", ASSET_ID)
    set_meta("prior_asset_id", PRIOR_ASSET_ID)
    set_meta("source", SOURCE)
    set_meta("license", "CC0-1.0")
    set_meta("status", "provisional-continuous-surface-rebuild")
    set_meta("console_visible", false)
    set_meta("physical_calibration_complete", false)
    set_meta("prior_geometry_accepted", false)
    set_meta("may_approve_final_geometry", false)
    set_meta("may_start_m2_3_blockout", false)
    set_meta("may_start_m3", false)

    _shell = MeshInstance3D.new()
    _shell.name = "ContinuousShell"
    _shell.mesh = _build_shell_mesh()
    _shell.material_override = _material("M2.2 v2 shell clay", Color("b0b4bd"), 0.76)
    _shell.set_meta("surface_topology", "single-connected-watertight-shell")
    _shell.set_meta("triangle_count", EXPECTED_SHELL_TRIANGLES)
    add_child(_shell)

    _label = MeshInstance3D.new()
    _label.name = "LabelSurface"
    _label.mesh = _build_label_mesh()
    _label.material_override = _material("M2.2 v2 label placeholder", Color("8f96a3"), 0.72)
    _label.set_meta("m3_texture_slot", "snes-front-label")
    add_child(_label)

    _anchor("DockPivot", Vector3.ZERO)
    _anchor("CenterOfMass", Vector3(0.0, 0.044, 0.0052))
    _anchor("LabelAnchor", Vector3(0.0, 0.06625, (FRONT_DEPTH_MM - 0.88) / 1000.0))
    _anchor("ConnectorAnchor", Vector3.ZERO)
    var focused := _anchor("BrowseFocusedAnchor", Vector3.ZERO)
    focused.rotation_degrees = Vector3(-5, -9, 0)
    var approach := _anchor("DockApproachAnchor", Vector3.ZERO)
    approach.rotation_degrees = Vector3(-2, -2, 0)

func _build_rows() -> Array[Vector2]:
    var wing_top := HEIGHT_MM - TOP_DROP_MM
    var controls: Array[Vector2] = [
        Vector2(0.0, 64.0),
        Vector2(1.2, 66.5),
        Vector2(4.2, 68.0),
        Vector2(wing_top - 4.0, 68.0),
        Vector2(wing_top - 1.4, 66.8),
        Vector2(wing_top, 64.0),
        Vector2(wing_top, CENTRAL_WIDTH_MM * 0.5 + 2.5),
        Vector2(wing_top + 1.4, CENTRAL_WIDTH_MM * 0.5 + 0.9),
        Vector2(HEIGHT_MM - 2.2, CENTRAL_WIDTH_MM * 0.5 + 0.9),
        Vector2(HEIGHT_MM, CENTRAL_WIDTH_MM * 0.5 - 1.0),
    ]
    var rows: Array[Vector2] = []
    for index in range(controls.size() - 1):
        var start := controls[index]
        var finish := controls[index + 1]
        if is_equal_approx(start.x, finish.x):
            if rows.is_empty() or rows.back() != start:
                rows.append(start)
            rows.append(finish)
            continue
        var steps := maxi(1, ceili((finish.x - start.x) / GRID_STEP_MM))
        for step in range(steps):
            var t := float(step) / float(steps)
            var row := start.lerp(finish, t)
            if rows.is_empty() or rows.back() != row:
                rows.append(row)
    rows.append(controls.back())
    return rows

func _build_shell_mesh() -> ArrayMesh:
    var rows := _build_rows()
    var row_count := rows.size()
    var cols := GRID_COLUMNS + 1
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()

    for row in rows:
        var y := row.x
        var half_width := row.y
        for col in range(cols):
            var t := float(col) / float(GRID_COLUMNS)
            var x := lerpf(-half_width, half_width, t)
            vertices.append(Vector3(x, y, _front_surface_z(x, y)) / 1000.0)

    var seam_offset := vertices.size()
    for row in rows:
        var y := row.x
        var half_width := row.y
        for col in range(cols):
            var t := float(col) / float(GRID_COLUMNS)
            var x := lerpf(-half_width, half_width, t)
            vertices.append(Vector3(x, y, 0.0) / 1000.0)

    for row_index in range(row_count - 1):
        for col in range(GRID_COLUMNS):
            var a := row_index * cols + col
            var b := a + 1
            var c := (row_index + 1) * cols + col
            var d := c + 1
            _tri(indices, a, c, d)
            _tri(indices, a, d, b)
            var sa := a + seam_offset
            var sb := b + seam_offset
            var sc := c + seam_offset
            var sd := d + seam_offset
            _tri(indices, sa, sd, sc)
            _tri(indices, sa, sb, sd)

    var boundary := PackedInt32Array()
    for col in range(cols):
        boundary.append(col)
    for row_index in range(1, row_count):
        boundary.append(row_index * cols + GRID_COLUMNS)
    for col in range(GRID_COLUMNS - 1, -1, -1):
        boundary.append((row_count - 1) * cols + col)
    for row_index in range(row_count - 2, 0, -1):
        boundary.append(row_index * cols)

    for index in range(boundary.size()):
        var front_a := boundary[index]
        var front_b := boundary[(index + 1) % boundary.size()]
        var seam_a := front_a + seam_offset
        var seam_b := front_b + seam_offset
        _tri(indices, front_a, front_b, seam_b)
        _tri(indices, front_a, seam_b, seam_a)

    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for vertex in vertices:
        surface.add_vertex(vertex)
    for index in indices:
        surface.add_index(index)
    surface.generate_normals()
    return surface.commit()

func _build_label_mesh() -> ArrayMesh:
    var z := (FRONT_DEPTH_MM - 0.88) / 1000.0
    var left := -LABEL_WIDTH_MM * 0.5 / 1000.0
    var right := LABEL_WIDTH_MM * 0.5 / 1000.0
    var bottom := LABEL_BOTTOM_MM / 1000.0
    var top := (LABEL_BOTTOM_MM + LABEL_HEIGHT_MM) / 1000.0
    var vertices := [
        Vector3(left, bottom, z),
        Vector3(right, bottom, z),
        Vector3(right, top, z),
        Vector3(left, top, z),
    ]
    var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index in range(vertices.size()):
        surface.set_uv(uvs[index])
        surface.set_normal(Vector3(0, 0, 1))
        surface.add_vertex(vertices[index])
    for index in [0, 1, 2, 0, 2, 3]:
        surface.add_index(index)
    return surface.commit()

func _front_surface_z(x: float, y: float) -> float:
    var nx := absf(x) / (WIDTH_MM * 0.5)
    var ny := absf((y - HEIGHT_MM * 0.48) / (HEIGHT_MM * 0.52))
    var crown := 0.34 * (1.0 - pow(clampf(nx, 0.0, 1.0), 1.8)) * (1.0 - pow(clampf(ny, 0.0, 1.0), 2.2))
    var edge_ease := 0.18 * pow(clampf(nx, 0.0, 1.0), 2.0)
    var z := FRONT_DEPTH_MM - 0.28 + crown - edge_ease

    var label_distance := _rounded_box_sdf(x, y, 0.0, LABEL_BOTTOM_MM + LABEL_HEIGHT_MM * 0.5, LABEL_WIDTH_MM * 0.5, LABEL_HEIGHT_MM * 0.5, LABEL_RADIUS_MM)
    var label_blend := _recess_weight(label_distance, 1.15)
    z = lerpf(z, FRONT_DEPTH_MM - 0.92, label_blend)

    var channel_distance := _rounded_box_sdf(x, y, 0.0, 28.0, 36.0, 2.6, 2.6)
    z -= 0.82 * _recess_weight(channel_distance, 0.85)

    var central_half := CENTRAL_WIDTH_MM * 0.5
    var wing_inner := central_half + 1.8
    for center_y in GROOVE_CENTERS_MM:
        for sign_value in [-1.0, 1.0]:
            var center_x: float = float(sign_value) * ((wing_inner + WIDTH_MM * 0.5) * 0.5)
            var groove_width := WIDTH_MM * 0.5 - wing_inner - 1.4
            var groove_distance := _rounded_box_sdf(x, y, center_x, center_y, groove_width * 0.5, GROOVE_HEIGHT_MM * 0.5, GROOVE_HEIGHT_MM * 0.45)
            z -= 0.52 * _recess_weight(groove_distance, 0.40)

    for screw_x in [-SCREW_X_MM, SCREW_X_MM]:
        var screw_distance := Vector2(x - screw_x, y - SCREW_Y_MM).length() - SCREW_RADIUS_MM
        z -= 1.15 * _recess_weight(screw_distance, 0.75)
    return maxf(6.0, z)

func _rounded_box_sdf(x: float, y: float, center_x: float, center_y: float, half_width: float, half_height: float, radius: float) -> float:
    var qx := absf(x - center_x) - (half_width - radius)
    var qy := absf(y - center_y) - (half_height - radius)
    var outside := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length()
    var inside := minf(maxf(qx, qy), 0.0)
    return outside + inside - radius

func _recess_weight(distance: float, feather: float) -> float:
    return 1.0 - _smoothstep(-feather, feather, distance)

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
    if is_equal_approx(edge0, edge1):
        return 1.0 if x >= edge1 else 0.0
    var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

func _tri(indices: PackedInt32Array, a: int, b: int, c: int) -> void:
    indices.append(a)
    indices.append(b)
    indices.append(c)

func _material(name_value: String, color_value: Color, roughness_value: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.resource_name = name_value
    material.albedo_color = color_value
    material.metallic = 0.0
    material.roughness = roughness_value
    return material

func _anchor(name_value: String, position_value: Vector3) -> Marker3D:
    var marker := Marker3D.new()
    marker.name = name_value
    marker.position = position_value
    add_child(marker)
    return marker
