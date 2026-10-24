extends PopupPanel

## Read-only collection across the current library. Progress remains in Rust.
const Profiles = preload("res://scripts/workspace/collection_profiles.gd")
const Preferences = preload("res://scripts/workspace/preferences.gd")
const Journal = preload("res://scripts/workspace/journey_panel.gd")
const RewardStamp = preload("res://scripts/workspace/reward_stamp.gd")
const JourneyTheme = preload("res://scripts/workspace/journey_theme.gd")
const PAGE_SIZE := 6
const INK := Color("eaf0f5")
const MUTED := Color("a6b6c5")

var backend: Node
var _catalog: RefCounted
var _games: Array[Dictionary] = []
var _library_size := 0
var _states: Dictionary = {}
var _global: Dictionary = {}
var _totals: Dictionary = {}
var _generation := 0
var _page := 0
var _selected_game_id := ""
var _status_filter := 0
var _art_cache: Dictionary = {}
var _game_filter: OptionButton
var _status_select: OptionButton
var _close: Button
var _refresh: Button
var _level: Label
var _xp: Label
var _collected: Label
var _time: Label
var _library_count: Label
var _subtitle: Label
var _level_progress: ProgressBar
var _message: Label
var _scroll: ScrollContainer
var _sections: VBoxContainer
var _pager: HBoxContainer
var _page_label: Label
var _previous: Button
var _next: Button


func _ready() -> void:
    wrap_controls = false
    min_size = Vector2i(620, 420)
    add_theme_stylebox_override("panel", _style(Color("101821"), Color("344354"), 22, 24))
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 14)
    add_child(column)
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 16)
    column.add_child(header)
    var introduction := VBoxContainer.new()
    introduction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    introduction.add_theme_constant_override("separation", 6)
    header.add_child(introduction)
    _text(introduction, "Your keepsakes", 24)
    _subtitle = _text(introduction, "Keepsakes unlocked automatically by what happens in your games.", 16, MUTED)
    _close = _button("Close", hide)
    _close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    header.add_child(_close)
    var totals := HBoxContainer.new()
    totals.add_theme_constant_override("separation", 14)
    column.add_child(totals)
    var level_card := _stat_card(totals)
    _text(level_card, "YOUR LEVEL", 14, MUTED)
    _level = _text(level_card, "—", 24)
    _xp = _text(level_card, "All-time XP", 16, MUTED)
    _level_progress = _progress(level_card, 200, Color("a99ad9"))
    var collection_card := _stat_card(totals)
    _text(collection_card, "KEEPSAKES", 14, MUTED)
    _collected = _text(collection_card, "—", 24)
    _text(collection_card, "In your current library", 16, MUTED)
    var time_card := _stat_card(totals)
    _text(time_card, "ACTIVE PLAY", 14, MUTED)
    _time = _text(time_card, "—", 24)
    _library_count = _text(time_card, "Across your games", 16, MUTED)
    var filters := HBoxContainer.new()
    filters.add_theme_constant_override("separation", 12)
    column.add_child(filters)
    _game_filter = OptionButton.new()
    _game_filter.fit_to_longest_item = false
    _game_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _game_filter.custom_minimum_size = Vector2(220, 44)
    _game_filter.add_theme_font_size_override("font_size", 16)
    _game_filter.tooltip_text = "Choose a game's keepsakes"
    _game_filter.item_selected.connect(_select_game)
    filters.add_child(_game_filter)
    _status_select = OptionButton.new()
    _status_select.custom_minimum_size = Vector2(190, 44)
    _status_select.add_theme_font_size_override("font_size", 16)
    for caption in ["All keepsakes", "Collected", "Still to discover"]:
        _status_select.add_item(caption)
    _status_select.item_selected.connect(func(index: int): _status_filter = index; _page = 0; _render_games())
    filters.add_child(_status_select)
    _refresh = _button("Refresh", refresh)
    filters.add_child(_refresh)
    _message = _text(column, "", 16, MUTED)
    _message.hide()
    _scroll = ScrollContainer.new()
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _scroll.follow_focus = true
    _scroll.focus_mode = Control.FOCUS_ALL
    _scroll.resized.connect(_update_columns)
    column.add_child(_scroll)
    _sections = VBoxContainer.new()
    _sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _sections.add_theme_constant_override("separation", 26)
    _scroll.add_child(_sections)
    _pager = HBoxContainer.new()
    _pager.alignment = BoxContainer.ALIGNMENT_CENTER
    _pager.add_theme_constant_override("separation", 16)
    column.add_child(_pager)
    _previous = _button("Previous", func(): _page -= 1; _render_games())
    _pager.add_child(_previous)
    _page_label = _text(_pager, "", 16, MUTED)
    _page_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    _page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _next = _button("Next", func(): _page += 1; _render_games())
    _pager.add_child(_next)
    _pager.hide()
    close_requested.connect(hide)
    about_to_popup.connect(func(): _close.call_deferred("grab_focus"))
    popup_hide.connect(func(): _generation += 1; _clear_sections(); _art_cache.clear())
    size_changed.connect(_update_columns)


