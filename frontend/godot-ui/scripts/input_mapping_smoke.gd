extends SceneTree

## Headless contract check for the Godot-side SNES controls.
##
## The Rust smoke checks the twelve logical bridge bits. This companion check
## verifies that the playable scene exposes those actions to keyboard and
## standard gamepads, including a pause fallback that is not Guide-only.

const ACTIONS: Array[String] = [
    "game_up", "game_down", "game_left", "game_right",
    "game_south", "game_east", "game_west", "game_north",
    "game_left_shoulder", "game_right_shoulder", "game_start", "game_select",
]


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
    if main_scene == null:
        _fail("Main scene could not be loaded")
        return
    var main: Node = main_scene.instantiate()
    root.add_child(main)
    await process_frame

    for action in ACTIONS:
        if not InputMap.has_action(action):
            _fail("missing input action: %s" % action)
            return

    var expected_keys := {
        "game_south": KEY_X,
        "game_east": KEY_Z,
        "game_west": KEY_C,
        "game_north": KEY_V,
        "game_left_shoulder": KEY_Q,
        "game_right_shoulder": KEY_E,
        "game_start": KEY_ENTER,
        "game_select": KEY_SHIFT,
        "game_pause": KEY_ESCAPE,
    }
    for action in expected_keys:
        if not _has_key(action, int(expected_keys[action])):
            _fail("missing keyboard mapping for %s" % action)
            return

    var expected_buttons := {
        "game_south": JOY_BUTTON_A,
        "game_east": JOY_BUTTON_B,
        "game_west": JOY_BUTTON_X,
        "game_north": JOY_BUTTON_Y,
        "game_left_shoulder": JOY_BUTTON_LEFT_SHOULDER,
        "game_right_shoulder": JOY_BUTTON_RIGHT_SHOULDER,
        "game_start": JOY_BUTTON_START,
        "game_select": JOY_BUTTON_BACK,
    }
    for action in expected_buttons:
        if not _has_button(action, int(expected_buttons[action])):
            _fail("missing gamepad mapping for %s" % action)
            return
    if not _has_button("game_pause", JOY_BUTTON_GUIDE) \
        or not _has_button("game_pause", JOY_BUTTON_RIGHT_STICK):
        _fail("pause must include Guide and right-stick click")
        return

    main.free()
    print("RetroLife input mapping smoke passed")
    quit(0)


func _has_key(action: String, keycode: int) -> bool:
    for event in InputMap.action_get_events(action):
        if event is InputEventKey and (event as InputEventKey).keycode == keycode:
            return true
    return false


func _has_button(action: String, button_index: int) -> bool:
    for event in InputMap.action_get_events(action):
        if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button_index:
            return true
    return false


func _fail(message: String) -> void:
    push_error("RetroLife input mapping smoke failed: %s" % message)
    quit(1)
