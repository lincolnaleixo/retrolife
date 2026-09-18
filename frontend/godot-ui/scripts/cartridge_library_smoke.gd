extends SceneTree

## Presentation-only fixtures. No ROMs, commercial labels or user library reads.
const Carousel = preload("res://scripts/library/carousel.gd")
const Cartridge = preload("res://scripts/library/cartridge.gd")
const LabelCache = preload("res://scripts/library/label_cache.gd")

class FakeCatalog extends RefCounted:
    var entries: Array = []
    var page_calls := 0

    func _init(count := 10000) -> void:
        for index in range(count):
            entries.append({"id": "fixture-%05d" % index, "title": "Collection %05d" % index, "systemId": "snes", "systemName": "Super Nintendo", "playable": false})

    func view(_system := "", query := "", offset := 0, limit := 500) -> Dictionary:
        page_calls += 1
        var filtered: Array = []
        for entry in entries:
            if query.is_empty() or query.to_lower() in str(entry["title"]).to_lower():
                filtered.append(entry)
        return {"ok": true, "data": {"revision": entries.size(), "games": filtered.slice(offset, offset + limit), "totalGames": entries.size(), "filteredGames": filtered.size(), "hasMore": offset + limit < filtered.size(), "systems": [{"id": "snes", "name": "Super Nintendo", "gameCount": entries.size()}]}}

    func details(id: String) -> Dictionary:
        for entry in entries:
            if entry["id"] == id:
                return {"ok": true, "data": entry}
        return {"ok": false, "error": "Missing fixture"}

    func import_file(_path: String) -> Dictionary:
        var entry := {"id": "imported-fixture", "title": "A Newly Imported Game", "systemId": "snes", "systemName": "Super Nintendo", "playable": false}
        entries.push_front(entry)
        return {"ok": true, "data": entry}


