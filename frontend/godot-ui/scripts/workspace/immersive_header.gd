extends HBoxContainer

signal action_requested(action: String)
signal drag_requested()

const INK := Color("eaf0fa")
const MUTED := Color("a7aec4")
const MENU_ACTIONS := ["import", "controllers", "storage", "settings", "fullscreen", "minimize", "quit", "media"]

var _back: Button
var _box: Button
var _details: Button
var _search: Button
var _menu: MenuButton
var _rewards: Button
var _busy := false
var _at_console_home := true


func _ready() -> void:
    custom_minimum_size.y = 46
    add_theme_constant_override("separation", 8)
    _back = _action_button("←", "back", "Back to consoles")
    _back.accessibility_name = "Back to consoles"
    _back.custom_minimum_size.x = 42
    add_child(_back)

    var brand := HBoxContainer.new()
    brand.name = "WindowDragRegion"
    brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    brand.add_theme_constant_override("separation", 10)
    brand.mouse_default_cursor_shape = Control.CURSOR_MOVE
    brand.gui_input.connect(_brand_input)
    add_child(brand)
    var icon := TextureRect.new()
    icon.texture = preload("res://assets/brand/retrolife-icon.png")
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.custom_minimum_size = Vector2(34, 34)
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    brand.add_child(icon)
    var wordmark := Label.new()
    wordmark.text = "RetroLife"
    wordmark.add_theme_font_override("font", preload("res://scripts/workspace/presentation_theme.gd").heading_font())
    wordmark.add_theme_font_size_override("font_size", 22)
    wordmark.add_theme_color_override("font_color", INK)
    wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
    brand.add_child(wordmark)

    _rewards = _action_button("Rewards", "rewards", "Keepsakes from supported games")
    _rewards.icon = preload("res://scripts/workspace/ui_icons.gd").icon("trophy")
    add_child(_rewards)
    _box = _action_button("Box", "box", "Inspect this game's box in 3D")
    _details = _action_button("Details", "details", "Game details")
    _search = _action_button("Search", "search", "Search this collection  ·  /")
    _box.icon = preload("res://scripts/workspace/ui_icons.gd").icon("box")
    _search.icon = preload("res://scripts/workspace/ui_icons.gd").icon("search")
    add_child(_box)
    add_child(_details)
    add_child(_search)
    _menu = MenuButton.new()
    _menu.focus_mode = Control.FOCUS_ALL
    _menu.text = "Menu"
    _menu.icon = preload("res://scripts/workspace/ui_icons.gd").icon("menu")
    _menu.name = "CollectionMenu"
    _menu.tooltip_text = "Library, controllers and display options"
    _style_button(_menu)
    add_child(_menu)
    _build_menu()
    configure_page(true, false, false)


func configure_page(at_console_home: bool, has_game: bool, has_box: bool) -> void:
    _at_console_home = at_console_home
    if not is_instance_valid(_back):
        return
    _back.visible = not at_console_home
    _box.visible = not at_console_home and has_game and has_box
    _details.visible = not at_console_home and has_game
    _search.visible = not at_console_home
    _search.disabled = _busy


func set_busy(busy: bool) -> void:
    _busy = busy
    if not is_instance_valid(_back):
        return
    for button in [_back, _box, _details, _search, _rewards]:
        button.disabled = busy
    var popup := _menu.get_popup()
    for action_id in MENU_ACTIONS.size():
        popup.set_item_disabled(popup.get_item_index(action_id), busy and MENU_ACTIONS[action_id] not in ["fullscreen", "minimize"])


func set_search_query(query: String) -> void:
    if is_instance_valid(_search):
        _search.text = "Search" if query.is_empty() else "Filtered"
        _search.tooltip_text = "Search this collection  ·  /" if query.is_empty() else "Current search: " + query


func focus_back_if_visible() -> void:
    if is_instance_valid(_back) and _back.is_visible_in_tree() and not _back.disabled:
        _back.grab_focus()


func is_menu_open() -> bool:
    return is_instance_valid(_menu) and _menu.get_popup().visible


func close_menu() -> void:
    if is_instance_valid(_menu):
        _menu.get_popup().hide()


func _build_menu() -> void:
    var popup := _menu.get_popup()
    popup.add_item("Import ROM…", 0)
    popup.add_item("Controllers", 1)
    popup.add_item("Storage & assets", 2)
    popup.add_item("Game media · ScreenScraper", 7)
    popup.add_separator()
    popup.add_item("Display settings", 3)
    popup.add_item("Enter fullscreen", 4)
    popup.add_item("Minimize", 5)
    popup.add_separator()
    popup.add_item("Quit RetroLife", 6)
    popup.add_theme_color_override("font_color", INK)
    popup.add_theme_color_override("font_hover_color", Color.WHITE)
    popup.add_theme_color_override("font_disabled_color", Color("596078"))
    popup.add_theme_font_size_override("font_size", 16)
    popup.add_theme_constant_override("v_separation", 14)
    popup.add_theme_constant_override("h_separation", 16)
    var panel := StyleBoxFlat.new()
    panel.bg_color = Color("191c2d")
    panel.border_color = Color("363a55")
    panel.set_border_width_all(1)
    panel.set_corner_radius_all(14)
    panel.content_margin_left = 14
    panel.content_margin_right = 14
    panel.content_margin_top = 14
    panel.content_margin_bottom = 14
    panel.shadow_color = Color(0, 0, 0, 0.35)
    panel.shadow_size = 14
    popup.add_theme_stylebox_override("panel", panel)
    var hover := StyleBoxFlat.new()
    hover.bg_color = Color("32364d")
    hover.set_corner_radius_all(6)
    popup.add_theme_stylebox_override("hover", hover)
    popup.about_to_popup.connect(_update_window_menu)
    popup.id_pressed.connect(func(id: int) -> void:
        if id >= 0 and id < MENU_ACTIONS.size():
            action_requested.emit(MENU_ACTIONS[id]))


func _update_window_menu() -> void:
    var fullscreen := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
    var popup := _menu.get_popup()
    popup.set_item_text(popup.get_item_index(4), "Exit fullscreen" if fullscreen else "Enter fullscreen")


func _action_button(caption: String, action: String, hint: String) -> Button:
    var button := Button.new()
    button.text = caption
    button.tooltip_text = hint
    button.name = action.capitalize() + "Action"
    button.pressed.connect(func() -> void: action_requested.emit(action))
    _style_button(button)
    return button


func _style_button(button: Button) -> void:
    button.custom_minimum_size.y = 46
    button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    button.add_theme_font_size_override("font_size", 16)
    button.add_theme_color_override("font_color", MUTED)
    button.add_theme_color_override("font_hover_color", INK)
    button.add_theme_color_override("font_focus_color", INK)
    button.add_theme_color_override("font_pressed_color", Color.WHITE)
    button.add_theme_color_override("font_disabled_color", Color("535b71"))
    for state in ["normal", "hover", "pressed", "disabled", "focus"]:
        var style := StyleBoxFlat.new()
        style.bg_color = Color(0, 0, 0, 0)
        style.set_corner_radius_all(11)
        style.content_margin_left = 14
        style.content_margin_right = 14
        if state == "hover":
            style.bg_color = Color(0.48, 0.49, 0.69, 0.13)
        elif state == "pressed":
            style.bg_color = Color(0.48, 0.49, 0.69, 0.22)
        elif state == "focus":
            style.set_border_width_all(2)
            style.border_color = Color("b4a0ed")
        button.add_theme_stylebox_override(state, style)


func _brand_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        if event.double_click:
            action_requested.emit("fullscreen")
        else:
            drag_requested.emit()
        accept_event()
