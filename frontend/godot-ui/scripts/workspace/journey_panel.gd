extends PanelContainer

const Profiles = preload("res://scripts/workspace/collection_profiles.gd")
const Preferences = preload("res://scripts/workspace/preferences.gd")
const RewardStamp = preload("res://scripts/workspace/reward_stamp.gd")
const TARGETS := [60, 600, 1800, 3600]
const TIME_NAMES := ["First adventure", "Finding your rhythm", "Half-hour explorer", "One-hour companion"]
const PERSONAL_IDS := ["first_stage", "secret", "boss", "finale"]
const PERSONAL_NAMES := ["Finish a stage", "Discover a secret", "Defeat a boss", "Finish the adventure"]
const GIFTS := ["First-light badge", "Explorer pin", "Adventure ticket", "Golden hour trophy", "Stage star", "Secret compass", "Boss crown", "Victory gift"]
const INK := Color("eaf0f5")
const MUTED := Color("9baebc")

var backend: Node
var game_id := ""
var _level: Label
var _xp: ProgressBar
var _summary: Label
var _time: Label
var _quest: Label
var _quest_progress: ProgressBar
var _collection: VBoxContainer
var _collection_progress: ProgressBar
var _collection_summary: Label
var _reward_grid: GridContainer
var _personal_buttons: Array[CheckBox] = []
var _chapter_titles: Array[Label] = []
var _chapter_cards: Array[PanelContainer] = []
var _chapter_icons: Array[TextureRect] = []
var _chapter_numbers: Array[Label] = []
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
    _cover_frame.custom_minimum_size.y = 190
    _cover_frame.clip_contents = true
    _cover_frame.add_theme_stylebox_override("panel", _panel_style(Color("1b2835"), Color.TRANSPARENT, 12, 0))
    column.add_child(_cover_frame)
    _art = TextureRect.new()
    _art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    _art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
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
    var tabs := HBoxContainer.new()
    tabs.add_theme_constant_override("separation", 6)
    column.add_child(tabs)
    _quests_tab = _tab(tabs, "Chapters")
    _quests_tab.button_pressed = true
    _gift_tab = _tab(tabs, "Collection · 0/8")
    var group := ButtonGroup.new()
    _quests_tab.button_group = group
    _gift_tab.button_group = group
    _quests = VBoxContainer.new()
    _quests.add_theme_constant_override("separation", 10)
    column.add_child(_quests)
    _text(_quests, "YOUR STORY · 100 XP PER CHAPTER", 10, MUTED)
    for index in PERSONAL_IDS.size():
        _build_chapter(index)
    _text(_quests, "Mark moments you completed in the game. Every check can be undone.", 11, MUTED)
    var session_card := PanelContainer.new()
    session_card.add_theme_stylebox_override("panel", _panel_style(Color("192832"), Color("2b3c47"), 12, 13))
    _quests.add_child(session_card)
    var session := VBoxContainer.new()
    session.add_theme_constant_override("separation", 8)
    session_card.add_child(session)
    _text(session, "NEXT KEEPSAKE · 50 XP", 10, MUTED)
    _quest = _text(session, "First adventure", 14)
    _quest_progress = _progress(session, 6)
    _time = _text(session, "0 minutes played", 11, MUTED)
    _text(session, "Emulated time only. Pauses do not count.", 10, MUTED)
    _collection = VBoxContainer.new()
    _collection.add_theme_constant_override("separation", 12)
    column.add_child(_collection)
    _collection_summary = _text(_collection, "A little collection of big moments.", 13)
    _collection_progress = _progress(_collection, 5)
    _collection_progress.max_value = 8
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
    icon.custom_minimum_size = Vector2(42, 42)
    icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(icon)
    _chapter_icons.append(icon)
    var number := _text(row, "%02d" % [index + 1], 18, MUTED)
    number.custom_minimum_size.x = 28
    number.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _chapter_numbers.append(number)
    var copy := VBoxContainer.new()
    copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    copy.add_theme_constant_override("separation", 4)
    row.add_child(copy)
    _chapter_titles.append(_text(copy, PERSONAL_NAMES[index], 15))
    _quest_notes.append(_text(copy, "", 13, MUTED))
    var button := CheckBox.new()
    # The live game keeps keyboard/gamepad focus while the journal is clicked.
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(26, 32)
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    button.accessibility_name = PERSONAL_NAMES[index]
    button.toggled.connect(_confirm.bind(PERSONAL_IDS[index]))
    _personal_buttons.append(button)
    row.add_child(button)

