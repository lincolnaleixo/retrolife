extends Control

const ExtensionLoader = preload("res://scripts/extension_loader.gd")
const CatalogClient = preload("res://scripts/catalog_client.gd")

const GRID_COLUMNS := 3
const PAGE_LIMIT := 500
const CARD_MINIMUM_SIZE := Vector2(330, 184)
const BACKGROUND_COLOR := Color("#0B0D13")
const SURFACE_COLOR := Color("#151A24")
const MUTED_COLOR := Color("#9AA4B2")
const TEXT_COLOR := Color("#F5F7FB")
const DANGER_COLOR := Color("#FF7B86")

var _backend: Node
var _catalog: RefCounted
var _selected_system_id := ""
var _search_query := ""
var _last_game_id := ""
var _return_game_id := ""
var _systems: Array = []
var _current_games: Array = []
var _card_by_id := {}
var _filter_buttons: Array[Button] = []
var _filter_group: ButtonGroup

var _source_label: Label
var _count_label: Label
var _status_label: Label
var _warning_label: Label
var _search_edit: LineEdit
var _filter_row: HBoxContainer
var _games_scroll: ScrollContainer
var _grid: GridContainer
var _empty_label: Label
var _details_overlay: Control
var _details_back_button: Button
var _details_title: Label
var _details_system: Label
var _details_year_region: Label
var _details_creator: Label
var _details_genres: Label
var _details_players: Label
var _details_aliases: Label
var _details_description: Label
var _details_artwork: Label
var _details_state: Label


func _ready() -> void:
    _ensure_input_actions()
    _build_shell()

    var extension_error := ExtensionLoader.ensure_loaded()
    if not extension_error.is_empty():
        _show_fatal_error(extension_error)
        return

    _backend = ClassDB.instantiate("RetroLifeBackend") as Node
    if _backend == null:
        _show_fatal_error("RetroLifeBackend exists but could not be instantiated.")
        return
    add_child(_backend)
    _catalog = CatalogClient.new(_backend)

    var reset: Dictionary = _catalog.reset_reference()
    if not bool(reset.get("ok", false)):
        _show_fatal_error(str(reset.get("error", "Could not initialize the reference catalog.")))
        return

    var startup_snapshot: Dictionary = _catalog.load_startup_snapshot()
    if not str(startup_snapshot.get("error", "")).is_empty():
        _warning_label.text = "Snapshot fallback: %s" % startup_snapshot.get("error")
        _warning_label.visible = true
    elif bool(startup_snapshot.get("loaded", false)):
        _warning_label.text = "Loaded catalog snapshot: %s" % startup_snapshot.get("path")
        _warning_label.visible = true

    _status_label.text = str(_backend.call("ping"))
    _refresh_library()


func _unhandled_input(event: InputEvent) -> void:
    if _details_overlay.visible:
        if event.is_action_pressed("ui_cancel"):
            _close_details()
            get_viewport().set_input_as_handled()
        return

    if event.is_action_pressed("library_previous_system"):
        _cycle_system(-1)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("library_next_system"):
        _cycle_system(1)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("library_search"):
        _search_edit.grab_focus()
        _search_edit.select_all()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("ui_cancel"):
        if not _search_query.is_empty() or not _selected_system_id.is_empty():
            _selected_system_id = ""
            _search_query = ""
            _search_edit.text = ""
            _refresh_library()
            get_viewport().set_input_as_handled()


