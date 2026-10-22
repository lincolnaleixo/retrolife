extends VBoxContainer

signal selected(system_id: String)
const Profiles = preload("res://scripts/workspace/collection_profiles.gd")
const Preferences = preload("res://scripts/workspace/preferences.gd")
const ModelView = preload("res://scripts/workspace/model_view.gd")
var allow_local_art := true
var _available: Array[String] = []
var _counts := {}
var _index := 0
var _view: SubViewportContainer
var _title: Label
var _detail: Label
var _hint: Label
var _position: Label
var _previous: Button
var _next: Button
var _open: Button
var _path := ""
var _attempted := false

func _ready() -> void:
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", 10)
    var eyebrow := _label("YOUR CONSOLES", 12, Color("78dbba"))
    add_child(eyebrow)
    _view = ModelView.new()
    _view.auto_frame = true
    _view.minimum_view_size = Vector2(300, 220)
    _view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(_view)
    _view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
    _title = _label("Your collection starts here", 32)
    add_child(_title)
    _detail = _label("Import a ROM to add its console to your collection.", 14, Color("9aa8b8"))
    add_child(_detail)
    var navigation := HBoxContainer.new()
    navigation.alignment = BoxContainer.ALIGNMENT_CENTER
    navigation.add_theme_constant_override("separation", 16)
    add_child(navigation)
    _previous = _button("←", func(): navigate(-1))
    _previous.tooltip_text = "Previous console · Left arrow"
    _previous.custom_minimum_size.x = 56
    navigation.add_child(_previous)
    _open = _button("Open collection", _open_selected)
    _open.custom_minimum_size.x = 240
    navigation.add_child(_open)
    _next = _button("→", func(): navigate(1))
    _next.tooltip_text = "Next console · Right arrow"
    _next.custom_minimum_size.x = 56
    navigation.add_child(_next)
    _position = _label("", 12, Color("78dbba"))
    add_child(_position)
    _hint = _label("", 12, Color("939eaf"))
    add_child(_hint)

func configure(systems: Array) -> void:
    var previous_id := selected_id()
    _counts.clear()
    _available.clear()
    for system in systems:
        var id := str(system.get("id", ""))
        var count := int(system.get("gameCount", 0))
        if Profiles.SYSTEMS.has(id) and count > 0:
            _counts[id] = count
    for id in Profiles.SYSTEMS:
        if _counts.has(id):
            _available.append(id)
    _index = maxi(_available.find(previous_id), 0)
    _update_selection()

func selected_id() -> String:
    return _available[_index] if not _available.is_empty() else ""

func navigate(direction: int) -> void:
    if _available.size() < 2:
        return
    _index = posmod(_index + direction, _available.size())
    _update_selection()

func handle_navigation(event: InputEvent) -> bool:
    if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
        navigate(-1 if event.is_action_pressed("ui_left") else 1)
        accept_event()
        return true
    return false

func _open_selected() -> void:
    var id := selected_id()
    if not id.is_empty():
        selected.emit(id)

func _update_selection() -> void:
    var id := selected_id()
    var empty := id.is_empty()
    _view.visible = not empty
    _open.visible = not empty
    _open.disabled = empty
    _previous.visible = _available.size() > 1
    _next.visible = _available.size() > 1
    _position.visible = _available.size() > 1
    _title.text = "Your collection starts here" if empty else Profiles.SYSTEMS[id]
    _detail.text = "Import a ROM to add its console to your collection." if empty else "%d game%s in your collection" % [_counts[id], "" if _counts[id] == 1 else "s"]
    _position.text = "%d / %d" % [_index + 1, _available.size()] if not empty else ""
    var path := Preferences.asset("consoles/%s/%s-console.glb" % [id, id]) if allow_local_art and not empty else ""
    if path != _path:
        _view.load_model("")
        _path = path
        _attempted = false
    _view.default_view = Vector2(-0.35, 0.12) if id in ["game-boy", "game-boy-advance"] else Vector2(-0.55, 0.55)
    _view.frame_scale = 1.0
    _hint.text = "" if empty else ("Drag to rotate · Scroll to zoom · Double-click to reset" if not path.is_empty() else "Link a local 3D model in Storage & assets.")

func _process(_delta: float) -> void:
    var active := is_visible_in_tree() and not _available.is_empty()
    _view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if active else SubViewport.UPDATE_DISABLED
    if active and not _attempted and not _path.is_empty():
        _attempted = true
        if not _view.load_model(_path):
            _hint.text = "3D model unavailable. Check Storage & assets."

func focus_first() -> void:
    if not _open.disabled:
        _open.grab_focus()

func _label(content: String, font_size: int, color := Color("eaf2f6")) -> Label:
    var label := Label.new()
    label.text = content
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label

func _button(caption: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = caption
    button.custom_minimum_size.y = 44
    button.pressed.connect(action)
    button.gui_input.connect(handle_navigation)
    return button
