extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const USER_SNAPSHOT_PATH := "user://catalog.json"

var _failed := false
var _verify_pointer := false


func _initialize() -> void:
    _verify_pointer = OS.get_environment("RETROLIFE_POINTER_TEST") == "1"
    call_deferred("_run")


func _run() -> void:
    await _verify_valid_snapshot_startup()
    if _failed:
        return
    await _verify_invalid_snapshot_fallback()
    if _failed:
        return
    await _verify_library_and_details_flow()
    if _failed:
        return
    print(
        "RETROLIFE_LIBRARY_UI_SMOKE_OK keyboard=true gamepad=true mouse=%s"
        % str(_verify_pointer)
    )
    quit(0)


func _verify_valid_snapshot_startup() -> void:
    _write_user_snapshot(_server_snapshot_json())
    if _failed:
        return
    var scene := await _spawn_scene()
    var cards := _game_cards(scene)
    var source := scene.find_child("SourceLabel", true, false) as Label
    if cards.size() != 1:
        _fail("A valid startup snapshot did not render one game.")
        return
    if source == null or not source.text.contains("serverSnapshot"):
        _fail("The startup snapshot source was not visible in the main scene.")
        return
    await _discard_scene(scene)
    _remove_user_snapshot()


func _verify_invalid_snapshot_fallback() -> void:
    _write_user_snapshot('{"games":[],"nextCursor":"more"}')
    if _failed:
        return
    var scene := await _spawn_scene()
    var warning := scene.find_child("CatalogWarning", true, false) as Label
    if _game_cards(scene).size() != 5:
        _fail("An invalid startup snapshot did not fall back to the reference catalog.")
        return
    if warning == null or not warning.visible or not warning.text.contains("incomplete"):
        _fail("The invalid startup snapshot did not produce an actionable warning.")
        return
    await _discard_scene(scene)
    _remove_user_snapshot()


func _verify_library_and_details_flow() -> void:
    var scene := await _spawn_scene()
    var cards := _game_cards(scene)
    if cards.size() != 5:
        _fail("The reference catalog did not render five game cards.")
        return
    if str(cards[0].get_meta("game_id", "")) != "chrono-trigger":
        _fail("The game cards are not deterministically ordered.")
        return
    if scene.get_viewport().gui_get_focus_owner() != cards[0]:
        _fail("The first game card did not receive initial focus.")
        return

    await _send_key(KEY_ENTER)
    if not _details_visible(scene, "CHRONO TRIGGER"):
        _fail("Keyboard confirm did not open the focused game details.")
        return
    await _send_key(KEY_ESCAPE)
    if _details_is_visible(scene):
        _fail("Keyboard cancel did not close game details.")
        return
    if scene.get_viewport().gui_get_focus_owner() != cards[0]:
        _fail("Keyboard cancel did not restore the originating game focus.")
        return

    await _send_joy_button(0)
    if not _details_visible(scene, "CHRONO TRIGGER"):
        _fail("Gamepad confirm did not open the focused game details.")
        return
    await _send_joy_button(1)
    if _details_is_visible(scene):
        _fail("Gamepad cancel did not close game details.")
        return

    if not _has_joy_button_mapping("library_next_system", 10) \
        or not _has_joy_button_mapping("library_previous_system", 9):
        _fail("The shoulder-button system mappings are missing.")
        return
    scene.call("_cycle_system", 1)
    await _settle()
    if _game_cards(scene).size() != 2:
        _fail("The next-system behavior did not select the first system filter.")
        return
    scene.call("_cycle_system", -1)
    await _settle()
    if _game_cards(scene).size() != 5:
        _fail("The previous-system behavior did not return to all systems.")
        return

    var search := scene.find_child("SearchEdit", true, false) as LineEdit
    search.text = "bare knuckle"
    search.text_changed.emit(search.text)
    await _settle()
    cards = _game_cards(scene)
    if cards.size() != 1 \
        or str(cards[0].get_meta("game_id", "")) != "streets-of-rage-2":
        _fail("The main scene did not render the Rust-owned alias search result.")
        return

    search.text = "no matching catalog entry"
    search.text_changed.emit(search.text)
    await _settle()
    var empty_state := scene.find_child("EmptyState", true, false) as Label
    if empty_state == null or not empty_state.visible or not _game_cards(scene).is_empty():
        _fail("The empty library state was not rendered.")
        return

    search.text = ""
    search.text_changed.emit(search.text)
    await _settle()
    cards = _game_cards(scene)
    if cards.size() != 5:
        _fail("Clearing search did not restore the catalog.")
        return

    var mouse_back := scene.find_child("DetailsBackButton", true, false) as Button
    if cards[0].mouse_filter == Control.MOUSE_FILTER_IGNORE \
        or mouse_back == null \
        or mouse_back.mouse_filter == Control.MOUSE_FILTER_IGNORE:
        _fail("The library or details controls are not pointer accessible.")
        return

    if _verify_pointer:
        var mouse_card: Button = cards[0]
        await _click_control(mouse_card)
        if not _details_is_visible(scene):
            _fail("Mouse input did not open a visible game card.")
            return
        await _click_control(mouse_back)
        if _details_is_visible(scene):
            _fail("Mouse input did not close game details.")
            return
        if scene.get_viewport().gui_get_focus_owner() != mouse_card:
            _fail("Mouse details flow did not restore the originating game identity.")
            return

    await _discard_scene(scene)


