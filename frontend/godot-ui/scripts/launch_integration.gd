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
const UiIcons = preload("res://scripts/workspace/ui_icons.gd")
const PresentationTheme = preload("res://scripts/workspace/presentation_theme.gd")
const SNESDisplay = preload("res://scripts/workspace/snes_display.gd")
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
var preferences_path := "user://gameplay-ui.cfg"
var persist_preferences := true
var _journey_visible := true
var _journey_supported := false
var _shader_preset := "original"
var _shader_strength := 0.65
var _shader_was_paused := false
var _shader_input_release_pending := false
var _shader_panel: Control
var _shader_button: Button
var _settings_open := false
var _settings_child := ""
var _settings_was_paused := false
var _settings_panel: Control
var _settings_button: Button
var _controller_settings: PopupPanel
var _library_settings_window: PopupPanel
var _gameplay_volume := 1.0

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
var _journey: PanelContainer
var _journey_toggle: Button
var _gameplay_header: HBoxContainer
var _pause_button: Button


func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_process(false)
    set_process_unhandled_input(true)
    _load_view_preferences()
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
    _pause_button.text = "Pause"
    _pause_button.icon = UiIcons.icon("pause")
    _metadata_ready = false
    _frame_accumulator = 0.0
    _frame_method_missing = false
    _advance_method_missing = false
    _audio_method_missing = false
    _advance_error_shown = false
    _last_input_state.clear()
    _shader_input_release_pending = false
    _dismiss_settings_views()
    _settings_button.disabled = false
    _shader_panel.dismiss()
    _shader_button.disabled = false
    _pause_button.disabled = false
    _audio_player.stream_paused = false
    _audio_player.volume_linear = _gameplay_volume
    SNESDisplay.apply(_frame, _shader_preset, _shader_strength)
    var profile := preload("res://scripts/workspace/collection_profiles.gd").for_game(title, "snes")
    _game_title.text = str(profile.get("title", title)) if not title.is_empty() else game_id
    # This launch bridge supports the SNES core only. Keep artwork platform-scoped.
    _journey.configure(_backend, game_id, title, "snes")
    _session_status.text = "Playing  •  %s × %s" % [_video_width, _video_height]
    _pause_overlay.visible = false
    _resume_button.disabled = false
    _exit_button.disabled = false
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
    if _shader_panel.visible or _settings_open:
        return
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
    # Controller capture owns every keyboard/gamepad event, including shortcuts
    # and Escape. Its own handler cancels capture or reports reserved keys.
    if _settings_open and _settings_child == "controllers" and not _controller_settings._pending.is_empty():
        return

    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
        _toggle_window_fullscreen()
        get_viewport().set_input_as_handled()
        return

    if event is InputEventKey and event.keycode == KEY_F9:
        if event.pressed and not event.echo:
            _toggle_gameplay_settings()
        get_viewport().set_input_as_handled()
        return

    if _settings_open:
        if event is InputEventKey and event.keycode == KEY_F8:
            if event.pressed and not event.echo:
                if _settings_child == "shaders":
                    _return_to_gameplay_settings()
                elif _settings_child.is_empty():
                    _open_settings_section("shaders")
        elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("game_pause"):
            if _settings_child.is_empty():
                _close_gameplay_settings()
            else:
                _return_to_gameplay_settings()
        # Child settings windows capture their own mapping input. Nothing
        # unhandled by those windows reaches the emulated controller.
        get_viewport().set_input_as_handled()
        return

    if event is InputEventKey and event.keycode == KEY_F8:
        if event.pressed and not event.echo:
            _toggle_shader_options()
        get_viewport().set_input_as_handled()
        return

    if _shader_panel.visible:
        if event.is_action_pressed("ui_cancel") or event.is_action_pressed("game_pause"):
            _close_shader_options()
        # A preview is a UI operation, never an input to the emulated game.
        get_viewport().set_input_as_handled()
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

    if _shader_input_release_pending and not _event_logical_action(event).is_empty():
        get_viewport().set_input_as_handled()
        return

    # Poll the configured InputMap as a whole: releasing one device must not
    # cancel another device holding the same action.
    if not _event_logical_action(event).is_empty():
        _sync_inputs()
        get_viewport().set_input_as_handled()


