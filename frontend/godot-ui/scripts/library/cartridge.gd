extends Node3D

## One pooled cartridge. Geometry is shared, per-game artwork is not.
const MODEL_PATH := "res://assets/cartridges/snes-ntsc-u.glb"
const MODEL_SCALE := 24.0
const PALETTE := [Color("8b7db7"), Color("659c9b"), Color("c29468"), Color("9a7995"), Color("6f91bb")]
static var _shared_model: PackedScene

var force_fallback := false
var uses_fallback := true
var game_id := ""
var library_index := -1
var _visual: Node3D
var _plate: MeshInstance3D
var _stripe: MeshInstance3D
var _title: Label3D
var _system: Label3D
var _number: Label3D
var _movement: Tween
var _target_rotation := Vector3.ZERO
var _selected := false
var _motion_enabled := true
var _artwork_present := false


func _ready() -> void:
    _visual = Node3D.new()
    _visual.name = "VisualPivot"
    add_child(_visual)
    if not force_fallback and _shared_model == null and ResourceLoader.exists(MODEL_PATH):
        _shared_model = load(MODEL_PATH) as PackedScene
    if not force_fallback and _shared_model != null:
        var model := _shared_model.instantiate() as Node3D
        if model != null:
            model.scale = Vector3.ONE * MODEL_SCALE
            model.position.y = -0.044 * MODEL_SCALE
            _visual.add_child(model)
            uses_fallback = false
    if uses_fallback:
        _build_fallback()
    # Independent runtime display layer; the released model stays unchanged.
    _plate = _box(Vector3(2.05, 1.46, 0.018), Vector3(0.0, 0.13, 0.255), Color("242531"))
    _stripe = _box(Vector3(2.05, 0.045, 0.022), Vector3(0.0, 0.84, 0.268), PALETTE[0])
    _title = _text("", Vector3(0.0, 0.18, 0.274), 72, 0.0018)
    _system = _text("SUPER NINTENDO", Vector3(0.0, 0.68, 0.275), 36, 0.0016)
    _system.modulate = Color("c7c9d4")
    _number = _text("", Vector3(0.0, -0.43, 0.275), 32, 0.0015)
    _number.modulate = Color("bab9c8")
    var anchor := Marker3D.new()
    anchor.name = "CameraAnchor"
    anchor.position = Vector3(0, 0, 0.25)
    add_child(anchor)


func bind_game(game: Dictionary, index: int, artwork: Texture2D) -> void:
    game_id = str(game.get("id", ""))
    library_index = index
    var tone: Color = PALETTE[posmod(game_id.hash(), PALETTE.size())]
    var material := StandardMaterial3D.new()
    material.albedo_color = Color.WHITE if artwork != null else tone.darkened(0.68)
    material.albedo_texture = artwork
    material.roughness = 0.78
    # Use the plane's UVs, not a box atlas, for user artwork.
    if artwork != null:
        var plane := QuadMesh.new()
        plane.size = Vector2(2.05, 1.46)
        _plate.mesh = plane
        _plate.position = Vector3(0, 0.13, 0.267)
    else:
        var box := BoxMesh.new()
        box.size = Vector3(2.05, 1.46, 0.018)
        _plate.mesh = box
        _plate.position = Vector3(0, 0.13, 0.255)
    _plate.material_override = material
    (_stripe.material_override as StandardMaterial3D).albedo_color = tone
    _title.text = _wrap_title(str(game.get("title", "Untitled")))
    _system.text = "SUPER NINTENDO" if str(game.get("systemId", "")) == "snes" else str(game.get("systemName", "RETROLIFE")).to_upper()
    _number.text = "%03d  /  RETROLIFE COLLECTION" % (index + 1)
    _artwork_present = artwork != null
    _title.visible = not _artwork_present
    _system.visible = not _artwork_present
    _number.visible = not _artwork_present


func place(target: Vector3, angles: Vector3, size_factor: float, selected: bool, animate: bool) -> void:
    if _movement != null and _movement.is_valid():
        _movement.kill()
    _selected = selected
    _target_rotation = angles
    if not animate or not visible:
        position = target
        rotation = angles
        scale = Vector3.ONE * size_factor
    else:
        _movement = create_tween().set_parallel(true)
        _movement.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        _movement.tween_property(self, "position", target, 0.22)
        _movement.tween_property(self, "rotation", angles, 0.22)
        _movement.tween_property(self, "scale", Vector3.ONE * size_factor, 0.22)
    visible = true


func set_motion_enabled(enabled: bool) -> void:
    _motion_enabled = enabled
    if not enabled:
        _visual.rotation = Vector3.ZERO


func set_pointer(normalized: Vector2) -> void:
    if _selected and _motion_enabled:
        _visual.rotation = Vector3(-normalized.y * 0.022, normalized.x * 0.035, 0)
    else:
        _visual.rotation = Vector3.ZERO


func _box(dimensions: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.76
    instance.mesh = mesh
    instance.material_override = material
    instance.position = at
    _visual.add_child(instance)
    return instance


func _text(value: String, at: Vector3, font_size: int, pixel_size: float) -> Label3D:
    var label := Label3D.new()
    label.text = value
    label.position = at
    label.font_size = font_size
    label.pixel_size = pixel_size
    label.outline_size = 0
    label.modulate = Color("f3f0f7")
    label.no_depth_test = false
    _visual.add_child(label)
    return label


func _build_fallback() -> void:
    _box(Vector3(3.25, 2.04, 0.40), Vector3.ZERO, Color("9798a1"))
    _box(Vector3(2.22, 2.09, 0.43), Vector3(0, 0.02, 0), Color("a9aab1"))
    for side in [-1, 1]:
        for groove in range(5):
            _box(Vector3(0.32, 0.028, 0.014), Vector3(side * 1.39, 0.58 - groove * 0.17, 0.21), Color("74757f"))
    _box(Vector3(1.20, 0.10, 0.25), Vector3(0, -1.02, 0), Color("555660"))


static func _wrap_title(value: String) -> String:
    var words := value.left(90).split(" ", false)
    var lines: Array[String] = []
    var line := ""
    for word in words:
        if not line.is_empty() and line.length() + word.length() > 18:
            lines.append(line)
            line = ""
        line += (" " if not line.is_empty() else "") + word.left(22)
    if not line.is_empty():
        lines.append(line)
    if lines.size() > 4:
        lines.resize(4)
        lines[3] = lines[3].left(16) + "..."
    return "\n".join(lines)
