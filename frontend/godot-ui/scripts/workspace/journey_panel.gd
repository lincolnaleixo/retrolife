extends PanelContainer

signal support_changed(supported: bool)

const Profiles = preload("res://scripts/workspace/collection_profiles.gd")
const Preferences = preload("res://scripts/workspace/preferences.gd")
const RewardStamp = preload("res://scripts/workspace/reward_stamp.gd")
const JourneyTheme = preload("res://scripts/workspace/journey_theme.gd")
const ACHIEVEMENT_IDS := ["first_stage", "secret", "boss", "finale", "power_up", "yoshi", "dragon_coins", "castle_2", "castle_3", "castle_4", "castle_5", "castle_6", "castle_7"]
const GIFTS := ["First-light badge", "Explorer pin", "Adventure ticket", "Golden hour trophy", "Stage star", "Secret compass", "Boss crown", "Victory gift"]
const INK := Color("eaf0f5")
const MUTED := Color("9baebc")

var backend: Node
var game_id := ""
var _level: Label
var _xp: ProgressBar
var _summary: Label
var _time: Label
var _detection: Label
var _legacy: Label
var _unlock_notice: Label
var _notice_remaining := 0.0
var _has_snapshot := false
var _earned_ids: Array[String] = []
var _next_reward: Label
var _future_hint: Label
var _collection: VBoxContainer
var _collection_progress: ProgressBar
var _collection_summary: Label
var _reward_grid: GridContainer
var _chapter_statuses: Array[Label] = []
var _chapter_titles: Array[Label] = []
var _chapter_cards: Array[PanelContainer] = []
var _chapter_icons: Array[TextureRect] = []
var _chapter_numbers: Array[Label] = []
var _chapter_regions: Array[Label] = []
var _chapter_icon_frames: Array[PanelContainer] = []
var _theme_data: Dictionary = {}
var _customized := false
var _support_available := false
var _game_title := ""
var _art_configured := false
var _timer := 0.0
var _collection_key := ""
var _error: Label
var _gift_tab: Button
var _quests_tab: Button
var _quests: VBoxContainer
var _profile: Dictionary = {}
var _world: Label
var _chapter: Label
var _description: Label
var _cover_frame: PanelContainer
var _art: TextureRect
var _accent := Color("8eb5ca")
var _gift_names: Array = GIFTS
var _quest_notes: Array[Label] = []
var _art_cache: Dictionary = {}
var _chapter_textures: Array[Texture2D] = []
var _reward_textures: Array[Texture2D] = []
var _scroll: ScrollContainer

