extends "res://scripts/main.gd"

## Cartridge-first presentation over the existing local library/gameplay contract.
const Carousel = preload("res://scripts/library/carousel.gd")
var settings_path := "user://library-ui.cfg"

var persist_preferences := true
var _carousel: Control
var _hero_title: Label
var _hero_meta: Label
var _hero_count: Label
var _search_panel: PopupPanel
var _settings_panel: PopupPanel
var _search_button: Button
var _art_dialog: FileDialog
var _artwork_game_id := ""
var _view_selections: Dictionary = {}
var _view_order: Array[String] = []
var _refresh_generation := 0
var _refreshing := false
var _importing := false
var _search_timer: Timer
var _settings_timer: Timer
var _preferences := ConfigFile.new()
var _reduce_motion := false
var _low_quality := false
var _textual_view := false


func _ready() -> void:
    _load_preferences()
    super._ready()


func _load_preferences() -> void:
    if persist_preferences and _preferences.load(settings_path) == OK:
        _reduce_motion = bool(_preferences.get_value("view", "reduced_motion", false))
        _low_quality = bool(_preferences.get_value("view", "low_quality", false))
        _textual_view = bool(_preferences.get_value("view", "textual_view", false))
        _selected_system_id = str(_preferences.get_value("selection", "system", ""))
        _last_game_id = str(_preferences.get_value("selection", "game", ""))


func _build_shell() -> void:
    var background := ColorRect.new()
    background.name = "ShowcaseBackground"
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var material := ShaderMaterial.new()
    material.shader = preload("res://shaders/showcase.gdshader")
    background.material = material
    add_child(background)
    theme = _make_theme()
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right"]:
        margin.add_theme_constant_override("margin_" + side, 28)
    for side in ["top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 18)
    add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    margin.add_child(column)
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 10)
    column.add_child(header)
    var brand := _label("RetroLife", 24, TEXT_COLOR)
    brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(brand)
    _search_button = _button("Search  /", _show_search)
    header.add_child(_search_button)
    _import_button = _button("+  Import ROM", _open_import_dialog)
    _import_button.name = "ImportButton"
    header.add_child(_import_button)
    header.add_child(_button("View", _show_settings))
    _warning_label = _label("", 13, DANGER_COLOR)
    _warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _warning_label.max_lines_visible = 2
    _warning_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _warning_label.hide()
    column.add_child(_warning_label)
    var filter_scroll := ScrollContainer.new()
    filter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    filter_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    filter_scroll.custom_minimum_size.y = 40
    column.add_child(filter_scroll)
    _filter_row = HBoxContainer.new()
    _filter_row.add_theme_constant_override("separation", 8)
    filter_scroll.add_child(_filter_row)
    _count_label = _label("YOUR COLLECTION", 12, MUTED_COLOR)
    _count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_count_label)
    _carousel = Carousel.new()
    _carousel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _carousel.selection_changed.connect(_on_cartridge_selected)
    _carousel.game_activated.connect(_open_details)
    column.add_child(_carousel)
    _carousel.set_presentation(_reduce_motion, _low_quality, _textual_view)
    _empty_label = _label("Import an .sfc or .smc file to start your collection.", 16, MUTED_COLOR)
    _empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_empty_label)
    _hero_title = _label("Your next adventure starts here", 30, TEXT_COLOR)
    _hero_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hero_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _hero_title.max_lines_visible = 2
    _hero_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_hero_title)
    _hero_meta = _label("A collection worth coming back to", 14, MUTED_COLOR)
    _hero_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_hero_meta)
    var bottom := HBoxContainer.new()
    bottom.add_theme_constant_override("separation", 12)
    column.add_child(bottom)
    bottom.add_child(_button("<", _navigate.bind(-1)))
    _hero_count = _label("", 13, MUTED_COLOR)
    _hero_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _hero_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hero_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    bottom.add_child(_hero_count)
    bottom.add_child(_button(">", _navigate.bind(1)))
    var hints := _label("Arrows / D-pad  Browse     A / Enter  Details     LB / RB  System     Y / /  Search     B / Esc  Back", 12, MUTED_COLOR)
    hints.name = "InputHints"
    hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(hints)
    _file_dialog = FileDialog.new()
    _file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    _file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _file_dialog.filters = PackedStringArray(["*.sfc ; Super Nintendo ROM", "*.smc ; Super Nintendo ROM"])
    _file_dialog.files_selected.connect(_on_files_selected)
    _file_dialog.canceled.connect(_restore_carousel_focus)
    add_child(_file_dialog)
    _search_timer = Timer.new()
    _search_timer.one_shot = true
    _search_timer.wait_time = 0.14
    _search_timer.timeout.connect(_refresh_library)
    add_child(_search_timer)
    _settings_timer = Timer.new()
    _settings_timer.one_shot = true
    _settings_timer.wait_time = 0.4
    _settings_timer.timeout.connect(_save_preferences)
    add_child(_settings_timer)
    _build_search()
    _build_settings()
    _build_details_overlay()
    resized.connect(_update_layout_density)
    _update_layout_density()


