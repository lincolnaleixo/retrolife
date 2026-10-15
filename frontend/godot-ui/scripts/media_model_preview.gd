extends Node

## Display released media models; optional owner examples are staged locally, without ROMs.
const Cartridge = preload("res://scripts/library/cartridge.gd")
var _items: Array[Node3D] = []
var _selected := 0
var _dragging := false
var _focused := false
var _disc_flipped := false
var _collection_labels: Array[Label] = []
var _detail: Label
var _status: Label
var _camera: Camera3D
const POSITIONS := [Vector3(-4.0, 1.4, 0), Vector3(0, 1.4, 0), Vector3(4.0, 1.4, 0), Vector3(-2.1, -1.95, 0), Vector3(2.1, -1.95, 0)]
const SYSTEMS := ["snes", "mega-drive", "playstation-1", "nintendo-64", "nes"]
const NAMES := ["SUPER NINTENDO", "MEGA DRIVE", "PLAYSTATION", "NINTENDO 64", "NES"]
const NEUTRAL_TITLES := ["Amber Coast", "Midnight Rally", "Beyond the Stars", "Cloud Castle", "Pixel Expedition"]
const OWNER_TITLES := ["Amber Coast", "Sonic the Hedgehog", "Crash Bandicoot", "Super Mario 64", "Super Mario Bros."]
const COLLECTION_CAMERA_SIZE := 9.8
const CONTROLS := "1–5 select  ·  F focus  ·  drag rotates  ·  wheel zooms  ·  V flips CD  ·  R resets"


func _ready() -> void:
    call_deferred("_start")


func _start() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("Media preview requires a graphics display. Use media_model_smoke.gd for headless verification.")
        get_tree().quit(1)
        return
    get_tree().root.size = Vector2i(1600, 1000)
    get_tree().root.msaa_3d = Viewport.MSAA_4X
    var world := Node3D.new()
    get_tree().root.add_child(world)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("11121b")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color.WHITE
    environment.environment.ambient_light_energy = 0.35
    # Broad studio reflections are needed for clear plastic and optical media.
    # Neutral illumination keeps printed inks free from a warm/cool color cast.
    # Keep the backdrop plain while using the sky only as a reflection source.
    var studio_sky := ProceduralSkyMaterial.new()
    studio_sky.sky_top_color = Color("303030")
    studio_sky.sky_horizon_color = Color("d3d3d3")
    studio_sky.ground_bottom_color = Color("1c1c1c")
    studio_sky.ground_horizon_color = Color("929292")
    studio_sky.sky_curve = 0.22
    studio_sky.ground_curve = 0.3
    var sky := Sky.new()
    sky.sky_material = studio_sky
    environment.environment.sky = sky
    environment.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    world.add_child(environment)
    _light(world, Vector3(-35, -30, 0), Color.WHITE, 1.0)
    _light(world, Vector3(-15, 140, 0), Color.WHITE, 0.55)
    _light(world, Vector3(40, 15, 0), Color.WHITE, 0.25)
    var camera := Camera3D.new()
    _camera = camera
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    # A collection-sized depth range keeps the disc's thin matrix/rim layers
    # distinct in Compatibility instead of spending precision on empty space.
    camera.near = 0.1
    camera.far = 60.0
    camera.size = COLLECTION_CAMERA_SIZE
    camera.position = Vector3(0, 1.5, 15)
    world.add_child(camera)
    camera.look_at(Vector3.ZERO)
    camera.current = true
    var owner_ids: Array = []
    if FileAccess.file_exists("res://owner-artwork-preview.json"):
        var owner_record = JSON.parse_string(FileAccess.get_file_as_string("res://owner-artwork-preview.json"))
        if owner_record is Dictionary:
            owner_ids = owner_record.get("ownerExampleIds", ["mega-drive", "playstation-1"])
    var titles: Array[String] = []
    for index in range(SYSTEMS.size()):
        var has_owner_artwork: bool = SYSTEMS[index] in owner_ids
        titles.append(OWNER_TITLES[index] if has_owner_artwork else NEUTRAL_TITLES[index])
        var item := Cartridge.new()
        item.preserve_imported_artwork = has_owner_artwork
        world.add_child(item)
        item.bind_game({"id": "original-media-demo-%d" % index, "title": titles[index], "systemId": SYSTEMS[index]}, index, null)
        item.position = POSITIONS[index]
        item.rotation_degrees = Vector3(-10, -22, 0)
        _items.append(item)
        if item.uses_fallback:
            push_error("Stage the actual development models before previewing: " + SYSTEMS[index])
            get_tree().quit(1)
            return
    var ui := CanvasLayer.new()
    get_tree().root.add_child(ui)
    _text(ui, "RETROLIFE   /   PHYSICAL COLLECTION", Vector2(76, 52), 20, Color("a9acd0"))
    _text(ui, "Five formats. One collection.", Vector2(76, 96), 48, Color("f2f0f8"))
    _text(ui, "SNES  /  Mega Drive  /  PlayStation CD  /  Nintendo 64  /  NES", Vector2(80, 167), 19, Color("a3a4b5"))
    for index in range(SYSTEMS.size()):
        _collection_labels.append(_text(ui, "%02d / %s" % [index + 1, NAMES[index]], Vector2.ZERO, 16, Color("c8c5da")))
        _collection_labels.append(_text(ui, titles[index], Vector2.ZERO, 23, Color("f2f0f8")))
    for label in _collection_labels:
        label.custom_minimum_size.x = 400
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _detail = _text(ui, "", Vector2(80, 810), 27, Color("f2f0f8"))
    _status = _text(ui, CONTROLS, Vector2(80, 924), 18, Color("989caf"))
    _layout()
    if OS.get_environment("RETROLIFE_PREVIEW_INPUT_SMOKE") == "1":
        var controls_passed: bool = await _exercise_controls()
        if not controls_passed:
            return
    var path := OS.get_environment("RETROLIFE_CAPTURE_PATH")
    if not path.is_empty():
        await _capture(path)
        for item in _items:
            item.rotation_degrees.y = 165
        await _capture(path.get_basename() + "-rear.png")
        _reset()
        _selected = 1
        _focused = true
        _layout()
        _items[1].rotation_degrees = Vector3(-12, 145, 0)
        await _capture(path.get_basename() + "-mega-detail.png")
        _reset()
        _selected = 2
        _focused = true
        _layout()
        await _capture(path.get_basename() + "-disc.png")
        _toggle_disc_face()
        await _capture(path.get_basename() + "-disc-underside.png")
        for index in [3, 4]:
            _reset()
            _selected = index
            _focused = true
            _layout()
            await _capture(path.get_basename() + "-" + SYSTEMS[index] + "-detail.png")
            _items[index].rotation_degrees.y = 158
            await _capture(path.get_basename() + "-" + SYSTEMS[index] + "-rear.png")
        print("Media preview captured: five-model collection, rear, cartridge details and both CD faces")
        get_tree().quit(0)


