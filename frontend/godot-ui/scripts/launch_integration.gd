extends Control

## Godot-side presentation for one local SNES session.
##
## The Rust bridge owns the core, the worker thread, and save files. This
## node owns the Godot texture, audio output, input mapping, and the visible
## pause/exit flow. The calls intentionally use a small capability contract so
## the UI can still open in a clean checkout while the native extension is
## being built.

signal game_exited(game_id: String)

const RESPONSE_SCHEMA_VERSION := 1
const DEFAULT_VIDEO_WIDTH := 256
const DEFAULT_VIDEO_HEIGHT := 224
const DEFAULT_SAMPLE_RATE := 32_040
const DEFAULT_CORE_FPS := 60.0
const MAX_FRAME_CATCH_UP := 4
const FRAME_METHODS: Array[String] = [
    "emulation_frame_rgba",
    "poll_emulation_frame_rgba",
    "emulation_video_frame",
]
const ADVANCE_METHODS: Array[String] = [
    "emulation_advance_frame_json",
    "advance_emulation_frame_json",
    "run_emulation_frame_json",
]
const AUDIO_METHODS: Array[String] = [
    "emulation_audio_samples_available",
    "emulation_audio_samples",
    "poll_emulation_audio",
]
const INPUT_METHODS: Array[String] = [
    "set_emulation_input_json",
    "emulation_set_input_json",
    "set_emulation_input",
]

var _backend: Node
var _owner: Control
var _session_id := ""
var _game_id := ""
var _video_width := DEFAULT_VIDEO_WIDTH
var _video_height := DEFAULT_VIDEO_HEIGHT
var _sample_rate: float = DEFAULT_SAMPLE_RATE
var _core_fps := DEFAULT_CORE_FPS
var _frame_accumulator := 0.0
var _paused := false
var _stopping := false
var _frame_method_missing := false
var _advance_method_missing := false
var _audio_method_missing := false
var _metadata_ready := false
var _advance_error_shown := false
var _last_input_state := {}

var _background: ColorRect
var _frame: TextureRect
var _frame_texture: ImageTexture
var _audio_player: AudioStreamPlayer
var _audio_playback: AudioStreamGeneratorPlayback
var _frame_aspect: AspectRatioContainer
var _game_title: Label
var _session_status: Label
var _pause_overlay: Control
var _pause_title: Label
var _resume_button: Button
var _exit_button: Button


func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_process(false)
    set_process_unhandled_input(true)
    _build_gameplay_view()


func configure(backend: Node, owner: Control) -> void:
    _backend = backend
    _owner = owner


func start_game(game_id: String, title := "") -> Dictionary:
    if _backend == null:
        return _fail("The Rust bridge is unavailable.")
    if not _has_any_method(["start_emulation_json", "emulation_start_json", "start_game_json"]):
        return _fail("The bundled SNES core is not available in this build.")

    var response := _call_first(
        ["start_emulation_json", "emulation_start_json", "start_game_json"],
        [game_id]
    )
    if not bool(response.get("ok", false)):
        return response

    var data: Dictionary = response.get("data", {})
    _session_id = str(data.get("sessionId", data.get("id", game_id)))
    _game_id = game_id
    _video_width = _positive_int(data.get("videoWidth", data.get("width", DEFAULT_VIDEO_WIDTH)), DEFAULT_VIDEO_WIDTH)
    _video_height = _positive_int(data.get("videoHeight", data.get("height", DEFAULT_VIDEO_HEIGHT)), DEFAULT_VIDEO_HEIGHT)
    _sample_rate = _positive_float(data.get("sampleRate", DEFAULT_SAMPLE_RATE), DEFAULT_SAMPLE_RATE)
    _core_fps = DEFAULT_CORE_FPS
    _paused = false
    _stopping = false
    _metadata_ready = false
    _frame_accumulator = 0.0
    _frame_method_missing = false
    _advance_method_missing = false
    _audio_method_missing = false
    _advance_error_shown = false
    _last_input_state.clear()
    _game_title.text = title if not title.is_empty() else game_id
    _session_status.text = "Playing  •  %s × %s" % [_video_width, _video_height]
    _pause_overlay.visible = false
    visible = true
    move_to_front()
    set_process(true)
    _frame.grab_focus()
    return response


