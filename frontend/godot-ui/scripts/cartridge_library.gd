extends "res://scripts/main.gd"

## Console-first presentation over the existing local library/gameplay contract.
const CollectionProfiles = preload("res://scripts/workspace/collection_profiles.gd")
var _console_home: VBoxContainer
var _game_sections: Array[Control] = []
var _at_console_home := true
var _box_button: Button
var _box_panel: PopupPanel
var _box_view: SubViewportContainer
var _box_title: Label
var _box_hint: Label
var _box_path := ""
const Carousel = preload("res://scripts/library/carousel.gd")
const UpdatePanel = preload("res://scripts/updates/update_panel.gd")
const WorkspacePreferences = preload("res://scripts/workspace/preferences.gd")
var _controller_panel: PopupPanel
var _storage_panel: PopupPanel
var _storage_summary: Button
var _console_preview: TextureRect
var _box_preview: TextureRect
var _workspace_play: Button
var _workspace_side: VBoxContainer
var _workspace_column: VBoxContainer
var _workspace_filters: ScrollContainer
var _workspace_navigation: HBoxContainer
var _workspace_hints: Label
var _controllers_button: Button
var _storage_button: Button
var _settings_button: Button
var _updates_panel: PopupPanel
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
var _fetch_collection_labels := true


func _ready() -> void:
    _load_preferences()
    if not WorkspacePreferences.read_value("collection_root").is_empty():
        _fetch_collection_labels = false
    super._ready()
    # Starting the optional signed updater is independent of library loading.
    _update_command("status")


