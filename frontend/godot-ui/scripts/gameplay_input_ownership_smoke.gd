extends SceneTree

# Real viewport dispatch with synthetic controller input; no ROM or user saves.
const Fixture = preload("res://scripts/gameplay_shader_smoke.gd")
class Game:
    extends "res://scripts/launch_integration.gd"
    var fullscreen_requests := 0
    func _toggle_window_fullscreen() -> void:
        fullscreen_requests += 1

var failure := ""
func _init() -> void: call_deferred("run")
func run() -> void:
    var mapping := preload("res://scripts/main.gd").new()
    mapping._ensure_input_actions()
    mapping.free()
    var backend := Fixture.BackendFixture.new()
    root.add_child(backend)
    var game := Game.new()
    game.persist_preferences = false
    root.add_child(game)
    game.configure(backend, game)
    game.start_game("synthetic", "Controller ownership")
    game.set_process(false)
    await process_frame
    await process_frame
    var fullscreen := game.find_child("GameplayFullscreen", true, false) as Button
    for pair in [[JOY_BUTTON_B, "east"], [JOY_BUTTON_A, "south"], [JOY_BUTTON_X, "west"], [JOY_BUTTON_Y, "north"], [JOY_BUTTON_START, "start"]]:
        fullscreen.grab_focus()
        var before := backend.input_calls.size()
        await send_button(int(pair[0]), true)
        check(not game.is_paused(), "Face/Start buttons cannot pause gameplay")
        check(game.fullscreen_requests == 0, "Focused fullscreen button cannot consume game input")
        check(backend.input_calls.slice(before).has({"action": pair[1], "pressed": true}), "Game receives " + str(pair[1]))
        await send_button(int(pair[0]), false)
        check(backend.input_calls.has({"action": pair[1], "pressed": false}), "Release reaches game")
    await send_button(JOY_BUTTON_RIGHT_STICK, true)
    check(game.is_paused(), "R3 still opens pause")
    await send_button(JOY_BUTTON_RIGHT_STICK, false)
    game._resume_game()
    game._open_gameplay_settings()
    check(game._settings_open and game.is_paused(), "Settings still pauses")
    await send_button(JOY_BUTTON_B, true)
    check(not game._settings_open and not game.is_paused(), "Circle returns from settings without reaching game")
    await send_button(JOY_BUTTON_B, false)
    game._session_id = ""
    game.free()
    backend.free()
    if failure.is_empty(): print("Controller ownership passed: face buttons/Start reach the core, stale fullscreen focus is isolated, R3 pauses and Circle returns from settings.")
    else: push_error(failure)
    quit(0 if failure.is_empty() else 1)
func send_button(index: int, pressed: bool) -> void:
    var event := InputEventJoypadButton.new()
    event.device = 0
    event.button_index = index
    event.pressed = pressed
    Input.parse_input_event(event)
    await process_frame
    await process_frame
func check(ok: bool, message: String) -> void:
    if not ok and failure.is_empty(): failure = message
