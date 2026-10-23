extends SceneTree

## In-game settings must own the pause across nested editors. These fixtures
## do not load a native core, a ROM, saved bindings, or a real user preference.
const ShaderSmoke = preload("res://scripts/gameplay_shader_smoke.gd")

class GameplayFixture:
    extends "res://scripts/launch_integration.gd"

class RealOwnerFixture:
    extends "res://scripts/cartridge_library.gd"

    func _ready() -> void:
        persist_preferences = false
        _fetch_collection_labels = false
        _ensure_input_actions()
        _build_shell()

class OwnerFixture:
    extends Control
    var _settings_panel: PopupPanel
    var library_open_calls := 0

    func _ready() -> void:
        _settings_panel = PopupPanel.new()
        _settings_panel.size = Vector2i(340, 220)
        add_child(_settings_panel)

    func _show_settings() -> void:
        library_open_calls += 1
        _settings_panel.popup_centered(Vector2i(340, 220))

var _failure := ""
var _settings_path := ""

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _settings_path = "user://gameplay-settings-smoke-%d.cfg" % Time.get_ticks_usec()
    for action in preload("res://scripts/workspace/bindings.gd").ACTIONS:
        if not InputMap.has_action("game_" + action):
            InputMap.add_action("game_" + action)
    if not InputMap.has_action("game_pause"):
        InputMap.add_action("game_pause")
    root.size = Vector2i(1280, 800)
    var backend := ShaderSmoke.BackendFixture.new()
    root.add_child(backend)
    var owner := OwnerFixture.new()
    root.add_child(owner)
    var first := _new_gameplay(backend, owner)
    first._open_gameplay_settings()
    _check(not first._settings_open and not first._settings_panel.visible and backend.pause_calls == 0, "Inactive gameplay cannot open in-game settings")
    _check(first.start_game("settings-fixture", "Settings fixture").get("ok", false), "Synthetic settings session starts")
    first.set_process(false)
    first._refresh_session_metadata()
    first._poll_video()
    await process_frame
    await process_frame
    _check(first._settings_button.visible and first._settings_button.focus_mode == Control.FOCUS_ALL and not first._settings_button.accessibility_name.is_empty(), "Settings is a discoverable, keyboard-accessible in-game action")

    first.set_journey_visible(false)
    first._set_shader_preset("scanlines", 0.4)
    first._settings_panel.emit_signal("volume_changed", 0.35)
    var config := ConfigFile.new()
    _check(config.load(_settings_path) == OK and is_equal_approx(float(config.get_value("audio", "volume", 1.0)), 0.35), "Gameplay volume is saved in the isolated preferences file")
    _check(config.get_value("display_snes", "preset", "") == "scanlines" and config.get_value("view", "journey_visible", true) == false, "Saving volume preserves shader and Journey preferences")
    _check(is_equal_approx(db_to_linear(first._audio_player.volume_db), 0.35), "Volume changes reach the actual gameplay audio player")
    first.set_journey_visible(true)
    config.load(_settings_path)
    _check(is_equal_approx(float(config.get_value("audio", "volume", 1.0)), 0.35), "Saving Journey preference preserves audio volume")
    _check(not FileAccess.file_exists(_settings_path + ".tmp"), "Preference replacement leaves no temporary file")

    first._set_logical_input("south", true)
    var pause_before := backend.pause_calls
    first._unhandled_input(_key(KEY_F9))
    _check(first._settings_open and first._settings_panel.visible and first.is_paused(), "F9 opens settings after pausing gameplay")
    _check(backend.pause_calls == pause_before + 1 and not bool(first._last_input_state.get("south", true)), "Opening settings pauses once and releases held game buttons")
    var resume_before := backend.resume_calls
    var frames_before := backend.advance_calls
    var inputs_before := backend.input_calls.size()
    Input.action_press("game_south")
    first._process(0.2)
    _check(backend.advance_calls == frames_before, "The settings hub cannot advance emulation")
    _check_no_pressed_inputs(backend.input_calls.slice(inputs_before), "Hub input cannot reach the core")
    Input.action_release("game_south")
    first._unhandled_input(_key(KEY_F9, true))
    _check(first._settings_open, "Held F9 does not repeatedly close settings")
    first._journey_support_changed(false)
    _check(not first._settings_panel.get("_journey_check").visible, "Settings cannot expose Journey for an unsupported game")
    first._journey_support_changed(true)
    _check(first._settings_panel.get("_journey_check").visible, "Validated support restores the Journey setting")

    first._settings_panel.get("_section_buttons")["shaders"].emit_signal("pressed")
    _check(first._settings_open and first._settings_child == "shaders" and first._shader_panel.visible and not first._settings_panel.visible, "Shaders opens as a child of the settings pause")
    _check(backend.pause_calls == pause_before + 1 and backend.resume_calls == resume_before, "Moving from settings into shaders neither pauses twice nor resumes")
    first._shader_panel.emit_signal("preset_changed", "crt", 0.55)
    _check(first._shader_preset == "crt", "The nested shader editor remains functional")
    first._unhandled_input(_key(KEY_ESCAPE))
    await process_frame
    _check(first._settings_open and first._settings_panel.visible and first._settings_child.is_empty() and not first._shader_panel.visible, "Escape from a shader child returns to settings")
    _check(first.is_paused() and backend.resume_calls == resume_before, "Leaving the shader child keeps the original settings pause")

    first._settings_panel.get("_section_buttons")["library"].emit_signal("pressed")
    _check(owner.library_open_calls == 1 and owner._settings_panel.visible and first._settings_child == "library", "Library settings reuse the owner's existing preferences window")
    inputs_before = backend.input_calls.size()
    Input.action_press("game_south")
    first._process(0.2)
    _check(backend.advance_calls == frames_before, "An external settings window still freezes emulation")
    _check_no_pressed_inputs(backend.input_calls.slice(inputs_before), "External dialog input cannot reach the game")
    Input.action_release("game_south")
    owner._settings_panel.hide()
    await process_frame
    _check(first._settings_open and first._settings_panel.visible and first._settings_child.is_empty(), "Closing library preferences returns to the settings hub")
    _check(backend.resume_calls == resume_before, "Closing a child window never resumes the game")

    first._settings_panel.get("_section_buttons")["controllers"].emit_signal("pressed")
    _check(first._settings_child == "controllers" and first._controller_settings.visible, "Controller settings are accessible without ending the current session")
    var controller = first._controller_settings
    controller._mode.select(1)
    var bindings_before: Dictionary = preload("res://scripts/workspace/bindings.gd").snapshot()
    controller._capture("south")
    first._unhandled_input(_key(KEY_F9))
    _check(first._settings_open and first._settings_child == "controllers" and controller.visible, "F9 cannot close settings while the controller is capturing an input")
    controller._input(_key(KEY_F9))
    _check(controller._pending == "south" and "reserved" in controller._status.text.to_lower(), "Capturing F9 reports the reserved shortcut without completing a binding")
    _check(preload("res://scripts/workspace/bindings.gd").snapshot() == bindings_before, "A reserved shortcut cannot mutate the current input bindings")
    first._unhandled_input(_key(KEY_ESCAPE))
    controller._input(_key(KEY_ESCAPE))
    _check(controller._pending.is_empty() and controller.visible and first._settings_child == "controllers", "Escape cancels capture without closing its controller dialog")
    inputs_before = backend.input_calls.size()
    Input.action_press("game_south")
    first._process(0.2)
    _check_no_pressed_inputs(backend.input_calls.slice(inputs_before), "Controller configuration input cannot press an emulated button")
    Input.action_release("game_south")
    first._controller_settings.hide()
    await process_frame
    _check(first._settings_open and first._settings_panel.visible and first._settings_child.is_empty(), "Finishing controller setup returns to the settings hub")
    _check(backend.pause_calls == pause_before + 1 and backend.resume_calls == resume_before, "All child dialogs share one uninterrupted pause")

    Input.action_press("game_south")
    first._close_gameplay_settings()
    await process_frame
    _check(not first._settings_open and not first._settings_panel.visible and not first.is_paused(), "Done restores a game that was playing before settings")
    _check(backend.resume_calls == resume_before + 1 and first._frame.has_focus(), "Leaving settings resumes once and restores game focus")
    inputs_before = backend.input_calls.size()
    first._sync_inputs()
    _check_no_pressed_inputs(backend.input_calls.slice(inputs_before), "A held confirmation button cannot leak out of settings")
    Input.action_release("game_south")
    first._sync_inputs()
    Input.action_press("game_south")
    first._sync_inputs()
    _check(bool(first._last_input_state.get("south", false)), "Fresh gameplay input works after releasing the closing button")
    Input.action_release("game_south")
    first._sync_inputs()

    first._toggle_pause()
    pause_before = backend.pause_calls
    resume_before = backend.resume_calls
    first._open_gameplay_settings()
    first._open_settings_section("shaders")
    first._close_shader_options()
    first._unhandled_input(_key(KEY_ESCAPE))
    await process_frame
    _check(not first._settings_open and first.is_paused() and first._pause_overlay.visible, "Settings opened from Pause restores the original paused screen")
    _check(backend.pause_calls == pause_before and backend.resume_calls == resume_before and backend.stop_calls == 0, "Nested settings preserve an existing pause without stop or resume")
    first._resume_game()

    first._open_shader_options()
    pause_before = backend.pause_calls
    resume_before = backend.resume_calls
    first._unhandled_input(_key(KEY_F9))
    _check(first._settings_open and first._settings_panel.visible and not first._shader_panel.visible, "F9 can transfer an existing standalone shader preview into settings")
    _check(backend.pause_calls == pause_before and backend.resume_calls == resume_before, "Transferring a preview preserves pause ownership without a running frame")
    first._close_gameplay_settings()
    _check(not first.is_paused() and backend.resume_calls == resume_before + 1, "Leaving transferred settings restores the original playing state")

    backend.fail_pause = true
    first._open_gameplay_settings()
    _check(not first._settings_open and not first._settings_panel.visible and not first.is_paused(), "A rejected backend pause cannot open an apparently frozen settings screen")
    backend.fail_pause = false
    first._open_gameplay_settings()
    backend.fail_resume = true
    first._close_gameplay_settings()
    _check(not first._settings_open and first.is_paused() and first._pause_overlay.visible, "A failed settings resume leaves normal pause controls available")
    backend.fail_resume = false
    first._resume_game()

    first._open_gameplay_settings()
    first._open_settings_section("library")
    resume_before = backend.resume_calls
    backend.fail_stop = true
    await first._stop_session()
    _check(not first._settings_open and not first._settings_panel.visible and not owner._settings_panel.visible, "A failed quit dismisses the settings hub and external child safely")
    _check(first.is_paused() and first._pause_overlay.visible and first._exit_button.is_visible_in_tree() and not first._exit_button.disabled, "A failed quit from settings restores an available exit retry")
    _check(not first.active_session_id().is_empty() and backend.resume_calls == resume_before, "Child close signals during failed quit do not resume the retained session")
    backend.fail_stop = false
    first._resume_game()
    first._open_gameplay_settings()
    first._open_settings_section("controllers")
    resume_before = backend.resume_calls
    await first._stop_session()
    await process_frame
    _check(first.active_session_id().is_empty() and not first._settings_open and not first._controller_settings.visible, "Stopping gameplay closes the controller child and settings state")
    _check(backend.resume_calls == resume_before, "Child close signals cannot resume a stopped session")
    first.free()

    var fresh := _new_gameplay(backend, owner)
    _check(is_equal_approx(fresh._gameplay_volume, 0.35), "A fresh gameplay instance restores saved audio volume")
    fresh.start_game("settings-fixture-restored", "Restored settings fixture")
    fresh.set_process(false)
    _check(is_equal_approx(db_to_linear(fresh._audio_player.volume_db), 0.35), "Restored volume is applied when the new game starts")
    _check(fresh._shader_preset == "crt" and fresh._journey_visible, "Restored audio coexists with shader and Journey preferences")
    fresh._set_gameplay_volume(4.0)
    _check(is_equal_approx(db_to_linear(fresh._audio_player.volume_db), 1.0), "Volume above full scale is clamped")
    fresh._set_gameplay_volume(-4.0)
    _check(db_to_linear(fresh._audio_player.volume_db) <= 0.001, "Negative volume safely mutes the game")
    fresh._set_gameplay_volume(NAN)
    _check(is_finite(db_to_linear(fresh._audio_player.volume_db)), "Non-finite input cannot become an invalid audio gain")
    fresh._session_id = ""
    fresh.free()
    owner.free()
    await _exercise_real_owner(backend)
    backend.free()
    Input.action_release("game_south")
    for path in [_settings_path, _settings_path + ".tmp"]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    if _failure.is_empty():
        print("Gameplay settings smoke passed: shared pause across nested dialogs, input isolation, saved audio and recoverable exit failures. No user bindings or native core were touched.")
        quit(0)
    else:
        push_error(_failure)
        quit(1)

