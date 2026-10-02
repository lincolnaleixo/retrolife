extends Node3D

## One pooled physical-media slot. Geometry is shared; game artwork is not.
const MODEL_PATH := "res://assets/cartridges/snes-ntsc-u.glb"
const MODEL_SCALE := 24.0
const MediaProfiles = preload("res://scripts/library/media_profiles.gd")
const LabelPainter = preload("res://scripts/library/label_painter.gd")
const PALETTE := [Color("8b7db7"), Color("659c9b"), Color("c29468"), Color("9a7995"), Color("6f91bb")]
static var _shared_models: Dictionary = {}
static var _soft_materials: Dictionary = {}
static var _full_detail_labels: Dictionary = {}

var force_fallback := false
var preserve_imported_artwork := false
var media_profile := ""
var _built_fallback := false
var _profile: Dictionary = {}
var uses_fallback := true
var game_id := ""
var library_index := -1
var _visual: Node3D
var _visual_bounds := AABB()
var _label_surface: MeshInstance3D
var _rear_surface: MeshInstance3D
var _rear_default_material: Material
var _front_source_material: Material
var _rear_source_material: Material
var _label_viewport: SubViewport
var _label_canvas: Node2D
var _painter_material: StandardMaterial3D
var _rear_viewport: SubViewport
var _rear_canvas: Node2D
var _rear_painter_material: StandardMaterial3D
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
    _label_viewport = SubViewport.new()
    _label_viewport.name = "LocalLabel"
    _label_viewport.size = Vector2i(1024, 512)
    _label_viewport.disable_3d = true
    _label_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    _label_viewport.transparent_bg = false
    add_child(_label_viewport)
    _label_canvas = LabelPainter.new()
    _label_viewport.add_child(_label_canvas)
    # Runtime-only material override retains the released mesh, UVs and folded top.
    # The source GLB on disk is never rewritten or re-exported with game artwork.
    _ensure_model({"systemId": "snes"})
    var anchor := Marker3D.new()
    anchor.name = "CameraAnchor"
    anchor.position = Vector3(0, 0, 0.25)
    add_child(anchor)


func _ensure_model(game: Dictionary) -> void:
    var requested := MediaProfiles.id_for(game)
    if requested == media_profile and _built_fallback == force_fallback:
        return
    media_profile = requested
    _built_fallback = force_fallback
    _profile = MediaProfiles.for_game(game)
    # A pool slot can change systems. Free its old visual immediately so rapid
    # rebinds cannot accumulate hidden model trees or stale label references.
    for child in _visual.get_children():
        child.free()
    _label_surface = null
    _rear_surface = null
    _rear_default_material = null
    _front_source_material = null
    _rear_source_material = null
    _rear_painter_material = null
    _visual_bounds = AABB()
    uses_fallback = true
    var path: String = _profile["path"]
    if not force_fallback and not path.is_empty():
        if not _shared_models.has(path) and ResourceLoader.exists(path):
            _shared_models[path] = load(path) as PackedScene
        var scene := _shared_models.get(path) as PackedScene
        if scene != null:
            var model := scene.instantiate() as Node3D
            if model != null:
                _visual.add_child(model)
                if media_profile == "snes":
                    # Preserve the published model's framing and folded UVs.
                    model.scale = Vector3.ONE * MODEL_SCALE
                    model.position.y = -0.044 * MODEL_SCALE
                else:
                    var bounds := _bounds_in(model)
                    var factor := minf(3.3 / maxf(bounds.size.x, 0.001), 2.4 / maxf(bounds.size.y, 0.001))
                    model.scale = Vector3.ONE * factor
                    model.position = -bounds.get_center() * factor
                if media_profile == "snes":
                    _soften_shell_materials(model)
                var surfaces := _find_label_surfaces(model)
                _label_surface = surfaces.get("front")
                _rear_surface = surfaces.get("rear")
                for label in [_label_surface, _rear_surface]:
                    if label != null and label.mesh != null:
                        label.mesh = _label_mesh_without_lods(label.mesh)
                if _rear_surface != null:
                    _rear_default_material = _rear_surface.material_override
                uses_fallback = false
    if uses_fallback:
        _build_fallback()
    if _label_surface == null:
        _label_surface = MeshInstance3D.new()
        var plane := QuadMesh.new()
        plane.size = Vector2(1.96, 0.87) if media_profile == "snes" else Vector2(1.96, 1.96 / float(_profile["front_ratio"]))
        _label_surface.mesh = plane
        _label_surface.position = Vector3(0.0, 0.57 if media_profile == "snes" else 0.0, 0.28)
        _visual.add_child(_label_surface)
    _visual_bounds = _bounds_in(_visual)
    _label_viewport.size = _profile["canvas"]
    _front_source_material = _label_surface.get_active_material(0)
    if _rear_surface != null:
        _rear_source_material = _rear_surface.get_active_material(0)
    _painter_material = _surface_material(_label_viewport.get_texture(), _front_source_material)
    _label_surface.material_override = _painter_material


