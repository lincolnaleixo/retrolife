extends PanelContainer

const TARGETS := [60, 600, 1800, 3600]
const TIME_NAMES := ["First adventure", "Finding your rhythm", "Half-hour explorer", "One-hour companion"]
const PERSONAL_IDS := ["first_stage", "secret", "boss", "finale"]
const PERSONAL_NAMES := ["Finish a stage", "Discover a secret", "Defeat a boss", "Finish the adventure"]
const GIFTS := ["First-light badge", "Explorer pin", "Adventure ticket", "Golden hour trophy", "Stage star", "Secret compass", "Boss crown", "Victory gift"]
var backend: Node
var game_id := ""
var _level: Label
var _xp: ProgressBar
var _summary: Label
var _time: Label
var _quest: Label
var _quest_progress: ProgressBar
var _collection: VBoxContainer
var _personal_buttons: Array[CheckBox] = []
var _timer := 0.0
var _collection_key := ""
var _error: Label
var _gift_tab: Button
var _profile: Dictionary = {}
var _chapter: Label
var _description: Label
var _art: TextureRect
var _accent := Color("6ae4c4")
var _gift_names: Array = GIFTS
var _quest_notes: Array[Label] = []

func _ready() -> void:
    custom_minimum_size.x = 340
    var style := StyleBoxFlat.new()
    style.bg_color = Color("101b25")
    style.border_color = Color("293e49")
    style.set_border_width_all(1)
    style.set_corner_radius_all(18)
    style.set_content_margin_all(16)
    add_theme_stylebox_override("panel", style)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(scroll)
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 9)
    scroll.add_child(column)
    _text(column, "YOUR GAME JOURNAL", 12, Color("6ae4c4"))
    _art = TextureRect.new()
    _art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    _art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _art.custom_minimum_size.y = 100
    column.add_child(_art)
    _chapter = _text(column, "Your next adventure", 22)
    _description = _text(column, "A personal journal for this game.", 12, Color("aebdcb"))
    _level = _text(column, "Level 1 · New explorer", 18)
    _xp = ProgressBar.new()
    _xp.max_value = 200
    _xp.show_percentage = false
    _style_progress(_xp)
    _xp.custom_minimum_size.y = 7
    column.add_child(_xp)
    _summary = _text(column, "0 / 200 XP to next level", 12)
    var tabs := HBoxContainer.new()
    column.add_child(tabs)
    var quests_tab := Button.new()
    quests_tab.text = "Quests"
    quests_tab.focus_mode = Control.FOCUS_NONE
    quests_tab.toggle_mode = true
    quests_tab.button_pressed = true
    quests_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tabs.add_child(quests_tab)
    _gift_tab = Button.new()
    _gift_tab.text = "Gifts · 0 / 8"
    _gift_tab.focus_mode = Control.FOCUS_NONE
    _gift_tab.toggle_mode = true
    _gift_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tabs.add_child(_gift_tab)
    var group := ButtonGroup.new()
    quests_tab.button_group = group
    _gift_tab.button_group = group
    var quests := VBoxContainer.new()
    quests.add_theme_constant_override("separation", 8)
    column.add_child(quests)
    _text(quests, "STORY CHAPTERS · 100 XP EACH", 12, Color("6ae4c4"))
    _text(quests, "Complete in the game, then check here. You can undo a check.", 12, Color("99aebb"))
    for index in range(PERSONAL_IDS.size()):
        var button := CheckBox.new()
        button.text = PERSONAL_NAMES[index]
        button.focus_mode = Control.FOCUS_NONE
        button.clip_text = true
        button.add_theme_font_size_override("font_size", 13)
        button.toggled.connect(_confirm.bind(PERSONAL_IDS[index]))
        _personal_buttons.append(button)
        quests.add_child(button)
        var note := _text(quests, "", 11, Color("99aebb"))
        _quest_notes.append(note)
    quests.add_child(HSeparator.new())
    _text(quests, "NEXT SESSION KEEPSAKE", 12, Color("6ae4c4"))
    _quest = _text(quests, "First adventure · 50 XP", 14)
    _quest_progress = ProgressBar.new()
    _quest_progress.show_percentage = false
    _style_progress(_quest_progress)
    _quest_progress.custom_minimum_size.y = 7
    quests.add_child(_quest_progress)
    _time = _text(quests, "0 minutes played", 12)
    _text(quests, "Emulated time only. Pauses do not count.", 11, Color("99aebb"))
    _collection = VBoxContainer.new()
    _collection.add_theme_constant_override("separation", 8)
    column.add_child(_collection)
    _collection.hide()
    quests_tab.pressed.connect(func(): quests.show(); _collection.hide())
    _gift_tab.pressed.connect(func(): quests.hide(); _collection.show())
    _error = _text(column, "", 12, Color("ffa494"))
    _error.hide()

