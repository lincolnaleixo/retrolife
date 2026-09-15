extends SceneTree

## Render the real interface with neutral synthetic metadata, never personal data.
const Fixtures = preload("res://scripts/cartridge_library_smoke.gd")


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
    for _frame in range(30):
        await process_frame
    await RenderingServer.frame_post_draw
    var path := OS.get_environment("RETROLIFE_CAPTURE_PATH")
    if path.is_empty():
        path = "res://../../.cache/captures/cartridge-library.png"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var error := root.get_texture().get_image().save_png(path)
    shell.queue_free()
    await process_frame
    if error != OK:
        push_error("The interface screenshot could not be saved")
        quit(1)
    else:
        print("Cartridge library rendered capture saved")
        quit(0)