func configure(node: Node, id: String, title: String, system := "") -> void:
    backend = node
    game_id = id
    _timer = 0.0
    _collection_key = ""
    _profile = Profiles.for_game(title, system)
    _accent = Color(_profile.get("color", "8eb5ca"))
    _world.text = str(_profile.get("title", title)).to_upper() + " · JOURNAL"
    _world.add_theme_color_override("font_color", _accent)
    _chapter.text = str(_profile.get("chapter", "Your personal journey"))
    _description.text = str(_profile.get("subtitle", "Keep the moments that matter, one chapter at a time."))
    _gift_names = _profile.get("gifts", GIFTS)
    var unchecked := _check_icon(false)
    var checked := _check_icon(true)
    for button in _personal_buttons:
        button.add_theme_icon_override("unchecked", unchecked)
        button.add_theme_icon_override("checked", checked)
    _art_cache.clear()
    _chapter_textures.clear()
    _reward_textures.clear()
    var base := Profiles.asset_base(_profile)
    var journey := base + "/journey/" if not base.is_empty() else ""
    _art.texture = _load_art(journey + "cover.png") if not journey.is_empty() else null
    _cover_frame.visible = _art.texture != null
    _art.visible = _art.texture != null
    for index in PERSONAL_IDS.size():
        _chapter_textures.append(_load_art(journey + "chapters/" + PERSONAL_IDS[index] + ".svg") if not journey.is_empty() else null)
    for index in GIFTS.size():
        _reward_textures.append(_load_art(journey + "rewards/%02d.svg" % [index + 1]) if not journey.is_empty() else null)
    var captions: Array = _profile.get("quests", PERSONAL_NAMES)
    var notes: Array = _profile.get("notes", ["Complete a stage and mark your first milestone.", "Explore an optional path or hidden reward.", "Overcome a memorable challenge.", "Reach the end of this adventure."])
    for index in PERSONAL_IDS.size():
        var caption: String = str(captions[index]) if index < captions.size() else PERSONAL_NAMES[index]
        var note := str(notes[index]) if index < notes.size() else "Complete this in the game, then mark it here."
        _chapter_titles[index].text = caption
        _personal_buttons[index].accessibility_name = caption
        _personal_buttons[index].tooltip_text = "Mark complete or undo · " + note
        _quest_notes[index].text = note
        _chapter_icons[index].texture = _chapter_textures[index]
        _chapter_icons[index].visible = _chapter_textures[index] != null
        _chapter_numbers[index].visible = _chapter_textures[index] == null
        _personal_buttons[index].set_pressed_no_signal(false)
    for bar in [_xp, _quest_progress, _collection_progress]:
        _style_progress(bar)
    _quests_tab.button_pressed = true
    _quests.show()
    _collection.hide()
    _scroll.scroll_vertical = 0
    _render_response({"ok": true, "data": {}})
    refresh()

func _art_path(relative: String) -> String:
    return Preferences.asset(relative)

func _check_icon(checked: bool) -> Texture2D:
    var background := "#" + _accent.to_html(false) if checked else "#15232e"
    var stroke := background if checked else "#9badbd"
    var mark := '<path d="M4.5 9l3 3 6-6" fill="none" stroke="#10211b" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' if checked else ""
    var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18"><rect x="1" y="1" width="16" height="16" rx="4" fill="%s" stroke="%s" stroke-width="1.5"/>%s</svg>' % [background, stroke, mark]
    var pixels := Image.new()
    if pixels.load_svg_from_string(svg) != OK:
        return null
    return ImageTexture.create_from_image(pixels)

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

func _process(delta: float) -> void:
    if not is_visible_in_tree() or game_id.is_empty():
        return
    _timer += delta
    if _timer >= 1:
        _timer = 0
        refresh()

func refresh() -> void:
    if backend == null or not backend.has_method("journey_state_json") or game_id.is_empty():
        return
    _render_response(JSON.parse_string(str(backend.call("journey_state_json", game_id))))

