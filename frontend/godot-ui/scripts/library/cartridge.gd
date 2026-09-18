extends Node3D

## One pooled cartridge. Geometry is shared, per-game display materials are not.
const MODEL_PATH := "res://assets/cartridges/snes-ntsc-u.glb"
const MODEL_SCALE := 24.0
const LabelPainter = preload("res://scripts/library/label_painter.gd")
const PALETTE := [Color("8b7db7"), Color("659c9b"), Color("c29468"), Color("9a7995"), Color("6f91bb")]
static var _shared_model: PackedScene

var force_fallback := false
var uses_fallback := true
var game_id := ""
var library_index := -1
var _visual: Node3D
var _label_surface: MeshInstance3D
var _rear_surface: MeshInstance3D
var _label_viewport: SubViewport
var _label_canvas: Node2D
var _painter_material: StandardMaterial3D
var _movement: Tween
var _selected := false
var _motion_enabled := true
var _artwork_present := false
var _pointer := Vector2.ZERO
var _inspect_yaw := 0.0
var _inspect_pitch := 0.0
var _inspect_zoom := 1.0


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
            _soften_shell_materials(model)
            _visual.add_child(model)
            var surfaces := _find_label_surfaces(model)
            _label_surface = surfaces.get("front")
            _rear_surface = surfaces.get("rear")
            uses_fallback = false
    if uses_fallback:
        _build_fallback()
    if _label_surface == null:
        # Unknown model layout: use a separate front-facing surface, never fail browsing.
        _label_surface = MeshInstance3D.new()
        var plane := QuadMesh.new()
        plane.size = Vector2(1.96, 0.87)
        _label_surface.mesh = plane
        _label_surface.position = Vector3(0.0, 0.57, 0.28)
        _visual.add_child(_label_surface)
    _label_viewport = SubViewport.new()
    _label_viewport.name = "LocalLabel"
    _label_viewport.size = Vector2i(1024, 512)
    _label_viewport.disable_3d = true
    _label_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    _label_viewport.transparent_bg = false
    add_child(_label_viewport)
    _label_canvas = LabelPainter.new()
    _label_viewport.add_child(_label_canvas)
    _painter_material = StandardMaterial3D.new()
    _painter_material.albedo_texture = _label_viewport.get_texture()
    _painter_material.roughness = 0.82
    _painter_material.metallic_specular = 0.1
    _painter_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
    _painter_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    # Runtime-only material override retains the released mesh, UVs and folded top.
    # The source GLB on disk is never rewritten or re-exported with game artwork.
    _label_surface.material_override = _painter_material
    var anchor := Marker3D.new()
    anchor.name = "CameraAnchor"
    anchor.position = Vector3(0, 0, 0.25)
    add_child(anchor)


func bind_game(game: Dictionary, index: int, artwork: Texture2D, rear_artwork: Texture2D = null) -> void:
    game_id = str(game.get("id", ""))
    library_index = index
    var tone: Color = PALETTE[posmod(game_id.hash(), PALETTE.size())]
    _artwork_present = artwork != null
    if artwork != null and _label_proportioned(artwork):
        # Label-shaped artwork is applied straight to the mesh: the source
        # resolution survives and mipmapped anisotropic sampling keeps the
        # folded top crisp instead of resampling through the 1024 canvas.
        _label_surface.material_override = _surface_material(artwork)
    else:
        _label_canvas.call("configure", game, index, tone, artwork)
        _label_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
        _label_surface.material_override = _painter_material
    if _rear_surface != null:
        if rear_artwork != null:
            _rear_surface.material_override = _surface_material(rear_artwork)
        else:
            _rear_surface.material_override = null


static func _label_proportioned(texture: Texture2D) -> bool:
    var size := texture.get_size()
    if size.y <= 0.0:
        return false
    return absf(size.x / size.y - 2.0) <= 0.16