func _ready() -> void:
    custom_minimum_size.x = 340
    add_theme_stylebox_override("panel", _panel_style(Color("111a24"), Color("263342"), 18, 16))
    _scroll = ScrollContainer.new()
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(_scroll)
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 12)
    _scroll.add_child(column)
    _world = _text(column, "YOUR GAME JOURNAL", 11, MUTED)
    _world.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _world.max_lines_visible = 1
    _cover_frame = PanelContainer.new()
    _cover_frame.custom_minimum_size.y = 100
    _cover_frame.clip_contents = true
    _cover_frame.add_theme_stylebox_override("panel", _panel_style(Color("1b2835"), Color.TRANSPARENT, 12, 0))
    column.add_child(_cover_frame)
    _art = TextureRect.new()
    _art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    _art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _cover_frame.add_child(_art)
    _cover_frame.hide()
    _chapter = _text(column, "Your next adventure", 24)
    _description = _text(column, "A personal journal for this game.", 14, MUTED)
    var level_row := HBoxContainer.new()
    level_row.add_theme_constant_override("separation", 12)
    column.add_child(level_row)
    _level = _text(level_row, "LEVEL 1", 12)
    _level.autowrap_mode = TextServer.AUTOWRAP_OFF
    _level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _summary = _text(level_row, "0 / 200 XP", 11, MUTED)
    _summary.autowrap_mode = TextServer.AUTOWRAP_OFF
    _summary.size_flags_horizontal = Control.SIZE_SHRINK_END
    _summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _xp = _progress(column, 5)
    _xp.max_value = 200
    _detection = _text(column, "Connecting to game events…", 13, MUTED)
    _unlock_notice = _text(column, "", 14, _accent)
    _unlock_notice.hide()
    var tabs := HBoxContainer.new()
    tabs.add_theme_constant_override("separation", 6)
    column.add_child(tabs)
    _quests_tab = _tab(tabs, "Discoveries")
    _quests_tab.button_pressed = true
    _gift_tab = _tab(tabs, "Collection · 0/0")
    var group := ButtonGroup.new()
    _quests_tab.button_group = group
    _gift_tab.button_group = group
    _quests = VBoxContainer.new()
    _quests.add_theme_constant_override("separation", 10)
    column.add_child(_quests)
    for index in ACHIEVEMENT_IDS.size():
        _build_chapter(index)
    _next_reward = _text(_quests, "", 14, _accent)
    _future_hint = _text(_quests, "New discoveries appear as your adventure unfolds.", 13, MUTED)
    var order := ["power_up", "yoshi", "first_stage", "dragon_coins", "boss", "secret", "castle_2", "castle_3", "castle_4", "castle_5", "castle_6", "castle_7", "finale"]
    for position in order.size():
        _quests.move_child(_chapter_cards[ACHIEVEMENT_IDS.find(order[position])], position)
    _time = _text(_quests, "", 11, MUTED)
    _legacy = _text(_quests, "Earlier journal entries are preserved separately. Verified rewards unlock from game events.", 11, MUTED)
    _legacy.hide()
    _collection = VBoxContainer.new()
    _collection.add_theme_constant_override("separation", 12)
    column.add_child(_collection)
    _collection_summary = _text(_collection, "A little collection of big moments.", 13)
    _collection_progress = _progress(_collection, 5)
    _collection_progress.max_value = 1
    _reward_grid = GridContainer.new()
    _reward_grid.columns = 2
    _reward_grid.add_theme_constant_override("h_separation", 10)
    _reward_grid.add_theme_constant_override("v_separation", 10)
    _reward_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _collection.add_child(_reward_grid)
    _collection.hide()
    _quests_tab.pressed.connect(func(): _quests.show(); _collection.hide())
    _gift_tab.pressed.connect(func(): _quests.hide(); _collection.show())
    _error = _text(column, "", 12, Color("ffa494"))
    _error.hide()

func _build_chapter(index: int) -> void:
    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", _panel_style(Color("17222d"), Color("2a3947"), 12, 11))
    _chapter_cards.append(card)
    _quests.add_child(card)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    card.add_child(row)
    var icon := TextureRect.new()
    var frame := PanelContainer.new()
    frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(frame)
    _chapter_icon_frames.append(frame)
    icon.custom_minimum_size = Vector2(64, 64)
    icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    frame.add_child(icon)
    _chapter_icons.append(icon)
    var number := _text(row, "%02d" % [index + 1], 18, MUTED)
    number.custom_minimum_size.x = 28
    number.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _chapter_numbers.append(number)
    var copy := VBoxContainer.new()
    copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    copy.add_theme_constant_override("separation", 4)
    row.add_child(copy)
    _chapter_regions.append(_text(copy, "", 11, MUTED))
    _chapter_titles.append(_text(copy, "", 15))
    _quest_notes.append(_text(copy, "", 13, MUTED))
    var status := _text(copy, "WAITING TO DISCOVER", 10, MUTED)
    _chapter_statuses.append(status)
    card.mouse_filter = Control.MOUSE_FILTER_IGNORE
    card.hide()

func configure(node: Node, id: String, title: String, system := "") -> void:
    _set_supported(false)
    backend = node
    game_id = id
    _timer = 0.0
    _collection_key = ""
    _has_snapshot = false
    _earned_ids.clear()
    _notice_remaining = 0.0
    _unlock_notice.hide()
    _profile = Profiles.for_game(title, system)
    _game_title = title
    _reset_art()
    _detection.text = "Connecting to game events…"
    _time.hide()
    _legacy.hide()
    _error.hide()
    _gift_tab.text = "Collection · 0/0"
    _collection_progress.value = 0
    _collection_progress.hide()
    _clear_rewards()
    _quests_tab.button_pressed = true
    _quests.show()
    _collection.hide()
    _scroll.scroll_vertical = 0
    refresh()