class TestShell extends "res://scripts/cartridge_library.gd":
    func _ready() -> void:
        persist_preferences = false
        _ensure_input_actions()
        _build_shell()


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    root.size = Vector2i(1280, 720)
    var errors: Array[String] = []
    var shell := TestShell.new()
    shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shell.set("_catalog", FakeCatalog.new())
    root.add_child(shell)
    await shell._refresh_library()
    await process_frame
    var carousel: Control = shell.get("_carousel")
    _check(carousel.games.size() == 10000, "All pages, not only the first 500 games, must be visible", errors)
    _check(carousel.pool_size() == 7, "The scene pool must have seven entries", errors)
    carousel.select_id("fixture-05000")
    _check(carousel.selected_id() == "fixture-05000", "Select by stable game ID", errors)
    _check(carousel.active_model_count() <= 7, "Bound active models", errors)
    var before := OS.get_static_memory_usage()
    var timings: Array[int] = []
    for index in range(300):
        var start := Time.get_ticks_usec()
        carousel.navigate(1 if index < 150 else -1)
        timings.append(Time.get_ticks_usec() - start)
        if index % 10 == 0:
            await process_frame
        _check(carousel.active_model_count() <= 7, "Rapid input must keep the scene pool bounded", errors)
        _check(carousel.labels.entry_count() <= 9, "Artwork cache must remain bounded", errors)
    await process_frame
    _check(carousel.selected_id() == "fixture-05000", "Rapid navigation must not drop or reorder input", errors)
    _check(OS.get_static_memory_usage() - before < 96 * 1024 * 1024, "Navigation memory growth exceeded 96 MiB", errors)
    timings.sort()
    print("Cartridge navigation CPU p95 (microseconds): ", timings[int(timings.size() * 0.95)])
    _check(timings[int(timings.size() * 0.95)] < 250000, "Navigation CPU p95 exceeded 250 ms on the test host", errors)
    shell._open_details(carousel.selected_id())
    _check((shell.get("_details_overlay") as Control).visible, "Details must open", errors)
    shell._close_details()
    await process_frame
    _check(carousel.selected_id() == "fixture-05000", "Details round trip must preserve selection", errors)
    shell._on_filter_pressed("snes")
    await _settle(shell)
    carousel.select_id("fixture-02000")
    shell._on_filter_pressed("")
    await _settle(shell)
    _check(carousel.selected_id() == "fixture-05000", "Restore selection per system view", errors)
    carousel.select_index(-200)
    _check(carousel.selected_index == 0, "Clamp the beginning of the collection", errors)
    carousel.select_index(50000)
    _check(carousel.selected_index == 9999, "Clamp the end of the collection", errors)
    shell._on_game_exited("fixture-04200")
    await process_frame
    _check(carousel.selected_id() == "fixture-04200", "Gameplay round trip must restore the selected game", errors)
    shell._on_search_changed("Collection 000")
    await create_timer(0.18).timeout
    await _settle(shell)
    _check(carousel.games.size() == 100, "Debounced search must filter the collection", errors)
    await shell._on_files_selected(PackedStringArray(["synthetic-import.sfc"]))
    await _settle(shell)
    _check(carousel.selected_id() == "imported-fixture", "A new import must be revealed even from an active search", errors)
    carousel.set_presentation(true, true, false)
    _check(carousel.active_model_count() <= 3, "Low-power view must render at most three models", errors)
    carousel.set_presentation(true, false, true)
    _check(carousel.active_model_count() == 0, "Text view must stop 3D rendering", errors)
    carousel.set_active(false)
    _check(int((carousel.get("_viewport") as SubViewport).render_target_update_mode) == SubViewport.UPDATE_DISABLED, "Inactive library rendering must stop", errors)
    carousel.set_active(true)
    carousel.set_presentation(false, false, false)
    var fallback := Cartridge.new()
    fallback.force_fallback = true
    root.add_child(fallback)
    fallback.bind_game({"id": "missing-model", "title": "Neutral Label", "systemId": "snes"}, 0, null)
    _check(fallback.uses_fallback, "Missing models must have a procedural fallback", errors)
    _check(not bool(fallback.get("_artwork_present")), "Missing artwork must display neutral metadata", errors)
    fallback.queue_free()
    var imported := Cartridge.new()
    root.add_child(imported)
    if ResourceLoader.exists(Cartridge.MODEL_PATH):
        _check(not imported.uses_fallback, "The staged GLB must actually instantiate", errors)
        _check(imported.get("_rear_surface") != null, "The staged GLB must expose the rear print surface", errors)
        var shell_softened := false
        var visual: Node3D = imported.get("_visual")
        if visual != null:
            for child in visual.get_children():
                shell_softened = shell_softened or _has_soft_material(child)
        _check(shell_softened, "Shell materials must render with the softened specular response", errors)
        var probe := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
        var wide := ImageTexture.create_from_image(Image.create(1024, 542, false, Image.FORMAT_RGBA8))
        imported.bind_game({"id": "wide-probe", "title": "Wide Probe", "systemId": "snes"}, 0, wide, null)
        _check((imported.get("_label_surface") as MeshInstance3D).material_override != imported.get("_painter_material"), "Label-proportioned artwork must bypass the painter canvas", errors)
        imported.bind_game({"id": "wide-probe", "title": "Wide Probe", "systemId": "snes"}, 0, probe, null)
        _check((imported.get("_label_surface") as MeshInstance3D).material_override == imported.get("_painter_material"), "Other artwork shapes must use the painter canvas", errors)
        imported.bind_game({"id": "rear-probe", "title": "Rear Probe", "systemId": "snes"}, 0, null, probe)
        _check((imported.get("_rear_surface") as MeshInstance3D).material_override != null, "Rear artwork must override the rear surface material", errors)
        imported.bind_game({"id": "rear-probe", "title": "Rear Probe", "systemId": "snes"}, 0, null, null)
        _check((imported.get("_rear_surface") as MeshInstance3D).material_override == null, "Without rear artwork the unprinted rear surface must stay untouched", errors)
    imported.queue_free()
    await _exercise_input_events(shell, carousel, errors)
    await _exercise_inspection(shell, carousel, errors)
    await _exercise_compact_layout(shell, errors)
    _exercise_preferences(shell, errors)
    await _exercise_artwork(errors)
    carousel.set_games([])
    _check(carousel.selected_index == -1 and carousel.active_model_count() == 0, "Empty libraries must not leave stale cartridges", errors)
    shell.queue_free()
    await process_frame
    if errors.is_empty():
        print("RetroLife cartridge library smoke passed: 10000 entries, bounded pool/cache, navigation, filters, search, import, details, return, fallbacks and PNG validation")
        quit(0)
    else:
        for error in errors:
            push_error(error)
        quit(1)