func _load_preferences() -> void:
    if persist_preferences and _preferences.load(settings_path) == OK:
        _reduce_motion = bool(_preferences.get_value("view", "reduced_motion", false))
        _low_quality = bool(_preferences.get_value("view", "low_quality", false))
        _textual_view = bool(_preferences.get_value("view", "textual_view", false))
        _fetch_collection_labels = bool(_preferences.get_value("view", "fetch_collection_labels", true))
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
    _workspace_column = column
    column.add_theme_constant_override("separation", 6)
    margin.add_child(column)
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 10)
    column.add_child(header)
    var brand_icon := TextureRect.new()
    brand_icon.texture = preload("res://assets/brand/retrolife-icon.png")
    brand_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    brand_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    brand_icon.custom_minimum_size = Vector2(38, 38)
    header.add_child(brand_icon)
    var brand := _label("RetroLife", 24, TEXT_COLOR)
    brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(brand)
    _search_button = _button("Search  /", _show_search)
    header.add_child(_search_button)
    _import_button = _button("+  Import ROM", _open_import_dialog)
    _import_button.name = "ImportButton"
    header.add_child(_import_button)
    _controllers_button = _button("Controllers", _show_controllers)
    _storage_button = _button("Storage & assets", _show_storage)
    _settings_button = _button("Settings", _show_settings)
    header.add_child(_controllers_button)
    header.add_child(_storage_button)
    header.add_child(_settings_button)
    _warning_label = _label("", 13, DANGER_COLOR)
    _warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _warning_label.max_lines_visible = 2
    _warning_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _warning_label.hide()
    column.add_child(_warning_label)
    _console_home = preload("res://scripts/workspace/console_home.gd").new()
    _console_home.allow_local_art = persist_preferences
    _console_home.selected.connect(_open_console)
    column.add_child(_console_home)
    var filter_scroll := ScrollContainer.new()
    _workspace_filters = filter_scroll
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
    var showcase := HBoxContainer.new()
    showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
    showcase.add_theme_constant_override("separation", 20)
    column.add_child(showcase)
    _workspace_side = VBoxContainer.new()
    _workspace_side.custom_minimum_size.x = 230
    _workspace_side.alignment = BoxContainer.ALIGNMENT_CENTER
    _workspace_side.add_theme_constant_override("separation", 10)
    showcase.add_child(_workspace_side)
    _workspace_side.add_child(_label("THE SYSTEM", 12, MUTED_COLOR))
    _console_preview = _render_preview(_workspace_side, 150)
    _workspace_side.add_child(_label("Super Nintendo", 19, TEXT_COLOR))
    _workspace_side.add_child(_label("SNES · Ready for local play", 12, MUTED_COLOR))
    _box_preview = _render_preview(_workspace_side, 160)
    _workspace_side.add_child(_label("Your local 3D collection", 12, MUTED_COLOR))
    _carousel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    showcase.add_child(_carousel)
    _carousel.set_presentation(_reduce_motion, _low_quality, _textual_view)
    _carousel.set_label_fetching(_fetch_collection_labels)
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
    var quick_actions := HBoxContainer.new()
    quick_actions.alignment = BoxContainer.ALIGNMENT_CENTER
    quick_actions.add_theme_constant_override("separation", 12)
    column.add_child(quick_actions)
    quick_actions.add_child(_button("← Consoles", _show_console_home))
    _box_button = _button("Inspect box in 3D", _show_box)
    quick_actions.add_child(_box_button)
    _workspace_play = _button("Play game", _play_from_workspace)
    _workspace_play.custom_minimum_size = Vector2(220, 46)
    var play_style := StyleBoxFlat.new()
    play_style.bg_color = Color("287966")
    play_style.set_corner_radius_all(10)
    _workspace_play.add_theme_stylebox_override("normal", play_style)
    quick_actions.add_child(_workspace_play)
    quick_actions.add_child(_button("Game details", func():
        if not _last_game_id.is_empty():
            _open_details(_last_game_id)
    ))
    var bottom := HBoxContainer.new()
    _workspace_navigation = bottom
    bottom.add_theme_constant_override("separation", 12)
    column.add_child(bottom)
    bottom.add_child(_button("<", _navigate.bind(-1)))
    _hero_count = _label("", 13, MUTED_COLOR)
    _hero_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _hero_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hero_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    bottom.add_child(_hero_count)
    bottom.add_child(_button(">", _navigate.bind(1)))
    var hints := _label("Arrows / D-pad Browse  Drag Inspect  A / Enter Details  LB / RB System  Y / / Search  B / Esc Back", 12, MUTED_COLOR)
    hints.name = "InputHints"
    _workspace_hints = hints
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
    _controller_panel = preload("res://scripts/workspace/controller_panel.gd").new()
    add_child(_controller_panel)
    _storage_panel = preload("res://scripts/workspace/storage_panel.gd").new()
    _storage_panel.owner_ui = self
    _storage_panel.changed.connect(_refresh_workspace_assets)
    add_child(_storage_panel)
    _storage_summary = _button("", _show_storage)
    _storage_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _storage_summary.add_theme_font_size_override("font_size", 12)
    column.add_child(_storage_summary)
    _build_box_inspector()
    _game_sections = [filter_scroll, _count_label, showcase, _empty_label, _hero_title, _hero_meta, quick_actions, bottom, hints]
    _refresh_workspace_assets()
    _apply_library_page()
    resized.connect(_update_layout_density)
    _update_layout_density()


