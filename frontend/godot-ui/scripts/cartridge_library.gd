extends "res://scripts/main.gd"

## Console-first presentation over the existing local library/gameplay contract.
const CollectionProfiles = preload("res://scripts/workspace/collection_profiles.gd")
var _console_home: VBoxContainer
var _game_sections: Array[Control] = []
var _at_console_home := true
var _at_game_details := false
var _collection_footer: VBoxContainer
var _collection_title: Label
var _collection_position: Label
var _box_panel: PopupPanel
var _box_view: SubViewportContainer
var _box_title: Label
var _box_hint: Label
var _box_done: Button
var _box_path := ""
var _game_info: VBoxContainer
var _info_panel: PanelContainer
var _info_margin: MarginContainer
var _publisher_row: HBoxContainer
var _showcase_margin: MarginContainer
var _collection_hint: Label
var _preview_caption: Label
var _game_description: Label
var _game_facts: Label
var _game_source: Label
var _publisher_logo: TextureRect
var _publisher_plate: PanelContainer
var _music_percent: Label
var _game_backdrop: TextureRect
var _media_button: Button
var _media_group: VBoxContainer
var _media_hint: Label
var _external_preview_return: Button
var _external_preview_active := false
var _selection_launch_pending := false
var _music_controls: HBoxContainer
var _music_toggle: Button
var _music_slider: HSlider
var _selection_music: AudioStreamPlayer
var _selection_music_enabled := false
var _selection_music_volume := 0.35
var _selection_music_path := ""
var _selection_music_failed_path := ""
var _inline_preview: AspectRatioContainer
var _inline_video: VideoStreamPlayer
var _inline_still: TextureRect
var _inline_path := ""
var _preview_delay := 0.0
var _inline_checked_path := ""
var _inline_valid := false
var _video_panel: PopupPanel
var _video_player: VideoStreamPlayer
var _presentation: Dictionary = {}
var _presentation_key := ""
var _presentation_revision: Variant = null
var _presentation_cache: Dictionary = {}
var _rewards_panel: PopupPanel
var _media_settings: Window
const Carousel = preload("res://scripts/library/carousel.gd")
const UpdatePanel = preload("res://scripts/updates/update_panel.gd")
const WorkspacePreferences = preload("res://scripts/workspace/preferences.gd")
var _controller_panel: PopupPanel
var _storage_panel: PopupPanel
var _header: HBoxContainer
var _previous_game: Button
var _next_game: Button
var _workspace_column: VBoxContainer
var _workspace_filters: ScrollContainer
var _updates_panel: PopupPanel
var settings_path := "user://library-ui.cfg"

var persist_preferences := true
var _carousel: Control
var _hero_title: Label
var _hero_meta: Label
var _search_panel: PopupPanel
var _settings_panel: PopupPanel
var _software_updates_button: Button
var _art_dialog: FileDialog
var _artwork_game_id := ""
var _view_selections: Dictionary = {}
var _view_order: Array[String] = []
var _refresh_generation := 0
var _refreshing := false
var _folder_poll_seconds := 0.0
var _folder_watch_enabled := false
var _importing := false
var _search_timer: Timer
var _settings_timer: Timer
var _preferences := ConfigFile.new()
var _reduce_motion := false
var _low_quality := false
var _textual_view := false
var _fetch_collection_labels := true


func _ready() -> void:
    _folder_watch_enabled = persist_preferences
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
        _selection_music_enabled = bool(_preferences.get_value("media", "selection_music_enabled", false))
        _selection_music_volume = _valid_music_volume(_preferences.get_value("media", "selection_music_volume", 0.35))


