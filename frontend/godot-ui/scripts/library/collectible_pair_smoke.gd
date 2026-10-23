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
    var path := OS.get_cache_dir().path_join("retrolife-paired-fixture-%d.glb" % OS.get_process_id())
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
    root.size = Vector2i(1000, 800)
    var carousel := PairFixture.new()
    carousel.fixture_path = path
    carousel.force_fallback_model = true
    carousel.set_label_fetching(false)
    carousel.size = Vector2(1000, 800)
    root.add_child(carousel)
    carousel.set_presentation(true, false, false)
    carousel.set_games([
        {"id": "paired", "title": "Original Pair", "systemId": "fixture"},
        {"id": "bare", "title": "Original Single", "systemId": "fixture"}
    ])
    await process_frame
    _check(carousel.selected_box_count() == 1, "A selected game with local box art shows one box")
    _check(carousel._selected_box.get_child_count() == 1, "The loading viewer must be disposed; only the box pivot remains")
    var box_model: Node3D = carousel._selected_box.get("_model")
    var box_bounds: AABB = carousel._selected_box.call("world_bounds")
    var cartridge_bounds: AABB = carousel._hero.call("world_bounds")
    _check(box_bounds.size.x > cartridge_bounds.size.x * 1.5, "The box leads the composition while the cartridge stays smaller")
    _check(carousel._selected_box.position.x < carousel._hero.position.x and carousel._selected_box.position.z < carousel._hero.position.z, "The box sits behind-left and cartridge in foreground-right")
    carousel._layout(false)
    _check(carousel._selected_box.get("_model") == box_model, "Repeated layout must reuse the single selected box")

    var point := carousel._camera.unproject_position(box_bounds.get_center()) * carousel.size / Vector2(carousel._viewport.size)
    _check(carousel._cartridge_index_at(point) == 0, "Clicking the box identifies its selected game")
    var activations: Array[String] = []
    carousel.game_activated.connect(func(id: String): activations.append(id))
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.position = point
    press.pressed = true
    carousel._gui_input(press)
    var release: InputEventMouseButton = press.duplicate()
    release.pressed = false
    carousel._gui_input(release)
    _check(activations == ["paired"], "Clicking the box activates the game exactly once")
    carousel._gui_input(press)
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(40, 10)
    carousel._gui_input(motion)
    carousel._gui_input(release)
    carousel._step_inspection(1.0)
    _check(activations.size() == 1, "Dragging the box inspects without launching")
    _check(absf(carousel._selected_box.get("_pivot").rotation.y) > 0.1, "Box inspection follows the shared carousel interaction")

    carousel.select_id("bare")
    _check(carousel.selected_box_count() == 0 and not is_instance_valid(box_model), "Changing to a game without a box releases the previous model")
    _check(is_equal_approx(carousel._hero.scale.x, 0.68), "A game without box art retains the centered cartridge presentation")
    carousel.select_id("paired")
    _check(carousel.selected_box_count() == 1, "Returning to a paired game reloads its own box")
    carousel.set_presentation(true, false, true)
    _check(carousel.selected_box_count() == 0, "Text presentation releases the box")
    carousel.set_presentation(true, false, false)
    _check(carousel.selected_box_count() == 1, "Returning to the 3D stage restores the pair")
    carousel.allow_local_art = false
    carousel._layout(false)
    _check(carousel.selected_box_count() == 0, "Synthetic and privacy-safe views can suppress local artwork")
    carousel.set_games([])
    _check(carousel.selected_box_count() == 0 and carousel.active_model_count() == 0, "Empty selections must clear all visible models")
    carousel.queue_free()
    await process_frame
    DirAccess.remove_absolute(path)
    if _errors.is_empty():
        print("Collectible pair smoke passed: bounded loading, composition, box click, drag inspection, selection clearing, text and neutral fallbacks.")
        quit(0)
    else:
        for error in _errors:
            push_error(error)
        quit(1)

func _check(condition: bool, message: String) -> void:
    if not condition:
        _errors.append(message)
