extends SceneTree

## Synthetic presentation checks only. No ROM, native core, saves or journey
## mutations are used; visual shader quality is checked separately on a GPU.

class GameplayFixture:
    extends "res://scripts/launch_integration.gd"

class BackendFixture:
    extends Node
    var pause_calls := 0
    var resume_calls := 0
    var stop_calls := 0
    var advance_calls := 0
    var input_calls: Array = []
    var fail_pause := false
    var fail_resume := false
    var fail_stop := false
    var fail_stop_late := false
    var status := "playing"
    var width := 256
    var height := 224

    func _response(data: Dictionary = {}) -> String:
        return JSON.stringify({"schemaVersion": 1, "ok": true, "data": data})

    func start_emulation_json(_id: String) -> String:
        status = "playing"
        return _response({"sessionId": "synthetic-snes", "videoWidth": width, "videoHeight": height})

    func journey_state_json(_id: String) -> String:
        var achievements: Array = []
        for index in 4:
            achievements.append({"id": ["first_stage", "secret", "boss", "finale"][index], "title": "Synthetic event %d" % index, "description": "Fixture only", "xp": 100, "earned": false, "artIndex": index + 4})
        return _response({"seconds": 0, "achievements": achievements, "supported": true, "detectionStatus": "waiting", "detectionMessage": "Synthetic game events.", "legacyPreserved": false, "collected": 0, "totalRewards": 4, "gameXp": 0, "totalXp": 0, "level": 1, "levelProgress": 0})

    func emulation_status_json() -> String:
        return _response({"status": status, "videoWidth": width, "videoHeight": height, "sampleRate": 32040, "fps": 60, "aspectRatio": 4.0 / 3.0})

    func emulation_frame_info_json() -> String:
        return _response({"width": width, "height": height, "sampleRate": 32040, "fps": 60, "aspectRatio": 4.0 / 3.0})

    func emulation_frame_rgba() -> PackedByteArray:
        var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
        image.fill(Color(0.2, 0.55, 0.8, 1.0))
        return image.get_data()

    func emulation_advance_frame_json() -> String:
        advance_calls += 1
        return _response()

    func set_emulation_input_json(action: String, pressed: bool) -> String:
        input_calls.append({"action": action, "pressed": pressed})
        return _response()

    func pause_emulation_json() -> String:
        pause_calls += 1
        if fail_pause:
            return JSON.stringify({"schemaVersion": 1, "ok": false, "error": "Synthetic pause failure."})
        status = "paused"
        return _response()

    func resume_emulation_json() -> String:
        resume_calls += 1
        if fail_resume:
            return JSON.stringify({"schemaVersion": 1, "ok": false, "error": "Synthetic resume failure."})
        status = "playing"
        return _response()

    func stop_emulation_json() -> String:
        stop_calls += 1
        if fail_stop:
            return JSON.stringify({"schemaVersion": 1, "ok": false, "error": "Synthetic stop failure."})
        status = "failed" if fail_stop_late else "stopped"
        return _response()