func _exercise_artwork(errors: Array[String]) -> void:
    var id := "artwork-smoke-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
    var directory := "user://" + id
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
    var source := directory.path_join("source.png")
    var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
    image.fill(Color("786694"))
    image.save_png(source)
    var cache := LabelCache.new()
    _check(cache.import_artwork(id, source).is_empty(), "Import a valid local PNG", errors)
    _check(cache.texture_for(id) != null, "Imported artwork must load as a texture", errors)
    var invalid := directory.path_join("invalid.png")
    var file := FileAccess.open(invalid, FileAccess.WRITE)
    file.store_string("not a PNG")
    file.close()
    _check(not cache.validate_png(invalid).is_empty(), "Reject malformed artwork before decoding", errors)
    var oversized := directory.path_join("oversized.png")
    file = FileAccess.open(oversized, FileAccess.WRITE)
    file.store_buffer(PackedByteArray([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,32,0,0,0,32,0]))
    file.close()
    _check(not cache.validate_png(oversized).is_empty(), "Reject oversized PNG dimensions before decoding", errors)
    _check(LabelCache.titles_match("Super Mario World (USA) 2", "Super Mario World"), "Region and dedup markers must not block a collection label match", errors)
    _check(LabelCache.titles_match("Donkey Kong Country (USA) (Rev 1)", "Donkey Kong Country"), "Revision markers must not block a collection label match", errors)
    _check(LabelCache.titles_match("Game (World)", "Game"), "A parenthesized World region marker must not block a match", errors)
    _check(LabelCache.titles_match("Super Mario World", "Super Mario World"), "A bare World title word must be preserved", errors)
    _check(not LabelCache.titles_match("Super Mario 2", "Super Mario World"), "A sequel number without a region marker must change the title", errors)
    _check(not LabelCache.titles_match("Super Mario World 2: Yoshi's Island", "Super Mario World"), "A different game must not match a collection label", errors)
    _check(not LabelCache.titles_match("Donkey Kong Country", "Super Mario World"), "Unrelated titles must not match a collection label", errors)
    _check(not LabelCache.titles_match("", "Super Mario World"), "Empty titles must never match", errors)

    var payload := PackedByteArray([7, 11, 13, 17, 19])
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(payload)
    var digest := context.finish().hex_encode()
    _check(not LabelCache.install_downloaded_label("smoke-label", "front", payload, "0".repeat(64)).is_empty(), "A fetched label with the wrong checksum must be rejected", errors)
    _check(not FileAccess.file_exists(LabelCache.collection_cache_path("smoke-label", "front")), "A rejected label must not be installed", errors)
    _check(LabelCache.install_downloaded_label("smoke-label", "front", payload, digest).is_empty(), "A verified fetched label must install", errors)
    _check(FileAccess.file_exists(LabelCache.collection_cache_path("smoke-label", "front")), "The fetched label must land in the user cache", errors)
    _check(FileAccess.get_sha256(LabelCache.collection_cache_path("smoke-label", "front")) == digest, "The cached label must match its approved checksum", errors)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(LabelCache.collection_cache_path("smoke-label", "front")))
    for path in [source, invalid, oversized, LabelCache.path_for(id)]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
    await process_frame


func _has_soft_material(node: Node) -> bool:
    if node is MeshInstance3D:
        var mesh := node as MeshInstance3D
        for surface in range(mesh.get_surface_override_material_count()):
            var material := mesh.get_active_material(surface)
            if material is StandardMaterial3D and (material as StandardMaterial3D).metallic_specular < 0.2:
                return true
    for child in node.get_children():
        if _has_soft_material(child):
            return true
    return false


func _settle(shell: Control) -> void:
    for _frame in range(1000):
        if not bool(shell.get("_refreshing")):
            break
        await process_frame
    await process_frame


func _check(condition: bool, message: String, errors: Array[String]) -> void:
    if not condition and not errors.has(message):
        errors.append(message)


