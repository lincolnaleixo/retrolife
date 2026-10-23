extends SceneTree

## Original geometry only. No ROM, remote media, persisted settings or private artwork.
const Carousel = preload("res://scripts/library/carousel.gd")

class PairFixture extends Carousel:
    var fixture_path := ""

    func _box_path_for(game: Dictionary) -> String:
        return fixture_path if str(game.get("id", "")) == "paired" and allow_local_art else ""

var _errors: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    for action in ["library_inspect_right", "library_inspect_left", "library_inspect_up", "library_inspect_down", "library_zoom_in", "library_zoom_out", "library_reset_view"]:
        if not InputMap.has_action(action):
            InputMap.add_action(action)
    var path := OS.get_cache_dir().path_join("retrolife-separated-fixture-%d.glb" % OS.get_process_id())
    var fixture := Node3D.new()
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(0.18, 0.128, 0.03)
    mesh.mesh = box
    mesh.position.y = 0.064
    fixture.add_child(mesh)
    mesh.owner = fixture
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    _check(document.append_from_scene(fixture, state) == OK and document.write_to_filesystem(state, path) == OK, "The original fixture must export")
    fixture.free()
    root.size = Vector2i(1440, 900)
    var carousel := PairFixture.new()
    carousel.fixture_path = path
    carousel.force_fallback_model = true
    carousel.set_label_fetching(false)
    carousel.size = Vector2(1440, 800)
    root.add_child(carousel)
    carousel.set_presentation(true, false, false)
    carousel.set_games([
        {"id": "left", "title": "Original Left", "systemId": "fixture"},
        {"id": "paired", "title": "Original Pair", "systemId": "fixture"},
        {"id": "right", "title": "Original Right", "systemId": "fixture"}
    ], "paired")
    await process_frame
    _check(carousel.selected_box_count() == 1 and carousel.active_model_count() == 1, "Detail displays only the selected game's box and cartridge")
    _check(carousel._selected_box.get_child_count() == 1, "Only one box pivot remains after loading")
    var box_model: Node3D = carousel._selected_box.get("_model")
    carousel._layout(false)
    _check(carousel._selected_box.get("_model") == box_model, "Repeated layout reuses the selected box")
    _check(carousel._box_caption.visible and carousel._media_caption.visible, "Detail identifies its two independent collectibles")
    _verify_interactions(carousel)
    _verify_separated_inspection(carousel)
    _verify_overview(carousel)
    carousel.select_id("left")
    _check(carousel.selected_box_count() == 0 and carousel.active_model_count() == 1, "A game without box art clears the previous box and keeps detail scoped to one game")
    _check(is_equal_approx(carousel._hero.scale.x, 0.68), "Games without box art retain the centered cartridge fallback")
    carousel.select_id("paired")
    _check(carousel.selected_box_count() == 1, "Returning to a matched game restores its box")
    carousel.set_presentation(true, false, true)
    _check(carousel.selected_box_count() == 0 and not carousel._box_caption.visible, "Text view releases box art and hides collectible captions")
    carousel.set_presentation(true, false, false)
    _check(carousel.selected_box_count() == 1, "Returning to 3D restores separate collectibles")
    carousel.allow_local_art = false
    carousel._layout(false)
    _check(carousel.selected_box_count() == 0, "Synthetic views can suppress external box art")
    carousel.set_games([])
    _check(carousel.selected_box_count() == 0 and carousel.active_model_count() == 0, "Empty selections clear all visible objects")
    carousel.queue_free()
    await process_frame
    DirAccess.remove_absolute(path)
    if _errors.is_empty():
        print("Separate collectibles smoke passed: 243 independent poses, projected clearance, click actions, object-specific drag/zoom, keyboard target, reset, overview neighbors, bounded resources and fallbacks.")
        quit(0)
    else:
        for error in _errors:
            push_error(error)
        quit(1)


func _verify_interactions(carousel: Control) -> void:
    var games: Array[String] = []
    var boxes: Array[String] = []
    carousel.game_activated.connect(func(id: String): games.append(id))
    carousel.box_activated.connect(func(id: String): boxes.append(id))
    _click(carousel, _center(carousel, carousel._selected_box))
    _check(boxes == ["paired"] and games.is_empty(), "Clicking the box opens inspection without launching the game")
    _click(carousel, _center(carousel, carousel._hero))
    _check(games == ["paired"], "Clicking the cartridge activates the game")
    var box_rect: Rect2 = carousel._projected_bounds(carousel._selected_box.call("world_bounds"))
    var media_rect: Rect2 = carousel._projected_bounds(carousel._hero.call("world_bounds"))
    var gap_point := Vector2((box_rect.end.x + media_rect.position.x) * 0.5, minf(box_rect.end.y, media_rect.end.y) - 10.0) * carousel.size / Vector2(carousel._viewport.size)
    _click(carousel, gap_point)
    _check(games.size() == 1 and boxes.size() == 1, "The breathing room between collectibles is not an activation target")
    var media_basis: Basis = carousel._hero.basis
    var press := _press(_center(carousel, carousel._selected_box))
    carousel._gui_input(press)
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(80, 30)
    carousel._gui_input(motion)
    press.pressed = false
    carousel._gui_input(press)
    carousel._step_inspection(1.0)
    _check(boxes.size() == 1 and games.size() == 1, "Dragging either object must not activate it")
    _check(absf(carousel._collectible_current.box.x) > 0.1 and carousel._hero.basis.is_equal_approx(media_basis), "Dragging the box rotates only the box")
    var box_state: Vector3 = carousel._collectible_target.box
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    wheel.pressed = true
    wheel.position = _center(carousel, carousel._hero)
    carousel._gui_input(wheel)
    carousel._step_inspection(1.0)
    _check(carousel._collectible_current.cartridge.z > 1.0 and carousel._collectible_target.box.is_equal_approx(box_state), "Wheel zoom affects only its hovered object")
    Input.action_press("library_inspect_right")
    carousel._step_inspection(0.2)
    Input.action_release("library_inspect_right")
    _check(carousel._collectible_target.cartridge.x > 0.1 and carousel._collectible_target.box.is_equal_approx(box_state), "Keyboard/right-stick inspection targets the last touched object")
    carousel._reset_inspection()
    _check(carousel._collectible_current.box == Vector3(0, 0, 1) and carousel._collectible_current.cartridge == Vector3(0, 0, 1), "Reset restores both collectibles")
    _check(carousel._active_collectible == "cartridge", "Default inspection target is the cartridge")