func _reset_art() -> void:
    _art_configured = false
    _customized = false
    _theme_data.clear()
    _art_cache.clear()
    _accent = Color("8eb5ca")
    _chapter.text = _game_title
    _description.text = "Milestones detected automatically while you play."
    _world.text = "GAME PROGRESS"
    _world.add_theme_color_override("font_color", _accent)
    _quests_tab.text = "Milestones"
    _art.texture = null
    _cover_frame.hide()
    _art.hide()
    _chapter_textures.clear()
    _chapter_textures.resize(ACHIEVEMENT_IDS.size())
    _reward_textures.clear()
    _reward_textures.resize(ACHIEVEMENT_IDS.size() + 4)
    for index in ACHIEVEMENT_IDS.size():
        _chapter_icons[index].texture = null
        _chapter_icons[index].hide()
        _chapter_icon_frames[index].hide()
        _chapter_regions[index].hide()
        _chapter_numbers[index].show()
        _chapter_cards[index].hide()
    for bar in [_xp, _collection_progress]:
        _style_progress(bar)

func _configure_art() -> void:
    _accent = Color(_profile.get("color", "8eb5ca"))
    _world.text = str(_profile.get("title", _game_title)).to_upper() + " · JOURNAL"
    _world.add_theme_color_override("font_color", _accent)
    _chapter.text = str(_profile.get("chapter", "Your personal journey"))
    _description.text = str(_profile.get("subtitle", "Rewards from the moments you discover while playing."))
    _gift_names = _profile.get("gifts", GIFTS)
    _art_cache.clear()
    _chapter_textures.clear()
    _reward_textures.clear()
    var base := Profiles.asset_base(_profile)
    var journey := base + "/journey/" if not base.is_empty() else ""
    _theme_data = JourneyTheme.from_file(_art_path(journey + "theme.json")) if not journey.is_empty() else {}
    var pixel_art: bool = _theme_data.get("artStyle") == "pixel"
    var art_filter := CanvasItem.TEXTURE_FILTER_NEAREST if pixel_art else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    _art.texture_filter = art_filter
    _art.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED if pixel_art else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _art.texture = _load_art(journey + "cover.png") if not journey.is_empty() else null
    _cover_frame.visible = _art.texture != null
    _art.visible = _art.texture != null
    for index in ACHIEVEMENT_IDS.size():
        _chapter_textures.append(_load_icon(journey + "chapters/" + ACHIEVEMENT_IDS[index]) if not journey.is_empty() else null)
    _reward_textures.resize(ACHIEVEMENT_IDS.size() + 4)
    for index in ACHIEVEMENT_IDS.size():
        var texture := _load_icon(journey + "rewards/" + ACHIEVEMENT_IDS[index]) if not journey.is_empty() else null
        if texture == null and index < 4 and not journey.is_empty():
            texture = _load_icon(journey + "rewards/%02d" % [index + 5])
        _reward_textures[index + 4] = texture
    _customized = _art.texture != null or _chapter_textures.any(func(texture: Texture2D): return texture != null) or _reward_textures.any(func(texture: Texture2D): return texture != null)
    if not _customized:
        _theme_data.clear()
        _accent = Color("8eb5ca")
        _chapter.text = _game_title
        _description.text = "Milestones detected automatically while you play."
        _world.text = "GAME PROGRESS"
        _world.add_theme_color_override("font_color", _accent)
    else:
        _chapter.text = str(_theme_data.get("title", _chapter.text))
        _description.text = str(_theme_data.get("subtitle", _description.text))
    _quests_tab.text = "Discoveries" if _customized else "Milestones"
    for index in ACHIEVEMENT_IDS.size():
        var art_direction := JourneyTheme.card(_theme_data, ACHIEVEMENT_IDS[index])
        var card_accent := Color(art_direction.get("accent", _accent.to_html(false)))
        _chapter_icons[index].texture = _chapter_textures[index]
        _chapter_icons[index].texture_filter = art_filter
        _chapter_icons[index].visible = _chapter_textures[index] != null
        _chapter_icon_frames[index].visible = _chapter_textures[index] != null
        _chapter_icon_frames[index].add_theme_stylebox_override("panel", _panel_style(card_accent.darkened(0.84), card_accent.darkened(0.55), 3 if pixel_art else 14, 3))
        var region := str(art_direction.get("region", ""))
        _chapter_regions[index].text = region
        _chapter_regions[index].visible = not region.is_empty() and _chapter_textures[index] != null
        _chapter_regions[index].add_theme_color_override("font_color", card_accent)
        _chapter_numbers[index].visible = _chapter_textures[index] == null
        _chapter_cards[index].hide()
    for bar in [_xp, _collection_progress]:
        _style_progress(bar)
    _art_configured = true

