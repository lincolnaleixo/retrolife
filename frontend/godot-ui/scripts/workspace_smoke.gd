extends SceneTree

const Bindings = preload("res://scripts/workspace/bindings.gd")

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _test_model_texture_coordinates()
    var main := preload("res://scripts/main.gd").new()
    main._ensure_input_actions()
    var defaults := Bindings.snapshot()
    Bindings.defaults = defaults
    var gameplay := preload("res://scripts/launch_integration.gd").new()
    var key := InputEventKey.new()
    key.keycode = KEY_F7
    key.pressed = true
    assert(Bindings.assign("south", key).is_empty())
    assert(gameplay._event_logical_action(key) == "south")
    var old_key := InputEventKey.new()
    old_key.keycode = KEY_X
    assert(gameplay._event_logical_action(old_key).is_empty())
    assert(not Bindings.assign("east", key).is_empty())
    for shortcut in [KEY_F8, KEY_F9, KEY_F11]:
        for physical in [false, true]:
            var reserved := InputEventKey.new()
            if physical:
                reserved.physical_keycode = shortcut
            else:
                reserved.keycode = shortcut
            var message := Bindings.assign("south", reserved)
            assert(message.contains("reserved") and message.contains("remapped"))
            assert(gameplay._event_logical_action(key) == "south")
            assert(gameplay._event_logical_action(reserved).is_empty())
    var mixed := InputEventKey.new()
    mixed.keycode = KEY_G
    mixed.physical_keycode = KEY_F9
    assert(Bindings.assign("south", mixed).contains("Game settings"))
    assert(gameplay._event_logical_action(key) == "south")
    var test_path := "user://workspace-bindings-smoke-%d.cfg" % OS.get_process_id()
    assert(Bindings.save(test_path) == OK)
    Bindings.restore(defaults)
    assert(gameplay._event_logical_action(key).is_empty())
    Bindings.load_saved(test_path)
    assert(gameplay._event_logical_action(key) == "south")
    # Keep an older shortcut binding intact on load, but label it for remapping.
    var legacy := InputEventKey.new()
    legacy.keycode = KEY_F9
    InputMap.action_add_event("game_south", legacy)
    assert(Bindings.save(test_path) == OK)
    var legacy_bytes := FileAccess.get_file_as_bytes(test_path)
    Bindings.restore(defaults)
    Bindings.load_saved(test_path)
    assert(gameplay._event_logical_action(legacy) == "south")
    assert(Bindings.caption("south", false).contains("reserved; remap"))
    assert(FileAccess.get_file_as_bytes(test_path) == legacy_bytes)
    InputMap.action_erase_event("game_south", legacy)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
    var panel := preload("res://scripts/workspace/controller_panel.gd").new()
    root.add_child(panel)
    panel._start_guided()
    assert(Bindings.caption("south", true) == "Not mapped")
    panel._cancel()
    assert(Bindings.caption("south", true) != "Not mapped")
    assert(gameplay._event_logical_action(key) == "south")
    panel._start_guided()
    panel._process(16)
    assert(panel._pending.is_empty())
    assert(Bindings.caption("south", true) != "Not mapped")
    Bindings.restore(defaults)
    panel.free()
    gameplay.free()
    main.free()
    var profiles = preload("res://scripts/workspace/collection_profiles.gd")
    assert(profiles.GAMES.size() == 7)
    for profile in profiles.GAMES:
        assert(profiles.for_game(profile.title, profile.system).slug == profile.slug)
        assert(profile.quests.size() == 4 and profile.gifts.size() == 8)
        assert(profiles.for_game(profile.title, "unrelated-system").is_empty())
    assert(profiles.for_game("Super Mario World (USA) 2", "snes").slug == "super-mario-world")
    assert(profiles.for_game("Super Mario Bros. 2", "nes").is_empty())
    assert(profiles.for_game("Crash Bandicoot 2", "playstation-1").is_empty())
    assert(profiles.for_game("Unlisted Game").is_empty())
    print("Workspace mapping smoke passed: live remap routing, reserved shortcut and duplicate rejection, non-destructive legacy reload, guided cancellation and timeout rollback.")
    quit()