func _exercise_input_events(shell: Control, carousel: Control, errors: Array[String]) -> void:
    carousel.set_presentation(true, false, false)
    carousel.select_index(100)
    carousel.grab_focus()
    await process_frame
    var key := InputEventKey.new()
    key.keycode = KEY_RIGHT
    key.pressed = true
    Input.parse_input_event(key)
    await process_frame
    key = InputEventKey.new()
    key.keycode = KEY_RIGHT
    key.pressed = false
    Input.parse_input_event(key)
    await process_frame
    _check(carousel.selected_index == 101, "Routed keyboard input must move one cartridge", errors)
    var controller := InputEventJoypadButton.new()
    controller.button_index = JOY_BUTTON_DPAD_LEFT
    controller.pressed = true
    Input.parse_input_event(controller)
    await process_frame
    controller = InputEventJoypadButton.new()
    controller.button_index = JOY_BUTTON_DPAD_LEFT
    controller.pressed = false
    Input.parse_input_event(controller)
    await process_frame
    _check(carousel.selected_index == 100, "Routed controller input must move one cartridge", errors)
    var motion := InputEventMouseMotion.new()
    motion.position = carousel.get_global_rect().get_center()
    motion.global_position = motion.position
    Input.parse_input_event(motion)
    await process_frame
    var mouse := InputEventMouseButton.new()
    mouse.button_index = MOUSE_BUTTON_WHEEL_DOWN
    mouse.pressed = true
    mouse.position = carousel.get_global_rect().get_center()
    Input.parse_input_event(mouse)
    await process_frame
    _check(carousel.selected_index == 100, "Mouse wheel must not change the selection", errors)
    _check(float(carousel.get("_inspect_target_zoom")) < 1.0, "Mouse wheel must zoom the inspection view", errors)
    var action := InputEventAction.new()
    action.action = "ui_accept"
    action.pressed = true
    Input.parse_input_event(action)
    await process_frame
    _check((shell.get("_details_overlay") as Control).visible, "Routed accept must open details", errors)
    action = InputEventAction.new()
    action.action = "ui_accept"
    action.pressed = false
    Input.parse_input_event(action)
    shell._close_details()
    await process_frame
    _check(carousel.selected_index == 100, "Input-driven details must retain selection", errors)
    var selected_before: int = carousel.selected_index
    var zoom_before: float = float(carousel.get("_inspect_target_zoom"))
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    wheel.pressed = true
    carousel.set_active(false)
    carousel._gui_input(wheel)
    _check(carousel.selected_index == selected_before, "Inactive library must reject navigation input", errors)
    _check(is_equal_approx(float(carousel.get("_inspect_target_zoom")), zoom_before), "Inactive library must reject inspection input", errors)
    carousel.set_active(true)
    var original_size := root.size
    for dimensions in [Vector2i(720, 540), Vector2i(1600, 900), Vector2i(1920, 800), Vector2i(2560, 1440)]:
        root.size = dimensions
        for _frame in range(3):
            await process_frame
        _check(carousel.size.x > 0 and carousel.size.y >= 180, "Resized library must retain a usable stage", errors)
        _check(carousel.active_model_count() <= 7, "Resizing must retain the model budget", errors)
        var viewport: SubViewport = carousel.get("_viewport")
        _check(viewport.size.x <= 2560 and viewport.size.y <= 1440, "Resizing must retain the 2K render-resolution budget", errors)
    root.size = original_size
    await process_frame