func _update_layout_density() -> void:
    if _carousel == null or _hero_title == null:
        return
    _carousel.custom_minimum_size.y = 180 if size.y < 660 else 220
    _hero_title.add_theme_font_size_override("font_size", 24 if size.x < 900 else 30)


func _build_search() -> void:
    _search_panel = PopupPanel.new()
    _search_panel.popup_hide.connect(_restore_carousel_focus)
    add_child(_search_panel)
    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 16)
    _search_panel.add_child(margin)
    _search_edit = LineEdit.new()
    _search_edit.name = "SearchEdit"
    _search_edit.custom_minimum_size = Vector2(480, 44)
    _search_edit.placeholder_text = "Search your collection"
    _search_edit.max_length = 64
    _search_edit.clear_button_enabled = true
    _search_edit.text_changed.connect(_on_search_changed)
    _search_edit.text_submitted.connect(func(_text: String): _search_panel.hide())
    _search_edit.gui_input.connect(func(event: InputEvent):
        if event.is_action_pressed("ui_cancel"):
            _search_panel.hide()
            _search_edit.accept_event()
    )
    margin.add_child(_search_edit)


func _build_settings() -> void:
    _settings_panel = PopupPanel.new()
    _settings_panel.popup_hide.connect(_restore_carousel_focus)
    add_child(_settings_panel)
    var column := VBoxContainer.new()
    column.custom_minimum_size.x = 340
    column.add_theme_constant_override("separation", 12)
    _settings_panel.add_child(column)
    column.add_child(_label("Library presentation", 20, TEXT_COLOR))
    var motion := CheckButton.new()
    motion.text = "Reduce motion"
    motion.button_pressed = _reduce_motion
    motion.toggled.connect(func(value: bool):
        _reduce_motion = value
        _apply_presentation()
    )
    column.add_child(motion)
    var quality := CheckButton.new()
    quality.text = "Low-power rendering"
    quality.button_pressed = _low_quality
    quality.toggled.connect(func(value: bool):
        _low_quality = value
        _apply_presentation()
    )
    column.add_child(quality)
    var text_view := CheckButton.new()
    text_view.text = "Text library instead of 3D"
    text_view.button_pressed = _textual_view
    text_view.toggled.connect(func(value: bool):
        _textual_view = value
        _apply_presentation()
    )
    column.add_child(text_view)
    var diagnostics := CheckButton.new()
    diagnostics.text = "Show diagnostics"
    diagnostics.toggled.connect(func(value: bool):
        _status_label.visible = value
        _source_label.visible = value
    )
    column.add_child(diagnostics)
    _status_label = _label("Connecting to Rust...", 12, MUTED_COLOR)
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label.hide()
    column.add_child(_status_label)
    _source_label = _label("Local library", 12, MUTED_COLOR)
    _source_label.hide()
    column.add_child(_source_label)
    var credit := _label("SNES model v0.1.0 by Lincoln Aleixo\nCC BY-NC-ND 4.0; separate from application code.\nGame artwork is not included.", 12, MUTED_COLOR)
    credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(credit)
    column.add_child(_button("Close", _settings_panel.hide))