func _build_shell() -> void:
    var background := ColorRect.new()
    background.name = "Background"
    background.color = BACKGROUND_COLOR
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)

    var margin := MarginContainer.new()
    margin.name = "LibraryMargin"
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 40)
    margin.add_theme_constant_override("margin_top", 28)
    margin.add_theme_constant_override("margin_right", 40)
    margin.add_theme_constant_override("margin_bottom", 24)
    add_child(margin)

    var root_column := VBoxContainer.new()
    root_column.name = "LibraryRoot"
    root_column.add_theme_constant_override("separation", 14)
    margin.add_child(root_column)

    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 18)
    root_column.add_child(header)

    var heading := VBoxContainer.new()
    heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    heading.add_theme_constant_override("separation", 2)
    header.add_child(heading)

    var title := _label("RetroLife", 36, TEXT_COLOR)
    title.name = "AppTitle"
    heading.add_child(title)

    _status_label = _label("Connecting to Rust...", 14, MUTED_COLOR)
    _status_label.name = "StatusLabel"
    heading.add_child(_status_label)

    var source_column := VBoxContainer.new()
    source_column.alignment = BoxContainer.ALIGNMENT_CENTER
    header.add_child(source_column)

    _source_label = _label("Catalog pending", 14, TEXT_COLOR)
    _source_label.name = "SourceLabel"
    _source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    source_column.add_child(_source_label)

    _count_label = _label("0 games", 13, MUTED_COLOR)
    _count_label.name = "CountLabel"
    _count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    source_column.add_child(_count_label)

    _warning_label = _label("", 13, DANGER_COLOR)
    _warning_label.name = "CatalogWarning"
    _warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _warning_label.visible = false
    root_column.add_child(_warning_label)

    var toolbar := HBoxContainer.new()
    toolbar.name = "Toolbar"
    toolbar.add_theme_constant_override("separation", 12)
    root_column.add_child(toolbar)

    _search_edit = LineEdit.new()
    _search_edit.name = "SearchEdit"
    _search_edit.placeholder_text = "Search title, alias, studio, genre, or system"
    _search_edit.custom_minimum_size = Vector2(430, 48)
    _search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _search_edit.clear_button_enabled = true
    _search_edit.text_changed.connect(_on_search_changed)
    toolbar.add_child(_search_edit)

    var search_hint := _label("Y or /  Search", 13, MUTED_COLOR)
    search_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    toolbar.add_child(search_hint)

    var filters_scroll := ScrollContainer.new()
    filters_scroll.name = "SystemFiltersScroll"
    filters_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    filters_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    filters_scroll.custom_minimum_size.y = 50
    root_column.add_child(filters_scroll)

    _filter_row = HBoxContainer.new()
    _filter_row.name = "SystemFilters"
    _filter_row.add_theme_constant_override("separation", 10)
    filters_scroll.add_child(_filter_row)

    _games_scroll = ScrollContainer.new()
    _games_scroll.name = "GamesScroll"
    _games_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _games_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _games_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    root_column.add_child(_games_scroll)

    var games_content := VBoxContainer.new()
    games_content.name = "GamesContent"
    games_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    games_content.add_theme_constant_override("separation", 16)
    _games_scroll.add_child(games_content)

    _empty_label = _label("No games match this view.", 20, MUTED_COLOR)
    _empty_label.name = "EmptyState"
    _empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _empty_label.custom_minimum_size.y = 160
    _empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _empty_label.visible = false
    games_content.add_child(_empty_label)

    _grid = GridContainer.new()
    _grid.name = "GameGrid"
    _grid.columns = GRID_COLUMNS
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _grid.add_theme_constant_override("h_separation", 16)
    _grid.add_theme_constant_override("v_separation", 16)
    games_content.add_child(_grid)

    var footer := _label(
        "D-pad or arrows  Navigate     A or Enter  Details     LB/RB  System     B or Esc  Clear/Back",
        13,
        MUTED_COLOR
    )
    footer.name = "InputHints"
    footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    root_column.add_child(footer)

    _build_details_overlay()