func _exercise_inspection(shell: Control, carousel: Control, errors: Array[String]) -> void:
    carousel.set_presentation(false, false, false)
    carousel.select_index(100)
    carousel.grab_focus()
    await process_frame
    var hero: Node3D = carousel.get("_hero")
    var camera: Camera3D = carousel.get("_camera")
    var viewport: SubViewport = carousel.get("_viewport")
    _check(hero != null and camera != null, "Inspection requires a hero cartridge and camera", errors)
    if hero == null or camera == null:
        return
    var view_point := camera.unproject_position(hero.global_position)
    var point := view_point * Vector2(carousel.size) / Vector2(viewport.size).max(Vector2.ONE)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = point
    Input.parse_input_event(press)
    await process_frame
    _check(bool(carousel.get("_inspecting")), "Dragging the selected cartridge must start inspection", errors)
    var drag := InputEventMouseMotion.new()
    drag.position = point + Vector2(48, 16)
    drag.global_position = drag.position
    drag.relative = Vector2(48, 16)
    Input.parse_input_event(drag)
    await process_frame
    _check(float(carousel.get("_inspect_target_yaw")) > 0.1, "Dragging right must rotate the cartridge to the right", errors)
    _check(float(carousel.get("_inspect_target_pitch")) > 0.05, "Dragging down must pitch the cartridge down", errors)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = drag.position
    Input.parse_input_event(release)
    await process_frame
    _check(carousel.selected_index == 100, "Inspection drag must not change the selection", errors)
    _check(not (shell.get("_details_overlay") as Control).visible, "Inspection drag must not open details", errors)

    var reset_key := InputEventKey.new()
    reset_key.keycode = KEY_R
    reset_key.pressed = true
    Input.parse_input_event(reset_key)
    await process_frame
    reset_key = InputEventKey.new()
    reset_key.keycode = KEY_R
    reset_key.pressed = false
    Input.parse_input_event(reset_key)
    await process_frame
    _check(absf(float(carousel.get("_inspect_target_yaw"))) < 0.001, "R must reset the inspection yaw", errors)
    _check(absf(float(carousel.get("_inspect_target_pitch"))) < 0.001, "R must reset the inspection pitch", errors)
    _check(is_equal_approx(float(carousel.get("_inspect_target_zoom")), 1.0), "R must reset the inspection zoom", errors)

    var shift_right := InputEventKey.new()
    shift_right.keycode = KEY_RIGHT
    shift_right.shift_pressed = true
    shift_right.pressed = true
    Input.parse_input_event(shift_right)
    var rotated := false
    for _frame in range(240):
        await process_frame
        if absf(float(carousel.get("_inspect_target_yaw"))) > 0.001:
            rotated = true
            break
    _check(carousel.selected_index == 100, "Shifted arrows must not browse the library", errors)
    _check(rotated, "Shifted arrows must rotate the cartridge", errors)
    shift_right = InputEventKey.new()
    shift_right.keycode = KEY_RIGHT
    shift_right.shift_pressed = true
    shift_right.pressed = false
    Input.parse_input_event(shift_right)
    await process_frame
    var stopped_yaw := float(carousel.get("_inspect_target_yaw"))
    for _frame in range(60):
        await process_frame
    _check(is_equal_approx(float(carousel.get("_inspect_target_yaw")), stopped_yaw), "Releasing the shifted arrow must stop rotation", errors)

    for _step in range(40):
        var zoom_in := InputEventMouseButton.new()
        zoom_in.button_index = MOUSE_BUTTON_WHEEL_UP
        zoom_in.pressed = true
        zoom_in.position = point
        Input.parse_input_event(zoom_in)
    await process_frame
    _check(float(carousel.get("_inspect_target_zoom")) <= 1.6 + 0.0001, "Zoom must respect the upper limit", errors)
    for _step in range(60):
        var zoom_out := InputEventMouseButton.new()
        zoom_out.button_index = MOUSE_BUTTON_WHEEL_DOWN
        zoom_out.pressed = true
        zoom_out.position = point
        Input.parse_input_event(zoom_out)
    await process_frame
    _check(float(carousel.get("_inspect_target_zoom")) >= 0.75 - 0.0001, "Zoom must respect the lower limit", errors)
    var cleanup := InputEventKey.new()
    cleanup.keycode = KEY_R
    cleanup.pressed = true
    Input.parse_input_event(cleanup)
    await process_frame
    cleanup = InputEventKey.new()
    cleanup.keycode = KEY_R
    cleanup.pressed = false
    Input.parse_input_event(cleanup)
    await process_frame


func _exercise_preferences(shell: Control, errors: Array[String]) -> void:
    var path := "user://preferences-smoke-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
    shell.set("settings_path", path)
    shell.set("persist_preferences", true)
    shell.set("_reduce_motion", true)
    shell.set("_low_quality", true)
    shell.set("_textual_view", true)
    shell.set("_last_game_id", "fixture-preference")
    shell.set("_selected_system_id", "snes")
    shell._save_preferences()
    var reader := TestShell.new()
    reader.set("settings_path", path)
    reader.set("persist_preferences", true)
    reader._load_preferences()
    _check(bool(reader.get("_reduce_motion")) and bool(reader.get("_low_quality")) and bool(reader.get("_textual_view")), "Presentation preferences must survive a fresh controller instance", errors)
    _check(str(reader.get("_last_game_id")) == "fixture-preference" and str(reader.get("_selected_system_id")) == "snes", "Selection preferences must survive a fresh controller instance", errors)
    reader.free()
    shell.set("persist_preferences", false)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _exercise_compact_layout(shell: Control, errors: Array[String]) -> void:
    var original_size := root.size
    var title: Label = shell.get("_hero_title")
    var warning: Label = shell.get("_warning_label")
    var previous_title := title.text
    var previous_warning := warning.text
    var warning_visible := warning.visible
    root.size = Vector2i(720, 540)
    title.text = "The Extraordinary Adventures of the Retro Cartridge Collection: A Very Long Game Title With Multiple Editions and Lots of Extra Words"
    warning.text = "An import could not be completed. A long error message must not push the navigation controls outside the screen when a long game title is also visible."
    warning.show()
    for _frame in range(10):
        await process_frame
    var hints: Control = shell.find_child("InputHints", true, false)
    _check(hints != null and hints.get_global_rect().end.y <= root.size.y, "Long titles and errors must not push control hints outside the compact window", errors)
    var carousel: Control = shell.get("_carousel")
    _check(carousel.size.y >= 180, "Compact error layout must retain the cartridge stage", errors)
    title.text = previous_title
    warning.text = previous_warning
    warning.visible = warning_visible
    root.size = original_size
    await process_frame