func _build_gameplay_view() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    theme = PresentationTheme.make_theme()

    _background = ColorRect.new()
    _background.name = "GameplayBackground"
    _background.color = Color("#07090F")
    _background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_background)

    var margin := MarginContainer.new()
    margin.name = "GameplayMargin"
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 28)
    margin.add_theme_constant_override("margin_top", 18)
    margin.add_theme_constant_override("margin_right", 28)
    margin.add_theme_constant_override("margin_bottom", 24)
    add_child(margin)

    var column := VBoxContainer.new()
    column.name = "GameplayColumn"
    column.add_theme_constant_override("separation", 14)
    margin.add_child(column)

    var header := HBoxContainer.new()
    header.name = "GameplayHeader"
    header.custom_minimum_size.y = 54
    header.add_theme_constant_override("separation", 10)
    _gameplay_header = header
    column.add_child(header)

    var drag_region := HBoxContainer.new()
    drag_region.name = "WindowDragRegion"
    drag_region.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    drag_region.mouse_default_cursor_shape = Control.CURSOR_MOVE
    drag_region.add_theme_constant_override("separation", 12)
    drag_region.gui_input.connect(_gameplay_header_input)
    header.add_child(drag_region)
    var brand := TextureRect.new()
    brand.texture = preload("res://assets/brand/retrolife-icon.png")
    brand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    brand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    brand.custom_minimum_size = Vector2(38, 38)
    brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
    drag_region.add_child(brand)
    var title_column := VBoxContainer.new()
    title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    title_column.add_theme_constant_override("separation", 2)
    drag_region.add_child(title_column)

    _game_title = _label("RetroLife", 22, Color("#F5F7FB"))
    _game_title.name = "GameplayTitle"
    _game_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _game_title.clip_text = true
    _game_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
    title_column.add_child(_game_title)
    _session_status = _label("Preparing session…", 13, Color("#9AA4B2"))
    _session_status.name = "GameplayStatus"
    _session_status.clip_text = true
    _session_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
    title_column.add_child(_session_status)

    var fullscreen := _header_button("", "monitor", "Toggle fullscreen · F11")
    fullscreen.name = "GameplayFullscreen"
    fullscreen.accessibility_name = "Toggle fullscreen"
    fullscreen.pressed.connect(func(): _toggle_window_fullscreen(); _restore_play_focus())
    header.add_child(fullscreen)
    _shader_button = _header_button("Shaders", "spark", "Super Nintendo display shaders · F8")
    _shader_button.name = "GameplayShaders"
    _shader_button.accessibility_name = "Super Nintendo shaders"
    _shader_button.pressed.connect(_toggle_shader_options)
    header.add_child(_shader_button)
    _settings_button = _header_button("Settings", "settings", "Game settings · F9")
    _settings_button.name = "GameplaySettings"
    _settings_button.accessibility_name = "Game settings"
    _settings_button.pressed.connect(_toggle_gameplay_settings)
    header.add_child(_settings_button)
    _journey_toggle = _header_button("Hide Journey", "book", "Show or hide your game journal")
    _journey_toggle.name = "JourneyToggle"
    _journey_toggle.toggle_mode = true
    _journey_toggle.button_pressed = _journey_visible
    _journey_toggle.toggled.connect(set_journey_visible)
    header.add_child(_journey_toggle)
    _pause_button = _header_button("Pause", "pause", "Pause the game · Esc")
    _pause_button.name = "PauseButton"
    _pause_button.pressed.connect(_toggle_pause)
    header.add_child(_pause_button)

    var play_row := HBoxContainer.new()
    play_row.name = "PlayAndJourney"
    play_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
    play_row.add_theme_constant_override("separation", 18)
    column.add_child(play_row)
    var frame_panel := PanelContainer.new()
    frame_panel.name = "GameplayFramePanel"
    frame_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    frame_panel.add_theme_stylebox_override(
        "panel",
        _style_box(Color("#020307"), Color("#30394B"), 2, 18)
    )
    frame_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    play_row.add_child(frame_panel)
    _journey = preload("res://scripts/workspace/journey_panel.gd").new()
    _journey.support_changed.connect(_journey_support_changed)
    play_row.add_child(_journey)
    _sync_journey_visibility()

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

    _audio_player = AudioStreamPlayer.new()
    _audio_player.name = "GameplayAudio"
    add_child(_audio_player)
    _build_pause_overlay()
    _shader_panel = preload("res://scripts/workspace/shader_panel.gd").new()
    _shader_panel.name = "GameplayShaderPanel"
    add_child(_shader_panel)
    _shader_panel.preset_changed.connect(_set_shader_preset)
    _shader_panel.closed.connect(_close_shader_options)
    _settings_panel = preload("res://scripts/workspace/gameplay_settings_panel.gd").new()
    _settings_panel.name = "GameplaySettingsPanel"
    add_child(_settings_panel)
    _settings_panel.section_requested.connect(_open_settings_section)
    _settings_panel.closed.connect(_close_gameplay_settings)
    _settings_panel.volume_changed.connect(_set_gameplay_volume)
    _settings_panel.fullscreen_changed.connect(_set_settings_fullscreen)
    _settings_panel.journey_changed.connect(set_journey_visible)
    _controller_settings = preload("res://scripts/workspace/controller_panel.gd").new()
    _controller_settings.name = "GameplayControllerSettings"
    add_child(_controller_settings)
    _controller_settings.popup_hide.connect(_settings_child_hidden.bind("controllers"))
    SNESDisplay.apply(_frame, _shader_preset, _shader_strength)
    resized.connect(_update_journey_width)
    _update_journey_width()