static func _soften_shell_materials(node: Node) -> void:
    # Molded edges in the pinned model are sharp; under the showcase lights a
    # default specular response draws a bright line along them. Soften the
    # response with runtime material copies; the released GLB stays untouched.
    if node is MeshInstance3D:
        var mesh := node as MeshInstance3D
        var surfaces := mesh.get_surface_override_material_count()
        for surface in range(surfaces):
            var material := mesh.get_active_material(surface)
            if material is StandardMaterial3D and (material as StandardMaterial3D).metallic_specular > 0.1:
                var copy := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
                copy.metallic_specular = 0.1
                if surfaces == 1:
                    mesh.material_override = copy
                else:
                    mesh.set_surface_override_material(surface, copy)
    for child in node.get_children():
        _soften_shell_materials(child)


static func _surface_material(texture: Texture2D) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_texture = texture
    material.roughness = 0.82
    material.metallic_specular = 0.1
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func place(target: Vector3, angles: Vector3, size_factor: float, selected: bool, animate: bool) -> void:
    if _movement != null and _movement.is_valid():
        _movement.kill()
    _selected = selected
    if not selected and (_pointer != Vector2.ZERO or _inspect_yaw != 0.0 or _inspect_pitch != 0.0 or _inspect_zoom != 1.0):
        _pointer = Vector2.ZERO
        _inspect_yaw = 0.0
        _inspect_pitch = 0.0
        _inspect_zoom = 1.0
        _visual.position.y = 0.0
        _apply_visual()
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
        _pointer = Vector2.ZERO
    _apply_visual()


func set_pointer(normalized: Vector2) -> void:
    _pointer = normalized if _selected and _motion_enabled else Vector2.ZERO
    _apply_visual()


func set_inspection(yaw: float, pitch: float, zoom: float, float_offset: float) -> void:
    _inspect_yaw = yaw
    _inspect_pitch = pitch
    _inspect_zoom = zoom
    _visual.position.y = float_offset
    _apply_visual()


func inspection_state() -> Vector3:
    return Vector3(_inspect_yaw, _inspect_pitch, _inspect_zoom)


func _apply_visual() -> void:
    _visual.rotation = Vector3(
        _inspect_pitch - _pointer.y * 0.035,
        _inspect_yaw + _pointer.x * 0.055,
        0.0
    )
    _visual.scale = Vector3.ONE * _inspect_zoom


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


func _build_fallback() -> void:
    _box(Vector3(3.25, 2.04, 0.40), Vector3.ZERO, Color("9798a1"))
    _box(Vector3(2.22, 2.09, 0.43), Vector3(0, 0.02, 0), Color("a9aab1"))
    for side in [-1, 1]:
        for groove in range(5):
            _box(Vector3(0.32, 0.028, 0.014), Vector3(side * 1.39, 0.58 - groove * 0.17, 0.21), Color("74757f"))
    _box(Vector3(1.20, 0.10, 0.25), Vector3(0, -1.02, 0), Color("555660"))


static func _find_label_surfaces(node: Node) -> Dictionary:
    # The pinned neutral GLB and prepared per-game exports share the same
    # continuous front-label and rear printed-information meshes; identify
    # them by name first and the label material family second.
    var front: MeshInstance3D = null
    var rear: MeshInstance3D = null
    var fallback: MeshInstance3D = null
    for candidate in _label_candidates(node):
        var candidate_name := str(candidate.name).to_lower()
        if "front" in candidate_name:
            if front == null:
                front = candidate
        elif "rear" in candidate_name:
            if rear == null:
                rear = candidate
        elif fallback == null:
            fallback = candidate
    if front == null:
        front = fallback
        fallback = null
    if rear == null and fallback != null:
        rear = fallback
    return {"front": front, "rear": rear}


static func _label_candidates(node: Node) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        var material := mesh_instance.get_active_material(0)
        var material_name := str(material.resource_name).to_lower() if material != null else ""
        if "label" in material_name or "label" in str(mesh_instance.name).to_lower():
            result.append(mesh_instance)
    for child in node.get_children():
        result.append_array(_label_candidates(child))
    return result