func _exercise_controls() -> bool:
    for _frame in range(12):
        await get_tree().process_frame
    var accumulated_input := Input.use_accumulated_input
    Input.use_accumulated_input = false
    for index in range(SYSTEMS.size()):
        var selection := InputEventKey.new()
        selection.keycode = KEY_1 + index
        selection.pressed = true
        Input.parse_input_event(selection)
        await get_tree().process_frame
        if not _preview_check(_selected == index, "Every number key must select its preview item"):
            return false
        var rotate_press := InputEventMouseButton.new()
        rotate_press.button_index = MOUSE_BUTTON_LEFT
        rotate_press.pressed = true
        Input.parse_input_event(rotate_press)
        await get_tree().process_frame
        var before := _items[index].rotation.y
        var rotate_drag := InputEventMouseMotion.new()
        rotate_drag.relative = Vector2(20, 10)
        Input.parse_input_event(rotate_drag)
        await get_tree().process_frame
        if not _preview_check(_items[index].rotation.y > before, "Dragging must rotate media type " + SYSTEMS[index]):
            return false
        rotate_press = InputEventMouseButton.new()
        rotate_press.button_index = MOUSE_BUTTON_LEFT
        rotate_press.pressed = false
        Input.parse_input_event(rotate_press)
    var choose := InputEventKey.new()
    choose.keycode = KEY_3
    choose.pressed = true
    Input.parse_input_event(choose)
    await get_tree().process_frame
    if not _preview_check(_selected == 2, "Number keys must select the preview item"):
        return false
    var focus := InputEventKey.new()
    focus.keycode = KEY_F
    focus.pressed = true
    Input.parse_input_event(focus)
    await get_tree().process_frame
    if not _preview_check(_focused and _items[2].visible and not _items[1].visible, "F must isolate the selected model"):
        return false
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    Input.parse_input_event(press)
    var drag := InputEventMouseMotion.new()
    drag.relative = Vector2(40, 20)
    Input.parse_input_event(drag)
    await get_tree().process_frame
    if not _preview_check(_items[2].rotation.y > -0.1, "Dragging must rotate the selected model"):
        return false
    press = InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = false
    Input.parse_input_event(press)
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    wheel.pressed = true
    Input.parse_input_event(wheel)
    await get_tree().process_frame
    if not _preview_check(_camera.size < 4.8, "The wheel must zoom the focused preview"):
        return false
    if not _preview_check(_items[2].find_child("FrontLid", true, false) == null, "PlayStation must contain only a CD"):
        return false
    var flip := InputEventKey.new()
    flip.keycode = KEY_V
    flip.pressed = true
    Input.parse_input_event(flip)
    await get_tree().process_frame
    if not _preview_check(_disc_flipped, "V must turn the standalone CD to its reading face"):
        return false
    var reset := InputEventKey.new()
    reset.keycode = KEY_R
    reset.pressed = true
    Input.parse_input_event(reset)
    await get_tree().process_frame
    if not _preview_check(not _disc_flipped and not _focused and is_equal_approx(_camera.size, COLLECTION_CAMERA_SIZE), "R must reset the preview"):
        return false
    for item in _items:
        if not _preview_check(item.visible, "Reset must restore every model in the collection"):
            return false
    Input.use_accumulated_input = accumulated_input
    print("Preview routed input smoke passed: five-model selection and rotation, zoom, focus, standalone disc flip and reset")

    return true


