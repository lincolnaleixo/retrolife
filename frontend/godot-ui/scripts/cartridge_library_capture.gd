extends SceneTree

## Actual rendered UI with original synthetic titles; never reads the user's library.
const Fixtures = preload("res://scripts/cartridge_library_smoke.gd")
var _capture_errors: Array[String] = []


func _init() -> void:
    call_deferred("_capture")


func _capture() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("A rendering display is required for screenshots; use Xvfb on CI.")
        quit(1)
        return
    root.size = Vector2i(1280, 720)
    var shell := Fixtures.TestShell.new()
    shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var catalog := Fixtures.FakeCatalog.new(11)
    var titles := ["Amber Coast", "Arcade Nights", "Beyond the Stars", "Crystal Valley", "Dream Runner", "Endless Summer", "Forest Quest", "Gravity Shift", "Midnight Rally", "Pixel Odyssey", "Silver Horizon"]
    for index in range(titles.size()):
        catalog.entries[index]["title"] = titles[index]
    shell.set("_catalog", catalog)
    root.add_child(shell)
    await shell._refresh_library()
    var carousel: Control = shell.get("_carousel")
    carousel.select_index(4)
    var path := OS.get_environment("RETROLIFE_CAPTURE_PATH")
    if path.is_empty():
        path = "res://../../.cache/captures/cartridge-library.png"
    await _save_frame(path)
    root.size = Vector2i(720, 540)
    await _save_frame(path.get_basename() + "-narrow.png")
    root.size = Vector2i(1600, 900)
    await _save_frame(path.get_basename() + "-wide.png")
    root.size = Vector2i(1280, 720)
    carousel.set_presentation(true, false, true)
    await _save_frame(path.get_basename() + "-text.png")
    carousel.set_presentation(true, true, false)
    await _save_frame(path.get_basename() + "-low-power.png")
    carousel.set_presentation(true, false, false)
    catalog.entries = catalog.entries.slice(0, 1)
    await shell._refresh_library()
    await _save_frame(path.get_basename() + "-single.png")
    carousel.set_presentation(true, false, false)
    carousel.set("_inspect_target_pitch", 0.5)
    await _save_frame(path.get_basename() + "-folded-top.png")
    carousel.set("_inspect_target_pitch", -PI / 3.0)
    carousel.set("_inspect_target_zoom", 1.6)
    await _save_frame(path.get_basename() + "-inspection.png")
    carousel.set("_inspect_target_pitch", 0.0)
    carousel.set("_inspect_target_yaw", PI)
    carousel.set("_inspect_target_zoom", 1.0)
    await _save_frame(path.get_basename() + "-rear.png")
    carousel._reset_inspection()
    catalog.entries.clear()
    await shell._refresh_library()
    await _save_frame(path.get_basename() + "-empty.png")
    shell.queue_free()
    await process_frame
    if _capture_errors.is_empty():
        print("Cartridge library rendered captures saved: default, narrow, wide, text, low-power, single, folded top, inspection, rear and empty")
        quit(0)
    else:
        for error in _capture_errors:
            push_error(error)
        quit(1)


func _save_frame(path: String) -> void:
    for _frame in range(25):
        await process_frame
    await RenderingServer.frame_post_draw
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.save_png(path) != OK:
        _capture_errors.append("The interface screenshot could not be saved: " + path.get_file())