func _header_button(caption: String, symbol: String, hint: String) -> Button:
    var button := Button.new()
    button.text = caption
    button.icon = UiIcons.icon(symbol)
    button.tooltip_text = hint
    button.custom_minimum_size = Vector2(42, 42)
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    button.focus_mode = Control.FOCUS_ALL
    button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    button.flat = true
    return button


func _gameplay_header_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        if event.double_click:
            _toggle_window_fullscreen()
        else:
            _begin_window_drag()
        accept_event()


func _begin_window_drag() -> void:
    if get_window().mode == Window.MODE_WINDOWED and DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_DRAG):
        DisplayServer.window_start_drag()


func _toggle_window_fullscreen() -> void:
    var full := get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
    get_window().mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN
    _refresh_gameplay_settings()


func _update_journey_width() -> void:
    if _journey != null:
        _journey.custom_minimum_size.x = 400 if size.x > 1280 else 340


func _restore_play_focus() -> void:
    if not _session_id.is_empty() and not _shader_panel.visible and not _settings_open:
        if _paused:
            _resume_button.grab_focus()
        else:
            _frame.grab_focus()


func _journey_support_changed(supported: bool) -> void:
    _journey_supported = supported
    _sync_journey_visibility()


func _sync_journey_visibility() -> void:
    # The backend validates the actual ROM. A matching title or an art pack
    # cannot enable a journal for a game without automatic event detection.
    var shown := _journey_supported and _journey_visible
    _journey.visible = shown
    _journey_toggle.visible = _journey_supported
    _journey_toggle.set_pressed_no_signal(shown)
    _journey_toggle.text = "Hide Journey" if shown else "Show Journey"
    _journey_toggle.accessibility_name = _journey_toggle.text
    _refresh_gameplay_settings()