func _set_supported(supported: bool) -> void:
    if _support_available == supported:
        return
    _support_available = supported
    support_changed.emit(supported)

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
    pixels.generate_mipmaps()
    _art_cache[relative] = ImageTexture.create_from_image(pixels)
    return _art_cache[relative]

func _load_icon(stem: String) -> Texture2D:
    var illustration := _load_art(stem + ".png")
    return illustration if illustration != null else _load_art(stem + ".svg")

func _process(delta: float) -> void:
    if game_id.is_empty():
        return
    if _notice_remaining > 0:
        _notice_remaining = maxf(0, _notice_remaining - delta)
        _unlock_notice.visible = _notice_remaining > 0
    _timer += delta
    if _timer >= 1 and (is_visible_in_tree() or not _support_available):
        _timer = 0
        refresh()

func refresh() -> void:
    if backend == null or not backend.has_method("journey_state_json") or game_id.is_empty():
        return
    _render_response(JSON.parse_string(str(backend.call("journey_state_json", game_id))))

func _render_response(response: Variant) -> void:
    if not response is Dictionary or not bool(response.get("ok", false)):
        _set_supported(false)
        _error.text = str(response.get("error", "Progress is unavailable.")) if response is Dictionary else "Progress is unavailable."
        _error.show()
        _detection.text = "Game-event detection is unavailable. Retrying…"
        _detection.add_theme_color_override("font_color", MUTED)
        return
    var data: Variant = response.get("data")
    var problem := validate_summary(data)
    if not problem.is_empty():
        _set_supported(false)
        _error.text = problem
        _error.show()
        _detection.text = "Game-event detection is unavailable. Retrying…"
        _detection.add_theme_color_override("font_color", MUTED)
        return
    _error.hide()
    if bool(data.supported) and not _art_configured:
        _configure_art()
    elif not bool(data.supported) and _art_configured:
        _reset_art()
    _set_supported(bool(data.supported))
    _level.text = "LEVEL %d" % int(data.level)
    _xp.value = int(data.levelProgress)
    _summary.text = "%d / 200 XP" % int(_xp.value)
    _summary.tooltip_text = "%d total XP" % int(data.totalXp)
    var collected := int(data.collected)
    var available := int(data.totalRewards)
    _gift_tab.text = "Collection · %d/%d" % [collected, available]
    _collection_summary.text = "%s\n%d of %d discovered" % [str(_theme_data.get("collectionTitle", "Your keepsake collection")), collected, available] if available > 0 else "No automatic rewards available for this game yet."
    _collection_progress.max_value = maxi(1, available)
    _collection_progress.value = collected
    _collection_progress.visible = available > 0
    _detection.text = str(data.detectionMessage)
    _detection.add_theme_color_override("font_color", _accent if str(data.detectionStatus) == "watching" else MUTED)
    var seconds := int(data.seconds)
    _time.text = "%dh %02dm active play · Rewards unlock from game events" % [seconds / 3600, (seconds / 60) % 60]
    _time.visible = bool(data.supported)
    _legacy.visible = bool(data.legacyPreserved)
    var achievements: Array = data.achievements
    var now_earned: Array[String] = []
    var newly_earned: Array[String] = []
    for card in _chapter_cards:
        card.hide()
    var upcoming: Array[String] = []
    var hidden_count := 0
    for achievement: Dictionary in achievements:
        var id := str(achievement.id)
        var index := ACHIEVEMENT_IDS.find(id)
        var done := bool(achievement.earned)
        if done:
            now_earned.append(id)
            if _has_snapshot and not _earned_ids.has(id):
                newly_earned.append(str(achievement.get("rewardTitle", achievement.title)))
        if index < 0:
            continue
        if not bool(achievement.get("revealed", true)):
            hidden_count += 1
            continue
        if done:
            continue
        upcoming.append(str(achievement.get("rewardTitle", achievement.title)))
        var art_direction := JourneyTheme.card(_theme_data, id)
        var card_accent := Color(art_direction.get("accent", _accent.to_html(false)))
        _chapter_cards[index].show()
        _chapter_titles[index].text = str(achievement.title)
        _quest_notes[index].text = str(achievement.description)
        _chapter_statuses[index].text = "GIFT · " + str(achievement.get("rewardTitle", achievement.title)) + " · %d XP" % int(achievement.xp)
        _chapter_statuses[index].add_theme_color_override("font_color", card_accent if done else MUTED)
        var style := _panel_style(card_accent.darkened(0.85) if done else Color("17222d"), card_accent.darkened(0.3) if done else card_accent.darkened(0.65), 14, 11)
        if _chapter_textures[index] != null:
            style.border_width_left = 3
        _chapter_cards[index].add_theme_stylebox_override("panel", style)
    _next_reward.text = "%d keepsakes collected · Open Collection to see your gifts." % collected if collected > 0 else "Your first gifts are waiting. Each discovery adds a keepsake to your collection."
    _future_hint.text = "%d more discoveries will appear as you progress." % hidden_count if hidden_count > 0 else ("Every keepsake collected. What an adventure!" if collected == available else "Keep exploring to complete your collection.")
    if not newly_earned.is_empty():
        _unlock_notice.text = "Keepsake unlocked · " + ", ".join(newly_earned)
        _unlock_notice.add_theme_color_override("font_color", _accent)
        _notice_remaining = 7.0
        _unlock_notice.show()
    _earned_ids = now_earned
    _has_snapshot = true
    var key := JSON.stringify(achievements)
    if key == _collection_key:
        return
    _collection_key = key
    _clear_rewards()
    for achievement: Dictionary in achievements:
        _build_reward(achievement)