func _build_details_overlay() -> void:
    _details_overlay = ColorRect.new()
    _details_overlay.name = "DetailsOverlay"
    _details_overlay.color = Color(0.02, 0.03, 0.05, 0.96)
    _details_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _details_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    _details_overlay.visible = false
    add_child(_details_overlay)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    center.offset_left = 48
    center.offset_top = 36
    center.offset_right = -48
    center.offset_bottom = -36
    _details_overlay.add_child(center)

    var panel := PanelContainer.new()
    panel.name = "DetailsPanel"
    panel.custom_minimum_size = Vector2(920, 590)
    panel.add_theme_stylebox_override("panel", _style_box(SURFACE_COLOR, Color("#3B465A"), 2, 22))
    center.add_child(panel)

    var details_margin := MarginContainer.new()
    details_margin.add_theme_constant_override("margin_left", 34)
    details_margin.add_theme_constant_override("margin_top", 30)
    details_margin.add_theme_constant_override("margin_right", 34)
    details_margin.add_theme_constant_override("margin_bottom", 28)
    panel.add_child(details_margin)

    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    details_margin.add_child(column)

    _details_title = _label("Game title", 34, TEXT_COLOR)
    _details_title.name = "DetailsTitle"
    _details_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_details_title)

    _details_system = _label("System", 18, Color("#B9C4D8"))
    _details_system.name = "DetailsSystem"
    column.add_child(_details_system)

    var separator := HSeparator.new()
    column.add_child(separator)

    var metadata := GridContainer.new()
    metadata.columns = 2
    metadata.add_theme_constant_override("h_separation", 24)
    metadata.add_theme_constant_override("v_separation", 8)
    column.add_child(metadata)

    _details_year_region = _details_row(metadata, "Year / region", "DetailsYearRegion")
    _details_creator = _details_row(metadata, "Developer / publisher", "DetailsCreator")
    _details_genres = _details_row(metadata, "Genres", "DetailsGenres")
    _details_players = _details_row(metadata, "Players", "DetailsPlayers")
    _details_aliases = _details_row(metadata, "Aliases", "DetailsAliases")
    _details_artwork = _details_row(metadata, "Artwork reference", "DetailsArtwork")

    _details_description = _label("Description", 17, Color("#D8DEEA"))
    _details_description.name = "DetailsDescription"
    _details_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _details_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(_details_description)

    _details_state = _label("State", 16, TEXT_COLOR)
    _details_state.name = "DetailsState"
    column.add_child(_details_state)

    _details_back_button = Button.new()
    _details_back_button.name = "DetailsBackButton"
    _details_back_button.text = "Back to library"
    _details_back_button.custom_minimum_size = Vector2(220, 52)
    _details_back_button.size_flags_horizontal = Control.SIZE_SHRINK_END
    _details_back_button.pressed.connect(_close_details)
    column.add_child(_details_back_button)


func _details_row(parent: GridContainer, title: String, value_name: String) -> Label:
    var title_label := _label(title, 14, MUTED_COLOR)
    parent.add_child(title_label)
    var value_label := _label("Unknown", 15, TEXT_COLOR)
    value_label.name = value_name
    value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(value_label)
    return value_label


func _refresh_library(preferred_game_id := "", preserve_control_focus := false) -> void:
    if _catalog == null:
        return

    var response: Dictionary = _catalog.view(
        _selected_system_id,
        _search_query,
        0,
        PAGE_LIMIT
    )
    if not bool(response.get("ok", false)):
        _show_nonfatal_error(str(response.get("error", "Catalog view failed.")))
        return

    _warning_label.visible = not _warning_label.text.is_empty()
    var data: Dictionary = response.get("data", {})
    _systems = data.get("systems", [])
    _current_games = data.get("games", [])
    _source_label.text = "%s  •  %s" % [
        str(data.get("sourceLabel", "Catalog")),
        str(data.get("source", "unknown")),
    ]
    _count_label.text = "%s of %s games" % [
        data.get("filteredGames", 0),
        data.get("totalGames", 0),
    ]

    _rebuild_filters()
    _rebuild_cards()

    if preserve_control_focus and _search_edit.has_focus():
        return
    var focus_id := preferred_game_id
    if focus_id.is_empty():
        focus_id = _last_game_id
    _focus_game_deferred(focus_id)


func _rebuild_filters() -> void:
    for child in _filter_row.get_children():
        child.queue_free()
    _filter_buttons.clear()
    _filter_group = ButtonGroup.new()

    _filter_buttons.append(_add_filter_button("All systems", "", _selected_system_id.is_empty()))
    for system_variant in _systems:
        var system: Dictionary = system_variant
        var filter_label := "%s  %s" % [system.get("name", "System"), system.get("gameCount", 0)]
        var system_id := str(system.get("id", ""))
        _filter_buttons.append(
            _add_filter_button(filter_label, system_id, system_id == _selected_system_id)
        )


func _add_filter_button(text: String, system_id: String, selected: bool) -> Button:
    var button := Button.new()
    button.name = "SystemFilter_%s" % ("all" if system_id.is_empty() else system_id)
    button.text = text
    button.toggle_mode = true
    button.button_group = _filter_group
    button.button_pressed = selected
    button.custom_minimum_size = Vector2(150, 42)
    button.set_meta("system_id", system_id)
    button.pressed.connect(_on_filter_pressed.bind(system_id))
    _filter_row.add_child(button)
    return button


