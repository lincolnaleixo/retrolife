extends Control

signal preset_changed(preset_id: String, strength: float)
signal closed

const SNESDisplay = preload("res://scripts/workspace/snes_display.gd")
const PresentationTheme = preload("res://scripts/workspace/presentation_theme.gd")
const ACCENT := Color("a7e7ce")
const PRESETS := [
    ["original", "Original", "Clean pixels", "The original pixel image, without a display effect."],
    ["smooth", "Smooth", "Soft edges", "A gentle interpolation softens pixel edges."],
    ["scanlines", "Scanlines", "Classic rhythm", "Fine scanlines recall the texture of a television."],
    ["crt", "CRT", "Living-room glow", "A curved television image with subtle glow, scanlines and a phosphor mask."],
]

var _preset_buttons: Dictionary = {}
var _strength_slider: HSlider
var _previews: Dictionary = {}
var _selection_labels: Dictionary = {}
var _preview_areas: Array[Control] = []
var _panel: PanelContainer
var _strength_value: Label
var _status: Label
var _done: Button
var _selected_id := "original"
var _strength := 0.65
var _frame_texture: Texture2D
var _updating := false
var _open_generation := 0

func _ready() -> void:
    theme = PresentationTheme.make_theme()
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    offset_top = 80
    mouse_filter = Control.MOUSE_FILTER_STOP
    var dim := ColorRect.new()
    dim.color = Color(0.0, 0.0, 0.0, 0.10)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.gui_input.connect(_outside_input)
    add_child(dim)
    _panel = PanelContainer.new()
    _panel.mouse_filter = Control.MOUSE_FILTER_STOP
    _panel.add_theme_stylebox_override("panel", _panel_style())
    add_child(_panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    _panel.add_child(column)
    var title_row := HBoxContainer.new()
    column.add_child(title_row)
    var heading := _label(title_row, "Super Nintendo · Display", 20)
    heading.add_theme_font_override("font", PresentationTheme.heading_font())
    heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _label(column, "Choose how your games feel.", 14, Color("a9bbc4"))
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroll.follow_focus = true
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_child(scroll)
    var body := VBoxContainer.new()
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 14)
    scroll.add_child(body)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", 10)
    grid.add_theme_constant_override("v_separation", 10)
    body.add_child(grid)
    for preset in PRESETS:
        _build_preset(grid, preset)
    var intensity := VBoxContainer.new()
    intensity.add_theme_constant_override("separation", 6)
    body.add_child(intensity)
    var intensity_header := HBoxContainer.new()
    intensity.add_child(intensity_header)
    var strength_title := _label(intensity_header, "Intensity", 14)
    strength_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _strength_value = _label(intensity_header, "65%", 14, ACCENT)
    _strength_slider = HSlider.new()
    _strength_slider.min_value = 0
    _strength_slider.max_value = 100
    _strength_slider.step = 1
    _strength_slider.value = 65
    _strength_slider.custom_minimum_size.y = 28
    _strength_slider.focus_mode = Control.FOCUS_ALL
    _strength_slider.accessibility_name = "Shader intensity"
    _strength_slider.tooltip_text = "Adjust the selected display effect. Original always keeps the unfiltered image."
    _strength_slider.value_changed.connect(_strength_changed)
    intensity.add_child(_strength_slider)
    _status = _label(body, "Game paused while you preview.", 12, Color("a9bbc4"))
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var actions := HBoxContainer.new()
    actions.add_theme_constant_override("separation", 10)
    column.add_child(actions)
    var reset := Button.new()
    reset.text = "Reset to Original"
    reset.tooltip_text = "Remove the display effect."
    reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reset.pressed.connect(_reset)
    actions.add_child(reset)
    _done = Button.new()
    _done.text = "Done"
    _done.tooltip_text = "Close display options and return to the game."
    _done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _done.pressed.connect(func(): closed.emit())
    actions.add_child(_done)
    resized.connect(_layout)
    _layout()
    hide()

func show_options(frame_texture: Texture2D, preset_id: String, strength: float) -> void:
    _open_generation += 1
    _frame_texture = frame_texture
    _selected_id = preset_id if _preset_buttons.has(preset_id) else "original"
    _strength = clampf(strength, 0.0, 1.0) if is_finite(strength) else 0.65
    _updating = true
    _strength_slider.value = _strength * 100.0
    _updating = false
    for preview in _previews.values():
        preview.texture = _frame_texture
    set_status("")
    _refresh()
    show()
    _layout()
    _focus_selected.call_deferred(_open_generation)

func _focus_selected(generation: int) -> void:
    if generation == _open_generation and is_visible_in_tree():
        _preset_buttons[_selected_id].grab_focus()

func dismiss() -> void:
    _open_generation += 1
    hide()
    _frame_texture = null
    for preview in _previews.values():
        preview.texture = null