static func _bounds_in(pivot: Node3D) -> AABB:
    var bounds := AABB()
    var first := true
    for candidate in pivot.find_children("*", "MeshInstance3D", true, false):
        var mesh := candidate as MeshInstance3D
        if mesh.mesh == null:
            continue
        var relative := pivot.global_transform.affine_inverse() * mesh.global_transform
        var next := relative * mesh.get_aabb()
        bounds = next if first else bounds.merge(next)
        first = false
    return bounds


func bind_game(game: Dictionary, index: int, artwork: Texture2D, rear_artwork: Texture2D = null) -> void:
    _ensure_model(game)
    game_id = str(game.get("id", ""))
    library_index = index
    var tone: Color = PALETTE[posmod(game_id.hash(), PALETTE.size())]
    _artwork_present = artwork != null
    if preserve_imported_artwork and artwork == null and not uses_fallback:
        # Owner-only preview GLBs can contain multiple mapped label surfaces.
        _label_surface.material_override = null
    elif artwork != null and _label_proportioned(artwork, float(_profile["front_ratio"])):
        # Label-shaped artwork is applied straight to the mesh: the source
        # resolution survives and mipmapped anisotropic sampling keeps the
        # folded top crisp instead of resampling through the 1024 canvas.
        _label_surface.material_override = _surface_material(artwork, _front_source_material)
    else:
        _label_canvas.call("configure", game, index, tone, artwork, _profile)
        _label_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
        _label_surface.material_override = _painter_material
    if _rear_surface != null:
        if rear_artwork != null:
            if media_profile == "snes" or _label_proportioned(rear_artwork, float(_profile["rear_ratio"])):
                _rear_surface.material_override = _surface_material(rear_artwork, _rear_source_material)
            else:
                _rear_surface.material_override = _compose_rear(game, index, tone, rear_artwork)
        else:
            # Keep the softened unprinted material from model setup; a bare
            # null would restore the original bright specular response.
            _rear_surface.material_override = _rear_default_material


func _compose_rear(game: Dictionary, index: int, tone: Color, artwork: Texture2D) -> Material:
    if _rear_viewport == null:
        _rear_viewport = SubViewport.new()
        _rear_viewport.name = "LocalRearLabel"
        _rear_viewport.disable_3d = true
        _rear_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
        add_child(_rear_viewport)
        _rear_canvas = LabelPainter.new()
        _rear_viewport.add_child(_rear_canvas)
    if _rear_painter_material == null:
        _rear_painter_material = _surface_material(_rear_viewport.get_texture(), _rear_source_material)
    var rear_profile := _profile.duplicate()
    rear_profile["front_ratio"] = _profile["rear_ratio"]
    rear_profile["top_fold_ratio"] = 0.0
    rear_profile["canvas"] = Vector2i(1024, roundi(1024.0 / float(_profile["rear_ratio"])))
    _rear_viewport.size = rear_profile["canvas"]
    _rear_canvas.call("configure", game, index, tone, artwork, rear_profile)
    _rear_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    return _rear_painter_material


static func _label_mesh_without_lods(source: Mesh) -> Mesh:
    if _full_detail_labels.has(source):
        return _full_detail_labels[source]
    # Automatic simplification preserves the silhouette but interpolates UVs
    # across the folded paper, bending printed letters. Keep original label
    # triangles at every distance; the much larger shell retains its LODs.
    # Share this runtime copy across the pool and leave the pinned GLB intact.
    var mesh := ArrayMesh.new()
    mesh.resource_name = source.resource_name + " Full Detail"
    for surface in range(source.get_surface_count()):
        mesh.add_surface_from_arrays(
            source.surface_get_primitive_type(surface),
            source.surface_get_arrays(surface)
        )
        mesh.surface_set_material(surface, source.surface_get_material(surface))
    _full_detail_labels[source] = mesh
    return mesh