func _build_shell() -> void:
    var background := ColorRect.new()
    background.name = "ShowcaseBackground"
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var material := ShaderMaterial.new()
    material.shader = preload("res://shaders/showcase.gdshader")
    background.material = material
    add_child(background)
    _game_backdrop = TextureRect.new()
    _game_backdrop.name = "GameBackdrop"
    _game_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _game_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _game_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    _game_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    _game_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var backdrop_material := ShaderMaterial.new()
    backdrop_material.shader = preload("res://shaders/game_backdrop.gdshader")
    _game_backdrop.material = backdrop_material
    _game_backdrop.hide()
    add_child(_game_backdrop)
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
    _header = preload("res://scripts/workspace/immersive_header.gd").new()
    _header.action_requested.connect(_on_header_action)
    _header.drag_requested.connect(_drag_window)
    column.add_child(_header)
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
    _carousel.allow_local_art = persist_preferences
    _carousel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _carousel.selection_changed.connect(_on_cartridge_selected)
    _carousel.game_activated.connect(_activate_game_art)
    _carousel.box_activated.connect(_activate_box_art)
    var showcase := HBoxContainer.new()
    showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
    showcase.name = "GameShowcase"
    showcase.add_theme_constant_override("separation", 24)
    _showcase_margin = MarginContainer.new()
    _showcase_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(_showcase_margin)
    _showcase_margin.add_child(showcase)
    _info_panel = PanelContainer.new()
    _info_panel.name = "GameDossier"
    _info_panel.custom_minimum_size.x = 420
    _info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # Keep a single illustrated canvas, without a full-height opaque sidebar.
    _info_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
    showcase.add_child(_info_panel)
    _info_margin = MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        _info_margin.add_theme_constant_override("margin_" + side, 28)
    _info_panel.add_child(_info_margin)
    _game_info = VBoxContainer.new()
    _game_info.name = "GameInformation"
    _game_info.alignment = BoxContainer.ALIGNMENT_CENTER
    _game_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _game_info.add_theme_constant_override("separation", 20)
    _info_margin.add_child(_game_info)
    _carousel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _carousel.size_flags_stretch_ratio = 1.15
    showcase.add_child(_carousel)
    _previous_game = _button("‹", _navigate.bind(-1))
    _next_game = _button("›", _navigate.bind(1))
    for arrow in [_previous_game, _next_game]:
        arrow.custom_minimum_size = Vector2(44, 64)
        arrow.add_theme_font_size_override("font_size", 32)
        _carousel.add_child(arrow)
    _previous_game.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
    _previous_game.position.y -= 32
    _next_game.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
    _next_game.position += Vector2(-44, -32)
    _previous_game.tooltip_text = "Previous game"
    _next_game.tooltip_text = "Next game"
    _carousel.set_presentation(_reduce_motion, _low_quality, _textual_view)
    _carousel.set_label_fetching(_fetch_collection_labels)
    _empty_label = _label("Import an .sfc or .smc file to start your collection.", 16, MUTED_COLOR)
    _empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_empty_label)
    column.move_child(_count_label, column.get_child_count() - 1)
    _collection_footer = VBoxContainer.new()
    _collection_footer.add_theme_constant_override("separation", 8)
    column.add_child(_collection_footer)
    column.move_child(_collection_footer, column.get_child_count() - 2)
    _collection_title = _label("", 32, TEXT_COLOR)
    _collection_title.add_theme_font_override("font", preload("res://scripts/workspace/presentation_theme.gd").heading_font())
    _collection_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _collection_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _collection_footer.add_child(_collection_title)
    _collection_position = _label("", 13, MUTED_COLOR)
    _collection_position.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _collection_footer.add_child(_collection_position)
    _hero_title = _label("Your next adventure starts here", 30, TEXT_COLOR)
    _hero_title.add_theme_font_override("font", preload("res://scripts/workspace/presentation_theme.gd").heading_font())
    _hero_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _hero_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _hero_title.max_lines_visible = 2
    _hero_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _game_info.add_child(_hero_title)
    _hero_meta = _label("A collection worth coming back to", 14, MUTED_COLOR)
    _hero_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _hero_meta.add_theme_color_override("font_color", Color("a7e7ce"))
    _publisher_row = HBoxContainer.new()
    _publisher_row.alignment = BoxContainer.ALIGNMENT_BEGIN
    _publisher_row.add_theme_constant_override("separation", 18)
    _game_info.add_child(_publisher_row)
    _game_info.move_child(_publisher_row, 0)
    _hero_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _hero_meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _publisher_row.add_child(_hero_meta)
    var accent := ColorRect.new()
    accent.color = Color("9ce1c1")
    accent.custom_minimum_size = Vector2(42, 3)
    accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _game_info.add_child(accent)
    _game_info.move_child(accent, 1)
    _game_facts = _label("", 16, Color("cbd8dc"))
    _game_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _game_info.add_child(_game_facts)
    _game_description = _label("", 19, Color("c5d1d8"))
    _game_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _game_description.max_lines_visible = 5
    _game_description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _game_info.add_child(_game_description)
    _inline_preview = AspectRatioContainer.new()
    _inline_preview.name = "SelectionPreview"
    _inline_preview.ratio = 4.0 / 3.0
    _inline_preview.custom_minimum_size.y = 170
    _inline_preview.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    _game_info.add_child(_inline_preview)
    _inline_still = TextureRect.new()
    _inline_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _inline_still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _inline_still.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _inline_preview.add_child(_inline_still)
    _inline_video = VideoStreamPlayer.new()
    _inline_video.expand = true
    _inline_video.volume_db = -80.0
    _inline_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _inline_video.finished.connect(func():
        if not _inline_path.is_empty() and _inline_preview.visible: _inline_video.play())
    _inline_preview.add_child(_inline_video)
    _inline_preview.hide()
    _media_group = VBoxContainer.new()
    _media_group.add_theme_constant_override("separation", 6)
    _game_info.add_child(_media_group)
    _media_button = _button("", _show_game_video)
    _media_button.name = "WatchPreview"
    _media_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    _media_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
    var preview_hover := StyleBoxFlat.new()
    preview_hover.bg_color = Color(0.02, 0.05, 0.07, 0.12)
    preview_hover.border_color = Color("9ce1c1")
    preview_hover.set_border_width_all(2)
    _media_button.add_theme_stylebox_override("hover", preview_hover)
    _media_button.add_theme_stylebox_override("focus", preview_hover)
    _media_button.accessibility_name = "Preview selected game video"
    _inline_preview.add_child(_media_button)
    _preview_caption = _label("↗  WATCH PREVIEW", 11, Color("e6f0ee"))
    _preview_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _preview_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
    _preview_caption.position = Vector2(-170, -28)
    _preview_caption.size = Vector2(170, 28)
    _preview_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var caption_style := StyleBoxFlat.new()
    caption_style.bg_color = Color(0.02, 0.04, 0.06, 0.86)
    caption_style.set_content_margin_all(6)
    _preview_caption.add_theme_stylebox_override("normal", caption_style)
    _media_button.add_child(_preview_caption)
    _external_preview_return = _button("Return to browsing", _return_from_external_preview)
    _external_preview_return.icon = preload("res://scripts/workspace/ui_icons.gd").icon("back")
    _external_preview_return.hide()
    _media_group.add_child(_external_preview_return)
    _media_hint = _label("", 12, MUTED_COLOR)
    _media_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _media_hint.hide()
    _media_group.add_child(_media_hint)
    _media_group.hide()
    _music_controls = HBoxContainer.new()
    _music_controls.add_theme_constant_override("separation", 16)
    _game_info.add_child(_music_controls)
    _music_toggle = _button("Game music", func(): _set_selection_music_enabled(_music_toggle.button_pressed))
    _music_toggle.toggle_mode = true
    _music_toggle.flat = false
    _music_toggle.custom_minimum_size = Vector2(138, 38)
    for state in ["normal", "hover", "pressed", "focus"]:
        var music_style := StyleBoxFlat.new()
        music_style.bg_color = Color(0.30, 0.65, 0.53, 0.20 if state == "pressed" else 0.09)
        music_style.border_color = Color(0.61, 0.88, 0.76, 0.65 if state == "focus" else 0.20)
        music_style.set_border_width_all(1)
        music_style.set_corner_radius_all(19)
        music_style.content_margin_left = 14
        music_style.content_margin_right = 14
        _music_toggle.add_theme_stylebox_override(state, music_style)
    _music_toggle.add_theme_font_size_override("font_size", 12)
    _music_toggle.icon = preload("res://scripts/workspace/ui_icons.gd").icon("play", Color("a7e7ce"), 16)
    _music_toggle.tooltip_text = "Play this game's local music while browsing. Music stops during gameplay and video previews."
    _music_controls.add_child(_music_toggle)
    _music_slider = HSlider.new()
    _music_slider.min_value = 0
    _music_slider.max_value = 100
    _music_slider.step = 1
    _music_slider.value = _selection_music_volume * 100.0
    _music_slider.custom_minimum_size.x = 64
    _music_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _music_slider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    _music_slider.accessibility_name = "Game selection music volume"
    _music_slider.value_changed.connect(func(value: float): _set_selection_music_volume(value / 100.0))
    _music_controls.add_child(_music_slider)
    for state in ["slider", "grabber_area", "grabber_area_highlight"]:
        var track := StyleBoxFlat.new()
        track.bg_color = Color("9ce1c1") if state != "slider" else Color(0.6, 0.8, 0.75, 0.18)
        track.content_margin_top = 2
        track.content_margin_bottom = 2
        track.set_corner_radius_all(2)
        _music_slider.add_theme_stylebox_override(state, track)
    _music_percent = _label("", 11, Color("b5ceca"))
    _music_percent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _music_controls.add_child(_music_percent)
    _music_controls.hide()
    _game_source = _label("", 11, MUTED_COLOR)
    _game_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _game_info.add_child(_game_source)
    _publisher_logo = TextureRect.new()
    _publisher_logo.custom_minimum_size = Vector2(136, 34)
    _publisher_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    _publisher_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    _publisher_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _publisher_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _publisher_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _publisher_logo.hide()
    _publisher_plate = PanelContainer.new()
    _publisher_plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _publisher_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var publisher_style := StyleBoxFlat.new()
    publisher_style.bg_color = Color("f4f2ed")
    publisher_style.set_corner_radius_all(5)
    publisher_style.content_margin_left = 12
    publisher_style.content_margin_right = 12
    publisher_style.content_margin_top = 8
    publisher_style.content_margin_bottom = 8
    _publisher_plate.add_theme_stylebox_override("panel", publisher_style)
    _publisher_plate.add_child(_publisher_logo)
    _publisher_plate.hide()
    _publisher_row.add_child(_publisher_plate)
    _publisher_row.move_child(_publisher_plate, 0)
    _file_dialog = FileDialog.new()
    _file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    _file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _file_dialog.filters = PackedStringArray(["*.sfc ; Super Nintendo ROM", "*.smc ; Super Nintendo ROM", "*.zip ; Single-game ZIP archive"])
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
    _build_box_inspector()
    _build_game_video()
    _selection_music = AudioStreamPlayer.new()
    _selection_music.name = "SelectionMusic"
    _selection_music.volume_linear = _selection_music_volume
    add_child(_selection_music)
    _rewards_panel = preload("res://scripts/workspace/rewards_center.gd").new()
    _rewards_panel.popup_hide.connect(_restore_carousel_focus)
    add_child(_rewards_panel)
    _media_settings = preload("res://scripts/workspace/media_settings_panel.gd").new()
    _media_settings.presentation_changed.connect(_refresh_game_presentation)
    _media_settings.popup_hide.connect(_restore_carousel_focus)
    add_child(_media_settings)
    _collection_hint = _label("Click the artwork to play  ·  Drag to explore", 13, Color("b5c9c5"))
    _collection_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _collection_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _collection_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    _collection_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
    _collection_hint.offset_left = -250
    _collection_hint.offset_right = 250
    _collection_hint.offset_top = -42
    _collection_hint.offset_bottom = -18
    _carousel.add_child(_collection_hint)
    _game_sections = [filter_scroll, _count_label, _showcase_margin, _empty_label, _collection_footer]
    _refresh_workspace_assets()
    _apply_library_page()
    resized.connect(_update_layout_density)
    _update_layout_density()


