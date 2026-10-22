extends VBoxContainer

signal selected(system_id: String)
const Profiles = preload("res://scripts/workspace/collection_profiles.gd")
const Preferences = preload("res://scripts/workspace/preferences.gd")
var _grid: GridContainer
var _buttons: Array[Button] = []
var allow_local_art := true

func _ready() -> void:
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", 16)
    var eyebrow := Label.new()
    eyebrow.text = "YOUR PLAYROOM"
    eyebrow.add_theme_color_override("font_color", Color("78dbba"))
    add_child(eyebrow)
    var title := Label.new()
    title.text = "Where do you want to play?"
    title.add_theme_font_size_override("font_size", 36)
    title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(title)
    var detail := Label.new()
    detail.text = "Choose a console, then explore the games in your collection."
    detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    detail.add_theme_color_override("font_color", Color("9aa8b8"))
    add_child(detail)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(scroll)
    _grid = GridContainer.new()
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _grid.add_theme_constant_override("h_separation", 18)
    _grid.add_theme_constant_override("v_separation", 18)
    scroll.add_child(_grid)
    resized.connect(_layout)
    _layout()

func configure(systems: Array) -> void:
    for child in _grid.get_children():
        child.free()
    _buttons.clear()
    var counts := {}
    for system in systems:
        counts[str(system.get("id", ""))] = int(system.get("gameCount", 0))
    for id in Profiles.SYSTEMS:
        var count := int(counts.get(id, 0))
        var card := Button.new()
        card.name = "Console_" + id
        card.custom_minimum_size = Vector2(210, 246)
        card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        card.tooltip_text = Profiles.SYSTEMS[id]
        for state in ["normal", "hover", "focus"]:
            var style := StyleBoxFlat.new()
            style.bg_color = Color("202936") if state != "normal" else Color("131b26")
            style.border_color = Color("7ce4ad") if state == "focus" else Color("394658")
            style.set_border_width_all(2 if state == "focus" else 1)
            style.set_corner_radius_all(16)
            card.add_theme_stylebox_override(state, style)
        var margin := MarginContainer.new()
        margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
        for side in ["left", "right", "top", "bottom"]:
            margin.add_theme_constant_override("margin_" + side, 16)
        card.add_child(margin)
        var column := VBoxContainer.new()
        column.mouse_filter = Control.MOUSE_FILTER_IGNORE
        margin.add_child(column)
        var art := TextureRect.new()
        art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
        art.texture = Preferences.image("consoles/%s/hero.png" % id) if allow_local_art else null
        art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        art.custom_minimum_size.y = 160
        art.size_flags_vertical = Control.SIZE_EXPAND_FILL
        art.mouse_filter = Control.MOUSE_FILTER_IGNORE
        column.add_child(art)
        var label := Label.new()
        label.text = Profiles.SYSTEMS[id]
        label.add_theme_font_size_override("font_size", 18)
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        column.add_child(label)
        var meta := Label.new()
        meta.text = "%d game%s  ·  Open collection →" % [count, "" if count == 1 else "s"] if count > 0 else "No games in this library"
        meta.add_theme_color_override("font_color", Color("7ce4ad") if count > 0 else Color("939eaf"))
        meta.add_theme_font_size_override("font_size", 13)
        meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
        column.add_child(meta)
        card.pressed.connect(func(): selected.emit(id))
        _grid.add_child(card)
        _buttons.append(card)
    _layout()

func focus_first() -> void:
    if not _buttons.is_empty():
        _buttons[0].grab_focus()

func _layout() -> void:
    if _grid != null:
        _grid.columns = 3 if size.x >= 1000 else (2 if size.x >= 620 else 1)