static func validate_summary(data: Variant) -> String:
    if not data is Dictionary:
        return "Progress is unavailable."
    for field in ["seconds", "achievements", "supported", "detectionStatus", "detectionMessage", "legacyPreserved", "collected", "totalRewards", "gameXp", "totalXp", "level", "levelProgress"]:
        if not data.has(field):
            return "The progress response was incomplete."
    if not data.achievements is Array or not data.supported is bool or not data.legacyPreserved is bool:
        return "The progress response was unsupported."
    if not str(data.detectionStatus) in ["watching", "waiting", "unsupported", "unavailable"]:
        return "The progress response was unsupported."
    var achievements: Array = data.achievements
    if int(data.totalRewards) != achievements.size() or int(data.collected) < 0 or int(data.collected) > achievements.size() or (data.supported and achievements.size() not in [4, ACHIEVEMENT_IDS.size()]) or (not data.supported and not achievements.is_empty()):
        return "The progress response was inconsistent."
    var seen := {}
    var earned := 0
    for achievement in achievements:
        if not achievement is Dictionary:
            return "The achievement response was incomplete."
        for field in ["id", "title", "description", "xp", "earned", "artIndex"]:
            if not achievement.has(field):
                return "The achievement response was incomplete."
        var id := str(achievement.id)
        if not id in ACHIEVEMENT_IDS or seen.has(id) or not achievement.earned is bool or int(achievement.xp) < 0 or int(achievement.artIndex) != ACHIEVEMENT_IDS.find(id) + 4:
            return "The achievement response was unsupported."
        if achievement.has("revealed") and not achievement.revealed is bool:
            return "The achievement response was unsupported."
        if achievement.has("rewardTitle") and not achievement.rewardTitle is String:
            return "The achievement response was unsupported."
        seen[id] = true
        earned += 1 if achievement.earned else 0
    if earned != int(data.collected):
        return "The progress response was inconsistent."
    return ""