func _update_layout_density() -> void:
    if _carousel == null or _hero_title == null:
        return
    _carousel.custom_minimum_size.y = 180 if size.y < 660 else 220
    var compact := size.y < 780 or size.x < 1150
    var wide := size.x >= 1800
    var sidebar_width := clampf(size.x * 0.32, 310, 620)
    _info_panel.custom_minimum_size.x = sidebar_width
    var outer_margin := int(clampf(size.x * 0.025, 8, 56))
    _showcase_margin.add_theme_constant_override("margin_left", outer_margin)
    _showcase_margin.add_theme_constant_override("margin_right", outer_margin)
    for side in ["left", "right"]:
        _info_margin.add_theme_constant_override("margin_" + side, 0)
    for side in ["top", "bottom"]:
        _info_margin.add_theme_constant_override("margin_" + side, 16 if compact else 36)
    _hero_title.add_theme_font_size_override("font_size", 30 if compact else (52 if wide else 40))
    _collection_title.add_theme_font_size_override("font_size", 26 if compact else 34)
    _hero_meta.add_theme_font_size_override("font_size", 13 if wide else 11)
    _game_facts.add_theme_font_size_override("font_size", 13 if compact else (17 if wide else 14))
    _game_description.add_theme_font_size_override("font_size", 15 if compact else (20 if wide else 17))
    _game_info.add_theme_constant_override("separation", 14 if compact else (24 if wide else 18))
    _game_description.max_lines_visible = 3
    _game_description.visible = not compact and not _game_description.text.is_empty()
    _publisher_logo.custom_minimum_size = Vector2(140, 35) if compact else Vector2(156, 39)
    if is_instance_valid(_inline_preview):
        var preview_width := minf(sidebar_width, minf(420.0, size.y * (0.36 if compact else 0.40)))
        _inline_preview.custom_minimum_size = Vector2(preview_width, preview_width * 0.75)
    if is_instance_valid(_collection_hint):
        _collection_hint.visible = not _textual_view and not _current_games.is_empty()
    _workspace_column.add_theme_constant_override("separation", 6 if compact else 12)
    _hero_title.max_lines_visible = 2
    _warning_label.max_lines_visible = 1 if compact else 2
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
    _software_updates_button = _button("Software updates...", _show_updates)
    _software_updates_button.tooltip_text = "Check for updates after returning to the library."
    column.add_child(_software_updates_button)
    _settings_panel.about_to_popup.connect(_update_settings_context)
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
    _warning_label.text = ""
    if _presentation_revision != revision:
        _presentation_cache.clear()
        _presentation_key = ""
        _presentation_revision = revision
    _current_games = entries
    _systems = data.get("systems", [])
    _source_label.text = str(data.get("sourceLabel", "Local library"))
    _count_label.text = "%d GAME%s  /  YOUR COLLECTION" % [int(data.get("filteredGames", entries.size())), "" if entries.size() == 1 else "S"]
    if not query.is_empty():
        _count_label.text = "%d RESULT%s FOR \"%s\"" % [entries.size(), "" if entries.size() == 1 else "S", query]
    _header.set_search_query(query)
    _rebuild_filters()
    _console_home.configure(_systems)
    _carousel.set_games(_current_games, desired)
    _empty_label.visible = _current_games.is_empty()
    _empty_label.text = ("Add .sfc, .smc or single-game .zip files to your SNES folder." if _selected_system_id in ["", "snes"] else "No games for this console yet. Local play currently supports Super Nintendo.") if query.is_empty() else "No games match this search. Press B or Esc to clear it."
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
    if _game_is_active():
        return
    _restore_carousel_focus_if_idle.call_deferred()