func configure(node: Node, catalog: RefCounted, preferred_game_id := "") -> void:
    backend = node
    _catalog = catalog
    _selected_game_id = preferred_game_id
    _status_filter = 0
    _status_select.select(0)
    refresh()


func open_centered(target: Vector2i) -> void:
    popup_centered(target)
    # PopupPanel initially wraps its contents even when a larger size is
    # requested. Restore the browsing viewport after the first layout passes.
    await get_tree().process_frame
    await get_tree().process_frame
    if not visible:
        return
    size = target
    var host := get_parent().get_window()
    position = (host.size - size) / 2
    if not is_embedded():
        position += host.position
    _update_columns.call_deferred()


func refresh() -> void:
    _generation += 1
    var generation := _generation
    _games.clear()
    _library_size = 0
    _states.clear()
    _global.clear()
    _totals.clear()
    _art_cache.clear()
    _clear_sections()
    _page = 0
    _pager.hide()
    _set_loading(true)
    _level.text = "—"
    _xp.text = "All-time XP"
    _collected.text = "—"
    _time.text = "—"
    _library_count.text = "Across your games"
    _level_progress.value = 0
    _message.text = "Reading your collection…"
    _message.show()
    if backend == null or not backend.has_method("journey_state_json") or _catalog == null:
        _fail("Your progress is unavailable. Reopen the library and try again.")
        return
    var offset := 0
    var revision: Variant = null
    var seen := {}
    while true:
        var response: Dictionary = _catalog.view("", "", offset, 500)
        if not bool(response.get("ok", false)):
            _fail(str(response.get("error", "The library could not be read.")))
            return
        var data: Dictionary = response.get("data", {})
        if revision != null and revision != data.get("revision"):
            _fail("Your library changed while loading. Refresh to try again.")
            return
        revision = data.get("revision")
        var batch: Array = data.get("games", [])
        for game in batch:
            var id := str(game.get("id", ""))
            if not id.is_empty() and not seen.has(id):
                seen[id] = true
                _games.append(game)
        if not bool(data.get("hasMore", false)):
            break
        if batch.is_empty():
            _fail("The library returned an incomplete collection. Please refresh.")
            return
        offset += batch.size()
        await get_tree().process_frame
        if generation != _generation:
            return
    _global = _read_summary("")
    if _global.has("error"):
        _fail(_global.error)
        return
    _library_size = _games.size()
    var supported_games: Array[Dictionary] = []
    var collected := 0
    var available := 0
    var seconds := 0
    for index in _games.size():
        var id := str(_games[index].id)
        var state := _read_summary(id)
        if state.has("error"):
            _fail("Progress could not be read for %s. %s" % [_title_for(_games[index]), state.error])
            return
        # Never infer support from a familiar game title or installed artwork.
        # Unsupported revisions do not create empty sections, filters or totals.
        if bool(state.supported):
            supported_games.append(_games[index])
            _states[id] = state
            collected += int(state.collected)
            available += int(state.totalRewards)
            seconds += int(state.seconds)
        if index % 16 == 15:
            _message.text = "Reading progress · %d / %d games" % [index + 1, _games.size()]
            await get_tree().process_frame
            if generation != _generation:
                return
    _games = supported_games
    _totals = {"collected": collected, "available": available, "seconds": seconds}
    _level.text = "Level %d" % int(_global.level)
    _xp.text = "%d total XP" % int(_global.totalXp)
    _level_progress.value = int(_global.levelProgress)
    _collected.text = "%d / %d" % [collected, available]
    _time.text = _duration(seconds)
    _library_count.text = "%d of %d games with automatic rewards" % [_games.size(), _library_size]
    _rebuild_game_filter()
    _set_loading(false)
    _game_filter.disabled = _games.is_empty()
    _status_select.disabled = _games.is_empty()
    _render_games()