func _clear_rewards() -> void:
    for child in _reward_grid.get_children():
        _reward_grid.remove_child(child)
        child.queue_free()

func _build_reward(achievement: Dictionary) -> void:
    var index := int(achievement.artIndex)
    var unlocked := bool(achievement.earned)
    if not unlocked and not bool(achievement.get("revealed", true)):
        return
    var art: Texture2D = _reward_textures[index] if index < _reward_textures.size() else null
    var art_direction := JourneyTheme.card(_theme_data, str(achievement.id)) if art != null else {}
    var card_accent := Color(art_direction.get("accent", _accent.to_html(false)))
    var card := PanelContainer.new()
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.add_theme_stylebox_override("panel", _panel_style(card_accent.darkened(0.86) if unlocked else Color("17212c"), card_accent.darkened(0.4) if unlocked else card_accent.darkened(0.67), 14, 10))
    _reward_grid.add_child(card)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 7)
    card.add_child(column)
    var stamp := RewardStamp.new()
    stamp.accent = card_accent
    stamp.earned = unlocked
    stamp.symbol = index
    stamp.artwork = art
    stamp.pixel_art = _theme_data.get("artStyle") == "pixel"
    stamp.custom_minimum_size = Vector2(88, 132 if stamp.artwork != null else 38)
    stamp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_child(stamp)
    var title := str(achievement.get("rewardTitle", art_direction.get("rewardName", _gift_names[index] if stamp.artwork != null and index < _gift_names.size() else achievement.title)))
    var caption := _text(column, title, 14, INK if unlocked else MUTED)
    caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    caption.custom_minimum_size.y = 34
    var status := _text(column, "COLLECTED" if unlocked else "EARN IN GAME · +%d XP" % int(achievement.xp), 10, card_accent if unlocked else MUTED)
    status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    card.tooltip_text = str(achievement.description) + " · %d XP" % int(achievement.xp)
    card.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _text(parent: Node, content: String, font_size: int, color := INK) -> Label:
    var label := Label.new()
    label.text = content
    label.add_theme_font_size_override("font_size", maxi(12, font_size))
    label.add_theme_color_override("font_color", color)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label

func _tab(parent: Node, caption: String) -> Button:
    var button := Button.new()
    button.focus_mode = Control.FOCUS_NONE
    button.text = caption
    button.toggle_mode = true
    button.custom_minimum_size.y = 38
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_theme_font_size_override("font_size", 14)
    for state in ["normal", "hover", "pressed", "focus"]:
        button.add_theme_stylebox_override(state, _panel_style(Color("263343") if state in ["pressed", "hover"] else Color("151f2b"), Color("a0bbce") if state == "focus" else Color("344251"), 9, 8))
    parent.add_child(button)
    return button

func _progress(parent: Node, height: int) -> ProgressBar:
    var bar := ProgressBar.new()
    bar.show_percentage = false
    bar.custom_minimum_size.y = height
    _style_progress(bar)
    parent.add_child(bar)
    return bar

func _style_progress(bar: ProgressBar) -> void:
    var background := StyleBoxFlat.new()
    background.bg_color = Color("293947")
    background.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("background", background)
    var fill := StyleBoxFlat.new()
    fill.bg_color = _accent
    fill.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("fill", fill)

func _panel_style(background: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = background
    style.border_color = border
    style.set_border_width_all(1 if border.a > 0 else 0)
    style.set_corner_radius_all(radius)
    style.set_content_margin_all(margin)
    return style