func _restore_carousel_focus_if_idle() -> void:
    # A dialog can close immediately before a game starts. Recheck at the
    # deferred boundary so library focus cannot escape into a live session.
    if _game_is_active() or not is_inside_tree() or _box_panel.visible:
        return
    if _at_console_home:
        _console_home.focus_first()
    elif _carousel != null and not _details_overlay.visible:
        _carousel.grab_focus()


func _on_cartridge_selected(game: Dictionary, index: int) -> void:
    _last_game_id = str(game.get("id", ""))
    var profile := CollectionProfiles.for_game(str(game.get("title", "")), str(game.get("systemId", "")))
    _hero_title.text = str(profile.get("title", game.get("title", "Your next adventure starts here")))
    _hero_meta.text = "" if game.is_empty() else ("Super Nintendo" if str(game.get("systemId", "")) == "snes" else str(game.get("systemName", ""))).to_upper()
    _collection_title.text = _hero_title.text if not game.is_empty() else ""
    _collection_position.text = "%02d / %02d  ·  %s" % [index + 1, _current_games.size(), _hero_meta.text] if not game.is_empty() else ""
    _box_path = CollectionProfiles.box_path(profile) if persist_preferences else ""
    _previous_game.visible = not _at_game_details and _current_games.size() > 1
    _next_game.visible = not _at_game_details and _current_games.size() > 1
    _previous_game.disabled = index <= 0
    _next_game.disabled = index >= _current_games.size() - 1
    _configure_page_header()
    _update_game_presentation(game, profile)
    _update_collection_hint()
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
    _header.set_busy(true)
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
    _header.set_busy(false)
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
        _at_game_details = false
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
    _update_settings_context()
    _settings_panel.popup_centered()


func _update_settings_context() -> void:
    if is_instance_valid(_software_updates_button):
        _software_updates_button.visible = not _game_is_active()


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
    _preferences.set_value("media", "selection_music_enabled", _selection_music_enabled)
    _preferences.set_value("media", "selection_music_volume", _selection_music_volume)
    var temporary := settings_path + ".tmp"
    var result := _preferences.save(temporary)
    if result == OK:
        result = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(settings_path))
    if result != OK:
        _show_nonfatal_error("Library preferences could not be saved.")


func _game_is_active() -> bool:
    return _gameplay != null and _gameplay.has_method("active_session_id") and not str(_gameplay.call("active_session_id")).is_empty()


func _process(_delta: float) -> void:
    _poll_rom_folder(_delta)
    _sync_inline_preview(_delta)
    _update_settings_context()
    _sync_selection_music()
    if _carousel != null:
        _carousel.set_active(not _importing and not _at_console_home and not _header.is_menu_open() and not _box_panel.visible and not _game_is_active() and not _details_overlay.visible and not _search_panel.visible and not _settings_panel.visible and not _updates_panel.visible and not _file_dialog.visible and not _controller_panel.visible and not _storage_panel.visible and not _rewards_panel.visible and not _media_settings.visible and not _video_panel.visible)


