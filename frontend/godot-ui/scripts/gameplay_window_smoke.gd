extends SceneTree

class GameplayFixture:
    extends "res://scripts/launch_integration.gd"
    var drag_requests := 0
    var fullscreen_requests := 0

    func _begin_window_drag() -> void:
        drag_requests += 1

    func _toggle_window_fullscreen() -> void:
        fullscreen_requests += 1

class BackendFixture:
    extends Node

    func start_emulation_json(_id: String) -> String:
        return JSON.stringify({"schemaVersion": 1, "ok": true, "data": {"sessionId": "fixture"}})

var _failure := ""
var _settings_path := ""

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _settings_path = "user://gameplay-window-smoke-%d.cfg" % Time.get_ticks_usec()
    for action in preload("res://scripts/workspace/bindings.gd").ACTIONS:
        if not InputMap.has_action("game_" + action):
            InputMap.add_action("game_" + action)
    if not InputMap.has_action("game_pause"):
        InputMap.add_action("game_pause")
    root.size = Vector2i(1024, 640)
    var backend := BackendFixture.new()
    root.add_child(backend)
    var first := _new_gameplay()
    first.configure(backend, first)
    _check(first.start_game("fixture", "Window fixture").get("ok", false), "Fixture session starts")
    first.set_process(false)
    await process_frame
    await process_frame
    _check(first._journey.visible, "Journey defaults to visible")
    _check(first._journey.custom_minimum_size.x == 340, "Compact window uses 340px journal")
    var frame_panel := first.get_node("GameplayMargin/GameplayColumn/PlayAndJourney/GameplayFramePanel") as Control
    var old_width := frame_panel.size.x
    first.set_journey_visible(false)
    await process_frame
    await process_frame
    _check(not first._journey.visible and not first._journey_toggle.button_pressed, "Journey button and panel hide together")
    _check(first._journey_toggle.text == "Show Journey", "Hidden journal retains a discoverable Show Journey action")
    _check(first._frame.has_focus(), "Toggling returns input focus to game")
    _check(frame_panel.size.x > old_width + 250, "Hiding Journey gives its space back to the game")
    _check(first._journey_toggle.focus_mode == Control.FOCUS_ALL, "Journey toggle remains keyboard accessible")
    _check(not first._journey_toggle.accessibility_name.is_empty(), "Journey toggle has an accessible label")
    var config := ConfigFile.new()
    _check(config.load(_settings_path) == OK and config.get_value("view", "journey_visible", true) == false, "Hidden preference saved")

    var click := InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_LEFT
    click.pressed = true
    first._gameplay_header_input(click)
    _check(first.drag_requests == 1, "Actual left press requests window drag")
    click.pressed = false
    first._gameplay_header_input(click)
    _check(first.drag_requests == 1, "Release does not begin another drag")
    click.pressed = true
    click.double_click = true
    first._gameplay_header_input(click)
    _check(first.drag_requests == 1 and first.fullscreen_requests == 1, "Double click toggles fullscreen without a drag")
    click.button_index = MOUSE_BUTTON_RIGHT
    first._gameplay_header_input(click)
    _check(first.fullscreen_requests == 1, "Right click does not toggle fullscreen")
    var key := InputEventKey.new()
    key.keycode = KEY_F11
    key.pressed = true
    first._unhandled_input(key)
    _check(first.fullscreen_requests == 2, "F11 works in gameplay")
    key.echo = true
    first._unhandled_input(key)
    _check(first.fullscreen_requests == 2, "F11 repeat cannot flicker window mode")
    _check(first._pause_overlay.offset_top >= first._gameplay_header.get_global_rect().end.y, "Pause overlay leaves window drag region exposed")
    first._session_id = ""
    first.free()

    var second := _new_gameplay()
    _check(not second._journey.visible and second._journey_toggle.text == "Show Journey", "Hidden Journey survives a fresh gameplay instance")
    second.set_journey_visible(true)
    second.free()
    root.size = Vector2i(1600, 900)
    var third := _new_gameplay()
    await process_frame
    await process_frame
    _check(third._journey.visible, "Showing Journey is persisted too")
    _check(third._journey.custom_minimum_size.x == 400, "Wide gameplay provides a 400px journal")
    _check(str(ProjectSettings.get_setting("application/boot_splash/image", "")).ends_with("retrolife-splash.png"), "Boot splash selects original RetroLife artwork")
    third.free()
    backend.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings_path))
    if FileAccess.file_exists(_settings_path + ".tmp"):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings_path + ".tmp"))
    if _failure.is_empty():
        print("Gameplay window smoke passed: drag/fullscreen intents, persistent Journey visibility, game focus and responsive frame layout.")
        quit(0)
    else:
        push_error(_failure)
        quit(1)

func _new_gameplay() -> GameplayFixture:
    var gameplay := GameplayFixture.new()
    gameplay.preferences_path = _settings_path
    root.add_child(gameplay)
    return gameplay

func _check(ok: bool, description: String) -> void:
    if not ok and _failure.is_empty():
        _failure = description
