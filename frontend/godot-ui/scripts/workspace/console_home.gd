extends VBoxContainer

signal selected(system_id: String)
const Profiles = preload("res://scripts/workspace/collection_profiles.gd")
const Preferences = preload("res://scripts/workspace/preferences.gd")
const ModelView = preload("res://scripts/workspace/model_view.gd")
var _grid: GridContainer
var _scroll: ScrollContainer
var _buttons: Array[Button] = []
var _views: Array[SubViewportContainer] = []
var _hints: Array[Label] = []
var _paths: Array[String] = []
var _attempted: Array[bool] = []
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
    detail.text = "Explore your consoles in 3D. Drag to rotate, then open a collection."
    detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    detail.add_theme_color_override("font_color", Color("9aa8b8"))
    add_child(detail)
    _scroll = ScrollContainer.new()
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(_scroll)
    _grid = GridContainer.new()
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _grid.add_theme_constant_override("h_separation", 18)
    _grid.add_theme_constant_override("v_separation", 18)
    _scroll.add_child(_grid)
    resized.connect(_layout)
    _layout()

func configure(systems: Array) -> void:
    if _buttons.is_empty():
        _build_cards()
    var counts := {}
    for system in systems:
        counts[str(system.get("id", ""))] = int(system.get("gameCount", 0))
    var ids: Array = Profiles.SYSTEMS.keys()
    for index in range(ids.size()):
        var id: String = ids[index]
        var count := int(counts.get(id, 0))
        _buttons[index].text = "Open collection · %d game%s →" % [count, "" if count == 1 else "s"]
        var path := Preferences.asset("consoles/%s/%s-console.glb" % [id, id]) if allow_local_art else ""
        if path != _paths[index]:
            _views[index].load_model("")
            _paths[index] = path
            _attempted[index] = false
        _hints[index].text = "Drag to rotate · Double-click to reset" if not path.is_empty() else "Link a local 3D model in Storage & assets."
    _layout()

func _build_cards() -> void:
    for id in Profiles.SYSTEMS:
        var card := PanelContainer.new()
        card.name = "ConsoleCard_" + id
        card.custom_minimum_size = Vector2(210, 310)
        card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var style := StyleBoxFlat.new()
        style.bg_color = Color("131b26")
        style.border_color = Color("394658")
        style.set_border_width_all(1)
        style.set_corner_radius_all(16)
        style.set_content_margin_all(16)
        card.add_theme_stylebox_override("panel", style)
        _grid.add_child(card)
        var column := VBoxContainer.new()
        column.add_theme_constant_override("separation", 8)
        card.add_child(column)
        var view := ModelView.new()
        view.auto_frame = true
        view.minimum_view_size = Vector2(180, 190)
        view.default_view = Vector2(-0.35, 0.12) if id in ["game-boy", "game-boy-advance"] else Vector2(-0.55, 0.55)
        view.frame_scale = 1.0 if id in ["game-boy", "game-boy-advance"] else 0.7
        view.allow_wheel_zoom = false
        view.mouse_filter = Control.MOUSE_FILTER_PASS
        view.size_flags_vertical = Control.SIZE_EXPAND_FILL
        column.add_child(view)
        view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
        _views.append(view)
        _paths.append("")
        _attempted.append(false)
        var label := Label.new()
        label.text = Profiles.SYSTEMS[id]
        label.add_theme_font_size_override("font_size", 18)
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        column.add_child(label)
        var hint := Label.new()
        hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        hint.add_theme_color_override("font_color", Color("939eaf"))
        hint.add_theme_font_size_override("font_size", 12)
        column.add_child(hint)
        _hints.append(hint)
        var button := Button.new()
        button.name = "Console_" + id
        button.custom_minimum_size.y = 36
        button.tooltip_text = "Open " + Profiles.SYSTEMS[id]
        button.pressed.connect(func(): selected.emit(id))
        if id != "nes":
            button.focus_entered.connect(func(): _scroll.call_deferred("ensure_control_visible", card))
        column.add_child(button)
        _buttons.append(button)

func _process(_delta: float) -> void:
    # Retain loaded models when navigating back, but only draw visible cards.
    # Load one visible model per frame so the gallery can paint before imports.
    var loaded_this_frame := false
    for index in range(_views.size()):
        var view := _views[index]
        var active := is_visible_in_tree() and view.get_global_rect().intersects(_scroll.get_global_rect())
        view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if active else SubViewport.UPDATE_DISABLED
        if active and not loaded_this_frame and not _attempted[index] and not _paths[index].is_empty():
            _attempted[index] = true
            loaded_this_frame = true
            if not view.load_model(_paths[index]):
                _hints[index].text = "3D model unavailable. Check Storage & assets."

func focus_first() -> void:
    if not _buttons.is_empty():
        _buttons[0].grab_focus()
        _scroll.scroll_vertical = 0

func _layout() -> void:
    if _grid != null:
        _grid.columns = 3 if size.x >= 1000 else (2 if size.x >= 620 else 1)
