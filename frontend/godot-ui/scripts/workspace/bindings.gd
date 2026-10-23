extends RefCounted

const PATH := "user://controller-bindings.cfg"
const ACTIONS := ["up", "down", "left", "right", "south", "east", "west", "north", "left_shoulder", "right_shoulder", "select", "start"]
const LABELS := ["Up", "Down", "Left", "Right", "B", "A", "Y", "X", "L", "R", "Select", "Start"]
static var defaults: Dictionary = {}

static func snapshot() -> Dictionary:
    var result := {}
    for action in ACTIONS:
        result[action] = InputMap.action_get_events("game_" + action)
    return result

static func restore(bindings: Dictionary) -> void:
    for action in ACTIONS:
        Input.action_release("game_" + action)
        InputMap.action_erase_events("game_" + action)
        for event in bindings.get(action, []):
            InputMap.action_add_event("game_" + action, event)

static func is_gamepad(event: InputEvent) -> bool:
    return event is InputEventJoypadButton or event is InputEventJoypadMotion

static func clear_kind(gamepad: bool) -> void:
    for action in ACTIONS:
        for event in InputMap.action_get_events("game_" + action):
            if is_gamepad(event) == gamepad:
                InputMap.action_erase_event("game_" + action, event)

static func caption(action: String, gamepad: bool) -> String:
    var names: PackedStringArray = []
    for event in InputMap.action_get_events("game_" + action):
        if is_gamepad(event) == gamepad:
            if event is InputEventJoypadMotion:
                names.append("Axis %d %s" % [event.axis, "+" if event.axis_value > 0 else "−"])
            elif event is InputEventJoypadButton:
                names.append("Button %d" % event.button_index)
            else:
                var name := event.as_text().replace(" (Physical)", "")
                if not _reserved_shortcut(event).is_empty():
                    name += " (reserved; remap)"
                names.append(name)
    return " / ".join(names) if not names.is_empty() else "Not mapped"

static func _reserved_shortcut(event: InputEvent) -> String:
    if event is InputEventKey:
        for key in [event.keycode, event.physical_keycode]:
            match key:
                KEY_F8:
                    return "F8 is reserved for Shaders."
                KEY_F9:
                    return "F9 is reserved for Game settings."
                KEY_F11:
                    return "F11 is reserved for Fullscreen."
    return ""

static func assign(action: String, event: InputEvent) -> String:
    var reserved := _reserved_shortcut(event)
    if not reserved.is_empty():
        return reserved + " Choose another key; existing shortcut bindings can be remapped here."
    var normalized: InputEvent = event.duplicate()
    normalized.device = -1
    if normalized is InputEventJoypadMotion:
        normalized.axis_value = signf(normalized.axis_value)
    if normalized is InputEventKey:
        normalized.pressed = false
        normalized.echo = false
    for other in ACTIONS:
        if other != action and InputMap.event_is_action(normalized, "game_" + other, true):
            return "Already assigned to %s. Use Guided setup to change the layout." % LABELS[ACTIONS.find(other)]
    for previous in InputMap.action_get_events("game_" + action):
        if is_gamepad(previous) == is_gamepad(normalized):
            InputMap.action_erase_event("game_" + action, previous)
    InputMap.action_add_event("game_" + action, normalized)
    return ""

static func save(path := PATH) -> Error:
    var config := ConfigFile.new()
    for action in ACTIONS:
        var events: Array = []
        for event in InputMap.action_get_events("game_" + action):
            if event is InputEventKey:
                events.append({"kind": "key", "key": event.keycode, "physical": event.physical_keycode})
            elif event is InputEventJoypadButton:
                events.append({"kind": "button", "button": event.button_index})
            elif event is InputEventJoypadMotion:
                events.append({"kind": "axis", "axis": event.axis, "sign": signf(event.axis_value)})
        config.set_value("bindings", action, events)
    var error := config.save(path + ".tmp")
    if error != OK:
        return error
    return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))

static func load_saved(path := PATH) -> void:
    if defaults.is_empty():
        defaults = snapshot()
    var config := ConfigFile.new()
    if config.load(path) != OK:
        return
    var loaded := {}
    for action in ACTIONS:
        var values: Variant = config.get_value("bindings", action, null)
        if not values is Array or values.size() > 12:
            return
        var events: Array[InputEvent] = []
        for value in values:
            if not value is Dictionary:
                return
            var event: InputEvent
            match value.get("kind", ""):
                "key":
                    event = InputEventKey.new()
                    event.keycode = int(value.get("key", 0))
                    event.physical_keycode = int(value.get("physical", 0))
                    if event.keycode == 0 and event.physical_keycode == 0:
                        return
                "button":
                    event = InputEventJoypadButton.new()
                    event.button_index = int(value.get("button", -1))
                    if event.button_index < 0 or event.button_index >= JOY_BUTTON_MAX:
                        return
                "axis":
                    event = InputEventJoypadMotion.new()
                    event.axis = int(value.get("axis", -1))
                    event.axis_value = float(value.get("sign", 0))
                    if event.axis < 0 or event.axis >= JOY_AXIS_MAX or absf(event.axis_value) != 1:
                        return
                _:
                    return
            event.device = -1
            events.append(event)
        loaded[action] = events
    restore(loaded)
