extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const CONFIGURATION_PATH := "user://launch-config.json"

var _failed := false
var _fixture_path := ""
var _root_path := ""
var _content_path := ""


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    _fixture_path = OS.get_environment("RETROLIFE_LAUNCH_FIXTURE").strip_edges()
    if _fixture_path.is_empty() or not FileAccess.file_exists(_fixture_path):
        _fail("RETROLIFE_LAUNCH_FIXTURE is unavailable for the launch UI test.")
        return
    _root_path = ProjectSettings.globalize_path("user://phase4-launch-ui")
    _content_path = _root_path.path_join("content/chrono-trigger.sfc")
    DirAccess.make_dir_recursive_absolute(_content_path.get_base_dir())
    var content := FileAccess.open(_content_path, FileAccess.WRITE)
    if content == null:
        _fail("Could not create UI fixture content.")
        return
    content.store_string("RetroLife UI fixture")
    if not _write_configuration(120, 0):
        return

    var scene := MAIN_SCENE.instantiate()
    root.add_child(scene)
    await _settle(8)

    var integration := scene.find_child("LaunchIntegration", true, false)
    var launch_button := scene.find_child("LaunchButton", true, false) as Button
    var cancel_button := scene.find_child("LaunchCancelButton", true, false) as Button
    var status_label := scene.find_child("LaunchStatus", true, false) as Label
    if integration == null or launch_button == null or cancel_button == null or status_label == null:
        _fail("The main scene did not create the Phase 4 launch controls.")
        return

    var cards := _game_cards(scene)
    if cards.is_empty():
        _fail("The launch UI test could not find the reference game cards.")
        return
    cards[0].grab_focus()
    await process_frame
    await _send_joy_button(0)
    await _settle(4)
    if not _details_visible(scene):
        _fail("Gamepad confirm did not open game details before launch.")
        return
    if launch_button.disabled:
        _fail("The configured game did not enable the launch button.")
        return
    if scene.get_viewport().gui_get_focus_owner() != launch_button:
        _fail("The launch button did not receive controller-first focus.")
        return

    await _send_joy_button(0)
    if str(integration.call("active_operation_id")).is_empty():
        _fail("Gamepad confirm did not queue the launch operation.")
        return
    if not cancel_button.visible:
        _fail("The cancellable launch did not expose its cancel action.")
        return
    if not await _wait_for_idle(integration, 900):
        return
    if not status_label.text.contains("RetroLife is ready"):
        _fail("Successful child exit did not restore the frontend-ready state.")
        return
    if not _details_visible(scene):
        _fail("The details flow disappeared after the child process returned.")
        return

    if not _write_configuration(80, 7):
        return
    integration.call("reload_launch_configuration")
    await _settle(3)
    launch_button.grab_focus()
    await _send_key(KEY_ENTER)
    if not await _wait_for_idle(integration, 900):
        return
    if not status_label.text.contains("Launch failed"):
        _fail("A nonzero child exit was not visible and actionable in the UI.")
        return

    if not _write_configuration(3_000, 0):
        return
    integration.call("reload_launch_configuration")
    await _settle(3)
    launch_button.grab_focus()
    await _send_joy_button(0)
    await _settle(4)
    if str(integration.call("active_operation_id")).is_empty():
        _fail("The cancellation fixture was not queued.")
        return
    cancel_button.grab_focus()
    await _send_joy_button(0)
    if not await _wait_for_idle(integration, 900):
        return
    if not status_label.text.contains("cancelled"):
        _fail("Controller cancellation did not produce a visible cancelled state.")
        return

    var mouse_verified := false
    if OS.get_environment("RETROLIFE_UI_SMOKE_WINDOWED") == "1":
        if not _write_configuration(80, 0):
            return
        integration.call("reload_launch_configuration")
        await _settle(3)
        await _click_control(launch_button)
        if not await _wait_for_idle(integration, 900):
            return
        if not status_label.text.contains("RetroLife is ready"):
            _fail("Mouse launch did not return to the ready state.")
            return
        mouse_verified = true

    await _send_joy_button(1)
    await _settle(3)
    if _details_visible(scene):
        _fail("Gamepad cancel did not return from details to the library.")
        return
    if scene.get_viewport().gui_get_focus_owner() == null:
        _fail("Returning from the launch flow lost controller focus.")
        return

    scene.queue_free()
    _remove_configuration()
    print(
        "RETROLIFE_LAUNCH_UI_SMOKE_OK keyboard=true gamepad=true mouse=%s failure=true cancel=true return=true"
        % str(mouse_verified).to_lower()
    )
    quit(0)