func _preview_check(condition: bool, message: String) -> bool:
    if not condition:
        push_error(message)
        get_tree().quit(1)
    return condition

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
        _camera.size = clampf(_camera.size + (-0.35 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.35), 2.8 if _focused else 6.5, 13.0)
        _place_collection_labels()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _dragging = event.pressed
    elif event is InputEventMouseMotion and _dragging and not _items.is_empty():
        _items[_selected].rotation.y += event.relative.x * 0.008
        _items[_selected].rotation.x = clampf(_items[_selected].rotation.x + event.relative.y * 0.008, -PI / 3, PI / 3)
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.keycode >= KEY_1 and event.keycode <= KEY_5:
            _selected = int(event.keycode - KEY_1)
            _layout()
        elif event.keycode == KEY_F:
            _focused = not _focused
            _layout()
        elif event.keycode == KEY_V:
            _toggle_disc_face()
        elif event.keycode == KEY_R:
            _reset()


func _toggle_disc_face() -> void:
    _disc_flipped = not _disc_flipped
    _items[2].rotation_degrees.y = 158.0 if _disc_flipped else -22.0
    _selected = 2
    _focused = true
    _layout()


func _layout() -> void:
    for index in range(_items.size()):
        _items[index].visible = not _focused or index == _selected
        _items[index].position = Vector3(0, -0.12, 0) if _focused else POSITIONS[index]
    for label in _collection_labels:
        label.visible = not _focused
    _detail.visible = _focused
    _detail.text = NAMES[_selected]
    if _selected == 2 and _focused:
        _detail.text += "  /  Dark reading face" if _disc_flipped else "  /  Printed CD face"
    _camera.size = 4.8 if _focused else COLLECTION_CAMERA_SIZE
    _camera.position = Vector3(0, 1.5, 15)
    _camera.look_at(Vector3.ZERO)
    _place_collection_labels()
    _status.text = CONTROLS


func _place_collection_labels() -> void:
    for index in range(_items.size()):
        var anchor := _camera.unproject_position(POSITIONS[index] + Vector3(0, -1.45, 0))
        _collection_labels[index * 2].position = anchor - Vector2(200, 0)
        _collection_labels[index * 2 + 1].position = anchor + Vector2(-200, 26)


func _reset() -> void:
    _focused = false
    _disc_flipped = false
    for item in _items:
        item.rotation_degrees = Vector3(-10, -22, 0)
    _layout()


func _light(world: Node3D, degrees: Vector3, color: Color, energy: float) -> void:
    var light := DirectionalLight3D.new()
    light.rotation_degrees = degrees
    light.light_color = color
    light.light_energy = energy
    world.add_child(light)


func _text(parent: Node, value: String, at: Vector2, size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = value
    label.position = at
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    parent.add_child(label)
    return label


func _capture(path: String) -> void:
    for _frame in range(12):
        await get_tree().process_frame
    await RenderingServer.frame_post_draw
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var frame := get_tree().root.get_texture().get_image()
    if frame == null or frame.is_empty() or frame.save_png(path) != OK:
        push_error("Could not save media preview capture")
        get_tree().quit(1)