func _read_summary(id: String) -> Dictionary:
    var response: Variant = JSON.parse_string(str(backend.call("journey_state_json", id)))
    if not response is Dictionary or not bool(response.get("ok", false)):
        return {"error": str(response.get("error", "Progress is unavailable.")) if response is Dictionary else "Progress is unavailable."}
    var data: Variant = response.get("data")
    if not data is Dictionary:
        return {"error": "The progress response was incomplete."}
    var problem := Journal.validate_summary(data)
    if not problem.is_empty():
        return {"error": problem}
    return data


func _rebuild_game_filter() -> void:
    _game_filter.clear()
    _game_filter.add_item("Games with rewards · %d" % _games.size())
    _game_filter.set_item_metadata(0, "")
    var selected := 0
    for game in _games:
        _game_filter.add_item(_title_for(game))
        var index := _game_filter.item_count - 1
        _game_filter.set_item_metadata(index, str(game.id))
        if str(game.id) == _selected_game_id:
            selected = index
    _game_filter.select(selected)
    _selected_game_id = str(_game_filter.get_item_metadata(selected))


func _select_game(index: int) -> void:
    _selected_game_id = str(_game_filter.get_item_metadata(index))
    _page = 0
    _render_games()


func _matching_games() -> Array[Dictionary]:
    var games: Array[Dictionary] = []
    for game in _games:
        if not _selected_game_id.is_empty() and str(game.id) != _selected_game_id:
            continue
        var state: Dictionary = _states.get(str(game.id), {})
        if state.is_empty() or not bool(state.get("supported", false)) or (_status_filter == 1 and int(state.collected) == 0) or (_status_filter == 2 and int(state.collected) == int(state.totalRewards)):
            continue
        games.append(game)
    return games


func _render_games() -> void:
    _clear_sections()
    _art_cache.clear()
    var games := _matching_games()
    var pages := maxi(1, ceili(float(games.size()) / PAGE_SIZE))
    _page = clampi(_page, 0, pages - 1)
    _pager.visible = pages > 1
    _previous.disabled = _page == 0
    _next.disabled = _page >= pages - 1
    _page_label.text = "%d / %d" % [_page + 1, pages]
    _message.visible = games.is_empty()
    if _library_size == 0:
        _message.text = "Import a supported game to start your keepsake collection."
    elif _games.is_empty():
        _message.text = "None of your games have automatic rewards yet. You can play them normally; quests and keepsakes appear only for supported games."
    else:
        _message.text = "No keepsakes in this view yet. Try another filter."
    for game in games.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE):
        _build_game(game, _states[str(game.id)])
    _scroll.scroll_vertical = 0
    _update_columns.call_deferred()