func configure(node: Node, id: String, title: String) -> void:
    backend = node
    game_id = id
    _collection_key = ""
    _profile = preload("res://scripts/workspace/collection_profiles.gd").for_game(title)
    _accent = Color(_profile.get("color", "6ae4c4"))
    _chapter.text = str(_profile.get("chapter", title))
    _chapter.add_theme_color_override("font_color", _accent)
    _description.text = str(_profile.get("subtitle", "A personal journey through " + title + ". Keep the moments that matter."))
    _gift_names = _profile.get("gifts", GIFTS)
    var base: String = preload("res://scripts/workspace/collection_profiles.gd").asset_base(_profile)
    _art.texture = preload("res://scripts/workspace/preferences.gd").image(base + "/journey/cover.png") if not base.is_empty() else null
    if _art.texture == null and not base.is_empty():
        _art.texture = preload("res://scripts/workspace/preferences.gd").image(base + "/box/hero.png")
    _art.visible = _art.texture != null
    _style_progress(_xp)
    _style_progress(_quest_progress)
    var captions: Array = _profile.get("quests", PERSONAL_NAMES)
    var notes: Array = _profile.get("notes", ["Complete this in the game, then mark it here.", "Explore an optional path or hidden reward.", "Overcome a memorable challenge.", "Reach the end of this adventure."])
    for index in range(captions.size()):
        _personal_buttons[index].text = "%02d  %s" % [index + 1, captions[index]]
        _personal_buttons[index].tooltip_text = str(notes[index])
        _quest_notes[index].text = str(notes[index])
    refresh()

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
    if backend == null or game_id.is_empty():
        return
    var response: Variant = JSON.parse_string(str(backend.call("journey_confirm_json", game_id, milestone, done)))
    _render_response(response)
    if response is Dictionary and not bool(response.get("ok", false)):
        # Reload the committed state; never leave a failed reward checked.
        refresh()
        _error.text = str(response.get("error", "The challenge could not be saved."))
        _error.show()

func _render_response(response: Variant) -> void:
    if not response is Dictionary or not bool(response.get("ok", false)):
        _error.text = str(response.get("error", "Progress is unavailable.")) if response is Dictionary else "Progress is unavailable."
        _error.show()
        return
    _error.hide()
    var data: Dictionary = response.get("data", {})
    var level := int(data.get("level", 1))
    _level.text = "Level %d · %s" % [level, "New explorer" if level == 1 else "World explorer"]
    _xp.value = int(data.get("levelProgress", 0))
    _summary.text = "%d / 200 XP · %d total XP" % [int(_xp.value), int(data.get("totalXp", 0))]
    _gift_tab.text = "Gifts · %d / 8" % int(data.get("collected", 0))
    var seconds := int(data.get("seconds", 0))
    _time.text = "%dh %02dm played · This game" % [seconds / 3600, (seconds / 60) % 60]
    var earned := int(data.get("earnedTime", 0))
    if earned < TARGETS.size():
        _quest.text = "%s · 50 XP\n%02d:%02d / %02d:00" % [_gift_names[earned], seconds / 60, seconds % 60, TARGETS[earned] / 60]
        _quest_progress.max_value = TARGETS[earned]
        _quest_progress.value = seconds
    else:
        _quest.text = "All session quests collected"
        _quest_progress.max_value = 1
        _quest_progress.value = 1
    var personal: Array = data.get("personal", [])
    for index in range(PERSONAL_IDS.size()):
        _personal_buttons[index].set_pressed_no_signal(personal.has(PERSONAL_IDS[index]))
    var key := str(earned) + str(personal)
    if key == _collection_key:
        return
    _collection_key = key
    for child in _collection.get_children():
        child.queue_free()
    _text(_collection, "%d / 8 collected · %d still to discover" % [int(data.get("collected", 0)), 8 - int(data.get("collected", 0))], 13)
    for index in range(GIFTS.size()):
        var unlocked: bool = index < earned if index < 4 else personal.has(PERSONAL_IDS[index - 4])
        var card := PanelContainer.new()
        var style := StyleBoxFlat.new()
        style.bg_color = Color("20382f") if unlocked else Color("18222e")
        style.border_color = _accent if unlocked else Color("344152")
        style.set_border_width_all(1)
        style.set_corner_radius_all(9)
        style.set_content_margin_all(10)
        card.add_theme_stylebox_override("panel", style)
        _collection.add_child(card)
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        card.add_child(row)
        var stamp := preload("res://scripts/workspace/reward_stamp.gd").new()
        stamp.accent = _accent
        stamp.earned = unlocked
        stamp.symbol = index
        row.add_child(stamp)
        var caption := _text(row, str(_gift_names[index]) + ("\nCollected" if unlocked else "\nStill to discover"), 13, _accent if unlocked else Color("9caabc"))
        caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _text(parent: Node, content: String, font_size: int, color := Color("eaf2f6")) -> Label:
    var label := Label.new()
    label.text = content
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    parent.add_child(label)
    return label


func _style_progress(bar: ProgressBar) -> void:
    var background := StyleBoxFlat.new()
    background.bg_color = Color("293e49")
    background.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("background", background)
    var fill := StyleBoxFlat.new()
    fill.bg_color = _accent
    fill.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("fill", fill)