func _build_details_overlay() -> void:
    _details_overlay = ColorRect.new()
    _details_overlay.name = "DetailsOverlay"
    _details_overlay.color = Color(0.025, 0.03, 0.047, 0.98)
    _details_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _details_overlay.hide()
    add_child(_details_overlay)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 32)
    _details_overlay.add_child(margin)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    margin.add_child(scroll)
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 16)
    scroll.add_child(column)
    _details_title = _label("", 32, TEXT_COLOR)
    _details_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_details_title)
    _details_system = _label("", 16, MUTED_COLOR)
    column.add_child(_details_system)
    column.add_child(HSeparator.new())
    var metadata := GridContainer.new()
    metadata.columns = 2
    metadata.add_theme_constant_override("h_separation", 24)
    metadata.add_theme_constant_override("v_separation", 10)
    column.add_child(metadata)
    _details_year_region = _details_row(metadata, "Year / region", "DetailsYearRegion")
    _details_creator = _details_row(metadata, "Developer / publisher", "DetailsCreator")
    _details_genres = _details_row(metadata, "Genres", "DetailsGenres")
    _details_players = _details_row(metadata, "Players", "DetailsPlayers")
    _details_aliases = _details_row(metadata, "Aliases", "DetailsAliases")
    _details_artwork = _label("", 12, MUTED_COLOR)
    _details_artwork.hide()
    column.add_child(_details_artwork)
    _details_description = _label("", 16, TEXT_COLOR)
    _details_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_details_description)
    _details_state = _label("", 14, MUTED_COLOR)
    column.add_child(_details_state)
    _details_play_button = _button("Play in RetroLife", _play_selected_game)
    _details_play_button.name = "PlayButton"
    _details_play_button.custom_minimum_size.y = 48
    column.add_child(_details_play_button)
    column.add_child(_button("Choose local cartridge label...", _choose_artwork))
    _details_back_button = _button("Back to collection", _close_details)
    column.add_child(_details_back_button)
    _art_dialog = FileDialog.new()
    _art_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _art_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _art_dialog.filters = PackedStringArray(["*.png ; Cartridge label (PNG, up to 2048 x 2048)"])
    _art_dialog.file_selected.connect(_on_artwork_selected)
    add_child(_art_dialog)


func _refresh_library(preferred_game_id := "", preserve_control_focus := false) -> void:
    if _catalog == null:
        return
    _refresh_generation += 1
    var generation := _refresh_generation
    var system := _selected_system_id
    var query := _search_query
    var desired := preferred_game_id
    if desired.is_empty():
        desired = str(_view_selections.get(_view_key(), _last_game_id))
    _refreshing = true
    var entries: Array = []
    var data: Dictionary = {}
    var revision: Variant = null
    var offset := 0
    while true:
        var response: Dictionary = _catalog.view(system, query, offset, PAGE_LIMIT)
        if not bool(response.get("ok", false)):
            _refreshing = false
            _show_nonfatal_error(str(response.get("error", "The collection could not be loaded.")))
            return
        data = response.get("data", {})
        if revision != null and data.get("revision") != revision:
            _refreshing = false
            _show_nonfatal_error("The library changed while loading. Search or select a system to refresh.")
            return
        revision = data.get("revision")
        var batch: Array = data.get("games", [])
        entries.append_array(batch)
        var has_more := bool(data.get("hasMore", entries.size() < int(data.get("filteredGames", entries.size()))))
        if not has_more:
            break
        if batch.is_empty():
            _refreshing = false
            _show_nonfatal_error("The library returned an empty page before all games were loaded.")
            return
        offset += batch.size()
        await get_tree().process_frame
        if generation != _refresh_generation or not is_inside_tree():
            return
    _refreshing = false
    _current_games = entries
    _systems = data.get("systems", [])
    _source_label.text = str(data.get("sourceLabel", "Local library"))
    _count_label.text = "%d GAME%s  /  YOUR COLLECTION" % [int(data.get("filteredGames", entries.size())), "" if entries.size() == 1 else "S"]
    if not query.is_empty():
        _count_label.text = "%d RESULT%s FOR \"%s\"" % [entries.size(), "" if entries.size() == 1 else "S", query]
    _search_button.text = "Search  /" if query.is_empty() else "Search: " + query.left(18)
    _rebuild_filters()
    _carousel.set_games(_current_games, desired)
    _empty_label.visible = _current_games.is_empty()
    _empty_label.text = "Import an .sfc or .smc file to start your collection." if query.is_empty() else "No games match this search. Press B or Esc to clear it."
    if not preserve_control_focus and not _search_panel.visible:
        _restore_carousel_focus()