func _write_configuration(sleep_ms: int, exit_code: int) -> bool:
    var file := FileAccess.open(CONFIGURATION_PATH, FileAccess.WRITE)
    if file == null:
        _fail("Could not write the launch UI configuration.")
        return false
    file.store_string(JSON.stringify({
        "schemaVersion": 1,
        "saveRoot": _root_path.path_join("saves"),
        "sessionRoot": _root_path.path_join("sessions"),
        "launchers": [{
            "id": "fixture",
            "systemIds": ["snes"],
            "executable": _fixture_path,
            "arguments": [
                "--game-id", "{gameId}",
                "--content", "{contentPath}",
                "--save-dir", "{saveDir}",
                "--session-dir", "{sessionDir}",
                "--input-profile", "{inputProfilePath}",
                "--sleep-ms", str(sleep_ms),
                "--exit-code", str(exit_code),
            ],
            "workingDirectory": "{sessionDir}",
            "environment": {
                "RETROLIFE_GAME_ID": "{gameId}",
                "RETROLIFE_SYSTEM_ID": "{systemId}",
            },
            "timeoutMs": 10_000,
            "maxOutputBytes": 16_384,
            "returnPolicy": "waitForExit",
        }],
        "games": [{
            "gameId": "chrono-trigger",
            "systemId": "snes",
            "contentPath": _content_path,
            "launcherId": "fixture",
        }],
        "inputProfiles": [_input_profile()],
    }))
    return true


func _input_profile() -> Dictionary:
    var bindings: Array = []
    var actions := ["up", "down", "left", "right", "south", "east", "start"]
    for index in range(actions.size()):
        bindings.append({
            "action": actions[index],
            "input": {"kind": "button", "code": index},
        })
    return {
        "id": "fixture-snes-player-1",
        "systemId": "snes",
        "player": 1,
        "glyphFamily": "generic",
        "controller": {
            "stableId": "fixture-controller",
            "displayName": "Fixture Controller",
        },
        "bindings": bindings,
    }


func _wait_for_idle(integration: Node, maximum_frames: int) -> bool:
    for _frame in range(maximum_frames):
        if str(integration.call("active_operation_id")).is_empty():
            return true
        await process_frame
    _fail("The launch UI did not return to idle within the frame budget.")
    return false


func _game_cards(scene: Node) -> Array[Button]:
    var grid := scene.find_child("GameGrid", true, false)
    var cards: Array[Button] = []
    if grid == null:
        return cards
    for child in grid.get_children():
        if child is Button and not child.is_queued_for_deletion():
            var game_id := str(child.get_meta("game_id", ""))
            if not game_id.is_empty():
                cards.append(child)
    return cards


func _details_visible(scene: Node) -> bool:
    var overlay := scene.find_child("DetailsOverlay", true, false) as Control
    return overlay != null and overlay.visible


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
    Input.warp_mouse(center)
    await process_frame
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.position = center
    press.global_position = center
    press.pressed = true
    control.get_viewport().push_input(press)
    await process_frame
    var release := press.duplicate()
    release.pressed = false
    control.get_viewport().push_input(release)
    await process_frame


func _settle(frames: int) -> void:
    for _frame in range(frames):
        await process_frame


func _remove_configuration() -> void:
    if FileAccess.file_exists(CONFIGURATION_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIGURATION_PATH))


func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    _remove_configuration()
    push_error("RETROLIFE_LAUNCH_UI_SMOKE_FAILED: %s" % message)
    quit(1)