func _new_gameplay(backend: Node, owner: Control) -> GameplayFixture:
    var gameplay := GameplayFixture.new()
    gameplay.preferences_path = _settings_path
    root.add_child(gameplay)
    gameplay.configure(backend, owner)
    return gameplay

func _exercise_real_owner(backend: Node) -> void:
    var owner := RealOwnerFixture.new()
    owner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(owner)
    var gameplay := _new_gameplay(backend, owner)
    owner._gameplay = gameplay
    owner._at_console_home = false
    owner._console_home.hide()
    owner._carousel.show()
    # A popup may request library focus just before the game is launched.
    owner._restore_carousel_focus()
    gameplay.start_game("actual-owner-fixture", "Actual owner fixture")
    gameplay.set_process(false)
    await process_frame
    await process_frame
    _check(gameplay._frame.has_focus(), "A queued library focus request cannot steal focus after a game starts")
    gameplay._open_gameplay_settings()
    gameplay._open_settings_section("library")
    _check(owner._settings_panel.visible and not owner._software_updates_button.visible, "Actual library preferences hide software updates during a live game")
    gameplay._unhandled_input(_key(KEY_F9))
    await process_frame
    await process_frame
    _check(not gameplay._settings_open and not owner._settings_panel.visible and gameplay._frame.has_focus(), "Actual owner popup_hide cannot steal gameplay focus when F9 closes all settings")
    gameplay._open_gameplay_settings()
    gameplay._open_settings_section("library")
    backend.fail_stop = true
    var resume_before: int = backend.resume_calls
    await gameplay._stop_session()
    await process_frame
    await process_frame
    _check(gameplay._pause_overlay.visible and gameplay._exit_button.has_focus(), "Actual owner popup_hide preserves the exit retry focus after a failed save")
    _check(not owner._settings_panel.visible and backend.resume_calls == resume_before, "Failed save closes actual library preferences without resuming gameplay")
    backend.fail_stop = false
    await gameplay._stop_session()
    owner._show_settings()
    _check(owner._software_updates_button.visible, "Software updates become available again after returning to the library")
    owner._settings_panel.hide()
    await process_frame
    gameplay.free()
    owner._gameplay = null
    owner.free()

func _key(code: Key, echo := false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    event.echo = echo
    return event

func _check_no_pressed_inputs(inputs: Array, description: String) -> void:
    for input in inputs:
        _check(not bool(input.get("pressed", false)), description)

func _check(ok: bool, description: String) -> void:
    if not ok and _failure.is_empty():
        _failure = description