func _rebuild_cards() -> void:
    for child in _grid.get_children():
        child.queue_free()
    _card_by_id.clear()
    _empty_label.visible = _current_games.is_empty()
    _grid.visible = not _current_games.is_empty()

    for game_variant in _current_games:
        var game: Dictionary = game_variant
        var card := _create_game_card(game)
        _grid.add_child(card)
        _card_by_id[str(game.get("id", ""))] = card


func _create_game_card(game: Dictionary) -> Button:
    var game_id := str(game.get("id", ""))
    var year := str(game.get("releaseYear", "Unknown year"))
    if game.get("releaseYear") == null:
        year = "Unknown year"
    var state := "Ready"
    if not bool(game.get("playable", true)):
        state = "Preview only"
    if bool(game.get("favorite", false)):
        state = "★  %s" % state

    var button := Button.new()
    button.name = "GameCard_%s" % game_id
    button.text = "%s\n%s  •  %s\n%s" % [
        game.get("title", "Untitled"),
        game.get("systemName", "Unknown system"),
        year,
        state,
    ]
    button.custom_minimum_size = CARD_MINIMUM_SIZE
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    button.tooltip_text = str(game.get("artworkRef", "No artwork reference"))
    button.set_meta("game_id", game_id)
    button.set_meta("system_id", str(game.get("systemId", "")))
    button.pressed.connect(_open_details.bind(game_id))

    var primary := _safe_color(str(game.get("accentPrimary", "#5865F2")), Color("#5865F2"))
    var secondary := _safe_color(str(game.get("accentSecondary", "#232946")), SURFACE_COLOR)
    button.add_theme_stylebox_override("normal", _style_box(secondary, primary.darkened(0.2), 2, 18))
    button.add_theme_stylebox_override("hover", _style_box(secondary.lightened(0.08), primary, 2, 18))
    button.add_theme_stylebox_override("pressed", _style_box(secondary.darkened(0.05), primary, 3, 18))
    button.add_theme_stylebox_override("focus", _style_box(secondary.lightened(0.12), primary, 5, 18))
    button.add_theme_color_override("font_color", TEXT_COLOR)
    button.add_theme_color_override("font_focus_color", TEXT_COLOR)
    button.add_theme_color_override("font_hover_color", TEXT_COLOR)
    button.add_theme_font_size_override("font_size", 17)
    button.add_theme_constant_override("outline_size", 2)
    return button


func _on_filter_pressed(system_id: String) -> void:
    _selected_system_id = system_id
    _refresh_library()


func _on_search_changed(query: String) -> void:
    _search_query = query
    _refresh_library("", true)


func _cycle_system(direction: int) -> void:
    if _filter_buttons.is_empty():
        return
    var current_index := 0
    for index in range(_filter_buttons.size()):
        if str(_filter_buttons[index].get_meta("system_id", "")) == _selected_system_id:
            current_index = index
            break
    var next_index := wrapi(current_index + direction, 0, _filter_buttons.size())
    _selected_system_id = str(_filter_buttons[next_index].get_meta("system_id", ""))
    _refresh_library()


func _open_details(game_id: String) -> void:
    if _catalog == null:
        return
    var response: Dictionary = _catalog.details(game_id)
    if not bool(response.get("ok", false)):
        _show_nonfatal_error(str(response.get("error", "Game details failed.")))
        return
    var game: Dictionary = response.get("data", {})
    _return_game_id = game_id
    _last_game_id = game_id

    _details_title.text = str(game.get("title", "Untitled"))
    _details_system.text = str(game.get("systemName", "Unknown system"))
    _details_year_region.text = "%s  •  %s" % [
        _optional_value(game.get("releaseYear"), "Unknown year"),
        _optional_value(game.get("region"), "Unknown region"),
    ]
    _details_creator.text = "%s  •  %s" % [
        _optional_value(game.get("developer"), "Unknown developer"),
        _optional_value(game.get("publisher"), "Unknown publisher"),
    ]
    _details_genres.text = _join_values(game.get("genres", []), "Unknown")
    _details_players.text = _optional_value(game.get("players"), "Unknown")
    _details_aliases.text = _join_values(game.get("aliases", []), "None")
    _details_description.text = _optional_value(
        game.get("description"),
        "No description is available for this catalog entry."
    )
    _details_artwork.text = _optional_value(game.get("artworkRef"), "Fallback color card")
    _details_state.text = "Ready to launch in a later phase"
    if not bool(game.get("playable", true)):
        _details_state.text = "Preview only  •  launch support is not available yet"
    if bool(game.get("favorite", false)):
        _details_state.text = "★  %s" % _details_state.text

    var accent := _safe_color(str(game.get("accentPrimary", "#5865F2")), Color("#5865F2"))
    _details_state.add_theme_color_override("font_color", accent)
    _details_overlay.visible = true
    _details_overlay.move_to_front()
    _details_back_button.call_deferred("grab_focus")