func _update_layout_density() -> void:
    if _carousel == null or _hero_title == null:
        return
    _workspace_side.hide()
    _carousel.custom_minimum_size.y = 180 if size.y < 660 else 220
    _hero_title.add_theme_font_size_override("font_size", 24 if size.x < 900 else 30)
    var compact := size.y < 660
    _workspace_column.add_theme_constant_override("separation", 3 if compact else 6)
    _workspace_filters.visible = not compact
    _workspace_navigation.visible = not compact
    _count_label.visible = not compact
    _hero_meta.visible = not compact
    _hero_title.max_lines_visible = 1 if compact else 2
    _warning_label.max_lines_visible = 1 if compact else 2
    _workspace_play.custom_minimum_size.y = 36 if compact else 46
    _workspace_hints.text = "← → Browse · Drag Rotate · Enter Details · Esc Back" if compact else "Arrows / D-pad Browse  Drag Inspect  A / Enter Details  LB / RB System  Y / / Search  B / Esc Back"
    for button in [_search_button, _import_button, _controllers_button, _storage_button, _settings_button]:
        button.add_theme_font_size_override("font_size", 12 if size.x < 1000 else 14)
    _storage_button.text = "Storage" if size.x < 1000 else "Storage & assets"
    _import_button.text = "+ Import" if size.x < 1000 else "+ Import ROM"


    _apply_library_page()


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
    var collection_labels := CheckButton.new()
    collection_labels.text = "Download approved labels"
    collection_labels.tooltip_text = "Fetch verified per-game labels from the public cartridge collection when a matching game is shown. Only the approved package URL is requested; your library is never uploaded."
    collection_labels.button_pressed = _fetch_collection_labels
    collection_labels.toggled.connect(func(value: bool):
        _fetch_collection_labels = value
        _apply_presentation()
        if value and not _carousel.selected_id().is_empty():
            _carousel.refresh_artwork(_carousel.selected_id())
    )
    column.add_child(collection_labels)
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
    var credit := _label("SNES model v0.1.0 by Lincoln Aleixo\nCC BY-NC-ND 4.0; separate from application code.\nApproved labels download on request; bundles stay art-free.", 12, MUTED_COLOR)
    credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(credit)
    column.add_child(HSeparator.new())
    column.add_child(_button("Software updates...", _show_updates))
    column.add_child(_button("Close", _settings_panel.hide))
    _updates_panel = UpdatePanel.new()
    _updates_panel.request = Callable(self, "_update_command")
    _updates_panel.popup_hide.connect(_restore_carousel_focus)
    add_child(_updates_panel)


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
    _console_home.configure(_systems)
    _carousel.set_games(_current_games, desired)
    _empty_label.visible = _current_games.is_empty()
    _empty_label.text = ("Import an .sfc or .smc file to start your SNES collection." if _selected_system_id in ["", "snes"] else "No games for this console yet. Local play currently supports Super Nintendo.") if query.is_empty() else "No games match this search. Press B or Esc to clear it."
    _apply_library_page()
    if not preserve_control_focus and not _search_panel.visible:
        _restore_carousel_focus()


func _rebuild_filters() -> void:
    super._rebuild_filters()
    for button in _filter_buttons:
        var id := str(button.get_meta("system_id", ""))
        button.custom_minimum_size = Vector2(80, 32)
        button.text = "← Consoles" if id.is_empty() else ("SNES" if id == "snes" else id.to_upper())


func _rebuild_cards() -> void:
    # Base-controller compatibility. The grid is never instantiated here.
    _carousel.set_games(_current_games, _last_game_id)


func _focus_game_deferred(game_id: String) -> void:
    _carousel.select_id(game_id)
    _restore_carousel_focus()


func _restore_carousel_focus() -> void:
    if _at_console_home:
        _console_home.call_deferred("focus_first")
    elif _carousel != null and not _details_overlay.visible:
        _carousel.call_deferred("grab_focus")