func _build_game(game: Dictionary, state: Dictionary) -> void:
    var profile := Profiles.for_game(str(game.get("title", "")), str(game.get("systemId", "")))
    var accent := Color(profile.get("color", "91b1c5"))
    var base := Profiles.asset_base(profile)
    var theme_data := JourneyTheme.from_file(_art_path(base + "/journey/theme.json")) if not base.is_empty() else {}
    var cover := _load_art(base + "/journey/cover.png") if not base.is_empty() else null
    var reward_art := {}
    var customized := cover != null
    for achievement: Dictionary in state.achievements:
        var index := int(achievement.artIndex)
        var texture := _load_icon(base + "/journey/rewards/" + str(achievement.id)) if not base.is_empty() else null
        if texture == null and index < 8 and not base.is_empty():
            texture = _load_icon(base + "/journey/rewards/%02d" % [index + 1])
        reward_art[str(achievement.id)] = texture
        customized = customized or texture != null
    if not customized:
        theme_data.clear()
        accent = Color("91b1c5")
    var section := VBoxContainer.new()
    section.add_theme_constant_override("separation", 12)
    section.set_meta("game_id", str(game.id))
    _sections.add_child(section)
    var heading := HBoxContainer.new()
    heading.add_theme_constant_override("separation", 14)
    section.add_child(heading)
    if cover != null:
        var image := TextureRect.new()
        image.texture = cover
        image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if theme_data.get("artStyle") == "pixel" else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
        image.custom_minimum_size = Vector2(72, 64)
        image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        image.mouse_filter = Control.MOUSE_FILTER_IGNORE
        heading.add_child(image)
    var copy := VBoxContainer.new()
    copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    copy.add_theme_constant_override("separation", 5)
    heading.add_child(copy)
    _text(copy, _title_for(game), 24)
    _text(copy, "%s · %d of %d collected · %s active play" % [str(game.get("systemName", Profiles.SYSTEMS.get(str(game.get("systemId", "")), ""))), int(state.collected), int(state.totalRewards), _duration(int(state.seconds))], 16, MUTED)
    _text(section, str(state.detectionMessage), 14, MUTED)
    if int(state.totalRewards) > 0:
        var progress := _progress(section, int(state.totalRewards), accent)
        progress.value = int(state.collected)
    if bool(state.legacyPreserved):
        _text(section, "Earlier journal entries are preserved separately from verified rewards.", 13, MUTED)
    var grid := GridContainer.new()
    grid.name = "KeepsakeGrid"
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", 12)
    grid.add_theme_constant_override("v_separation", 12)
    section.add_child(grid)
    var gifts: Array = profile.get("gifts", Journal.GIFTS)
    for achievement: Dictionary in state.achievements:
        var earned := bool(achievement.earned)
        var index := int(achievement.artIndex)
        if not earned and not bool(achievement.get("revealed", true)):
            continue
        if (_status_filter == 1 and not earned) or (_status_filter == 2 and earned):
            continue
        var art: Texture2D = reward_art.get(str(achievement.id))
        var art_direction := JourneyTheme.card(theme_data, str(achievement.id)) if art != null else {}
        var card_accent := Color(art_direction.get("accent", accent.to_html(false)))
        var requirement := str(achievement.description) + " · %d XP" % int(achievement.xp)
        var title := str(achievement.get("rewardTitle", art_direction.get("rewardName", gifts[index] if art != null and index < gifts.size() else achievement.title)))
        _build_keepsake(grid, title, requirement, earned, index, art, card_accent, theme_data.get("artStyle") == "pixel")


func _build_keepsake(parent: Control, title: String, requirement: String, earned: bool, index: int, art: Texture2D, accent: Color, pixel_art := false) -> void:
    var card := PanelContainer.new()
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.set_meta("earned", earned)
    card.set_meta("reward_index", index)
    card.add_theme_stylebox_override("panel", _style(accent.darkened(0.87) if earned else Color("17212b"), accent.darkened(0.40) if earned else accent.darkened(0.65), 14, 14))
    parent.add_child(card)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    card.add_child(column)
    _text(column, "COLLECTED" if earned else "LOCKED", 14, accent if earned else MUTED)
    var stamp := RewardStamp.new()
    stamp.accent = accent
    stamp.earned = earned
    stamp.symbol = index
    stamp.artwork = art
    stamp.pixel_art = pixel_art
    stamp.custom_minimum_size = Vector2(96, 160 if art != null else 60)
    stamp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_child(stamp)
    var label := _text(column, title, 16)
    label.custom_minimum_size.y = 42
    _text(column, requirement, 16, MUTED)