func set_journey_visible(show_panel: bool) -> void:
    if not _journey_supported:
        return
    _journey_visible = show_panel
    _sync_journey_visibility()
    var error := _save_view_preferences()
    if error != OK:
        _session_status.text = "Journey visibility changed, but its preference could not be saved."
        if _settings_open:
            _settings_panel.set_status("Journey visibility changed, but the preference could not be saved.")
    _restore_play_focus()


func _load_view_preferences() -> void:
    if not persist_preferences:
        return
    var config := ConfigFile.new()
    if config.load(preferences_path) == OK:
        _journey_visible = bool(config.get_value("view", "journey_visible", true))
        _shader_preset = SNESDisplay.normalize_id(config.get_value("display_snes", "preset", "original"))
        _shader_strength = _valid_shader_strength(config.get_value("display_snes", "strength", 0.65))
        _gameplay_volume = _valid_gameplay_volume(config.get_value("audio", "volume", 1.0))


func _save_view_preferences() -> Error:
    if not persist_preferences:
        return OK
    var config := ConfigFile.new()
    var loaded := config.load(preferences_path)
    if loaded != OK and loaded != ERR_FILE_NOT_FOUND:
        return loaded
    config.set_value("view", "journey_visible", _journey_visible)
    config.set_value("display_snes", "preset", _shader_preset)
    config.set_value("display_snes", "strength", _shader_strength)
    config.set_value("audio", "volume", _gameplay_volume)
    var error := config.save(preferences_path + ".tmp")
    if error != OK:
        return error
    return DirAccess.rename_absolute(ProjectSettings.globalize_path(preferences_path + ".tmp"), ProjectSettings.globalize_path(preferences_path))


func _valid_shader_strength(value: Variant) -> float:
    if (value is float or value is int) and is_finite(float(value)):
        return clampf(float(value), 0.0, 1.0)
    return 0.65


func _toggle_gameplay_settings() -> void:
    if _settings_open:
        _close_gameplay_settings()
    else:
        _open_gameplay_settings()


func _open_gameplay_settings() -> void:
    if _session_id.is_empty() or _stopping or _settings_open:
        return
    # Opening the hub from a shader preview transfers the original pause
    # state; a child dialog must never become the owner of session resume.
    _settings_was_paused = _shader_was_paused if _shader_panel.visible else _paused
    if not _paused:
        var response := _call_optional_response(["pause_emulation_json", "emulation_pause_json", "pause_game_json"], [])
        if not bool(response.get("ok", false)):
            _session_status.text = "Unable to open settings  •  Could not pause the game."
            return
    _release_game_inputs()
    _shader_panel.dismiss()
    _settings_open = true
    _settings_child = ""
    _paused = true
    _audio_player.stream_paused = true
    _pause_overlay.visible = false
    _pause_button.disabled = true
    _session_status.text = "Paused  •  Game settings"
    _show_gameplay_settings_hub()


func _show_gameplay_settings_hub() -> void:
    _settings_panel.show_options(_game_title.text, _gameplay_volume, _journey_supported,
        _journey_visible, _window_is_fullscreen(), _library_preferences_available())


func _refresh_gameplay_settings() -> void:
    if not is_instance_valid(_settings_panel) or not _settings_open:
        return
    _settings_panel.refresh_options(_gameplay_volume, _journey_supported,
        _journey_visible, _window_is_fullscreen(), _library_preferences_available())