func _confirm(done: bool, milestone: String) -> void:
    if backend == null or game_id.is_empty() or not backend.has_method("journey_confirm_json"):
        refresh()
        return
    var response: Variant = JSON.parse_string(str(backend.call("journey_confirm_json", game_id, milestone, done)))
    _render_response(response)
    if not response is Dictionary or not bool(response.get("ok", false)):
        # Restore committed state after a failed write; checking never creates XP locally.
        refresh()
        _error.text = str(response.get("error", "The chapter could not be saved.")) if response is Dictionary else "The chapter could not be saved."
        _error.show()

func _render_response(response: Variant) -> void:
    if not response is Dictionary or not bool(response.get("ok", false)):
        _error.text = str(response.get("error", "Progress is unavailable.")) if response is Dictionary else "Progress is unavailable."
        _error.show()
        return
    _error.hide()
    var data: Dictionary = response.get("data", {})
    var level := int(data.get("level", 1))
    _level.text = "LEVEL %d" % level
    _xp.value = int(data.get("levelProgress", 0))
    _summary.text = "%d / 200 XP" % int(_xp.value)
    _summary.tooltip_text = "%d total XP" % int(data.get("totalXp", 0))
    var collected := int(data.get("collected", 0))
    _gift_tab.text = "Collection · %d/8" % collected
    _collection_summary.text = "%d of 8 keepsakes collected" % collected
    _collection_progress.value = collected
    var seconds := int(data.get("seconds", 0))
    _time.text = "%dh %02dm played · This game" % [seconds / 3600, (seconds / 60) % 60]
    var earned := clampi(int(data.get("earnedTime", 0)), 0, TARGETS.size())
    if earned < TARGETS.size():
        _quest.text = "%s\n%02d:%02d / %02d:00" % [_gift_names[earned], seconds / 60, seconds % 60, TARGETS[earned] / 60]
        _quest_progress.max_value = TARGETS[earned]
        _quest_progress.value = seconds
    else:
        _quest.text = "Every session keepsake collected"
        _quest_progress.max_value = 1
        _quest_progress.value = 1
    var personal: Array = data.get("personal", [])
    for index in PERSONAL_IDS.size():
        var done := personal.has(PERSONAL_IDS[index])
        _personal_buttons[index].set_pressed_no_signal(done)
        _chapter_cards[index].add_theme_stylebox_override("panel", _panel_style(_accent.darkened(0.84) if done else Color("17222d"), _accent.darkened(0.35) if done else Color("2a3947"), 12, 11))
    var key := str(earned) + str(personal)
    if key == _collection_key:
        return
    _collection_key = key
    for child in _reward_grid.get_children():
        _reward_grid.remove_child(child)
        child.queue_free()
    for index in GIFTS.size():
        _build_reward(index, index < earned if index < 4 else personal.has(PERSONAL_IDS[index - 4]))

func _build_reward(index: int, unlocked: bool) -> void:
    var card := PanelContainer.new()
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.add_theme_stylebox_override("panel", _panel_style(_accent.darkened(0.86) if unlocked else Color("17212c"), _accent.darkened(0.4) if unlocked else Color("2b3745"), 12, 10))
    _reward_grid.add_child(card)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 7)
    card.add_child(column)
    var stamp := RewardStamp.new()
    stamp.accent = _accent
    stamp.earned = unlocked
    stamp.symbol = index
    stamp.artwork = _reward_textures[index] if index < _reward_textures.size() else null
    stamp.custom_minimum_size = Vector2(88, 106 if stamp.artwork != null else 38)
    stamp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_child(stamp)
    var caption := _text(column, str(_gift_names[index]), 14, INK if unlocked else MUTED)
    caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    caption.custom_minimum_size.y = 34
    var status := _text(column, "COLLECTED" if unlocked else "LOCKED", 9, _accent if unlocked else Color("748696"))
    status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var requirement := "%d minute%s of play" % [TARGETS[index] / 60, "" if index == 0 else "s"] if index < 4 else "Complete chapter %d" % [index - 3]
    card.tooltip_text = requirement + (" · Collected" if unlocked else " · Still to discover")

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