func _test_model_texture_coordinates() -> void:
    # Original tiny fixture: UV0 repeats across the object; UV1 is an AO atlas.
    # Omitting texCoord=0 is legal glTF and must not promote AO to primary UVs.
    var positions := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
    var normals := PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
    var grain_uv := PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(-8, 8)])
    var atlas_uv := PackedVector2Array([Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.1, 0.9)])
    var pixels := Image.create(4, 4, false, Image.FORMAT_RGBA8)
    pixels.fill(Color(0.5, 0.5, 1.0))
    var payloads := [positions.to_byte_array(), normals.to_byte_array(), grain_uv.to_byte_array(), atlas_uv.to_byte_array(), pixels.save_png_to_buffer()]
    var binary := PackedByteArray()
    var buffer_views: Array = []
    for payload in payloads:
        buffer_views.append({"buffer": 0, "byteOffset": binary.size(), "byteLength": payload.size()})
        binary.append_array(payload)
        while binary.size() % 4 != 0:
            binary.append(0)
    var data := {
        "asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
        "buffers": [{"byteLength": binary.size()}], "bufferViews": buffer_views,
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0,0,0], "max": [1,1,0]},
            {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC2"},
            {"bufferView": 3, "componentType": 5126, "count": 3, "type": "VEC2"}],
        "images": [{"bufferView": 4, "mimeType": "image/png"}], "textures": [{"source": 0}],
        "materials": [{"normalTexture": {"index": 0}, "occlusionTexture": {"index": 0, "texCoord": 1},
            "pbrMetallicRoughness": {"metallicRoughnessTexture": {"index": 0}}}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2, "TEXCOORD_1": 3}, "material": 0}]}]
    }
    var json_bytes := JSON.stringify(data).to_utf8_buffer()
    while json_bytes.size() % 4 != 0:
        json_bytes.append(0x20)
    var original := PackedByteArray()
    original.resize(20)
    original.encode_u32(0, 0x46546c67)
    original.encode_u32(4, 2)
    original.encode_u32(8, 28 + json_bytes.size() + binary.size())
    original.encode_u32(12, json_bytes.size())
    original.encode_u32(16, 0x4e4f534a)
    original.append_array(json_bytes)
    var bin_header := PackedByteArray()
    bin_header.resize(8)
    bin_header.encode_u32(0, binary.size())
    bin_header.encode_u32(4, 0x004e4942)
    original.append_array(bin_header)
    original.append_array(binary)
    var path := "user://workspace-model-smoke-%d.glb" % OS.get_process_id()
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(original)
    file.close()
    var view := preload("res://scripts/workspace/model_view.gd").new()
    root.add_child(view)
    assert(view.load_model(path))
    var meshes := view.model.find_children("*", "MeshInstance3D", true, false)
    assert(meshes.size() == 1)
    var arrays: Array = meshes[0].mesh.surface_get_arrays(0)
    for index in range(3):
        assert(arrays[Mesh.ARRAY_TEX_UV][index].distance_to(grain_uv[index]) < 0.002)
        assert(arrays[Mesh.ARRAY_TEX_UV2][index].distance_to(atlas_uv[index]) < 0.002)
    var material: BaseMaterial3D = meshes[0].get_active_material(0)
    assert(material.normal_enabled and material.ao_enabled and material.ao_on_uv2)
    assert(material.normal_texture.get_image().has_mipmaps())
    assert(material.roughness_texture.get_image().has_mipmaps())
    assert(FileAccess.get_file_as_bytes(path) == original)
    view.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    print("Runtime GLB UV smoke passed: repeating normal/roughness UV0, independent AO UV1, mipmaps and unchanged source bytes.")