static func _label_proportioned(texture: Texture2D, aspect := 2.0) -> bool:
    var size := texture.get_size()
    if size.y <= 0.0:
        return false
    return absf(size.x / size.y - aspect) <= aspect * 0.08


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
                if not _soft_materials.has(material):
                    var softened := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
                    softened.metallic_specular = 0.1
                    _soft_materials[material] = softened
                var copy := _soft_materials[material] as StandardMaterial3D
                if surfaces == 1:
                    mesh.material_override = copy
                else:
                    mesh.set_surface_override_material(surface, copy)
    for child in node.get_children():
        _soften_shell_materials(child)


static func _surface_material(texture: Texture2D, source: Material = null) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_texture = texture
    material.roughness = 0.82
    material.metallic_specular = 0.1
    # Game artwork replaces ink, while imported paper grain stays on the paper.
    # Copy only the surface maps so shell tint/transparency cannot leak into art.
    if source is StandardMaterial3D:
        var paper := source as StandardMaterial3D
        material.roughness = paper.roughness
        material.metallic = paper.metallic
        if paper.roughness_texture != null:
            material.roughness_texture = paper.roughness_texture
            material.roughness_texture_channel = paper.roughness_texture_channel
            material.roughness = paper.roughness
        if paper.normal_enabled:
            material.normal_enabled = true
            material.normal_texture = paper.normal_texture
            material.normal_scale = paper.normal_scale
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    # The folded label reaches the UV border; wrapping bleeds the opposite
    # edge into it under anisotropic filtering.
    material.texture_repeat = false
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


func world_bounds() -> AABB:
    return _visual.global_transform * _visual_bounds


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
    if media_profile == "playstation-1":
        _disc_face(0.36, 1.2, -0.012, Color("07060c"))
        _disc_face(0.36, 1.2, 0.010, Color("15131b"))
        _disc_face(0.15, 0.36, 0.0, Color(0.5, 0.5, 0.55, 0.2))
        _label_surface = _disc_face(0.42, 1.191, 0.012, Color("a0a2a8"))
        _label_surface.name = "FrontLabel"
        return
    if media_profile != "snes":
        # Unknown or unstaged platforms get a neutral sleeve, never an
        # unrelated console silhouette that could imply support.
        var height := 2.35 if media_profile == "playstation-1" else 1.9
        _box(Vector3(3.05, height, 0.36), Vector3.ZERO, Color("41434f"))
        _box(Vector3(2.86, height - 0.16, 0.38), Vector3.ZERO, Color("626572"))
        return
    _box(Vector3(3.25, 2.04, 0.40), Vector3.ZERO, Color("9798a1"))
    _box(Vector3(2.22, 2.09, 0.43), Vector3(0, 0.02, 0), Color("a9aab1"))
    for side in [-1, 1]:
        for groove in range(5):
            _box(Vector3(0.32, 0.028, 0.014), Vector3(side * 1.39, 0.58 - groove * 0.17, 0.21), Color("74757f"))
    _box(Vector3(1.20, 0.10, 0.25), Vector3(0, -1.02, 0), Color("555660"))


func _disc_face(inner: float, outer: float, depth: float, color: Color) -> MeshInstance3D:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index in range(96):
        var a := TAU * index / 96.0
        var b := TAU * (index + 1) / 96.0
        var points := [Vector2(cos(a), sin(a)) * outer, Vector2(cos(b), sin(b)) * outer,
            Vector2(cos(b), sin(b)) * inner, Vector2(cos(a), sin(a)) * inner]
        for corner in [0, 2, 1, 0, 3, 2]:
            var point: Vector2 = points[corner]
            surface.set_normal(Vector3.FORWARD)
            surface.set_uv(Vector2(point.x / 2.4 + 0.5, 0.5 - point.y / 2.4))
            surface.add_vertex(Vector3(point.x, point.y, depth))
    var instance := MeshInstance3D.new()
    instance.mesh = surface.commit()
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    if color.a < 1.0:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    instance.material_override = material
    _visual.add_child(instance)
    return instance


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
