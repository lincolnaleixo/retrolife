extends Control

## Presentation-only settings hub. The launcher owns pause, persistence and children.
signal section_requested(section: String)
signal volume_changed(value: float)
signal fullscreen_changed(enabled: bool)
signal journey_changed(enabled: bool)
signal closed

const PresentationTheme = preload("res://scripts/workspace/presentation_theme.gd")
const UiIcons = preload("res://scripts/workspace/ui_icons.gd")

var _section_buttons: Dictionary = {}
var _volume_slider: HSlider
var _fullscreen_check: CheckButton
var _journey_check: CheckButton
var _game_title: Label
var _volume_value: Label
var _status: Label
var _panel: PanelContainer
var _updating := false
var _open_generation := 0

func _ready() -> void:
    theme = PresentationTheme.make_theme()
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    offset_top = 80
    mouse_filter = Control.MOUSE_FILTER_STOP
    var dim := ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.015, 0.025, 0.04, 0.55)
    dim.gui_input.connect(func(event: InputEvent):
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            accept_event()
            closed.emit()
    )
    add_child(dim)
    _panel = PanelContainer.new()
    _panel.mouse_filter = Control.MOUSE_FILTER_STOP
    var style := StyleBoxFlat.new()
    style.bg_color = Color("101c26")
    style.border_color = Color("3b5260")
    style.set_border_width_all(1)
    style.set_corner_radius_all(20)
    style.set_content_margin_all(22)
    _panel.add_theme_stylebox_override("panel", style)
    add_child(_panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    _panel.add_child(column)
    var heading := _label(column, "Game settings", 25)
    heading.add_theme_font_override("font", PresentationTheme.heading_font())
    _game_title = _label(column, "Super Nintendo", 14, Color("a9bbc4"))
    _game_title.clip_text = true
    _game_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    column.add_child(scroll)
    var body := VBoxContainer.new()
    body.add_theme_constant_override("separation", 10)
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(body)
    for definition in [
        ["states", "Save & load states", "save", "Keep moments with screenshots, or return to a saved point."],
        ["controllers", "Controllers & keyboard", "controller", "Remap buttons with the original 3D SNES controller."],
        ["shaders", "Display shaders", "spark", "Compare Original, Smooth, Scanlines and CRT on the current frame."],
        ["library", "RetroLife preferences", "settings", "Open the existing library, motion and rendering preferences."],
    ]:
        var button := Button.new()
        button.text = str(definition[1])
        button.icon = UiIcons.icon(str(definition[2]), PresentationTheme.ACCENT, 24)
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.custom_minimum_size.y = 54
        button.tooltip_text = str(definition[3])
        button.pressed.connect(func(): section_requested.emit(str(definition[0])))
        body.add_child(button)
        _section_buttons[str(definition[0])] = button
    var volume_column := VBoxContainer.new()
    volume_column.add_theme_constant_override("separation", 4)
    body.add_child(volume_column)
    var volume_row := HBoxContainer.new()
    volume_column.add_child(volume_row)
    var volume_title := _label(volume_row, "Game volume", 15)
    volume_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _volume_value = _label(volume_row, "100%", 14, PresentationTheme.ACCENT)
    _volume_slider = HSlider.new()
    _volume_slider.min_value = 0
    _volume_slider.max_value = 100
    _volume_slider.step = 1
    _volume_slider.custom_minimum_size.y = 30
    _volume_slider.accessibility_name = "Game volume"
    _volume_slider.tooltip_text = "Change gameplay audio volume. Zero mutes the game."
    _volume_slider.value_changed.connect(func(value: float):
        _volume_value.text = "Muted" if is_zero_approx(value) else "%d%%" % roundi(value)
        if not _updating:
            volume_changed.emit(value / 100.0)
    )
    volume_column.add_child(_volume_slider)
    _fullscreen_check = CheckButton.new()
    _fullscreen_check.text = "Fullscreen"
    _fullscreen_check.toggled.connect(func(enabled: bool):
        if not _updating:
            fullscreen_changed.emit(enabled)
    )
    body.add_child(_fullscreen_check)
    _journey_check = CheckButton.new()
    _journey_check.text = "Show Journey"
    _journey_check.toggled.connect(func(enabled: bool):
        if not _updating:
            journey_changed.emit(enabled)
    )
    body.add_child(_journey_check)
    _status = _label(body, "Game paused. Closing settings restores your previous play state.", 12, Color("a9bbc4"))
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var done := Button.new()
    done.text = "Done"
    done.custom_minimum_size.y = 42
    done.pressed.connect(func(): closed.emit())
    column.add_child(done)
    resized.connect(_layout)
    _layout()
    hide()

func show_options(game_title: String, volume: float, journey_supported: bool, journey_visible: bool, fullscreen: bool, library_available: bool) -> void:
    _open_generation += 1
    _game_title.text = game_title + "  ·  Super Nintendo"
    refresh_options(volume, journey_supported, journey_visible, fullscreen, library_available)
    set_status("")
    show()
    _layout()
    _focus_first.call_deferred(_open_generation)

func refresh_options(volume: float, journey_supported: bool, journey_visible: bool, fullscreen: bool, library_available: bool) -> void:
    _updating = true
    _volume_slider.value = clampf(volume, 0.0, 1.0) * 100.0
    _fullscreen_check.button_pressed = fullscreen
    _journey_check.visible = journey_supported
    _journey_check.button_pressed = journey_supported and journey_visible
    _section_buttons.library.disabled = not library_available
    _updating = false

func dismiss() -> void:
    _open_generation += 1
    hide()

func set_status(message: String) -> void:
    _status.text = "Game paused. Closing settings restores your previous play state." if message.is_empty() else message
    _status.add_theme_color_override("font_color", Color("ffbc9c") if message.to_lower().contains("could not") else Color("a9bbc4"))

func _focus_first(generation: int) -> void:
    if generation == _open_generation and is_visible_in_tree():
        _section_buttons.controllers.grab_focus()

func _layout() -> void:
    if not is_instance_valid(_panel):
        return
    var dimensions := Vector2(minf(560.0, maxf(0.0, size.x - 32.0)), minf(660.0, maxf(0.0, size.y - 24.0)))
    _panel.size = dimensions
    _panel.position = (size - dimensions) / 2.0

func _label(parent: Node, text: String, font_size: int, color := Color("f0f4f5")) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label