func _rebuild_filters() -> void:
    super._rebuild_filters()
    for button in _filter_buttons:
        var id := str(button.get_meta("system_id", ""))
        button.custom_minimum_size = Vector2(80, 32)
        button.text = "All systems" if id.is_empty() else ("SNES" if id == "snes" else id.to_upper())


func _rebuild_cards() -> void:
    # Base-controller compatibility. The grid is never instantiated here.
    _carousel.set_games(_current_games, _last_game_id)


func _focus_game_deferred(game_id: String) -> void:
    _carousel.select_id(game_id)
    _restore_carousel_focus()


func _restore_carousel_focus() -> void:
    if _carousel != null and not _details_overlay.visible:
        _carousel.call_deferred("grab_focus")


func _on_cartridge_selected(game: Dictionary, index: int) -> void:
    _last_game_id = str(game.get("id", ""))
    _hero_title.text = str(game.get("title", "Your next adventure starts here"))
    _hero_meta.text = "A collection worth coming back to" if game.is_empty() else "%s  /  %s" % ["Super Nintendo" if str(game.get("systemId", "")) == "snes" else str(game.get("systemName", "")), "Ready to play" if bool(game.get("playable", false)) else "Not playable"]
    _hero_count.text = "%d / %d" % [index + 1, _current_games.size()] if index >= 0 else ""
    _remember_selection()
    if _settings_timer != null:
        _settings_timer.start()


func _remember_selection() -> void:
    if _last_game_id.is_empty():
        return
    var key := _view_key()
    _view_selections[key] = _last_game_id
    _view_order.erase(key)
    _view_order.append(key)
    while _view_order.size() > 32:
        _view_selections.erase(_view_order.pop_front())


func _view_key() -> String:
    return (_selected_system_id + "\n" + _search_query).sha256_text()


func _on_filter_pressed(system_id: String) -> void:
    _remember_selection()
    _selected_system_id = system_id
    _refresh_library()


func _cycle_system(direction: int) -> void:
    if _filter_buttons.is_empty():
        return
    var index := 0
    for candidate in range(_filter_buttons.size()):
        if str(_filter_buttons[candidate].get_meta("system_id", "")) == _selected_system_id:
            index = candidate
            break
    _on_filter_pressed(str(_filter_buttons[wrapi(index + direction, 0, _filter_buttons.size())].get_meta("system_id", "")))


func _on_search_changed(query: String) -> void:
    _remember_selection()
    _search_query = query
    _search_timer.start()


func _on_files_selected(paths: PackedStringArray) -> void:
    if _catalog == null or _importing:
        return
    _importing = true
    _import_button.disabled = true
    var failures: Array[String] = []
    var imported_id := ""
    for path in paths:
        var response: Dictionary = _catalog.import_file(path)
        if bool(response.get("ok", false)):
            imported_id = str((response.get("data", {}) as Dictionary).get("id", ""))
        else:
            failures.append(str(response.get("error", "Import failed.")))
        await get_tree().process_frame
    _importing = false
    _import_button.disabled = false
    _warning_label.text = "\n".join(failures)
    _warning_label.tooltip_text = _warning_label.text
    _warning_label.visible = not failures.is_empty()
    if not imported_id.is_empty():
        _remember_selection()
        _search_timer.stop()
        _search_query = ""
        _search_edit.text = ""
        _selected_system_id = ""
    _refresh_library(imported_id)