func _close_details() -> void:
    if not _details_overlay.visible:
        return
    _details_overlay.visible = false
    var focus_id := _return_game_id
    _return_game_id = ""
    _focus_game_deferred(focus_id)


func _focus_game_deferred(game_id: String) -> void:
    var button: Button = _card_by_id.get(game_id)
    if button == null and not _current_games.is_empty():
        button = _card_by_id.get(str((_current_games[0] as Dictionary).get("id", "")))
    if button == null:
        return
    _last_game_id = str(button.get_meta("game_id", ""))
    button.call_deferred("grab_focus")
    _games_scroll.call_deferred("ensure_control_visible", button)


func _show_fatal_error(message: String) -> void:
    _status_label.text = message
    _status_label.add_theme_color_override("font_color", DANGER_COLOR)
    _warning_label.text = message
    _warning_label.visible = true
    _search_edit.editable = false


func _show_nonfatal_error(message: String) -> void:
    _warning_label.text = message
    _warning_label.visible = true


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


func _safe_color(value: String, fallback: Color) -> Color:
    if Color.html_is_valid(value):
        return Color.from_string(value, fallback)
    return fallback


func _optional_value(value: Variant, fallback: String) -> String:
    if value == null:
        return fallback
    var text := str(value).strip_edges()
    return fallback if text.is_empty() else text


func _join_values(values: Variant, fallback: String) -> String:
    if typeof(values) != TYPE_ARRAY or (values as Array).is_empty():
        return fallback
    var strings: PackedStringArray = []
    for value in values:
        strings.append(str(value))
    return ", ".join(strings)


func _ensure_input_actions() -> void:
    _ensure_key_action("ui_accept", KEY_ENTER)
    _ensure_key_action("ui_cancel", KEY_ESCAPE)
    _ensure_key_action("ui_left", KEY_LEFT)
    _ensure_key_action("ui_right", KEY_RIGHT)
    _ensure_key_action("ui_up", KEY_UP)
    _ensure_key_action("ui_down", KEY_DOWN)
    _ensure_key_action("library_search", KEY_SLASH)

    _ensure_joy_button_action("ui_accept", 0)
    _ensure_joy_button_action("ui_cancel", 1)
    _ensure_joy_button_action("library_search", 3)
    _ensure_joy_button_action("library_previous_system", 9)
    _ensure_joy_button_action("library_next_system", 10)
    _ensure_joy_button_action("ui_up", 11)
    _ensure_joy_button_action("ui_down", 12)
    _ensure_joy_button_action("ui_left", 13)
    _ensure_joy_button_action("ui_right", 14)
    _ensure_joy_motion_action("ui_left", 0, -1.0)
    _ensure_joy_motion_action("ui_right", 0, 1.0)
    _ensure_joy_motion_action("ui_up", 1, -1.0)
    _ensure_joy_motion_action("ui_down", 1, 1.0)


func _ensure_key_action(action: StringName, keycode: int) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    for event in InputMap.action_get_events(action):
        if event is InputEventKey and event.keycode == keycode:
            return
    var key := InputEventKey.new()
    key.keycode = keycode
    InputMap.action_add_event(action, key)


func _ensure_joy_button_action(action: StringName, button_index: int) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    for event in InputMap.action_get_events(action):
        if event is InputEventJoypadButton and event.button_index == button_index:
            return
    var button := InputEventJoypadButton.new()
    button.button_index = button_index
    InputMap.action_add_event(action, button)


func _ensure_joy_motion_action(action: StringName, axis: int, axis_value: float) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    for event in InputMap.action_get_events(action):
        if event is InputEventJoypadMotion \
            and event.axis == axis \
            and is_equal_approx(event.axis_value, axis_value):
            return
    var motion := InputEventJoypadMotion.new()
    motion.axis = axis
    motion.axis_value = axis_value
    InputMap.action_add_event(action, motion)
