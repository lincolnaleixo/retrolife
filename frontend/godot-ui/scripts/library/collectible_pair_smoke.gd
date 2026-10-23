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
    _check(absf(carousel._pair_transform.basis.get_euler().y) > 0.1, "Dragging rotates the complete shared assembly")
    _check(carousel._selected_box.get("_pivot").transform.is_equal_approx(Transform3D.IDENTITY), "Box geometry must not rotate independently inside the assembly")
    _check((carousel._hero.call("inspection_state") as Vector3).is_equal_approx(Vector3(0, 0, 1)), "Cartridge geometry must not rotate independently inside the assembly")
    _verify_rigid_inspection(carousel)


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
        print("Collectible pair smoke passed: 405 rigid poses without intersection, geometric clearance, common ground, camera fit, contact shadow, click/drag, bounded resources and fallbacks.")
        quit(0)
    else:
        for error in _errors:
            push_error(error)
        quit(1)

func _verify_rigid_inspection(carousel: Control) -> void:
    carousel._inspect_yaw = 0.0
    carousel._inspect_pitch = 0.0
    carousel._inspect_zoom = 1.0
    carousel._apply_inspection()
    var box: Node3D = carousel._selected_box
    var media: Node3D = carousel._hero
    var rest_relative := box.global_transform.affine_inverse() * media.global_transform
    var rest_distance := box.global_position.distance_to(media.global_position)
    var box_bounds: AABB = box.call("world_bounds")
    var media_bounds: AABB = media.call("world_bounds")
    _check(is_equal_approx(box_bounds.position.y, media_bounds.position.y), "Both objects must stand on the same resting ground")
    _check(media_bounds.position.z - box_bounds.end.z >= Carousel.PAIR_CLEARANCE - 0.0001, "The entire cartridge must begin ahead of the box's foremost resting geometry")
    carousel.reduced_motion = false
    var pose_count := 0
    for dimensions in [Vector2(1000, 800), Vector2(1600, 900), Vector2(600, 800)]:
        carousel.size = dimensions
        carousel._resize_view()
        for yaw in [-PI, -PI * 0.75, -PI * 0.5, -PI * 0.25, 0.0, PI * 0.25, PI * 0.5, PI * 0.75, PI]:
            for pitch in [-Carousel.PITCH_LIMIT, -0.5, 0.0, 0.5, Carousel.PITCH_LIMIT]:
                for zoom in [Carousel.ZOOM_MINIMUM, 1.0, Carousel.ZOOM_MAXIMUM]:
                    carousel._inspect_yaw = yaw
                    carousel._inspect_pitch = pitch
                    carousel._inspect_zoom = zoom
                    carousel._idle_time = float(pose_count) * 1.7
                    carousel._apply_inspection()
                    carousel._update_contact_shadow()
                    var relative := box.global_transform.affine_inverse() * media.global_transform
                    _check(relative.is_equal_approx(rest_relative), "Relative object poses must remain rigid at every rotation and zoom")
                    _check(is_equal_approx(box.global_position.distance_to(media.global_position) / zoom, rest_distance), "Rotating or zooming must preserve normalized separation")
                    var separating_axis: Vector3 = carousel._pair_transform.basis.z.normalized()
                    var box_projection := _project_geometry(box, separating_axis)
                    var media_projection := _project_geometry(media, separating_axis)
                    _check(media_projection.x - box_projection.y >= Carousel.PAIR_CLEARANCE * zoom - 0.0001, "Actual mesh bounding volumes must remain separated throughout inspection")
                    box_bounds = box.call("world_bounds")
                    media_bounds = media.call("world_bounds")
                    var bounds := box_bounds.merge(media_bounds)
                    _check(is_equal_approx(bounds.position.y, Carousel.PAIR_GROUND_Y), "The assembly must stay grounded without idle floating")
                    _check(is_equal_approx(carousel._shadow.position.y, bounds.position.y - 0.015), "Contact shadow must sit immediately below the actual assembly")
                    for corner in range(8):
                        var point := bounds.get_endpoint(corner)
                        var screen: Vector2 = carousel._camera.unproject_position(point)
                        var viewport_size := Vector2(carousel._viewport.size)
                        _check(not carousel._camera.is_position_behind(point) and Rect2(Vector2.ZERO, viewport_size).has_point(screen), "Every pair corner must stay inside the camera at all supported inspection poses")
                    pose_count += 1
    _check(pose_count == 405, "Exercise all 405 angle, zoom and viewport combinations")
    carousel.size = Vector2(1000, 800)
    carousel.set_presentation(true, false, false)


func _project_geometry(node: Node3D, axis: Vector3) -> Vector2:
    var projection := Vector2(INF, -INF)
    for child in node.find_children("*", "MeshInstance3D", true, false):
        var mesh := child as MeshInstance3D
        if mesh.mesh == null:
            continue
        for corner in range(8):
            var point := mesh.global_transform * mesh.get_aabb().get_endpoint(corner)
            var projected := axis.dot(point)
            projection.x = minf(projection.x, projected)
            projection.y = maxf(projection.y, projected)
    return projection


func _check(condition: bool, message: String) -> void:
    if not condition and not _errors.has(message):
        _errors.append(message)
