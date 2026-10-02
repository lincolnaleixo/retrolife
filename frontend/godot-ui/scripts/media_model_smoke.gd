extends SceneTree

## Isolated presentation regression: synthetic metadata, no bridge or ROMs.
const Cartridge = preload("res://scripts/library/cartridge.gd")
const Profiles = preload("res://scripts/library/media_profiles.gd")
var errors: Array[String] = []


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    var slot := Cartridge.new()
    var peer := Cartridge.new()
    root.add_child(slot)
    root.add_child(peer)
    var cases := {"snes": "snes", "genesis": "mega-drive", "mega_drive": "mega-drive", "ps1": "playstation-1", "psx": "playstation-1", "not-a-system": "generic"}
    for system in cases:
        var game := {"id": "same-pooled-game", "title": "Original Test Artwork", "systemId": system}
        slot.bind_game(game, 3, null)
        var profile: Dictionary = Profiles.for_game(game)
        _check(slot.media_profile == cases[system], "Resolve system alias: " + system)
        _check((slot.get("_label_viewport") as SubViewport).size == profile["canvas"], "Use the physical label aspect: " + system)
        _check(slot.world_bounds().size.length() > 0.1, "Retain usable bounds: " + system)
        var model_id := (slot.get("_visual") as Node).get_child(0).get_instance_id()
        slot.bind_game(game, 4, null)
        _check((slot.get("_visual") as Node).get_child(0).get_instance_id() == model_id, "Same-system rebind must reuse geometry: " + system)
        var image := Image.create(1024, roundi(1024.0 / float(profile["front_ratio"])), false, Image.FORMAT_RGBA8)
        var texture := ImageTexture.create_from_image(image)
        slot.bind_game(game, 4, texture)
        var front: MeshInstance3D = slot.get("_label_surface")
        _check((front.material_override as StandardMaterial3D).albedo_texture == texture, "Matching artwork must keep its original texture: " + system)
        _check(not (front.material_override as StandardMaterial3D).texture_repeat, "Label borders must clamp: " + system)
        var source := slot.get("_front_source_material") as StandardMaterial3D
        if source != null and source.roughness_texture != null:
            _check((front.material_override as StandardMaterial3D).roughness_texture == source.roughness_texture, "Replacing ink must preserve imported paper grain: " + system)
        var odd := ImageTexture.create_from_image(Image.create(40, 100, false, Image.FORMAT_RGBA8))
        slot.bind_game(game, 4, odd)
        _check(front.material_override == slot.get("_painter_material"), "Other artwork must be letterboxed: " + system)
        var path: String = profile["path"]
        if not path.is_empty() and ResourceLoader.exists(path):
            _check(not slot.uses_fallback, "Staged model must load: " + system)
            _check_artwork_uvs(front, system + " front")
            peer.bind_game(game, 0, null)
            _check((peer.get("_label_surface") as MeshInstance3D).mesh == front.mesh, "Pool slots must share label geometry: " + system)
            var rear: MeshInstance3D = slot.get("_rear_surface")
            if bool(profile.get("disc", false)):
                _check(rear == null, "CD reading face must never be a rear artwork target")
                _check(slot.find_child("FrontLid", true, false) == null, "CD must not contain a jewel case")
                _check_disc_hole(front)
            else:
                _check(rear != null, "Cartridge must expose its rear label: " + system)
            if rear != null:
                _check_artwork_uvs(rear, system + " rear")
                var rear_image := Image.create(1024, roundi(1024.0 / float(profile["rear_ratio"])), false, Image.FORMAT_RGBA8)
                var rear_texture := ImageTexture.create_from_image(rear_image)
                slot.bind_game(game, 0, texture, rear_texture)
                _check((rear.material_override as StandardMaterial3D).albedo_texture == rear_texture, "Rear artwork must use the rear surface: " + system)
                slot.bind_game(game, 0, null, null)
                _check(rear.material_override == slot.get("_rear_default_material"), "Rebind must clear old rear artwork: " + system)
        elif OS.get_environment("RETROLIFE_REQUIRE_MEDIA_MODELS") == "1" and system != "not-a-system":
            _check(false, "Required model is unstaged: " + path)
        else:
            _check(slot.uses_fallback, "Missing and unknown models must use a fallback: " + system)
    for index in range(90):
        var system: String = ["snes", "mega-drive", "playstation-1"][index % 3]
        slot.bind_game({"id": "cycling", "title": "Cycling", "systemId": system}, index, null)
        _check((slot.get("_visual") as Node).get_child_count() <= 16, "Changing systems must not accumulate model trees")
    slot.force_fallback = true
    slot.bind_game({"systemId": "ps1"}, 0, null)
    _check(slot.uses_fallback, "An explicit fallback must replace an already loaded model")
    _check_disc_hole(slot.get("_label_surface"))
    _check(Profiles.collection_title({"systemId": "ps1", "title": "Super Mario World"}).is_empty(), "SNES collection artwork must never match another platform")
    _check(Profiles.collection_title({"systemId": "snes", "title": "Super Mario World"}) == "Super Mario World", "SNES collection labels must remain available")
    slot.free()
    peer.free()
    await process_frame
    if errors.is_empty():
        print("Media model smoke passed: aliases, pooled system switching, model sharing, physical artwork ratios, rear reset, bounded visuals and safe fallbacks")
        quit(0)
    else:
        for error in errors:
            push_error(error)
        quit(1)


func _check(condition: bool, message: String) -> void:
    if not condition and not errors.has(message):
        errors.append(message)


func _check_artwork_uvs(label: MeshInstance3D, context: String) -> void:
    # Importers can promote the material's second UV channel to the first one.
    # That is harmless for shell grain but would tile a replacement game cover.
    for surface in range(label.mesh.get_surface_count()):
        var coordinates: PackedVector2Array = label.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
        _check(not coordinates.is_empty(), "Artwork needs imported UV0: " + context)
        for uv in coordinates:
            if uv.x < -0.001 or uv.y < -0.001 or uv.x > 1.001 or uv.y > 1.001:
                _check(false, "Imported artwork UV0 must remain within 0–1: " + context)
                return


func _check_disc_hole(front: MeshInstance3D) -> void:
    for surface in range(front.mesh.get_surface_count()):
        var uv: PackedVector2Array = front.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
        var raw_indices = front.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
        var indices := PackedInt32Array() if raw_indices == null else raw_indices as PackedInt32Array
        var count := indices.size() if not indices.is_empty() else uv.size()
        for index in range(0, count, 3):
            var triangle: Array[Vector2] = []
            for corner in range(3):
                triangle.append(uv[indices[index + corner] if not indices.is_empty() else index + corner])
            _check(not Geometry2D.is_point_in_polygon(Vector2(0.5, 0.5), PackedVector2Array(triangle)), "Artwork triangles must not fill the CD hole")