func _open_settings_section(section: String) -> void:
    if not _settings_open or _stopping or _session_id.is_empty():
        return
    if section not in ["controllers", "shaders", "library"]:
        return
    if section == "library" and not _library_preferences_available():
        _settings_panel.set_status("Library preferences are not available in this view.")
        return
    # Hide any previous child without its close handler returning to the hub.
    _settings_child = ""
    _shader_panel.dismiss()
    _controller_settings.hide()
    if is_instance_valid(_library_settings_window):
        _library_settings_window.hide()
    _settings_panel.dismiss()
    _settings_child = section
    if section == "shaders":
        _session_status.text = "Paused  •  Previewing shaders"
        _shader_panel.show_options(_frame.texture, _shader_preset, _shader_strength)
    elif section == "controllers":
        _session_status.text = "Paused  •  Controller setup"
        var target := Vector2i(mini(980, maxi(320, int(size.x) - 40)), mini(620, maxi(240, int(size.y) - 40)))
        _controller_settings.popup_centered(target)
        _resize_controller_settings.call_deferred(target)
    else:
        _session_status.text = "Paused  •  RetroLife preferences"
        var candidate := _owner.get("_settings_panel") as PopupPanel
        if _library_settings_window != candidate:
            if is_instance_valid(_library_settings_window) and _library_settings_window.popup_hide.is_connected(_library_settings_hidden):
                _library_settings_window.popup_hide.disconnect(_library_settings_hidden)
            _library_settings_window = candidate
            _library_settings_window.popup_hide.connect(_library_settings_hidden)
        _owner.call("_show_settings")


func _resize_controller_settings(target: Vector2i) -> void:
    # Wrapped model captions need one layout pass before the popup can settle.
    await get_tree().process_frame
    if _settings_open and _settings_child == "controllers" and _controller_settings.visible:
        _controller_settings.popup_centered(target)


func _settings_child_hidden(section: String) -> void:
    if _settings_open and _settings_child == section and not _stopping:
        _return_to_gameplay_settings()


func _library_settings_hidden() -> void:
    _settings_child_hidden("library")


func _return_to_gameplay_settings() -> void:
    if not _settings_open or _stopping or _session_id.is_empty():
        return
    _settings_child = ""
    _shader_panel.dismiss()
    _controller_settings.hide()
    if is_instance_valid(_library_settings_window):
        _library_settings_window.hide()
    _release_game_inputs()
    _session_status.text = "Paused  •  Game settings"
    _show_gameplay_settings_hub()


func _close_gameplay_settings() -> void:
    if not _settings_open:
        return
    var was_paused := _settings_was_paused
    _dismiss_settings_views()
    _shader_input_release_pending = true
    _pause_button.disabled = false
    if _session_id.is_empty() or _stopping:
        return
    if not was_paused:
        var response := _call_optional_response(["resume_emulation_json", "emulation_resume_json", "resume_game_json"], [])
        if bool(response.get("ok", false)):
            _paused = false
            _audio_player.stream_paused = false
            _pause_button.text = "Pause"
            _pause_button.icon = UiIcons.icon("pause")
            _session_status.text = "Playing  •  %s × %s" % [_video_width, _video_height]
            _frame.grab_focus()
            return
        _session_status.text = "Paused  •  Could not resume. Try Resume again."
    else:
        _session_status.text = "Paused"
    _paused = true
    _pause_overlay.visible = true
    _pause_button.text = "Resume"
    _pause_button.icon = UiIcons.icon("play")
    _resume_button.grab_focus()


func _dismiss_settings_views() -> void:
    # Clear ownership first: PopupPanel.hide emits synchronously and must not
    # reopen the hub or resume a game that is in the middle of saving.
    _settings_open = false
    _settings_child = ""
    if is_instance_valid(_settings_panel):
        _settings_panel.dismiss()
    if is_instance_valid(_controller_settings):
        _controller_settings.hide()
    if is_instance_valid(_library_settings_window):
        _library_settings_window.hide()
    if is_instance_valid(_shader_panel):
        _shader_panel.dismiss()


func _library_preferences_available() -> bool:
    if not is_instance_valid(_owner) or not _owner.has_method("_show_settings"):
        return false
    for property in _owner.get_property_list():
        if str(property.name) == "_settings_panel":
            return _owner.get("_settings_panel") is PopupPanel
    return false


func _window_is_fullscreen() -> bool:
    return get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]


