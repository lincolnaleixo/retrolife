extends PopupPanel

const Bindings = preload("res://scripts/workspace/bindings.gd")
const Preferences = preload("res://scripts/workspace/preferences.gd")
const ModelView = preload("res://scripts/workspace/model_view.gd")
var model_view: SubViewportContainer
var _status: Label
var _device: Label
var _hint: Label
var _buttons: Array[Button] = []
var _mode: OptionButton
var _pending := ""
var _guided := false
var _backup: Dictionary = {}
var _remaining := 0.0
var _model_path := ""

func _ready() -> void:
    var popup_theme := Theme.new()
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color("141b27")
    panel_style.border_color = Color("3b5061")
    panel_style.set_border_width_all(1)
    panel_style.set_corner_radius_all(18)
    popup_theme.set_stylebox("panel", "PopupPanel", panel_style)
    theme = popup_theme
    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 22)
    add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    margin.add_child(column)
    var title := Label.new()
    title.text = "Make the controller yours"
    title.add_theme_font_size_override("font_size", 26)
    column.add_child(title)
    _device = Label.new()
    column.add_child(_device)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 24)
    column.add_child(row)
    var preview := VBoxContainer.new()
    preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(preview)
    model_view = ModelView.new()
    model_view.custom_minimum_size = Vector2(420, 300)
    model_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    preview.add_child(model_view)
    _hint = Label.new()
    _hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    preview.add_child(_hint)
    var reset_view := Button.new()
    reset_view.text = "Reset view"
    reset_view.pressed.connect(model_view.reset_view)
    preview.add_child(reset_view)
    var mapping := VBoxContainer.new()
    mapping.custom_minimum_size.x = 320
    row.add_child(mapping)
    _mode = OptionButton.new()
    _mode.add_item("Gamepad bindings")
    _mode.add_item("Keyboard bindings")
    _mode.item_selected.connect(func(_index: int): _cancel(); _refresh())
    mapping.add_child(_mode)
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(320, 320)
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    mapping.add_child(scroll)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(grid)
    for index in range(Bindings.ACTIONS.size()):
        var label := Label.new()
        label.text = Bindings.LABELS[index]
        label.custom_minimum_size.x = 60
        grid.add_child(label)
        var button := Button.new()
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.custom_minimum_size.y = 30
        button.pressed.connect(_capture.bind(Bindings.ACTIONS[index]))
        grid.add_child(button)
        _buttons.append(button)
    _status = Label.new()
    _status.custom_minimum_size.y = 42
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_status)
    var actions := HBoxContainer.new()
    column.add_child(actions)
    for definition in [["Guided setup", _start_guided], ["Restore defaults", _reset], ["Done", hide]]:
        var button := Button.new()
        button.text = definition[0]
        button.pressed.connect(definition[1])
        actions.add_child(button)
    popup_hide.connect(_cancel)
    about_to_popup.connect(_open)
    Input.joy_connection_changed.connect(func(_id: int, connected: bool):
        if not connected:
            _cancel()
        _refresh()
    )

func _open() -> void:
    var path := Preferences.asset("controllers/snes/snes-controller.glb")
    if path != _model_path or model_view.model == null:
        model_view.load_model(path)
        _model_path = path
    _hint.text = model_view.message + "\nSNES / SNS-005 · Target buttons match the original controller."
    _status.text = "Select a button or follow Guided setup. Esc cancels capture."
    _refresh()

func _refresh() -> void:
    var devices: PackedStringArray = []
    for id in Input.get_connected_joypads():
        devices.append(Input.get_joy_name(id))
    _device.text = "No gamepad connected · Keyboard is available" if devices.is_empty() else "Connected: " + ", ".join(devices)
    for index in range(_buttons.size()):
        _buttons[index].text = Bindings.caption(Bindings.ACTIONS[index], _mode.selected == 0)

func _capture(action: String) -> void:
    if not _guided:
        _backup = Bindings.snapshot()
    _pending = action
    _remaining = 15
    model_view.reset_view()
    model_view.highlight(action)
    _status.text = "Press %s on your %s. Esc cancels · 15 seconds" % [Bindings.LABELS[Bindings.ACTIONS.find(action)], "gamepad" if _mode.selected == 0 else "keyboard"]

func _start_guided() -> void:
    _cancel()
    _backup = Bindings.snapshot()
    _guided = true
    Bindings.clear_kind(_mode.selected == 0)
    _capture(Bindings.ACTIONS[0])
    _refresh()

func _cancel() -> void:
    if not _pending.is_empty() and not _backup.is_empty():
        Bindings.restore(_backup)
    _pending = ""
    _guided = false
    if model_view != null:
        model_view.highlight("")
    if _status != null:
        _status.text = "Setup cancelled. Previous bindings restored."
    if _mode != null:
        _refresh()

func _reset() -> void:
    _cancel()
    var previous := Bindings.snapshot()
    Bindings.restore(Bindings.defaults)
    if Bindings.save() != OK:
        Bindings.restore(previous)
        _status.text = "Could not save. Previous bindings restored."
    else:
        _status.text = "Default bindings restored."
    _refresh()

func _process(delta: float) -> void:
    if _pending.is_empty():
        return
    _remaining -= delta
    if _remaining <= 0:
        _cancel()
        _status.text = "Capture timed out. Previous bindings restored."

func _input(event: InputEvent) -> void:
    if not visible or _pending.is_empty():
        return
    if event is InputEventMouse:
        return
    get_viewport().set_input_as_handled()
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        _cancel()
        return
    if _mode.selected == 0 and not Bindings.is_gamepad(event):
        return
    if _mode.selected == 1 and not event is InputEventKey:
        return
    if event is InputEventJoypadMotion:
        if absf(event.axis_value) < 0.75:
            return
    elif not event.is_pressed() or (event is InputEventKey and event.echo):
        return
    if event.is_action("game_pause"):
        _status.text = "That input is reserved for Pause. Choose another."
        return
    var error := Bindings.assign(_pending, event)
    if not error.is_empty():
        _status.text = error
        return
    var index := Bindings.ACTIONS.find(_pending)
    if _guided and index + 1 < Bindings.ACTIONS.size():
        _capture(Bindings.ACTIONS[index + 1])
    else:
        if Bindings.save() != OK:
            _cancel()
            _status.text = "Could not save. Previous bindings restored."
            return
        _pending = ""
        _guided = false
        model_view.highlight("")
        _status.text = "Saved. These bindings are active in gameplay."
    _refresh()