func _on_cartridge_selected(game: Dictionary, index: int) -> void:
    _last_game_id = str(game.get("id", ""))
    _hero_title.text = str(game.get("title", "Your next adventure starts here"))
    _hero_meta.text = "A collection worth coming back to" if game.is_empty() else "%s  /  %s" % ["Super Nintendo" if str(game.get("systemId", "")) == "snes" else str(game.get("systemName", "")), "Ready to play" if bool(game.get("playable", false)) else "Not playable"]
    _hero_count.text = "%d / %d" % [index + 1, _current_games.size()] if index >= 0 else ""
    if _workspace_play != null:
        _workspace_play.disabled = game.is_empty() or not bool(game.get("playable", false))
    if _box_preview != null:
        _box_preview.visible = str(game.get("title", "")).to_lower().contains("super mario world") and _box_preview.texture != null
    var profile := CollectionProfiles.for_game(str(game.get("title", "")), str(game.get("systemId", "")))
    _box_path = CollectionProfiles.box_path(profile) if persist_preferences else ""
    _box_button.disabled = _box_path.is_empty()
    _box_button.tooltip_text = "Link the matching local box model in Storage & assets." if _box_path.is_empty() else "Rotate, zoom and inspect the printed box."
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
    if system_id.is_empty():
        _show_console_home()
    else:
        _open_console(system_id)


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
        _selected_system_id = "snes"
        _at_console_home = false
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
    _carousel.set_label_fetching(_fetch_collection_labels)
    _settings_timer.start()


func _save_preferences() -> void:
    if not persist_preferences:
        return
    _preferences.set_value("view", "reduced_motion", _reduce_motion)
    _preferences.set_value("view", "low_quality", _low_quality)
    _preferences.set_value("view", "textual_view", _textual_view)
    _preferences.set_value("view", "fetch_collection_labels", _fetch_collection_labels)
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
        _carousel.set_active(not _at_console_home and not _box_panel.visible and not _game_is_active() and not _details_overlay.visible and not _search_panel.visible and not _settings_panel.visible and not _updates_panel.visible and not _file_dialog.visible and not _controller_panel.visible and not _storage_panel.visible)


func _unhandled_input(event: InputEvent) -> void:
    if _box_panel != null and _box_panel.visible:
        if event.is_action_pressed("ui_cancel"):
            _box_panel.hide()
            get_viewport().set_input_as_handled()
        return
    if _at_console_home:
        return
    if (_controller_panel != null and _controller_panel.visible) or (_storage_panel != null and _storage_panel.visible):
        return
    if _updates_panel != null and _updates_panel.visible:
        return
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
        if _search_query.is_empty():
            _show_console_home()
            get_viewport().set_input_as_handled()
            return
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


func _show_updates() -> void:
    if _game_is_active():
        return
    _settings_panel.hide()
    _updates_panel.call_deferred("open_panel")


func _update_command(command: String) -> Dictionary:
    if _backend == null or not _backend.has_method("update_command_json"):
        return {"schemaVersion": 1, "ok": true, "data": {
            "available": false, "message": "Updates are available in installed, signed macOS releases.",
            "currentVersion": str(ProjectSettings.get_setting("application/config/version", "development build")),
        }}
    var parsed: Variant = JSON.parse_string(str(_backend.call("update_command_json", command)))
    if not parsed is Dictionary or int(parsed.get("schemaVersion", 0)) != 1:
        return {"schemaVersion": 1, "ok": false, "error": "The updater returned an invalid response."}
    return parsed


func _render_preview(parent: Node, height: int) -> TextureRect:
    var image := TextureRect.new()
    image.custom_minimum_size = Vector2(230, height)
    image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    parent.add_child(image)
    return image

func _refresh_workspace_assets() -> void:
    if not persist_preferences:
        _storage_summary.text = "Test library · Isolated fixtures"
        return
    _console_preview.texture = WorkspacePreferences.image("consoles/snes/hero.png")
    _box_preview.texture = WorkspacePreferences.image("reproductions/snes/super-mario-world/box/hero.png")
    _console_preview.visible = _console_preview.texture != null
    _box_preview.visible = _box_preview.texture != null and _hero_title.text.to_lower().contains("super mario world")
    var path := WorkspacePreferences.library_root()
    _storage_summary.text = ("ROM storage · " if DirAccess.dir_exists_absolute(path) else "Storage offline · ") + path
    _storage_summary.tooltip_text = "New ROMs are stored here in console folders. Click to change or reconnect."
    if _catalog != null:
        _refresh_library()