func set_status(message: String) -> void:
    if not is_instance_valid(_status):
        return
    _status.text = "Game paused while you preview." if message.is_empty() else message
    var failed := message.to_lower().contains("could not")
    _status.add_theme_color_override("font_color", Color("ffbc9c") if failed else Color("a9bbc4"))

func _build_preset(parent: Node, preset: Array) -> void:
    var id := str(preset[0])
    var button := Button.new()
    button.text = str(preset[1])
    button.tooltip_text = str(preset[3])
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.custom_minimum_size = Vector2(0, 172)
    button.clip_contents = true
    # Retain the button's accessible title; the child layout draws the visible caption.
    for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        button.add_theme_color_override(state, Color.TRANSPARENT)
    button.pressed.connect(_select.bind(id))
    parent.add_child(button)
    _preset_buttons[id] = button
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 9)
    button.add_child(margin)
    var column := VBoxContainer.new()
    column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    column.add_theme_constant_override("separation", 5)
    margin.add_child(column)
    var area := Control.new()
    area.mouse_filter = Control.MOUSE_FILTER_IGNORE
    area.custom_minimum_size.y = 110
    area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    area.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(area)
    _preview_areas.append(area)
    var background := ColorRect.new()
    background.color = Color("05090e")
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    area.add_child(background)
    var preview := TextureRect.new()
    preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    preview.stretch_mode = TextureRect.STRETCH_SCALE
    preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    area.add_child(preview)
    _previews[id] = preview
    area.resized.connect(_layout_preview.bind(area, preview))
    var label_row := HBoxContainer.new()
    label_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    column.add_child(label_row)
    var title := _label(label_row, str(preset[1]), 15)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var selected := _label(label_row, "", 12, ACCENT)
    _selection_labels[id] = selected
    _label(column, str(preset[2]), 11, Color("9db0bb"))

func _select(id: String) -> void:
    _selected_id = id
    _refresh()
    preset_changed.emit(_selected_id, _strength)

func _reset() -> void:
    _selected_id = "original"
    _strength = 0.65
    _updating = true
    _strength_slider.value = 65
    _updating = false
    _refresh()
    _preset_buttons.original.grab_focus()
    preset_changed.emit(_selected_id, _strength)

func _strength_changed(value: float) -> void:
    if _updating:
        return
    _strength = value / 100.0
    _refresh()
    preset_changed.emit(_selected_id, _strength)

func _refresh() -> void:
    for id in _preset_buttons:
        var selected := str(id) == _selected_id
        var button: Button = _preset_buttons[id]
        button.add_theme_stylebox_override("normal", _card_style(selected, false))
        button.add_theme_stylebox_override("hover", _card_style(selected, true))
        button.add_theme_stylebox_override("pressed", _card_style(true, true))
        var focus := _card_style(false, false)
        focus.bg_color = Color.TRANSPARENT
        focus.border_color = Color("e6fff4")
        focus.set_border_width_all(2)
        button.add_theme_stylebox_override("focus", focus)
        _selection_labels[id].text = "✓" if selected else ""
        SNESDisplay.apply(_previews[id], str(id), _strength)
    _strength_slider.editable = _selected_id != "original"
    _strength_slider.modulate = Color.WHITE if _strength_slider.editable else Color(1.0, 1.0, 1.0, 0.45)
    _strength_value.text = "%d%%" % roundi(_strength * 100.0) if _strength_slider.editable else "Off"

func _layout() -> void:
    if not is_instance_valid(_panel):
        return
    var inset := 12.0
    var width := minf(440.0, maxf(0.0, size.x - inset * 2.0))
    _panel.position = Vector2(maxf(inset, size.x - width - inset), inset)
    _panel.size = Vector2(width, minf(680.0, maxf(0.0, size.y - inset * 2.0)))
    var compact := size.y < 640.0
    for button in _preset_buttons.values():
        button.custom_minimum_size.y = 148.0 if compact else 172.0
    for area in _preview_areas:
        area.custom_minimum_size.y = 86.0 if compact else 110.0

func _layout_preview(area: Control, preview: TextureRect) -> void:
    var width := minf(area.size.x, area.size.y * 4.0 / 3.0)
    var dimensions := Vector2(width, width * 3.0 / 4.0)
    preview.size = dimensions
    preview.position = (area.size - dimensions) / 2.0

func _outside_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        accept_event()
        closed.emit()

func _label(parent: Node, text: String, font_size: int, color := Color("f0f4f5")) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label

func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color("101923")
    style.border_color = Color("354650")
    style.set_border_width_all(1)
    style.set_corner_radius_all(20)
    style.set_content_margin_all(18)
    style.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
    style.shadow_size = 14
    return style

func _card_style(selected: bool, hovered: bool) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color("22353b") if selected else Color("18242e")
    if hovered:
        style.bg_color = style.bg_color.lightened(0.08)
    style.border_color = ACCENT if selected else Color("354650")
    style.set_border_width_all(2 if selected else 1)
    style.set_corner_radius_all(12)
    return style