func _poll_rom_folder(delta: float) -> void:
    if not _folder_watch_enabled or _backend == null or not _backend.has_method("poll_library_changes_json"):
        return
    if _game_is_active() or _importing or _refreshing or _storage_panel.visible or _file_dialog.visible:
        return
    _folder_poll_seconds += delta
    if _folder_poll_seconds < 2.0:
        return
    _folder_poll_seconds = 0.0
    var raw: String = str(_backend.call("poll_library_changes_json"))
    if raw.is_empty():
        return
    var response: Variant = JSON.parse_string(raw)
    if not response is Dictionary or not bool(response.get("ok", false)):
        return # Keep the current collection while a drive is unavailable.
    var revision: Variant = response.get("data", {}).get("revision")
    if revision != _presentation_revision:
        _remember_selection()
        _refresh_library(_last_game_id, true)


func _unhandled_input(event: InputEvent) -> void:
    if _game_is_active():
        return # Gameplay owns shortcuts too; never toggle fullscreen twice.
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
        _on_header_action("fullscreen")
        get_viewport().set_input_as_handled()
        return
    if _header.is_menu_open():
        return
    if _box_panel != null and _box_panel.visible:
        if event.is_action_pressed("ui_cancel"):
            _box_panel.hide()
            get_viewport().set_input_as_handled()
        return
    if (_controller_panel != null and _controller_panel.visible) or (_storage_panel != null and _storage_panel.visible):
        return
    if _rewards_panel.visible or _media_settings.visible or _video_panel.visible:
        return
    if _updates_panel != null and _updates_panel.visible:
        return
    if _game_is_active():
        return
    if _settings_panel.visible or _file_dialog.visible or _art_dialog.visible or _search_panel.visible:
        return
    if _at_console_home:
        _console_home.handle_navigation(event)
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
        if _at_game_details:
            _return_to_collection()
            get_viewport().set_input_as_handled()
            return
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
    return preload("res://scripts/workspace/presentation_theme.gd").make_theme()


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


func _refresh_workspace_assets() -> void:
    _presentation_cache.clear()
    _presentation_key = ""
    if persist_preferences and _catalog != null:
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

func _activate_game_art(game_id: String) -> void:
    if _importing or _at_console_home or _game_is_active() or game_id.is_empty():
        return
    if not _at_game_details:
        _open_game_presentation(game_id)
        return
    var selected: Dictionary = {}
    for game in _current_games:
        if str(game.get("id", "")) == game_id:
            selected = game
            break
    if selected.is_empty():
        return
    if not bool(selected.get("playable", false)):
        _open_details(game_id)
        return
    _return_game_id = game_id
    _play_selected_game()


func _open_game_presentation(game_id: String) -> void:
    if _at_console_home or _game_is_active() or game_id.is_empty():
        return
    if not _current_games.any(func(game: Dictionary) -> bool: return str(game.get("id", "")) == game_id):
        return
    _carousel.select_id(game_id)
    _at_game_details = true
    _apply_library_page()
    _restore_carousel_focus()


func _return_to_collection() -> void:
    _stop_inline_preview()
    _stop_selection_music()
    _external_preview_active = false
    if _video_panel.visible:
        _video_panel.hide()
    if _box_panel.visible:
        _box_panel.hide()
    _at_game_details = false
    _apply_library_page()
    _restore_carousel_focus()


func _activate_box_art(game_id: String) -> void:
    if _at_game_details and game_id == _last_game_id and not _game_is_active():
        _show_box()

func _on_header_action(action: String) -> void:
    match action:
        "back":
            if _at_game_details: _return_to_collection()
            else: _show_console_home()
        "box": _show_box()
        "details":
            if not _last_game_id.is_empty(): _open_details(_last_game_id)
        "search": _show_search()
        "import":
            if not _importing: _open_import_dialog()
        "controllers": _show_controllers()
        "storage": _show_storage()
        "rewards": _show_rewards()
        "media": _show_media_settings()
        "settings": _show_settings()
        "fullscreen":
            var full := get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
            get_window().mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN
        "minimize": get_window().mode = Window.MODE_MINIMIZED
        "quit": _close_safely()

func _drag_window() -> void:
    if get_window().mode != Window.MODE_WINDOWED:
        return
    if DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_DRAG):
        DisplayServer.window_start_drag()


func _open_console(system_id: String) -> void:
    _remember_selection()
    _selected_system_id = system_id
    _search_query = ""
    _search_edit.text = ""
    _at_console_home = false
    _at_game_details = false
    _carousel.set_collection_overview(true)
    _refresh_library()
    _apply_library_page()

func _show_console_home() -> void:
    _stop_selection_music()
    _external_preview_active = false
    if is_instance_valid(_video_panel):
        _video_panel.hide()
    _remember_selection()
    _at_console_home = true
    _at_game_details = false
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
    _carousel.set_collection_overview(not _at_game_details)
    if _game_backdrop != null:
        _game_backdrop.visible = not _at_console_home and not _current_games.is_empty() and _game_backdrop.texture != null
    for section in _game_sections:
        section.visible = not _at_console_home
    _info_panel.visible = _at_game_details and not _current_games.is_empty()
    _collection_footer.visible = not _at_console_home and not _at_game_details and not _current_games.is_empty()
    _previous_game.visible = not _at_game_details and _current_games.size() > 1
    _next_game.visible = not _at_game_details and _current_games.size() > 1
    if not _at_console_home:
        _empty_label.visible = _current_games.is_empty()
        _hero_title.visible = not _current_games.is_empty()
        _workspace_filters.hide()
        _hero_meta.visible = true
        _count_label.visible = _at_game_details and size.y >= 660
    _configure_page_header()
    _update_collection_hint()
    _update_selection_media_controls()
    _sync_selection_music()