func _set_settings_fullscreen(enabled: bool) -> void:
    if _window_is_fullscreen() != enabled:
        _toggle_window_fullscreen()
    _refresh_gameplay_settings()


func _valid_gameplay_volume(value: Variant) -> float:
    if (value is float or value is int) and is_finite(float(value)):
        return clampf(float(value), 0.0, 1.0)
    return 1.0


func _set_gameplay_volume(value: float) -> void:
    _gameplay_volume = _valid_gameplay_volume(value)
    _audio_player.volume_linear = _gameplay_volume
    _refresh_gameplay_settings()
    var error := _save_view_preferences()
    if error != OK:
        _settings_panel.set_status("Volume changed, but the preference could not be saved.")
    else:
        _settings_panel.set_status("Game volume saved. The game stays paused until you close settings.")


func _toggle_shader_options() -> void:
    if _shader_panel.visible:
        _close_shader_options()
    else:
        _open_shader_options()


func _open_shader_options() -> void:
    if _settings_open:
        if _settings_child != "shaders":
            _open_settings_section("shaders")
        return
    if _session_id.is_empty() or _stopping or _shader_panel.visible:
        return
    _shader_was_paused = _paused
    if not _paused:
        var response := _call_optional_response(["pause_emulation_json", "emulation_pause_json", "pause_game_json"], [])
        if not bool(response.get("ok", false)):
            _session_status.text = "Unable to preview shaders  •  Could not pause the game."
            return
    _release_game_inputs()
    _paused = true
    _audio_player.stream_paused = true
    _pause_overlay.visible = false
    _pause_button.disabled = true
    _session_status.text = "Paused  •  Previewing shaders"
    _shader_panel.show_options(_frame.texture, _shader_preset, _shader_strength)


func _close_shader_options() -> void:
    if _settings_open:
        if _settings_child == "shaders":
            _return_to_gameplay_settings()
        return
    if not _shader_panel.visible:
        return
    _shader_panel.dismiss()
    _shader_input_release_pending = true
    _pause_button.disabled = false
    if _session_id.is_empty() or _stopping:
        return
    if not _shader_was_paused:
        var response := _call_optional_response(["resume_emulation_json", "emulation_resume_json", "resume_game_json"], [])
        if bool(response.get("ok", false)):
            _paused = false
            _audio_player.stream_paused = false
            _pause_button.text = "Pause"
            _pause_button.icon = UiIcons.icon("pause")
            _session_status.text = "Playing  •  %s × %s" % [_video_width, _video_height]
            _frame.grab_focus()
            return
        _session_status.text = "Paused  •  Could not resume. Try Resume again."
    else:
        _session_status.text = "Paused"
    _paused = true
    _pause_overlay.visible = true
    _pause_button.text = "Resume"
    _pause_button.icon = UiIcons.icon("play")
    _resume_button.grab_focus()


func _set_shader_preset(preset_id: String, strength: float) -> void:
    _shader_preset = SNESDisplay.normalize_id(preset_id)
    _shader_strength = _valid_shader_strength(strength)
    SNESDisplay.apply(_frame, _shader_preset, _shader_strength)
    var error := _save_view_preferences()
    if error != OK:
        _shader_panel.set_status("Preview applied, but the preference could not be saved.")
    else:
        _shader_panel.set_status("Game paused while you preview. Saved for Super Nintendo.")


func _release_game_inputs() -> void:
    for action in _last_input_state.keys():
        if bool(_last_input_state[action]):
            _set_logical_input(str(action), false)