func _spawn_scene() -> Node:
    var scene := MAIN_SCENE.instantiate()
    root.add_child(scene)
    await _settle()
    return scene


func _discard_scene(scene: Node) -> void:
    scene.queue_free()
    await process_frame


func _settle() -> void:
    await process_frame
    await process_frame


func _game_cards(scene: Node) -> Array[Button]:
    var grid := scene.find_child("GameGrid", true, false)
    var cards: Array[Button] = []
    if grid == null:
        return cards
    for child in grid.get_children():
        if child is Button \
            and not child.is_queued_for_deletion() \
            and not str(child.get_meta("game_id", "")).is_empty():
            cards.append(child)
    return cards


func _details_visible(scene: Node, expected_title: String) -> bool:
    if not _details_is_visible(scene):
        return false
    var title := scene.find_child("DetailsTitle", true, false) as Label
    return title != null and title.text == expected_title


func _details_is_visible(scene: Node) -> bool:
    var overlay := scene.find_child("DetailsOverlay", true, false) as Control
    return overlay != null and overlay.visible


func _has_joy_button_mapping(action: StringName, button_index: int) -> bool:
    for event in InputMap.action_get_events(action):
        if event is InputEventJoypadButton and event.button_index == button_index:
            return true
    return false


func _send_key(keycode: int) -> void:
    var event := InputEventKey.new()
    event.device = InputEvent.DEVICE_ID_KEYBOARD
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = true
    Input.parse_input_event(event)
    await process_frame
    var release := event.duplicate()
    release.pressed = false
    Input.parse_input_event(release)
    await process_frame


func _send_joy_button(button_index: int) -> void:
    var event := InputEventJoypadButton.new()
    event.button_index = button_index
    event.pressed = true
    event.device = 0
    Input.parse_input_event(event)
    await process_frame
    var release := event.duplicate()
    release.pressed = false
    Input.parse_input_event(release)
    await process_frame


func _click_control(control: Control) -> void:
    control.grab_focus()
    await process_frame
    var center := control.get_global_rect().get_center()

    var motion := InputEventMouseMotion.new()
    motion.position = center
    motion.global_position = center
    Input.parse_input_event(motion)
    await process_frame

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.position = center
    press.global_position = center
    press.pressed = true
    Input.parse_input_event(press)
    await process_frame

    var release := press.duplicate()
    release.pressed = false
    Input.parse_input_event(release)
    await process_frame


func _write_user_snapshot(content: String) -> void:
    var file := FileAccess.open(USER_SNAPSHOT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("Could not create the test catalog snapshot.")
        return
    file.store_string(content)


func _remove_user_snapshot() -> void:
    if FileAccess.file_exists(USER_SNAPSHOT_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_SNAPSHOT_PATH))


func _server_snapshot_json() -> String:
    return JSON.stringify({
        "games": [{
            "sha256": "c".repeat(64),
            "system": "megadrive",
            "title": "Snapshot Game",
            "aliases": ["Snapshot Alias"],
            "developer": "Snapshot Studio",
            "publisher": "Snapshot Publisher",
            "genres": ["Action"],
            "region": "World",
            "languages": ["en"],
            "players": 1,
            "summary": "Loaded from user://catalog.json.",
            "releaseYear": 1993,
            "media": {"boxFront": "d".repeat(64)},
        }],
        "nextCursor": null,
    })


func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    _remove_user_snapshot()
    push_error("RETROLIFE_LIBRARY_UI_SMOKE_FAILED: %s" % message)
    quit(1)