func active_session_id() -> String:
    return _session_id


func active_game_id() -> String:
    return _game_id


func is_paused() -> bool:
    return _paused


func _process(delta: float) -> void:
    if _session_id.is_empty():
        return
    if _stopping:
        return
    _sync_inputs()
    if not _metadata_ready:
        if not _refresh_session_metadata():
            return
        if not _metadata_ready:
            return
    if _paused:
        return
    var frame_period := 1.0 / maxf(_core_fps, 1.0)
    _frame_accumulator = minf(
        _frame_accumulator + maxf(delta, 0.0),
        frame_period * MAX_FRAME_CATCH_UP
    )
    var steps := mini(int(_frame_accumulator / frame_period), MAX_FRAME_CATCH_UP)
    if steps > 0:
        _frame_accumulator -= frame_period * steps
        for _index in range(steps):
            _advance_core_frame()
    _poll_video()
    _poll_audio()


func _unhandled_input(event: InputEvent) -> void:
    if _session_id.is_empty() or _stopping or not visible:
        return

    if event.is_action_pressed("game_pause"):
        _toggle_pause()
        get_viewport().set_input_as_handled()
        return
    if _paused:
        if event.is_action_pressed("ui_accept"):
            _resume_game()
            get_viewport().set_input_as_handled()
        elif event.is_action_pressed("ui_cancel"):
            _stop_session()
            get_viewport().set_input_as_handled()
        return
    if event.is_action_pressed("ui_cancel"):
        _toggle_pause()
        get_viewport().set_input_as_handled()

    var logical_action := _event_logical_action(event)
    if logical_action.is_empty():
        return
    if event.is_pressed() and not (event is InputEventKey and (event as InputEventKey).echo):
        _set_logical_input(logical_action, true)
    elif not event.is_pressed():
        _set_logical_input(logical_action, false)
    get_viewport().set_input_as_handled()


func _build_gameplay_view() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP

    _background = ColorRect.new()
    _background.name = "GameplayBackground"
    _background.color = Color("#07090F")
    _background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_background)

    var margin := MarginContainer.new()
    margin.name = "GameplayMargin"
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 44)
    margin.add_theme_constant_override("margin_top", 30)
    margin.add_theme_constant_override("margin_right", 44)
    margin.add_theme_constant_override("margin_bottom", 30)
    add_child(margin)

    var column := VBoxContainer.new()
    column.name = "GameplayColumn"
    column.add_theme_constant_override("separation", 14)
    margin.add_child(column)

    var header := HBoxContainer.new()
    header.name = "GameplayHeader"
    column.add_child(header)

    var title_column := VBoxContainer.new()
    title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title_column.add_theme_constant_override("separation", 2)
    header.add_child(title_column)

    _game_title = _label("SNES game", 28, Color("#F5F7FB"))
    _game_title.name = "GameplayTitle"
    title_column.add_child(_game_title)
    _session_status = _label("Preparing session…", 14, Color("#9AA4B2"))
    _session_status.name = "GameplayStatus"
    title_column.add_child(_session_status)

    var exit_hint := _label("Esc  Pause", 13, Color("#9AA4B2"))
    exit_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    header.add_child(exit_hint)

    var frame_panel := PanelContainer.new()
    frame_panel.name = "GameplayFramePanel"
    frame_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    frame_panel.add_theme_stylebox_override(
        "panel",
        _style_box(Color("#020307"), Color("#30394B"), 2, 18)
    )
    column.add_child(frame_panel)

    _frame_aspect = AspectRatioContainer.new()
    _frame_aspect.name = "GameplayFrameAspect"
    _frame_aspect.ratio = float(DEFAULT_VIDEO_WIDTH) / float(DEFAULT_VIDEO_HEIGHT)
    _frame_aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _frame_aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
    frame_panel.add_child(_frame_aspect)

    _frame = TextureRect.new()
    _frame.name = "GameplayFrame"
    _frame.custom_minimum_size = Vector2(256, 224)
    _frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _frame.stretch_mode = TextureRect.STRETCH_SCALE
    _frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _frame.focus_mode = Control.FOCUS_ALL
    _frame.mouse_filter = Control.MOUSE_FILTER_STOP
    _frame_aspect.add_child(_frame)

    var footer := HBoxContainer.new()
    footer.name = "GameplayFooter"
    footer.add_theme_constant_override("separation", 18)
    column.add_child(footer)
    var controls := _label(
        "Arrows / D-pad  Move     X/Z/C/V  B/A/Y/X     Q/E or bumpers  L/R     Enter / Start  Start",
        13,
        Color("#9AA4B2")
    )
    controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    footer.add_child(controls)
    var pause_button := Button.new()
    pause_button.name = "PauseButton"
    pause_button.text = "Pause"
    pause_button.custom_minimum_size = Vector2(130, 42)
    pause_button.pressed.connect(_toggle_pause)
    footer.add_child(pause_button)

    _audio_player = AudioStreamPlayer.new()
    _audio_player.name = "GameplayAudio"
    add_child(_audio_player)
    _build_pause_overlay()


