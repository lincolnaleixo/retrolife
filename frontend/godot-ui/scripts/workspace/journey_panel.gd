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
var _smw := false

func _ready() -> void:
    custom_minimum_size.x = 290
    var style := StyleBoxFlat.new()
    style.bg_color = Color("101b25")
    style.border_color = Color("293e49")
    style.set_border_width_all(1)
    style.set_corner_radius_all(18)
    for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
        style.set_content_margin(side, 18)
    add_theme_stylebox_override("panel", style)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(scroll)
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 12)
    scroll.add_child(column)
    _text(column, "YOUR JOURNEY", 12, Color("6ae4c4"))
    _level = _text(column, "Level 1 · New explorer", 23)
    _xp = ProgressBar.new()
    _xp.max_value = 200
    _xp.show_percentage = false
    _style_progress(_xp)
    _xp.custom_minimum_size.y = 7
    column.add_child(_xp)
    _summary = _text(column, "0 / 200 XP to next level", 13)
    _time = _text(column, "0 minutes played", 13)
    column.add_child(HSeparator.new())
    _text(column, "NEXT SESSION QUEST", 12, Color("6ae4c4"))
    _quest = _text(column, "First adventure · 50 XP", 17)
    _quest_progress = ProgressBar.new()
    _quest_progress.show_percentage = false
    _style_progress(_quest_progress)
    _quest_progress.custom_minimum_size.y = 8
    column.add_child(_quest_progress)
    _text(column, "Session quests track emulated time. Pauses do not count.", 12, Color("99aebb"))
    column.add_child(HSeparator.new())
    _text(column, "PERSONAL CHALLENGES · 100 XP EACH", 12, Color("6ae4c4"))
    _text(column, "Confirm these yourself after completing them in the game. You can undo a check.", 12, Color("99aebb"))
    for index in range(PERSONAL_IDS.size()):
        var button := CheckBox.new()
        button.text = PERSONAL_NAMES[index]
        button.focus_mode = Control.FOCUS_NONE
        button.add_theme_font_size_override("font_size", 14)
        button.toggled.connect(_confirm.bind(PERSONAL_IDS[index]))
        _personal_buttons.append(button)
        column.add_child(button)
    column.add_child(HSeparator.new())
    _text(column, "REWARD COLLECTION", 12, Color("6ae4c4"))
    _collection = VBoxContainer.new()
    _collection.add_theme_constant_override("separation", 7)
    column.add_child(_collection)
    _error = _text(column, "", 12, Color("ffa494"))
    _error.hide()

func configure(node: Node, id: String, title: String) -> void:
    backend = node
    game_id = id
    _collection_key = ""
    _smw = title.to_lower().contains("super mario world")
    var captions := ["Clear a Yoshi's Island stage", "Find a secret exit", "Beat a Koopaling", "Rescue Princess Peach"] if _smw else PERSONAL_NAMES
    for index in range(captions.size()):
        _personal_buttons[index].text = captions[index]
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
    _level.text = "Level %d · %s" % [level, "New explorer" if level == 1 else "Adventure collector"]
    _xp.value = int(data.get("levelProgress", 0))
    _summary.text = "%d / 200 XP · %d total XP\n%d / 8 rewards in this game" % [int(_xp.value), int(data.get("totalXp", 0)), int(data.get("collected", 0))]
    var seconds := int(data.get("seconds", 0))
    _time.text = "%dh %02dm played · This game" % [seconds / 3600, (seconds / 60) % 60]
    var earned := int(data.get("earnedTime", 0))
    if earned < TARGETS.size():
        _quest.text = "%s · 50 XP\n%02d:%02d / %02d:00" % [TIME_NAMES[earned], seconds / 60, seconds % 60, TARGETS[earned] / 60]
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
        _text(_collection, ("◆  " if unlocked else "◇  ") + GIFTS[index], 13, Color("6ae4c4") if unlocked else Color("6b7b8c"))

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
    fill.bg_color = Color("6ae4c4")
    fill.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("fill", fill)