func _show_controllers() -> void:
    var target := Vector2i(mini(980, int(size.x) - 40), mini(620, int(size.y) - 40))
    _controller_panel.popup_centered(target)
    # Wrapped text can report a transient tall minimum before first layout.
    await get_tree().process_frame
    await get_tree().process_frame
    if _controller_panel.visible:
        _controller_panel.popup_centered(target)

func _show_storage() -> void:
    var target := Vector2i(mini(680, int(size.x) - 40), mini(640, int(size.y) - 40))
    _storage_panel.popup_centered(target)
    await get_tree().process_frame
    await get_tree().process_frame
    if _storage_panel.visible:
        _storage_panel.popup_centered(target)

func _play_from_workspace() -> void:
    _return_game_id = _carousel.selected_id()
    _play_selected_game()


func _open_console(system_id: String) -> void:
    _remember_selection()
    _selected_system_id = system_id
    _search_query = ""
    _search_edit.text = ""
    _at_console_home = false
    _refresh_library()
    _apply_library_page()

func _show_console_home() -> void:
    _remember_selection()
    _at_console_home = true
    _search_query = ""
    _search_edit.text = ""
    _search_timer.stop()
    _console_home.configure(_systems)
    _apply_library_page()
    _console_home.focus_first()

func _apply_library_page() -> void:
    if _console_home == null:
        return
    _console_home.visible = _at_console_home
    for section in _game_sections:
        section.visible = not _at_console_home
    if not _at_console_home:
        _empty_label.visible = _current_games.is_empty()
        _hero_title.visible = not _current_games.is_empty()
        _workspace_navigation.visible = _current_games.size() > 1
        _workspace_filters.hide()
        _hero_meta.visible = size.y >= 660
        _count_label.visible = size.y >= 660
    _search_button.disabled = _at_console_home

func _build_box_inspector() -> void:
    _box_panel = PopupPanel.new()
    _box_panel.name = "BoxInspector"
    add_child(_box_panel)
    var style := StyleBoxFlat.new()
    style.bg_color = Color("111824")
    style.set_corner_radius_all(18)
    style.set_content_margin_all(20)
    _box_panel.add_theme_stylebox_override("panel", style)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 14)
    _box_panel.add_child(column)
    _box_title = _label("The box", 25, TEXT_COLOR)
    column.add_child(_box_title)
    _box_view = preload("res://scripts/workspace/model_view.gd").new()
    _box_view.auto_frame = true
    _box_view.custom_minimum_size = Vector2(320, 260)
    _box_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(_box_view)
    _box_hint = _label("Drag to rotate · Scroll to zoom", 14, MUTED_COLOR)
    column.add_child(_box_hint)
    var actions := HBoxContainer.new()
    actions.add_theme_constant_override("separation", 12)
    column.add_child(actions)
    actions.add_child(_button("Front", func(): _box_view.set_view(0.0, 0.0)))
    actions.add_child(_button("Back", func(): _box_view.set_view(0.0, PI)))
    actions.add_child(_button("Spine", func(): _box_view.set_view(0.0, PI / 2)))
    actions.add_child(_button("Reset view", _box_view.reset_view))
    actions.add_child(_button("Done", _box_panel.hide))
    _box_panel.popup_hide.connect(func():
        if _box_view.model != null:
            _box_view.model.free()
            _box_view.model = null
        _restore_carousel_focus()
    )

func _show_box() -> void:
    if _box_path.is_empty():
        return
    _box_title.text = _hero_title.text + " · The box"
    var target := Vector2i(mini(1040, int(size.x) - 40), mini(760, int(size.y) - 40))
    _box_panel.popup_centered(target)
    _box_view.load_model(_box_path)
    _box_hint.text = _box_view.message
    await get_tree().process_frame
    await get_tree().process_frame
    if _box_panel.visible:
        _box_panel.size = target
        _box_panel.position = (get_window().size - _box_panel.size) / 2