func _verify_separated_inspection(carousel: Control) -> void:
    var count := 0
    for dimensions in [Vector2(1440, 800), Vector2(800, 700), Vector2(600, 800)]:
        carousel.size = dimensions
        carousel._resize_view()
        for box_yaw in [-PI, -PI * 0.75, -PI * 0.5, -PI * 0.25, 0.0, PI * 0.25, PI * 0.5, PI * 0.75, PI]:
            for cartridge_yaw in [-PI * 0.5, 0.0, PI * 0.5]:
                for zoom in [Carousel.ZOOM_MINIMUM, 1.0, Carousel.ZOOM_MAXIMUM]:
                    var pitch := float(count % 3 - 1) * Carousel.PITCH_LIMIT
                    carousel._collectible_current.box = Vector3(box_yaw, pitch, zoom)
                    carousel._collectible_current.cartridge = Vector3(cartridge_yaw, -pitch, 2.35 - zoom)
                    carousel._apply_inspection()
                    carousel._update_contact_shadow()
                    var box_bounds: AABB = carousel._selected_box.call("world_bounds")
                    var media_bounds: AABB = carousel._hero.call("world_bounds")
                    _check(media_bounds.position.x > box_bounds.end.x, "Independently rotated geometry must never intersect")
                    var box_rect: Rect2 = carousel._projected_bounds(box_bounds)
                    var media_rect: Rect2 = carousel._projected_bounds(media_bounds)
                    var minimum := clampf(float(carousel._viewport.size.x) * 0.035, 24.0, 52.0)
                    _check(media_rect.position.x - box_rect.end.x >= minimum - 0.5, "Projected silhouettes retain visible horizontal breathing room")
                    _check(is_equal_approx(box_bounds.position.y, Carousel.PAIR_GROUND_Y) and is_equal_approx(media_bounds.position.y, Carousel.PAIR_GROUND_Y), "Both independently rotated objects stand on the same ground")
                    _check(is_equal_approx(carousel._shadow.position.y, box_bounds.position.y - 0.015) and is_equal_approx(carousel._media_shadow.position.y, media_bounds.position.y - 0.015), "Each collectible has its own close contact shadow")
                    var viewport_rect := Rect2(Vector2.ZERO, Vector2(carousel._viewport.size))
                    _check(viewport_rect.encloses(box_rect) and viewport_rect.encloses(media_rect), "Both collectibles stay inside the camera at every tested pose")
                    count += 1
    _check(count == 243, "Exercise 243 independent object rotations, zooms and viewport combinations")
    carousel._reset_inspection()
    carousel.size = Vector2(1440, 800)
    carousel._resize_view()


func _verify_overview(carousel: Control) -> void:
    var selections: Array[String] = []
    carousel.selection_changed.connect(func(game: Dictionary, _index: int): selections.append(str(game.get("id", ""))))
    var selected: String = carousel.selected_id()
    var hero: Node3D = carousel._hero
    carousel.set_collection_overview(true)
    _check(carousel.selected_id() == selected and selections.is_empty(), "Opening overview preserves selection without emitting a game change")
    _check(carousel.selected_box_count() == 0 and carousel.active_model_count() == 3, "Overview shows neighboring cartridges and suppresses the box")
    _check(carousel._hero == hero and carousel._hero.game_id == selected, "Overview reuses the selected cartridge binding")
    _check(not carousel._box_caption.visible and not carousel._media_caption.visible, "Overview leaves captions to its selected-game title")
    var visible_neighbors := 0
    for item in carousel._pool:
        if item.visible and item != hero:
            var screen: Vector2 = carousel._camera.unproject_position(item.global_position)
            if Rect2(Vector2.ZERO, Vector2(carousel._viewport.size)).has_point(screen):
                visible_neighbors += 1
    _check(visible_neighbors == 2, "At wide collection size both adjacent cartridge centers are visible")
    carousel.set_collection_overview(false)
    _check(carousel.selected_id() == selected and selections.is_empty(), "Returning to detail preserves selection without extra selection signals")
    _check(carousel.selected_box_count() == 1 and carousel.active_model_count() == 1, "Detail restores only the selected game's separate box and cartridge")


func _center(carousel: Control, object: Node3D) -> Vector2:
    var rect: Rect2 = carousel._projected_bounds(object.call("world_bounds"))
    return rect.get_center() * carousel.size / Vector2(carousel._viewport.size)


func _press(point: Vector2) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.position = point
    event.pressed = true
    return event


func _click(carousel: Control, point: Vector2) -> void:
    var event := _press(point)
    carousel._gui_input(event)
    event.pressed = false
    carousel._gui_input(event)


func _check(condition: bool, message: String) -> void:
    if not condition and not _errors.has(message):
        _errors.append(message)
