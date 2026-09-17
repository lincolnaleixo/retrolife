extends RefCounted

## Window sizing policy for the library shell.
##
## The preferred opening target is a 2K-class 2560x1440 content area. When the
## usable display area cannot provide it with breathing room, the window opens
## near the full usable area instead, and never below the 1024x640 floor.
##
## Godot reports macOS display metrics in backing pixels and window sizes use
## the same units, so the policy behaves consistently on Retina and standard
## displays without extra scale handling.

const PREFERRED_SIZE := Vector2i(2560, 1440)
const MINIMUM_SIZE := Vector2i(1024, 640)
const HORIZONTAL_MARGIN := 0.04
const VERTICAL_MARGIN := 0.08


static func compute_window_size(usable: Vector2i) -> Vector2i:
    if usable.x <= 0 or usable.y <= 0:
        return PREFERRED_SIZE
    var fitted := Vector2i(
        int(floor(float(usable.x) * (1.0 - HORIZONTAL_MARGIN))),
        int(floor(float(usable.y) * (1.0 - VERTICAL_MARGIN)))
    )
    var target := PREFERRED_SIZE
    if fitted.x < PREFERRED_SIZE.x or fitted.y < PREFERRED_SIZE.y:
        target = fitted
    target.x = maxi(target.x, MINIMUM_SIZE.x)
    target.y = maxi(target.y, MINIMUM_SIZE.y)
    return target


static func apply_default_window(window: Window) -> void:
    if DisplayServer.get_name() == "headless" or window == null:
        return
    var screen := DisplayServer.window_get_current_screen()
    var usable := DisplayServer.screen_get_usable_rect(screen)
    if usable.size.x <= 0 or usable.size.y <= 0:
        return
    var target := compute_window_size(usable.size)
    window.size = target
    window.position = usable.position + (usable.size - target) / 2