func _configure_page_header() -> void:
    _header.configure_page(_at_console_home, _at_game_details and not _current_games.is_empty(), _at_game_details and not _box_path.is_empty())
    _header.set_back_destination("collection" if _at_game_details else "consoles")


func _update_collection_hint() -> void:
    if not is_instance_valid(_collection_hint):
        return
    _collection_hint.visible = not _textual_view and not _current_games.is_empty()
    if not _at_game_details:
        _collection_hint.text = "Choose a cartridge  ·  ← → Browse" if _current_games.size() > 1 else "Choose the cartridge to explore this game"
    else:
        _collection_hint.text = "Cartridge: play  ·  Box: inspect  ·  Drag either to rotate" if not _box_path.is_empty() else "Click the cartridge to play  ·  Drag to explore"

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
    _box_done = _button("Done", _box_panel.hide)
    actions.add_child(_box_done)
    _box_panel.popup_hide.connect(func():
        if _box_view.model != null:
            _box_view.model.free()
            _box_view.model = null
        _restore_carousel_focus()
    )

func _show_box() -> void:
    if _box_path.is_empty():
        return
    _carousel.set_active(false)
    _box_title.text = _hero_title.text + " · The box"
    var target := Vector2i(mini(1040, int(size.x) - 40), mini(760, int(size.y) - 40))
    _box_panel.popup_centered(target)
    _box_done.call_deferred("grab_focus")
    _box_view.load_model(_box_path)
    _box_hint.text = _box_view.message
    await get_tree().process_frame
    await get_tree().process_frame
    if _box_panel.visible:
        _box_panel.size = target
        _box_panel.position = (get_window().size - _box_panel.size) / 2


func _presentation_identity() -> Dictionary:
    for game in _current_games:
        if str(game.get("id", "")) == _last_game_id:
            var profile := CollectionProfiles.for_game(str(game.get("title", "")), str(game.get("systemId", "")))
            return {"system": str(game.get("systemId", "")), "slug": str(profile.get("slug", _last_game_id)), "title": str(profile.get("title", game.get("title", "")))}
    return {}


func _update_game_presentation(game: Dictionary, profile: Dictionary) -> void:
    var key := str(game.get("id", ""))
    if key == _presentation_key:
        return
    _stop_selection_music()
    _stop_inline_preview()
    _preview_delay = 0.0
    _inline_checked_path = ""
    _inline_still.texture = null
    _presentation_key = key
    _presentation = {}
    _game_backdrop.texture = null
    _game_backdrop.hide()
    _game_facts.text = ""
    _game_description.text = ""
    _game_source.text = ""
    _publisher_logo.texture = null
    _publisher_logo.hide()
    _publisher_plate.hide()
    _media_group.hide()
    _music_controls.hide()
    if key.is_empty():
        _update_selection_media_controls()
        return
    if _presentation_cache.has(key):
        _presentation = _presentation_cache[key]
    else:
        var fields := game.duplicate(true)
        if _catalog != null:
            var response: Dictionary = _catalog.details(key)
            if bool(response.get("ok", false)):
                fields.merge(response.get("data", {}), true)
        var media: Dictionary = {}
        if persist_preferences:
            media = preload("res://scripts/workspace/game_presentation.gd").load_for_game(str(game.get("systemId", "")), str(profile.get("slug", key)))
        fields.merge(media, true)
        _presentation = fields
        if _presentation_cache.size() >= 16:
            _presentation_cache.erase(_presentation_cache.keys()[0])
        _presentation_cache[key] = fields
    var facts: Array[String] = []
    var year := str(_presentation.get("year", _presentation.get("releaseYear", "")))
    if year not in ["", "<null>", "0"]: facts.append(year)
    var genre: Variant = _presentation.get("genre", _presentation.get("genres", []))
    if genre is Array:
        if not genre.is_empty(): facts.append(" / ".join(genre))
    elif str(genre) not in ["", "<null>"]:
        facts.append("Platformer" if str(genre) == "Platform / Run & Jump, Platform" else str(genre))
    var players := str(_presentation.get("players", ""))
    if players not in ["", "<null>"]:
        facts.append(players + (" players" if players != "1" else " player") if players.is_valid_int() else players.replace("-", "–") + " players")
    _game_facts.text = "  ·  ".join(facts)
    _game_description.text = _selection_summary(str(_presentation.get("description", "")))
    if _game_description.text == "<null>": _game_description.text = ""
    _game_description.visible = size.y >= 780 and size.x >= 1150 and not _game_description.text.is_empty()
    var maker := str(_presentation.get("developer", ""))
    _game_source.text = maker if maker not in ["", "<null>"] else ""
    _publisher_logo.texture = null
    var logo_path := str(_presentation.get("publisher_logo_path", ""))
    if not logo_path.is_empty():
        var logo_image := Image.load_from_file(logo_path)
        if logo_image != null and not logo_image.is_empty() and logo_image.get_width() <= 2048 and logo_image.get_height() <= 2048:
            logo_image.generate_mipmaps()
            _publisher_logo.texture = ImageTexture.create_from_image(logo_image)
    _publisher_logo.visible = _publisher_logo.texture != null
    _publisher_plate.visible = _publisher_logo.visible
    _publisher_logo.tooltip_text = str(_presentation.get("publisher", maker))
    _game_source.visible = not _publisher_logo.visible and not _game_source.text.is_empty()
    var background := str(_presentation.get("background_path", ""))
    if background.is_empty() and persist_preferences and not profile.is_empty():
        background = WorkspacePreferences.asset(CollectionProfiles.asset_base(profile) + "/journey/cover.png")
    if not background.is_empty():
        var file := FileAccess.open(background, FileAccess.READ)
        if file != null and file.get_length() <= 24 * 1024 * 1024:
            var art := Image.load_from_file(background)
            if art != null and not art.is_empty() and art.get_width() <= 8192 and art.get_height() <= 8192:
                art.generate_mipmaps()
                _game_backdrop.texture = ImageTexture.create_from_image(art)
                _inline_still.texture = _game_backdrop.texture
                _game_backdrop.visible = not _at_console_home
    _update_selection_media_controls()
    _sync_selection_music()


