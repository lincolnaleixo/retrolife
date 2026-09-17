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

    var inspect_keys := {
        "library_inspect_left": KEY_LEFT,
        "library_inspect_right": KEY_RIGHT,
        "library_inspect_up": KEY_UP,
        "library_inspect_down": KEY_DOWN,
    }
    for action in inspect_keys:
        if not _has_key(action, int(inspect_keys[action]), true):
            _fail("missing shifted inspect binding for %s" % action)
            return
    var inspect_axes := {
        "library_inspect_left": [2, -1.0],
        "library_inspect_right": [2, 1.0],
        "library_inspect_up": [3, -1.0],
        "library_inspect_down": [3, 1.0],
        "library_zoom_in": [5, 1.0],
        "library_zoom_out": [4, 1.0],
    }
    for action in inspect_axes:
        if not _has_motion(action, int(inspect_axes[action][0]), float(inspect_axes[action][1])):
            _fail("missing gamepad inspection axis for %s" % action)
            return
    for action in ["library_zoom_in", "library_zoom_out", "library_reset_view"]:
        if InputMap.action_get_events(action).is_empty():
            _fail("missing key binding for %s" % action)
            return
    if not _has_button("library_reset_view", JOY_BUTTON_RIGHT_STICK):
        _fail("reset view must include the right-stick click")
        return

    main.free()
    print("RetroLife input mapping smoke passed")
    quit(0)


func _has_key(action: String, keycode: int, require_shift := false) -> bool:
    for event in InputMap.action_get_events(action):
        if event is InputEventKey and (event as InputEventKey).keycode == keycode \
            and (event as InputEventKey).shift_pressed == require_shift:
            return true
    return false


func _has_motion(action: String, axis: int, axis_value: float) -> bool:
    for event in InputMap.action_get_events(action):
        if event is InputEventJoypadMotion \
            and (event as InputEventJoypadMotion).axis == axis \
            and is_equal_approx((event as InputEventJoypadMotion).axis_value, axis_value):
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