func _update_columns() -> void:
    if _scroll == null:
        return
    _subtitle.visible = size.y >= 640
    var columns := clampi(int((_scroll.size.x + 12) / 230), 1, 4)
    for section in _sections.get_children():
        var grid := section.get_node_or_null("KeepsakeGrid") as GridContainer
        if grid != null:
            grid.columns = columns


func _set_loading(loading: bool) -> void:
    _game_filter.disabled = loading
    _status_select.disabled = loading
    _refresh.disabled = loading


func _fail(message: String) -> void:
    _games.clear()
    _states.clear()
    _totals.clear()
    _clear_sections()
    _game_filter.clear()
    _game_filter.add_item("Progress unavailable")
    _message.text = message
    _message.show()
    _game_filter.disabled = true
    _status_select.disabled = true
    _refresh.disabled = false


func _clear_sections() -> void:
    for child in _sections.get_children():
        _sections.remove_child(child)
        child.queue_free()


func _art_path(relative: String) -> String:
    return Preferences.asset(relative)


func _load_art(relative: String) -> Texture2D:
    if _art_cache.has(relative):
        return _art_cache[relative]
    _art_cache[relative] = null
    var path := _art_path(relative)
    if path.is_empty():
        return null
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null or file.get_length() > 16 * 1024 * 1024:
        return null
    var pixels := Image.load_from_file(path)
    if pixels == null or pixels.is_empty() or pixels.get_width() > 4096 or pixels.get_height() > 4096:
        return null
    var longest := maxi(pixels.get_width(), pixels.get_height())
    if longest > 512:
        var scale := 512.0 / longest
        pixels.resize(maxi(1, int(pixels.get_width() * scale)), maxi(1, int(pixels.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
    pixels.generate_mipmaps()
    _art_cache[relative] = ImageTexture.create_from_image(pixels)
    return _art_cache[relative]


func _load_icon(stem: String) -> Texture2D:
    var illustration := _load_art(stem + ".png")
    return illustration if illustration != null else _load_art(stem + ".svg")


func _title_for(game: Dictionary) -> String:
    return str(Profiles.for_game(str(game.get("title", "")), str(game.get("systemId", ""))).get("title", game.get("title", "Unknown game")))


func _duration(seconds: int) -> String:
    if seconds < 60:
        return "%ds" % seconds
    return "%dh %02dm" % [seconds / 3600, (seconds / 60) % 60] if seconds >= 3600 else "%dm" % [seconds / 60]


func _unhandled_input(event: InputEvent) -> void:
    if visible and event.is_action_pressed("ui_cancel"):
        hide()
        get_viewport().set_input_as_handled()


func _text(parent: Node, content: String, font_size: int, color := INK) -> Label:
    var label := Label.new()
    label.text = content
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", font_size)
    if font_size >= 22:
        label.add_theme_font_override("font", preload("res://scripts/workspace/presentation_theme.gd").heading_font())
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label


func _button(caption: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = caption
    button.custom_minimum_size.y = 44
    button.add_theme_font_size_override("font_size", 16)
    button.pressed.connect(action)
    return button


func _stat_card(parent: Control) -> VBoxContainer:
    var card := PanelContainer.new()
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.add_theme_stylebox_override("panel", _style(Color("1a2531"), Color("2b3b4b"), 14, 16))
    parent.add_child(card)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 7)
    card.add_child(column)
    return column


func _progress(parent: Control, maximum: int, accent: Color) -> ProgressBar:
    var progress := ProgressBar.new()
    progress.max_value = maximum
    progress.show_percentage = false
    progress.custom_minimum_size.y = 5
    progress.add_theme_stylebox_override("background", _style(Color("2c3b48"), Color.TRANSPARENT, 3, 0))
    progress.add_theme_stylebox_override("fill", _style(accent, Color.TRANSPARENT, 3, 0))
    parent.add_child(progress)
    return progress


func _style(background: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = background
    style.border_color = border
    style.set_border_width_all(1 if border.a > 0 else 0)
    style.set_corner_radius_all(radius)
    style.set_content_margin_all(margin)
    return style