func _selection_summary(description: String) -> String:
    # Keep the selection concise; the full scraped description stays in Details.
    for separator in [". ", "! ", "? "]:
        var end := description.find(separator)
        if end >= 40 and end < 240:
            return description.substr(0, end + 1)
    return description


func _refresh_game_presentation() -> void:
    _presentation_cache.clear()
    _presentation_key = ""
    for game in _current_games:
        if str(game.get("id", "")) == _last_game_id:
            _on_cartridge_selected(game, _carousel.selected_index)
            return


func _show_rewards() -> void:
    if _game_is_active():
        return
    _rewards_panel.configure(_backend, _catalog)
    _rewards_panel.open_centered(Vector2i(mini(1100, int(size.x) - 56), mini(820, int(size.y) - 56)))


func _show_media_settings() -> void:
    if _game_is_active():
        return
    var identity := _presentation_identity()
    if identity.is_empty():
        _show_nonfatal_error("Choose a console and a game before adding game media.")
        return
    _media_settings.open_for_game(identity.system, identity.slug, identity.title)


func _build_game_video() -> void:
    _video_panel = PopupPanel.new()
    _video_panel.name = "GameVideoPreview"
    var style := StyleBoxFlat.new()
    style.bg_color = Color("080f17")
    style.border_color = Color("36505b")
    style.set_border_width_all(1)
    style.set_corner_radius_all(18)
    style.set_content_margin_all(20)
    _video_panel.add_theme_stylebox_override("panel", style)
    add_child(_video_panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    _video_panel.add_child(column)
    var heading := _label("Game preview", 22, TEXT_COLOR)
    heading.name = "VideoPreviewTitle"
    heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    heading.clip_text = true
    column.add_child(heading)
    _video_player = VideoStreamPlayer.new()
    _video_player.expand = true
    _video_player.custom_minimum_size = Vector2(320, 180)
    _video_player.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _video_player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_child(_video_player)
    var actions := HBoxContainer.new()
    actions.add_theme_constant_override("separation", 12)
    column.add_child(actions)
    var pause := _button("Pause / Play", func():
        if not _video_player.is_playing():
            _video_player.play()
        else:
            _video_player.paused = not _video_player.paused
    )
    pause.icon = preload("res://scripts/workspace/ui_icons.gd").icon("pause")
    actions.add_child(pause)
    var close := _button("Close preview", _video_panel.hide)
    close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    actions.add_child(close)
    _video_panel.popup_hide.connect(func():
        _video_player.stop()
        _video_player.stream = null
        _sync_selection_music()
        _restore_carousel_focus())


func _show_game_video() -> void:
    if _game_is_active() or _at_console_home or not _at_game_details or _external_preview_active:
        return
    var path := str(_presentation.get("video_path", ""))
    if not _valid_local_preview(path):
        _media_hint.text = "The local preview is unavailable. Add it again through Game media."
        return
    _stop_selection_music(false)
    if path.get_extension().to_lower() != "ogv":
        var result := _open_external_game_video(path)
        _external_preview_active = result == OK
        _update_selection_media_controls()
        if result != OK:
            _media_hint.text = "The video player could not open this preview."
            _sync_selection_music()
        return
    var stream := VideoStreamTheora.new()
    stream.file = path
    _video_player.stream = stream
    _video_player.paused = false
    _video_panel.get_node("VBoxContainer/VideoPreviewTitle").text = _hero_title.text + " · Preview"
    _video_panel.popup_centered(Vector2i(mini(1000, int(size.x) - 60), mini(650, int(size.y) - 60)))
    _video_player.play()


func _valid_local_preview(path: String) -> bool:
    var packs = preload("res://scripts/workspace/game_presentation.gd")
    if path.is_empty() or not packs.valid_media_name(path.get_file(), "video"):
        return false
    var handle := FileAccess.open(path, FileAccess.READ)
    return handle != null and handle.get_length() > 0 and handle.get_length() <= packs.MAX_VIDEO_BYTES


func _open_external_game_video(path: String) -> Error:
    return OS.shell_open(path)


func _return_from_external_preview() -> void:
    _external_preview_active = false
    _update_selection_media_controls()
    _sync_selection_music()
    _restore_carousel_focus()


func _update_selection_media_controls() -> void:
    if not is_instance_valid(_media_group):
        return
    var selected := not _at_console_home and _at_game_details and not _presentation_key.is_empty()
    var video_path := str(_presentation.get("video_path", ""))
    var has_video := _valid_local_preview(video_path)
    _media_group.visible = selected and _external_preview_active
    _media_button.visible = has_video and not _external_preview_active
    _preview_caption.text = "↗  WATCH PREVIEW" if video_path.get_extension().to_lower() == "ogv" else "↗  OPEN VIDEO"
    _external_preview_return.visible = _external_preview_active
    _media_hint.visible = _external_preview_active
    if _external_preview_active:
        _media_hint.text = "Preview opened in your video player. Return when you finish watching."
    else:
        _media_hint.text = "Local video · Plays inside RetroLife" if video_path.get_extension().to_lower() == "ogv" else "Local MP4 · Opens your video player"
    _media_button.tooltip_text = _media_hint.text
    var music_path := str(_presentation.get("music_path", ""))
    _music_controls.visible = selected and not music_path.is_empty() and FileAccess.file_exists(music_path)
    _music_toggle.set_pressed_no_signal(_selection_music_enabled)
    _music_toggle.text = ("Sound off" if is_zero_approx(_selection_music_volume) else "Soundtrack") if _selection_music_enabled else "Enable music"
    _music_toggle.tooltip_text = "Play this game's local music while browsing. Music stops during gameplay and video previews."
    _music_slider.set_value_no_signal(_selection_music_volume * 100.0)
    _music_slider.tooltip_text = "Selection music volume · %d%%" % roundi(_selection_music_volume * 100.0)
    _music_slider.editable = _selection_music_enabled
    _music_slider.visible = _selection_music_enabled
    _music_percent.visible = _selection_music_enabled
    _music_percent.text = "%d%%" % roundi(_selection_music_volume * 100.0)
    _music_toggle.icon = preload("res://scripts/workspace/ui_icons.gd").icon("sound" if _selection_music_enabled and _selection_music_volume > 0 else "muted", Color("a7e7ce"), 18)
    if music_path == _selection_music_failed_path and not music_path.is_empty():
        _music_toggle.text = "Music unavailable"
        _music_toggle.tooltip_text = "This local track could not be decoded. Add a valid OGG, MP3 or WAV through Game media."


func _valid_music_volume(value: Variant) -> float:
    if (value is int or value is float) and is_finite(float(value)):
        return clampf(float(value), 0.0, 1.0)
    return 0.35


func _set_selection_music_enabled(enabled: bool) -> void:
    _selection_music_enabled = enabled
    _selection_music_failed_path = ""
    _save_preferences()
    _update_selection_media_controls()
    _sync_selection_music()


func _set_selection_music_volume(value: float) -> void:
    _selection_music_volume = _valid_music_volume(value)
    if is_instance_valid(_selection_music):
        _selection_music.volume_linear = _selection_music_volume
    _save_preferences()
    _update_selection_media_controls()


func _stop_selection_music(clear_track := true) -> void:
    if not is_instance_valid(_selection_music):
        return
    if _selection_music.playing:
        _selection_music.stop()
    if clear_track:
        _selection_music.stream = null
        _selection_music_path = ""
        _selection_music_failed_path = ""


func _sync_selection_music() -> void:
    if not is_instance_valid(_selection_music):
        return
    if _at_console_home or not _at_game_details or _game_is_active() or _selection_launch_pending:
        _external_preview_active = false
        if is_instance_valid(_video_panel) and _video_panel.visible:
            _video_panel.hide()
        _stop_selection_music()
        return
    var blocked := not is_visible_in_tree() or _external_preview_active or _importing
    for popup in [_video_panel, _media_settings, _settings_panel, _controller_panel, _storage_panel, _rewards_panel, _box_panel, _updates_panel, _details_overlay, _search_panel, _file_dialog, _art_dialog]:
        if is_instance_valid(popup) and popup.visible:
            blocked = true
    var path := str(_presentation.get("music_path", ""))
    if not _selection_music_enabled or blocked or path.is_empty():
        _stop_selection_music(not _selection_music_enabled or path.is_empty())
        return
    if path == _selection_music_failed_path:
        return
    if path != _selection_music_path or _selection_music.stream == null:
        _stop_selection_music()
        var stream := preload("res://scripts/workspace/game_presentation.gd").load_music_stream(path)
        if stream == null:
            _selection_music_failed_path = path
            _update_selection_media_controls()
            return
        _selection_music.stream = stream
        _selection_music_path = path
    _selection_music.volume_linear = _selection_music_volume
    if not _selection_music.playing:
        _selection_music.play()


func _play_selected_game() -> void:
    # Stop before the backend starts, not one UI frame after game audio begins.
    _selection_launch_pending = true
    _stop_inline_preview()
    _stop_selection_music()
    _external_preview_active = false
    if is_instance_valid(_video_panel):
        _video_panel.hide()
    super._play_selected_game()
    _selection_launch_pending = false
    _sync_selection_music()


func _stop_inline_preview() -> void:
    if not is_instance_valid(_inline_video):
        return
    _inline_video.stop()
    _inline_video.stream = null
    _inline_video.hide()
    _inline_path = ""


func _sync_inline_preview(delta: float) -> void:
    if not is_instance_valid(_inline_video):
        return
    var blocked := _at_console_home or not _at_game_details or _game_is_active() or _selection_launch_pending or not is_visible_in_tree() or _importing or _external_preview_active
    for popup in [_video_panel, _media_settings, _settings_panel, _controller_panel, _storage_panel, _rewards_panel, _box_panel, _updates_panel, _details_overlay, _search_panel, _file_dialog, _art_dialog]:
        if is_instance_valid(popup) and popup.visible:
            blocked = true
    var path := str(_presentation.get("video_path", ""))
    var playable := path.get_extension().to_lower() == "ogv"
    _inline_preview.visible = not _at_console_home and _at_game_details and not _presentation_key.is_empty() and (playable or _inline_still.texture != null or _media_button.visible)
    if blocked or _reduce_motion or not playable:
        _stop_inline_preview()
        _preview_delay = 0.0
        return
    if path == _inline_path:
        return
    _preview_delay += delta
    if _preview_delay < 0.8:
        return
    if path != _inline_checked_path:
        _inline_checked_path = path
        _inline_valid = _valid_local_preview(path)
    if not _inline_valid:
        _inline_preview.visible = _inline_still.texture != null
        return
    var stream := VideoStreamTheora.new()
    stream.file = path
    _inline_video.stream = stream
    _inline_video.paused = false
    _inline_video.show()
    _inline_path = path
    _inline_video.play()