func _build_pause_overlay() -> void:
    _pause_overlay = ColorRect.new()
    _pause_overlay.name = "PauseOverlay"
    _pause_overlay.color = Color(0.02, 0.025, 0.05, 0.92)
    _pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    _pause_overlay.visible = false
    add_child(_pause_overlay)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _pause_overlay.add_child(center)

    var panel := PanelContainer.new()
    panel.name = "PausePanel"
    panel.custom_minimum_size = Vector2(440, 260)
    panel.add_theme_stylebox_override(
        "panel",
        _style_box(Color("#151A24"), Color("#53627C"), 2, 20)
    )
    center.add_child(panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 30)
    margin.add_theme_constant_override("margin_top", 26)
    margin.add_theme_constant_override("margin_right", 30)
    margin.add_theme_constant_override("margin_bottom", 26)
    panel.add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    margin.add_child(column)

    _pause_title = _label("Game paused", 30, Color("#F5F7FB"))
    _pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_pause_title)
    var hint := _label("Resume when you are ready, or return to the library.", 15, Color("#B6C0D2"))
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(hint)

    _resume_button = Button.new()
    _resume_button.name = "ResumeButton"
    _resume_button.text = "Resume"
    _resume_button.custom_minimum_size.y = 48
    _resume_button.pressed.connect(_resume_game)
    column.add_child(_resume_button)
    _exit_button = Button.new()
    _exit_button.name = "ExitGameButton"
    _exit_button.text = "Exit to library"
    _exit_button.custom_minimum_size.y = 48
    _exit_button.pressed.connect(_stop_session)
    column.add_child(_exit_button)


func _configure_audio() -> void:
    if _audio_player == null:
        return
    # Godot's headless audio server retains the generator playback object at
    # process exit even after stop/stream cleanup. There is no output device
    # to feed in this mode, so leave the native audio queue untouched and let
    # desktop/mobile builds use the normal generator path.
    if DisplayServer.get_name() == "headless":
        _audio_playback = null
        return
    var generator := AudioStreamGenerator.new()
    generator.mix_rate = _sample_rate
    generator.buffer_length = 0.25
    _audio_player.stream = generator
    _audio_player.play()
    _audio_playback = _audio_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _refresh_session_metadata() -> bool:
    var response := _call_optional_response(["emulation_status_json"], [])
    if not bool(response.get("ok", false)):
        _session_status.text = "Starting  •  %s" % str(response.get("error", "Metadata unavailable."))
        return false
    var data: Dictionary = response.get("data", {})
    var status := str(data.get("status", "starting"))
    if status == "failed":
        _session_status.text = "Unable to start  •  %s" % str(data.get("lastError", "The emulator failed to start."))
        set_process(false)
        return false
    var width := _positive_int(data.get("videoWidth", 0), 0)
    var height := _positive_int(data.get("videoHeight", 0), 0)
    var sample_rate := _positive_float(data.get("sampleRate", 0.0), 0.0)
    var fps := _positive_float(data.get("fps", 0.0), 0.0)
    var aspect_ratio := _positive_float(data.get("aspectRatio", 0.0), 0.0)
    if width <= 0 or height <= 0 or sample_rate <= 0.0:
        _session_status.text = "Starting  •  waiting for core metadata"
        return true
    _update_video_metadata(width, height, sample_rate, fps, aspect_ratio)
    _metadata_ready = true
    _session_status.text = "Playing  •  %s × %s" % [_video_width, _video_height]
    _configure_audio()
    return true


