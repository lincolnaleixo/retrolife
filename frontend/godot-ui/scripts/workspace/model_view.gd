extends SubViewportContainer

var viewport_3d: SubViewport
var stage: Node3D
var pivot: Node3D
var camera: Camera3D
var marker: MeshInstance3D
var model: Node3D
var message := ""
var _dragging := false
var _angle := Vector2.ZERO

func _ready() -> void:
    stretch = true
    custom_minimum_size = Vector2(360, 260)
    mouse_default_cursor_shape = Control.CURSOR_DRAG
    viewport_3d = SubViewport.new()
    viewport_3d.own_world_3d = true
    viewport_3d.transparent_bg = true
    viewport_3d.msaa_3d = Viewport.MSAA_4X
    viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
    add_child(viewport_3d)
    stage = Node3D.new()
    viewport_3d.add_child(stage)
    pivot = Node3D.new()
    stage.add_child(pivot)
    var world := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_CLEAR_COLOR
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color.WHITE
    environment.ambient_light_energy = 0.65
    world.environment = environment
    stage.add_child(world)
    for rotation in [Vector3(-25, -30, 0), Vector3(15, 140, 0)]:
        var light := DirectionalLight3D.new()
        light.rotation_degrees = rotation
        light.light_energy = 0.8
        stage.add_child(light)
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.near = 0.001
    camera.far = 10
    camera.size = 0.14
    camera.position = Vector3(0, 0.031, 0.35)
    stage.add_child(camera)
    camera.current = true
    marker = MeshInstance3D.new()
    var ring := TorusMesh.new()
    ring.inner_radius = 0.0065
    ring.outer_radius = 0.008
    marker.mesh = ring
    marker.rotation.x = PI / 2
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("65e7c7")
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    marker.material_override = material
    marker.hide()
    pivot.add_child(marker)
    gui_input.connect(_input_view)

func load_model(path: String) -> bool:
    if model != null:
        model.free()
        model = null
    if path.is_empty():
        message = "Link your local 3D collection in Storage & assets."
        return false
    # Only self-contained GLBs; never fetch external buffers or textures.
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null or file.get_length() > 80 * 1024 * 1024 or file.get_length() < 20:
        message = "The local model cannot be opened."
        return false
    if file.get_32() != 0x46546c67 or file.get_32() != 2:
        return false
    file.get_32()
    var json_length := file.get_32()
    if file.get_32() != 0x4e4f534a or json_length > 4 * 1024 * 1024:
        return false
    var document_data: Variant = JSON.parse_string(file.get_buffer(json_length).get_string_from_utf8())
    if not document_data is Dictionary:
        return false
    for resource in document_data.get("images", []) + document_data.get("buffers", []):
        if resource.has("uri"):
            message = "Use an embedded GLB without external resources."
            return false
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    if document.append_from_file(path, state) != OK:
        message = "The local GLB could not be loaded."
        return false
    model = document.generate_scene(state)
    pivot.add_child(model)
    message = "Drag to rotate · Scroll to zoom"
    reset_view()
    return true

func reset_view() -> void:
    _angle = Vector2.ZERO
    pivot.transform = Transform3D.IDENTITY
    camera.size = 0.14

func highlight(action: String) -> void:
    var points := {"up": Vector2(-43, 9), "down": Vector2(-43, -9), "left": Vector2(-52, 0), "right": Vector2(-34, 0), "north": Vector2(43, 12), "west": Vector2(31, 0), "east": Vector2(55, 0), "south": Vector2(43, -12), "select": Vector2(-9, -7), "start": Vector2(8, -7), "left_shoulder": Vector2(-40, 29), "right_shoulder": Vector2(40, 29)}
    marker.visible = model != null and points.has(action)
    if marker.visible:
        var point: Vector2 = points[action]
        marker.position = Vector3(point.x * 0.001, point.y * 0.001 + 0.031, 0.019)

func _input_view(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            _dragging = event.pressed
        if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
            camera.size = clampf(camera.size * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.09, 0.32)
        accept_event()
    elif event is InputEventMouseMotion and _dragging:
        _angle += event.relative * 0.006
        var center := Vector3(0, 0.031, 0)
        var basis_value := Basis.from_euler(Vector3(clampf(_angle.y, -1.2, 1.2), _angle.x, 0))
        pivot.transform = Transform3D(basis_value, center - basis_value * center)
        accept_event()