func _build_pause_overlay() -> void:
    _pause_overlay = ColorRect.new()
    _pause_overlay.name = "PauseOverlay"
    _pause_overlay.color = Color(0.02, 0.025, 0.05, 0.92)
    _pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    # Keep the integrated window controls usable while the game is paused.
    _pause_overlay.offset_top = 80
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
    var settings := Button.new()
    settings.name = "PauseSettingsButton"
    settings.text = "Game settings"
    settings.icon = UiIcons.icon("settings")
    settings.custom_minimum_size.y = 44
    settings.pressed.connect(_open_gameplay_settings)
    column.add_child(settings)
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
    _audio_player.volume_linear = _gameplay_volume
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
    if _shader_panel.visible or _settings_open or _paused:
        _release_game_inputs()
        return
    var actions := [
        "up", "down", "left", "right", "south", "east", "west", "north",
        "left_shoulder", "right_shoulder", "start", "select",
    ]
    if _shader_input_release_pending:
        for action in actions:
            if InputMap.has_action("game_" + action) and Input.is_action_pressed("game_" + action):
                return
        _shader_input_release_pending = false
        return
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
    if _session_id.is_empty() or _stopping or _shader_panel.visible or _settings_open:
        return
    if _paused:
        _resume_game()
        return
    var response := _call_optional_response(["pause_emulation_json", "emulation_pause_json", "pause_game_json"], [])
    if not bool(response.get("ok", false)):
        _session_status.text = "Unable to pause  •  Please try again."
        return
    _release_game_inputs()
    _paused = true
    _audio_player.stream_paused = true
    _pause_button.text = "Resume"
    _pause_button.icon = UiIcons.icon("play")
    _pause_overlay.visible = true
    _session_status.text = "Paused"
    _restore_play_focus.call_deferred()


func _resume_game() -> void:
    if _session_id.is_empty() or _stopping or _shader_panel.visible or _settings_open:
        return
    var response := _call_optional_response(["resume_emulation_json", "emulation_resume_json", "resume_game_json"], [])
    if not bool(response.get("ok", false)):
        _session_status.text = "Paused  •  Could not resume. Try Resume again."
        return
    _shader_input_release_pending = true
    _paused = false
    _audio_player.stream_paused = false
    _pause_button.text = "Pause"
    _pause_button.icon = UiIcons.icon("pause")
    _pause_overlay.visible = false
    _session_status.text = "Playing  •  %s × %s" % [_video_width, _video_height]
    _restore_play_focus.call_deferred()


func _stop_session() -> void:
    if _session_id.is_empty() or _stopping:
        return
    _stopping = true
    _dismiss_settings_views()
    _settings_button.disabled = true
    _shader_panel.dismiss()
    _shader_button.disabled = true
    _pause_button.disabled = false
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
        _settings_button.disabled = false
        _shader_button.disabled = false
        _resume_button.disabled = false
        _exit_button.disabled = false
        _restore_pause_after_stop_failure()
        _session_status.text = "Unable to save  •  %s" % str(response.get("error", "Stop failed."))
        return

    var deadline := Time.get_ticks_msec() + 15000
    while Time.get_ticks_msec() < deadline:
        await get_tree().create_timer(0.016).timeout
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
    _settings_button.disabled = false
    _shader_button.disabled = false
    _resume_button.disabled = false
    _exit_button.disabled = false
    _restore_pause_after_stop_failure()
    _session_status.text = "Save incomplete  •  %s" % message


func _restore_pause_after_stop_failure() -> void:
    # Closing the shader preview to save must not strand a paused session if
    # saving fails. Restore the normal retry/exit controls before returning.
    if _paused:
        _pause_overlay.visible = true
        _pause_button.disabled = false
        _pause_button.text = "Resume"
        _pause_button.icon = UiIcons.icon("play")
        _exit_button.grab_focus()


func _complete_stop(ended_game_id: String) -> void:
    _session_id = ""
    _game_id = ""
    _journey.game_id = ""
    _dismiss_settings_views()
    _settings_button.disabled = false
    _shader_panel.dismiss()
    _shader_button.disabled = false
    _pause_button.disabled = false
    _frame.texture = null
    _frame_texture = null
    _journey_support_changed(false)
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
    for action in preload("res://scripts/workspace/bindings.gd").ACTIONS:
        if InputMap.event_is_action(event, "game_" + action):
            return action
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