func _advance_core_frame() -> void:
    if _advance_method_missing or _backend == null:
        return
    var method := _first_method(ADVANCE_METHODS)
    if method.is_empty():
        _advance_method_missing = true
        return
    var response := _decode(_backend.call(method))
    if bool(response.get("ok", false)):
        return
    var error := str(response.get("error", "The emulator could not advance."))
    if error.to_lower().contains("queue") and error.to_lower().contains("full"):
        return
    if not _advance_error_shown:
        _advance_error_shown = true
        _session_status.text = "Emulator error  •  %s" % error


func _poll_video() -> void:
    if _frame_method_missing or _backend == null:
        return
    var method := _first_method(FRAME_METHODS)
    if method.is_empty():
        _frame_method_missing = true
        _session_status.text = "Playing  •  video output is unavailable"
        return
    var raw: Variant = _backend.call(method)
    var payload := _payload_bytes(raw)
    if payload.is_empty():
        return
    var info_response := _call_optional_response(["emulation_frame_info_json"], [])
    if bool(info_response.get("ok", false)):
        var info: Dictionary = info_response.get("data", {})
        _update_video_metadata(
            _positive_int(info.get("width", 0), _video_width),
            _positive_int(info.get("height", 0), _video_height),
            _positive_float(info.get("sampleRate", 0.0), _sample_rate),
            _positive_float(info.get("fps", 0.0), _core_fps),
            _positive_float(info.get("aspectRatio", 0.0), 0.0)
        )
    var expected_size := _video_width * _video_height * 4
    if payload.size() != expected_size:
        _session_status.text = "Playing  •  invalid video frame received"
        return
    var image := Image.create_from_data(
        _video_width,
        _video_height,
        false,
        Image.FORMAT_RGBA8,
        payload
    )
    if image == null:
        return
    if _frame_texture == null \
        or _frame_texture.get_width() != _video_width \
        or _frame_texture.get_height() != _video_height:
        _frame_texture = ImageTexture.create_from_image(image)
        _frame.texture = _frame_texture
    else:
        _frame_texture.update(image)


func _poll_audio() -> void:
    if _audio_method_missing or _audio_playback == null or _backend == null:
        return
    var method := _first_method(AUDIO_METHODS)
    if method.is_empty():
        _audio_method_missing = true
        return
    var available := _audio_playback.get_frames_available()
    if available <= 0:
        return
    var raw: Variant
    if method == "emulation_audio_samples_available":
        raw = _backend.call(method, available)
    else:
        raw = _backend.call(method)
    var samples := _payload_floats(raw)
    if samples.is_empty():
        return
    var frames := mini(available, samples.size() / 2)
    for index in range(frames):
        _audio_playback.push_frame(Vector2(samples[index * 2], samples[index * 2 + 1]))


func _update_video_metadata(
    width: int,
    height: int,
    sample_rate: float,
    fps: float,
    aspect_ratio: float
) -> void:
    if width > 0:
        _video_width = width
    if height > 0:
        _video_height = height
    if sample_rate > 0.0:
        if not is_equal_approx(_sample_rate, sample_rate) and _metadata_ready:
            _sample_rate = sample_rate
            _configure_audio()
        else:
            _sample_rate = sample_rate
    if fps > 0.0:
        _core_fps = fps
    if aspect_ratio > 0.0 and _frame_aspect != null:
        _frame_aspect.ratio = aspect_ratio


func _sync_inputs() -> void:
    var actions := [
        "up", "down", "left", "right", "south", "east", "west", "north",
        "left_shoulder", "right_shoulder", "start", "select",
    ]
    for action in actions:
        var input_action := StringName("game_" + action)
        if not InputMap.has_action(input_action):
            continue
        var pressed := Input.is_action_pressed(input_action)
        if bool(_last_input_state.get(action, false)) != pressed:
            _set_logical_input(action, pressed)


