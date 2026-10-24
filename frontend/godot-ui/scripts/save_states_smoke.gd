extends SceneTree

## Synthetic state operations only. No core, ROM, actual save file or account is
## opened. Worker completion is explicitly controlled to exercise pending UI.
const ShaderSmoke = preload("res://scripts/gameplay_shader_smoke.gd")

class BackendFixture:
    extends ShaderSmoke.BackendFixture
    var supported := true
    var can_resume := true
    var fail_request := false
    var fail_snapshot := false
    var next_operation := 1
    var starts := 0
    var discontinuity := 0
    var requests: Array[Dictionary] = []
    var operation := {"id": 0, "kind": "", "slot": 0, "status": "idle", "error": ""}
    var slots: Array[Dictionary] = []
    var frame_color := Color(0.2, 0.55, 0.8, 1.0)

    func _init() -> void:
        for slot in 8:
            slots.append({"slot": slot, "occupied": slot in [1, 7], "createdAt": 1700000000, "previewWidth": 2, "previewHeight": 2, "compatible": true, "error": "", "stateBytes": 64})

    func start_emulation_json(_id: String) -> String:
        starts += 1
        status = "playing"
        operation = {"id": 0, "kind": "", "slot": 0, "status": "idle", "error": ""}
        return _response({"sessionId": "synthetic-state-session-%d" % starts, "videoWidth": width, "videoHeight": height})

    func save_states_json() -> String:
        if fail_snapshot:
            return JSON.stringify({"schemaVersion": 1, "ok": false, "error": "Synthetic state listing failure."})
        return _response({"supported": supported, "busy": operation.status == "pending", "slots": slots, "operation": operation, "discontinuity": discontinuity, "canResume": can_resume})

    func save_state_json(slot: int) -> String:
        return _request("save", slot)

    func load_state_json(slot: int) -> String:
        return _request("load", slot)

    func _request(kind: String, slot: int) -> String:
        if fail_request or not supported or operation.status == "pending":
            return JSON.stringify({"schemaVersion": 1, "ok": false, "error": "Synthetic state request failure."})
        var id := next_operation
        next_operation += 1
        operation = {"id": id, "kind": kind, "slot": slot, "status": "pending", "error": ""}
        requests.append(operation.duplicate(true))
        return _response({"operationId": id})

    func complete(success := true) -> void:
        operation.status = "complete" if success else "failed"
        operation.error = "" if success else "Synthetic disk or restore failure."
        if not success:
            return
        if operation.kind == "save":
            slots[operation.slot].occupied = true
            slots[operation.slot].createdAt += 1
        else:
            slots[7].occupied = true
            discontinuity += 1
            width = 512
            height = 239
            frame_color = Color(0.85, 0.25, 0.1, 1.0)

    func emulation_frame_rgba() -> PackedByteArray:
        var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
        image.fill(frame_color)
        return image.get_data()

    func save_state_preview_rgba(slot: int) -> PackedByteArray:
        if slot < 0 or slot >= slots.size() or not slots[slot].occupied:
            return PackedByteArray()
        var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
        image.fill(Color(0.3, 0.7, 0.5, 1.0))
        return image.get_data()

class GameplayFixture:
    extends "res://scripts/launch_integration.gd"