func _open_details(game_id: String) -> void:
    super._open_details(game_id)
    if _details_overlay.visible:
        _carousel.set_active(false)
        if not _details_play_button.disabled:
            _details_play_button.call_deferred("grab_focus")


func _choose_artwork() -> void:
    _artwork_game_id = _return_game_id
    _art_dialog.popup_centered_ratio(0.75)


func _on_artwork_selected(path: String) -> void:
    var error: String = _carousel.labels.import_artwork(_artwork_game_id, path)
    if not error.is_empty():
        _details_state.text = error
        return
    _carousel.refresh_artwork(_artwork_game_id)
    _details_state.text = "Local cartridge label saved."


func _navigate(direction: int) -> void:
    _carousel.navigate(direction)
    _restore_carousel_focus()


func _show_search() -> void:
    _search_panel.popup_centered(Vector2i(520, 80))
    _search_edit.grab_focus()
    _search_edit.select_all()


func _show_settings() -> void:
    _settings_panel.popup_centered()


func _apply_presentation() -> void:
    _carousel.set_presentation(_reduce_motion, _low_quality, _textual_view)
    _settings_timer.start()


func _save_preferences() -> void:
    if not persist_preferences:
        return
    _preferences.set_value("view", "reduced_motion", _reduce_motion)
    _preferences.set_value("view", "low_quality", _low_quality)
    _preferences.set_value("view", "textual_view", _textual_view)
    _preferences.set_value("selection", "system", _selected_system_id)
    _preferences.set_value("selection", "game", _last_game_id)
    var temporary := settings_path + ".tmp"
    if _preferences.save(temporary) == OK:
        var result := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(settings_path))
        if result != OK:
            _show_nonfatal_error("Library preferences could not be saved.")


func _game_is_active() -> bool:
    return _gameplay != null and _gameplay.has_method("active_session_id") and not str(_gameplay.call("active_session_id")).is_empty()


func _process(_delta: float) -> void:
    if _carousel != null:
        _carousel.set_active(not _game_is_active() and not _details_overlay.visible and not _search_panel.visible and not _settings_panel.visible and not _file_dialog.visible)


func _unhandled_input(event: InputEvent) -> void:
    if _game_is_active():
        return
    if _details_overlay.visible:
        super._unhandled_input(event)
        return
    if event.is_action_pressed("library_search"):
        _show_search()
    elif event.is_action_pressed("library_previous_system"):
        _cycle_system(-1)
    elif event.is_action_pressed("library_next_system"):
        _cycle_system(1)
    elif event.is_action_pressed("ui_cancel"):
        _remember_selection()
        _search_query = ""
        _search_edit.text = ""
        _search_timer.stop()
        _refresh_library()
    elif event.is_action_pressed("ui_left"):
        _navigate(-1)
    elif event.is_action_pressed("ui_right"):
        _navigate(1)
    else:
        return
    get_viewport().set_input_as_handled()


func _button(text: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.pressed.connect(callback)
    return button


func _make_theme() -> Theme:
    var result := Theme.new()
    result.default_font_size = 14
    for state in ["normal", "hover", "pressed", "focus", "disabled"]:
        var box := StyleBoxFlat.new()
        box.bg_color = Color("202332") if state == "normal" else Color("303449")
        if state == "focus":
            box.bg_color = Color.TRANSPARENT
        box.border_color = Color("b9a8e2") if state == "focus" else Color("404458")
        box.set_border_width_all(2 if state == "focus" else 1)
        box.set_corner_radius_all(10)
        box.content_margin_left = 14
        box.content_margin_right = 14
        box.content_margin_top = 9
        box.content_margin_bottom = 9
        result.set_stylebox(state, "Button", box)
    result.set_color("font_color", "Button", TEXT_COLOR)
    result.set_color("font_hover_color", "Button", TEXT_COLOR)
    result.set_color("font_focus_color", "Button", TEXT_COLOR)
    return result