func _set_logical_input(action: String, pressed: bool) -> void:
    if _session_id.is_empty() or _backend == null:
        return
    _last_input_state[action] = pressed
    var method := _first_method(INPUT_METHODS)
    if method.is_empty():
        return
    if method.ends_with("_json"):
        _backend.callv(method, [action, pressed])
    else:
        _backend.callv(method, [action, pressed])


func _toggle_pause() -> void:
    if _session_id.is_empty() or _stopping:
        return
    if _paused:
        _resume_game()
        return
    _paused = true
    _pause_overlay.visible = true
    _session_status.text = "Paused"
    _call_optional(["pause_emulation_json", "emulation_pause_json", "pause_game_json"], [])
    _resume_button.call_deferred("grab_focus")


func _resume_game() -> void:
    if _session_id.is_empty() or _stopping:
        return
    _paused = false
    _pause_overlay.visible = false
    _session_status.text = "Playing  •  %s × %s" % [_video_width, _video_height]
    _call_optional(["resume_emulation_json", "emulation_resume_json", "resume_game_json"], [])
    _frame.call_deferred("grab_focus")


func _stop_session() -> void:
    if _session_id.is_empty() or _stopping:
        return
    _stopping = true
    var ended_game_id := _game_id
    _session_status.text = "Saving…"
    _resume_button.disabled = true
    _exit_button.disabled = true
    var response := _call_optional_response(
        ["stop_emulation_json", "emulation_stop_json", "stop_game_json"],
        []
    )
    if not bool(response.get("ok", false)):
        _stopping = false
        _resume_button.disabled = false
        _exit_button.disabled = false
        _session_status.text = "Unable to save  •  %s" % str(response.get("error", "Stop failed."))
        return

    for _index in range(180):
        await get_tree().process_frame
        var status_response := _call_optional_response(["emulation_status_json"], [])
        if not bool(status_response.get("ok", false)):
            _stop_failed(str(status_response.get("error", "Could not verify stop.")))
            return
        var status_data: Dictionary = status_response.get("data", {})
        var status := str(status_data.get("status", ""))
        if status == "stopped":
            _complete_stop(ended_game_id)
            return
        if status == "failed":
            _stop_failed(str(status_data.get("lastError", "The emulator failed while saving.")))
            return

    _stop_failed("The emulator did not finish saving in time. Try Exit to library again.")


func _stop_failed(message: String) -> void:
    _stopping = false
    _resume_button.disabled = false
    _exit_button.disabled = false
    _session_status.text = "Save incomplete  •  %s" % message


func _complete_stop(ended_game_id: String) -> void:
    _session_id = ""
    _game_id = ""
    _paused = false
    _stopping = false
    _pause_overlay.visible = false
    _audio_playback = null
    if _audio_player != null:
        _audio_player.stop()
        _audio_player.stream = null
    visible = false
    set_process(false)
    game_exited.emit(ended_game_id)


func _event_logical_action(event: InputEvent) -> String:
    if event is InputEventKey:
        var key := event as InputEventKey
        var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
        return {
            KEY_UP: "up", KEY_W: "up",
            KEY_DOWN: "down", KEY_S: "down",
            KEY_LEFT: "left", KEY_A: "left",
            KEY_RIGHT: "right", KEY_D: "right",
            KEY_X: "south", KEY_J: "south",
            KEY_Z: "east", KEY_K: "east",
            KEY_C: "west", KEY_V: "north", KEY_Q: "left_shoulder",
            KEY_E: "right_shoulder", KEY_ENTER: "start",
            KEY_SHIFT: "select", KEY_SPACE: "select",
        }.get(code, "")
    if event is InputEventJoypadButton:
        var button := (event as InputEventJoypadButton).button_index
        return {
            JOY_BUTTON_A: "south",
            JOY_BUTTON_B: "east",
            JOY_BUTTON_X: "west",
            JOY_BUTTON_Y: "north",
            JOY_BUTTON_LEFT_SHOULDER: "left_shoulder",
            JOY_BUTTON_RIGHT_SHOULDER: "right_shoulder",
            JOY_BUTTON_BACK: "select",
            JOY_BUTTON_START: "start",
            JOY_BUTTON_DPAD_UP: "up",
            JOY_BUTTON_DPAD_DOWN: "down",
            JOY_BUTTON_DPAD_LEFT: "left",
            JOY_BUTTON_DPAD_RIGHT: "right",
        }.get(button, "")
    return ""