var _failure := ""
var _settings_path := ""

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _settings_path = "user://gameplay-shader-smoke-%d.cfg" % Time.get_ticks_usec()
    for action in preload("res://scripts/workspace/bindings.gd").ACTIONS:
        if not InputMap.has_action("game_" + action):
            InputMap.add_action("game_" + action)
    if not InputMap.has_action("game_pause"):
        InputMap.add_action("game_pause")
    root.size = Vector2i(1280, 800)
    var backend := BackendFixture.new()
    root.add_child(backend)
    var first := _new_gameplay(backend)
    _check(first._shader_preset == "original" and is_equal_approx(first._shader_strength, 0.65), "Fresh settings use Original and the default strength")
    first._open_shader_options()
    _check(not first._shader_panel.visible and backend.pause_calls == 0, "Display options cannot start an inactive emulation session")
    _check(first.start_game("shader-fixture", "Shader fixture").get("ok", false), "Synthetic SNES starts")
    first.set_process(false)
    first._refresh_session_metadata()
    first._poll_video()
    await process_frame
    await process_frame
    _check(first._frame.texture != null and first._frame.texture.get_size() == Vector2(256, 224), "Synthetic RGBA frame reaches the display")
    _check(first._frame.material == null and first._frame.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Original keeps unmodified nearest-neighbor pixels")
    _check(first._shader_button.visible and first._shader_button.focus_mode == Control.FOCUS_ALL and not first._shader_button.accessibility_name.is_empty(), "SNES shader action is visible and accessible")

    first.set_journey_visible(false)
    first._set_shader_preset("crt", 0.8)
    var config := ConfigFile.new()
    _check(config.load(_settings_path) == OK and config.get_value("view", "journey_visible", true) == false, "Saving display settings preserves the Journey preference")
    _check(config.get_value("display_snes", "preset", "") == "crt" and is_equal_approx(float(config.get_value("display_snes", "strength", 0.0)), 0.8), "Preset and intensity are persisted together")
    first.set_journey_visible(true)
    config.load(_settings_path)
    _check(config.get_value("display_snes", "preset", "") == "crt", "Saving Journey visibility preserves the display preference")
    _check(not FileAccess.file_exists(_settings_path + ".tmp"), "Atomic preference replacement leaves no staging file")

    var effect_values: Array = []
    for preset in ["smooth", "scanlines", "crt"]:
        first._set_shader_preset(preset, 0.65)
        _check(first._frame.material is ShaderMaterial, "%s installs a presentation shader" % preset)
        if first._frame.material is ShaderMaterial:
            effect_values.append(first._frame.material.get_shader_parameter("effect"))
    _check(effect_values == [0, 1, 2], "Each presentation preset selects its distinct effect")
    _check(first.material == null and first._journey.material == null, "Display shaders leave the app text and Journey unfiltered")
    var other_frame := TextureRect.new()
    preload("res://scripts/workspace/snes_display.gd").apply(other_frame, "crt", 0.65)
    _check(other_frame.material != first._frame.material, "Different frame views do not share mutable material state")
    other_frame.free()
    var prior_texture: Texture2D = first._frame.texture
    var prior_material: Material = first._frame.material
    backend.width = 512
    backend.height = 448
    first._poll_video()
    _check(first._frame.texture != prior_texture and first._frame.texture.get_size() == Vector2(512, 448), "Resolution changes replace the frame texture with the actual core dimensions")
    _check(first._frame.material == prior_material, "A core resolution change keeps the selected effect on the new frame")
    first._set_shader_preset("original", 0.65)
    _check(first._frame.material == null and first._frame.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Returning to Original fully removes shader processing")

    first._set_logical_input("south", true)
    var pause_before := backend.pause_calls
    first._unhandled_input(_key(KEY_F8))
    _check(first._shader_panel.visible and first.is_paused() and backend.pause_calls == pause_before + 1, "F8 pauses the actual backend before opening the editor")
    _check(not bool(first._last_input_state.get("south", true)), "Opening the editor releases a held game button")
    var held_count := backend.input_calls.size()
    var frames_before := backend.advance_calls
    Input.action_press("game_south")
    first._process(0.2)
    _check(backend.advance_calls == frames_before, "No emulated frames advance while choosing an effect")
    for input in backend.input_calls.slice(held_count):
        _check(not bool(input.get("pressed", false)), "Editor input must never press a game button")
    first._shader_panel.emit_signal("preset_changed", "scanlines", 0.4)
    _check(first._shader_preset == "scanlines" and is_equal_approx(first._shader_strength, 0.4), "Editor selection updates the game's preview material and saved preference")
    first._unhandled_input(_key(KEY_F8, true))
    _check(first._shader_panel.visible, "Repeated F8 key events cannot flicker the editor")
    first._unhandled_input(_key(KEY_F8))
    await process_frame
    _check(not first._shader_panel.visible and not first.is_paused() and backend.resume_calls == 1, "Closing F8 restores a previously playing game once")
    _check(first._frame.has_focus(), "Closing the editor returns keyboard focus to gameplay")
    held_count = backend.input_calls.size()
    first._sync_inputs()
    for input in backend.input_calls.slice(held_count):
        _check(not bool(input.get("pressed", false)), "A button held to close the editor cannot leak into the game")
    Input.action_release("game_south")
    first._sync_inputs()
    Input.action_press("game_south")
    first._sync_inputs()
    _check(bool(first._last_input_state.get("south", false)), "A fresh press works after the closing button is released")
    Input.action_release("game_south")
    first._sync_inputs()

    first._toggle_pause()
    pause_before = backend.pause_calls
    var resume_before := backend.resume_calls
    first._open_shader_options()
    _check(first._shader_panel.visible and backend.pause_calls == pause_before, "Opening from Pause does not issue another backend pause")
    first._unhandled_input(_key(KEY_ESCAPE))
    await process_frame
    _check(not first._shader_panel.visible and first.is_paused() and first._pause_overlay.visible, "Escape restores the existing pause screen")
    _check(backend.resume_calls == resume_before and backend.stop_calls == 0, "Escape from the editor neither resumes a paused game nor exits it")
    _check(first._resume_button.has_focus(), "Closing into Pause restores its keyboard focus")
    first._resume_game()

    backend.fail_pause = true
    first._open_shader_options()
    _check(not first._shader_panel.visible and not first.is_paused(), "A rejected backend pause cannot falsely open a frozen preview")
    backend.fail_pause = false
    first._open_shader_options()
    backend.fail_resume = true
    first._close_shader_options()
    _check(not first._shader_panel.visible and first.is_paused() and first._pause_overlay.visible, "A failed resume leaves an honest, recoverable paused screen")
    backend.fail_resume = false
    first._resume_game()

    first._set_shader_preset("crt", 0.72)
    first._session_id = ""
    first.free()
    var second := _new_gameplay(backend)
    _check(second._shader_preset == "crt" and is_equal_approx(second._shader_strength, 0.72), "Fresh gameplay instances restore the selected effect and intensity")
    second.start_game("shader-fixture-2", "Another shader fixture")
    second.set_process(false)
    _check(second._frame.material is ShaderMaterial, "A restored preset applies to a newly started session")
    second._set_shader_preset("not-a-preset", NAN)
    _check(second._shader_preset == "original" and is_finite(second._shader_strength) and second._frame.material == null, "Unknown IDs and non-finite intensity safely fall back")
    second._set_shader_preset("crt", 4.0)
    _check(is_equal_approx(second._shader_strength, 1.0), "Intensity above the range is clamped")
    second._set_shader_preset("crt", -4.0)
    _check(is_equal_approx(second._shader_strength, 0.0), "Intensity below the range is clamped")
    _check(second._frame.material == null and second._frame.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Zero intensity gives the original unfiltered picture")
    second._open_shader_options()
    resume_before = backend.resume_calls
    backend.fail_stop = true
    await second._stop_session()
    _check(not second.active_session_id().is_empty() and second.is_paused() and not second._stopping, "An immediately rejected stop preserves the paused session")
    _check(not second._shader_panel.visible and second._pause_overlay.visible and second._pause_button.text == "Resume", "A failed stop from the editor restores the normal pause screen and honest header action")
    _check(second._exit_button.is_visible_in_tree() and not second._exit_button.disabled, "A rejected stop leaves Exit to library available for retry")
    _check(backend.resume_calls == resume_before, "A rejected stop must not resume emulation implicitly")
    backend.fail_stop = false
    second._resume_game()
    second._open_shader_options()
    resume_before = backend.resume_calls
    backend.fail_stop_late = true
    await second._stop_session()
    _check(not second.active_session_id().is_empty() and second.is_paused() and not second._stopping, "An asynchronous save failure preserves the paused session")
    _check(not second._shader_panel.visible and second._pause_overlay.visible and second._pause_button.text == "Resume", "The asynchronous failure handler restores the pause screen after dismissing the editor")
    _check(second._exit_button.is_visible_in_tree() and not second._exit_button.disabled, "An asynchronous save failure keeps Exit to library available for retry")
    _check(backend.resume_calls == resume_before, "An asynchronous save failure never resumes an unconfirmed session")
    backend.fail_stop_late = false
    second._resume_game()
    second._open_shader_options()
    resume_before = backend.resume_calls
    var stop_before := backend.stop_calls
    await second._stop_session()
    _check(second.active_session_id().is_empty() and not second._shader_panel.visible, "Stopping a session also dismisses its display editor")
    _check(backend.resume_calls == resume_before and backend.stop_calls == stop_before + 1, "Stopping from the editor never resumes an ended session")
    second.free()

    config.set_value("display_snes", "preset", "unknown-effect")
    config.set_value("display_snes", "strength", "corrupt")
    config.set_value("view", "journey_visible", false)
    _check(config.save(_settings_path) == OK, "Malformed saved-value fixture is written in its isolated preferences file")
    var malformed := _new_gameplay(backend)
    _check(malformed._shader_preset == "original" and is_finite(malformed._shader_strength) and malformed._shader_strength >= 0.0 and malformed._shader_strength <= 1.0, "Malformed saved values cannot select an invalid effect or non-finite intensity")
    _check(not malformed._journey_visible, "Recovering corrupt display values preserves the unrelated visibility preference")
    malformed.free()
    backend.free()
    Input.action_release("game_south")
    for path in [_settings_path, _settings_path + ".tmp"]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    if _failure.is_empty():
        print("Gameplay shader smoke passed: synthetic frames, effect lifecycle, isolated input, pause restoration, persisted SNES preferences and safe failure states. GPU appearance requires separate visual review.")
        quit(0)
    else:
        push_error(_failure)
        quit(1)

func _new_gameplay(backend: Node) -> GameplayFixture:
    var gameplay := GameplayFixture.new()
    gameplay.preferences_path = _settings_path
    root.add_child(gameplay)
    gameplay.configure(backend, gameplay)
    return gameplay

func _key(code: Key, echo := false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    event.echo = echo
    return event

func _check(ok: bool, description: String) -> void:
    if not ok and _failure.is_empty():
        _failure = description