var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    for action in preload("res://scripts/workspace/bindings.gd").ACTIONS:
        if not InputMap.has_action("game_" + action):
            InputMap.add_action("game_" + action)
    if not InputMap.has_action("game_pause"):
        InputMap.add_action("game_pause")
    root.size = Vector2i(1280, 800)
    root.gui_embed_subwindows = true
    var backend := BackendFixture.new()
    root.add_child(backend)
    var game := _new_gameplay(backend)
    game._open_save_states()
    _check(not game._states_panel.visible and backend.pause_calls == 0, "Inactive gameplay cannot open a save-state operation")
    _check(game.start_game("state-fixture", "State fixture").get("ok", false), "Synthetic state session starts")
    game.set_process(false)
    game._refresh_session_metadata()
    game._poll_video()
    await _settle()
    _check(game._states_button.visible and game._states_button.focus_mode == Control.FOCUS_ALL, "Save states is available as a keyboard-accessible gameplay action")
    var frames_before := backend.advance_calls
    game._set_logical_input("south", true)
    game._unhandled_input(_key(KEY_F6))
    game._poll_save_states(true)
    await _settle()
    _check(game._states_panel.visible and game.is_paused() and backend.pause_calls == 1, "F6 pauses once before showing saved slots")
    _check(not bool(game._last_input_state.get("south", true)), "Entering the state browser releases held game buttons")
    var inputs_before := backend.input_calls.size()
    Input.action_press("game_south")
    game._process(0.2)
    _check(backend.advance_calls == frames_before, "An open state browser cannot advance the emulator")
    _check_no_pressed_inputs(backend.input_calls.slice(inputs_before), "Browser navigation cannot become game input")
    Input.action_release("game_south")
    var panel = game._states_panel
    var request_count := backend.requests.size()
    panel.request_slot_action("load", 0)
    _check(backend.requests.size() == request_count, "An empty slot cannot issue a restore request")
    panel.request_slot_action("save", 7)
    _check(backend.requests.size() == request_count, "Recovery is not a writable user slot")
    panel.request_slot_action("save", 1)
    _check(backend.requests.size() == request_count and panel._confirm_button.is_visible_in_tree(), "Overwriting an existing manual save requires confirmation")
    panel._cancel_button.emit_signal("pressed")
    _check(backend.requests.size() == request_count, "Cancelling overwrite preserves the existing save")
    panel.request_slot_action("save", 0)
    _check(backend.requests.size() == request_count + 1 and backend.requests.back().kind == "save", "Saving an empty slot issues one asynchronous request")
    _check(game.is_paused() and panel.visible, "A pending save keeps gameplay paused and the browser present")
    var resume_before := backend.resume_calls
    var stop_before := backend.stop_calls
    game._close_save_states()
    game._unhandled_input(_key(KEY_F9))
    await game._stop_session()
    _check(panel.visible and backend.resume_calls == resume_before and backend.stop_calls == stop_before, "Closing, changing editors and stopping cannot race a pending state write")
    inputs_before = backend.input_calls.size()
    Input.action_press("game_south")
    game._process(0.2)
    _check(backend.advance_calls == frames_before, "Pending storage work never advances a game frame")
    _check_no_pressed_inputs(backend.input_calls.slice(inputs_before), "Pending storage work cannot leak confirmation input")
    Input.action_release("game_south")
    backend.complete()
    game._poll_save_states(true)
    _check(panel.visible and game.is_paused() and not game._states_busy(), "A completed save updates the browser without starting the game behind it")
    Input.action_press("game_south")
    game._close_save_states()
    await _settle()
    _check(not panel.visible and not game.is_paused() and backend.resume_calls == resume_before + 1, "Closing the browser restores a previously playing game once")
    _check(game._frame.has_focus(), "Closing state controls returns focus to gameplay")
    inputs_before = backend.input_calls.size()
    game._sync_inputs()
    _check_no_pressed_inputs(backend.input_calls.slice(inputs_before), "A held closing button cannot leak into the resumed game")
    Input.action_release("game_south")
    game._sync_inputs()
    Input.action_press("game_south")
    game._sync_inputs()
    _check(bool(game._last_input_state.get("south", false)), "Fresh input works after the closing button is released")
    Input.action_release("game_south")
    game._sync_inputs()

    game._toggle_pause()
    resume_before = backend.resume_calls
    var pause_before := backend.pause_calls
    game._open_save_states()
    game._close_save_states()
    _check(game.is_paused() and game._pause_overlay.visible and backend.resume_calls == resume_before and backend.pause_calls == pause_before, "Save states opened from Pause preserves the original pause")
    game._resume_game()
    game._open_gameplay_settings()
    resume_before = backend.resume_calls
    game._open_settings_section("states")
    _check(panel.visible and game._settings_open, "Save states can open as a settings child")
    game._close_save_states()
    _check(not panel.visible and game._settings_panel.visible and game.is_paused() and backend.resume_calls == resume_before, "Closing nested states returns to settings without resuming")
    game._close_gameplay_settings()

    request_count = backend.requests.size()
    game._unhandled_input(_key(KEY_F5))
    _check(backend.requests.size() == request_count + 1 and backend.requests.back().slot == 6, "F5 saves an empty Quick slot")
    backend.complete()
    game._poll_save_states(true)
    game._close_save_states()
    request_count = backend.requests.size()
    game._unhandled_input(_key(KEY_F5))
    _check(backend.requests.size() == request_count and panel._confirm_button.is_visible_in_tree(), "F5 cannot overwrite an existing Quick save without confirmation")
    panel._cancel_button.emit_signal("pressed")
    game._close_save_states()
    game._unhandled_input(_key(KEY_F7))
    _check(backend.requests.size() == request_count and panel._confirm_button.is_visible_in_tree(), "F7 always asks before replacing the running position")
    panel._cancel_button.emit_signal("pressed")
    _check(backend.requests.size() == request_count, "Cancelling Quick Load does not restore a state")
    panel.request_slot_action("load", 6)
    panel._confirm_button.emit_signal("pressed")
    _check(backend.requests.size() == request_count + 1 and backend.requests.back().kind == "load", "Confirmed Quick Load begins the requested restore")
    backend.fail_snapshot = true
    game._poll_save_states(true)
    game._close_save_states()
    _check(game._states_busy() and panel.visible and game.is_paused(), "A transient polling error cannot release ownership of a pending restore")
    backend.fail_snapshot = false
    game._frame_accumulator = 0.5
    var generator := AudioStreamGenerator.new()
    generator.mix_rate = 32040
    generator.buffer_length = 0.1
    game._audio_player.stop()
    game._audio_player.stream = generator
    game._audio_player.play()
    game._audio_player.stream_paused = true
    var old_audio := game._audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
    game._audio_playback = old_audio
    old_audio.push_frame(Vector2(0.2, -0.2))
    var old_texture := game._frame.texture
    backend.complete()
    var accepted_operation_id: int = backend.operation.id
    backend.operation.id += 100
    game._poll_save_states(true)
    _check(game._states_busy() and game._frame.texture == old_texture, "A completion for another operation cannot apply this restore or release its lock")
    backend.operation.id = accepted_operation_id
    game._poll_save_states(true)
    _check(game._frame.texture != null and game._frame.texture.get_size() == Vector2(512, 239), "Loading refreshes the presented frame to the restored dimensions")
    _check(game._frame.texture != old_texture and game._frame.texture.get_image().get_pixel(0, 0).r > 0.8, "Loading presents restored pixels instead of the previous live frame")
    _check(game._audio_playback != old_audio, "Loading discards the pre-load audio playback buffer")
    old_audio = null
    generator = null
    _check(is_zero_approx(game._frame_accumulator), "Loading discards accumulated frame catch-up time")
    _check(backend.slots[7].occupied and panel._load_buttons[7].disabled == false, "A successful restore exposes Recovery as a loadable slot")
    request_count = backend.requests.size()
    panel.request_slot_action("load", 7)
    _check(backend.requests.size() == request_count and panel._confirm_button.is_visible_in_tree(), "Restoring Recovery also requires an explicit confirmation")
    panel._cancel_button.emit_signal("pressed")
    backend.slots[1].compatible = false
    game._poll_save_states(true)
    panel.request_slot_action("load", 1)
    _check(panel._load_buttons[1].disabled and backend.requests.size() == request_count, "An incompatible state cannot issue a load request")
    backend.slots[1].compatible = true
    game._close_save_states()

    game._open_save_states()
    backend.fail_request = true
    panel.request_slot_action("save", 0)
    panel._confirm_button.emit_signal("pressed")
    _check(game.is_paused() and panel.visible and not game._states_busy(), "An immediate request rejection remains paused with retry available")
    _check(panel._retry_button.visible and "Synthetic state request failure" in panel._status.text, "An acknowledged request failure exposes its error and Retry")
    backend.fail_request = false
    panel._retry_button.emit_signal("pressed")
    backend.complete(false)
    game._poll_save_states(true)
    _check(game.is_paused() and panel.visible and not game._states_busy(), "A worker failure remains paused without a permanently busy dialog")
    _check(panel._retry_button.visible and "Synthetic disk or restore failure" in panel._status.text, "Worker failures retain a usable Retry action")
    _check(backend.resume_calls > 0 and backend.stop_calls == stop_before, "State failures do not stop the current session")
    panel._retry_button.emit_signal("pressed")
    backend.complete()
    game._poll_save_states(true)
    _check(not game._states_busy(), "A failed operation can be retried successfully")
    game._close_save_states()

    backend.fail_snapshot = true
    game._open_save_states()
    _check(panel._save_buttons[0].disabled and panel._load_buttons[1].disabled and "Synthetic state listing failure" in panel._status.text, "A failed new listing cannot expose stale enabled slots from the previous browser")
    game._close_save_states()
    backend.fail_snapshot = false
    backend.fail_pause = true
    game._open_save_states()
    _check(not panel.visible and not game.is_paused(), "A rejected pause cannot open an apparently frozen browser")
    backend.fail_pause = false
    game._open_save_states()
    backend.fail_resume = true
    game._close_save_states()
    _check(game.is_paused() and game._pause_overlay.visible, "A failed browser resume keeps normal pause controls available")
    backend.fail_resume = false
    game._resume_game()
    backend.supported = false
    game._open_save_states()
    game._poll_save_states(true)
    request_count = backend.requests.size()
    panel.request_slot_action("save", 0)
    panel.request_slot_action("load", 1)
    _check(game.is_paused() and backend.requests.size() == request_count and panel._save_buttons[0].disabled and panel._load_buttons[1].disabled, "An unsupported core exposes no usable save/load actions")
    game._close_save_states()
    backend.supported = true

    game._open_save_states()
    game._request_save_state(0)
    var stale_operation: Dictionary = backend.operation.duplicate(true)
    game.start_game("new-state-fixture", "New fixture")
    game.set_process(false)
    backend.operation = stale_operation
    backend.complete()
    resume_before = backend.resume_calls
    game._poll_save_states(true)
    _check(game.active_game_id() == "new-state-fixture" and not game.is_paused() and not panel.visible and backend.resume_calls == resume_before, "A stale completion cannot reopen or resume controls for a new game")
    game._open_save_states()
    backend.can_resume = false
    game._poll_save_states(true)
    _check(panel._save_buttons[0].disabled and panel._load_buttons[0].disabled and not panel._retry_button.visible, "Unsafe rollback state disables Save, Load and Retry")
    resume_before = backend.resume_calls
    game._close_save_states()
    await _settle()
    _check(game.is_paused() and game._pause_overlay.visible and backend.resume_calls == resume_before, "Closing unsafe state controls never attempts to resume the core")
    _check(game._resume_button.disabled and game._exit_button.has_focus() and not game._exit_button.disabled, "Unsafe state close provides an enabled focused exit without a misleading Resume action")
    _check("Exit to library" in game._session_status.text and "Recovery" in game._session_status.text, "Unsafe state close explains how to leave safely and retain Recovery")
    game._session_id = ""
    game.free()
    var unsupported_backend := ShaderSmoke.BackendFixture.new()
    root.add_child(unsupported_backend)
    var unsupported := _new_gameplay(unsupported_backend)
    unsupported.start_game("legacy-core-fixture", "Legacy fixture")
    unsupported.set_process(false)
    unsupported._open_save_states()
    _check(unsupported.is_paused() and unsupported._states_panel.visible and not unsupported._states_busy(), "A build missing state capabilities shows an informative recoverable browser")
    unsupported._close_save_states()
    _check(not unsupported.is_paused(), "Missing state capabilities do not prevent returning to gameplay")
    unsupported._session_id = ""
    unsupported.free()
    unsupported_backend.free()
    backend.free()
    Input.action_release("game_south")
    await create_timer(0.15).timeout
    if _failures.is_empty():
        print("Save states smoke passed: %d checks; confirmations, pause ownership, pending operation isolation, restored frames and stale completion safety. No native core or user saves were opened." % _checks)
        quit(0)
    else:
        for failure in _failures:
            push_error(failure)
        quit(1)

func _new_gameplay(backend: Node) -> GameplayFixture:
    var game := GameplayFixture.new()
    game.persist_preferences = false
    root.add_child(game)
    game.configure(backend, null)
    return game

func _settle() -> void:
    await process_frame
    await process_frame

func _key(code: Key, repeat := false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    event.echo = repeat
    return event

func _check_no_pressed_inputs(values: Array, message: String) -> void:
    for value in values:
        if bool(value.get("pressed", false)):
            _check(false, message)
            return
    _check(true, message)

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if not condition:
        _failures.append(message)