func _has_any_method(methods: Array[String]) -> bool:
    return not _first_method(methods).is_empty()


func _first_method(methods: Array[String]) -> String:
    if _backend == null:
        return ""
    for method in methods:
        if _backend.has_method(method):
            return method
    return ""


func _call_optional(methods: Array[String], arguments: Array) -> void:
    var method := _first_method(methods)
    if not method.is_empty():
        _backend.callv(method, arguments)


func _call_optional_response(methods: Array[String], arguments: Array) -> Dictionary:
    var method := _first_method(methods)
    if method.is_empty():
        return _fail("The bridge cannot confirm this operation.")
    return _decode(_backend.callv(method, arguments))


func _call_first(methods: Array[String], arguments: Array) -> Dictionary:
    var method := _first_method(methods)
    if method.is_empty():
        return _fail("The bundled SNES core is not available in this build.")
    return _decode(_backend.callv(method, arguments))


func _decode(raw: Variant) -> Dictionary:
    if raw is Dictionary:
        var dictionary: Dictionary = raw
        if int(dictionary.get("schemaVersion", RESPONSE_SCHEMA_VERSION)) != RESPONSE_SCHEMA_VERSION:
            return _fail("Unsupported emulation bridge response schema.")
        return dictionary
    var parsed: Variant = JSON.parse_string(str(raw))
    if typeof(parsed) != TYPE_DICTIONARY:
        return _fail("The emulation bridge returned invalid JSON.")
    var response: Dictionary = parsed
    if int(response.get("schemaVersion", -1)) != RESPONSE_SCHEMA_VERSION:
        return _fail("Unsupported emulation bridge response schema.")
    return response


func _payload_bytes(raw: Variant) -> PackedByteArray:
    if raw is PackedByteArray:
        return raw
    var parsed: Variant = raw
    if raw is String or raw is StringName:
        parsed = JSON.parse_string(str(raw))
    if typeof(parsed) != TYPE_DICTIONARY:
        return PackedByteArray()
    var data: Dictionary = parsed
    if data.has("data") and data["data"] is Dictionary:
        data = data["data"]
    if data.has("base64"):
        return Marshalls.base64_to_raw(str(data["base64"]))
    if data.has("bytes"):
        var bytes := PackedByteArray()
        for value in data["bytes"]:
            bytes.append(int(value))
        return bytes
    return PackedByteArray()


func _payload_floats(raw: Variant) -> PackedFloat32Array:
    if raw is PackedFloat32Array:
        return raw
    var parsed: Variant = raw
    if raw is String or raw is StringName:
        parsed = JSON.parse_string(str(raw))
    if typeof(parsed) != TYPE_DICTIONARY:
        return PackedFloat32Array()
    var data: Dictionary = parsed
    if data.has("data") and data["data"] is Dictionary:
        data = data["data"]
    var result := PackedFloat32Array()
    if data.has("samples"):
        for value in data["samples"]:
            result.append(float(value))
    return result


func _positive_int(value: Variant, fallback: int) -> int:
    if value == null:
        return fallback
    var integer := int(value)
    return integer if integer > 0 else fallback


func _positive_float(value: Variant, fallback: float) -> float:
    if value == null:
        return fallback
    var number := float(value)
    return number if is_finite(number) and number > 0.0 else fallback


func _fail(message: String) -> Dictionary:
    return {"schemaVersion": RESPONSE_SCHEMA_VERSION, "ok": false, "error": message}


func _label(text: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


func _style_box(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = background
    box.border_color = border
    box.set_border_width_all(border_width)
    box.set_corner_radius_all(radius)
    box.content_margin_left = 20
    box.content_margin_top = 18
    box.content_margin_right = 20
    box.content_margin_bottom = 18
    return box
