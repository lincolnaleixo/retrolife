extends SceneTree

## Headless contract check for the window sizing policy.

const WindowLayout = preload("res://scripts/window_layout.gd")


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    var cases := [
        {"usable": Vector2i(6144, 3296), "expected": Vector2i(2560, 1440)},
        {"usable": Vector2i(3840, 2160), "expected": Vector2i(2560, 1440)},
        {"usable": Vector2i(2667, 1566), "expected": Vector2i(2560, 1440)},
        {"usable": Vector2i(2560, 1440), "expected": Vector2i(2457, 1324)},
        {"usable": Vector2i(2000, 1200), "expected": Vector2i(1920, 1104)},
        {"usable": Vector2i(1470, 900), "expected": Vector2i(1411, 828)},
        {"usable": Vector2i(800, 600), "expected": Vector2i(1024, 640)},
        {"usable": Vector2i(0, 0), "expected": Vector2i(2560, 1440)},
    ]
    for case in cases:
        var actual := WindowLayout.compute_window_size(case["usable"])
        if actual != case["expected"]:
            _fail("usable %s: expected %s, got %s" % [case["usable"], case["expected"], actual])
            return

    var min_width := int(ProjectSettings.get_setting("display/window/size/min_width", 0))
    var min_height := int(ProjectSettings.get_setting("display/window/size/min_height", 0))
    if min_width != WindowLayout.MINIMUM_SIZE.x or min_height != WindowLayout.MINIMUM_SIZE.y:
        _fail("project window minimum %s x %s does not match the 1024x640 floor" % [min_width, min_height])
        return

    var before := root.size
    WindowLayout.apply_default_window(root)
    if root.size != before:
        _fail("headless apply changed the window size")
        return

    print("RetroLife window layout smoke passed")
    quit(0)


func _fail(message: String) -> void:
    push_error("RetroLife window layout smoke failed: %s" % message)
    quit(1)
