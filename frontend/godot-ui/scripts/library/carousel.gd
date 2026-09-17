extends Control

signal selection_changed(game: Dictionary, index: int)
signal game_activated(game_id: String)

const CartridgeScene = preload("res://scenes/Cartridge3D.tscn")
const LabelCache = preload("res://scripts/library/label_cache.gd")
const POOL_SIZE := 7
const REPEAT_DELAY := 0.34
const REPEAT_INTERVAL := 0.11
const INSPECT_DAMP := 14.0
const PITCH_LIMIT := PI / 3.0
const ZOOM_MINIMUM := 0.75
const ZOOM_MAXIMUM := 1.6
const ROTATE_PER_PIXEL := 0.0075
const PITCH_PER_PIXEL := 0.0055
const WHEEL_ZOOM_STEP := 0.06
const KEY_ROTATE_SPEED := 1.7
const KEY_PITCH_SPEED := 1.1
const KEY_ZOOM_SPEED := 0.7
const IDLE_YAW_AMPLITUDE := 0.045
const IDLE_BOB_AMPLITUDE := 0.035
const IDLE_SPEED := 0.9

var games: Array = []
var selected_index := -1
var reduced_motion := false
var low_quality := false
var textual_view := false
var force_fallback_model := false
var labels := LabelCache.new()
var _indices: Dictionary = {}
var _pool: Array[Node3D] = []
var _container: SubViewportContainer
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _fallback: VBoxContainer
var _fallback_buttons: Array[Button] = []
var _active := true
var _drag_origin := Vector2.ZERO
var _dragging := false
var _drag_distance := 0.0
var _pan_distance := 0.0
var _held_direction := 0
var _repeat_remaining := REPEAT_DELAY
var _hero: Node3D
var _inspecting := false
var _inspect_yaw := 0.0
var _inspect_pitch := 0.0
var _inspect_zoom := 1.0
var _inspect_target_yaw := 0.0
var _inspect_target_pitch := 0.0
var _inspect_target_zoom := 1.0
var _idle_time := 0.0


func _ready() -> void:
    name = "CartridgeCarousel"
    focus_mode = Control.FOCUS_ALL
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true
    custom_minimum_size = Vector2(0, 220)
    _container = SubViewportContainer.new()
    _container.stretch = true
    _container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(_container)
    _viewport = SubViewport.new()
    _viewport.transparent_bg = true
    _viewport.own_world_3d = true
    _viewport.msaa_3d = Viewport.MSAA_2X
    _viewport.handle_input_locally = false
    _container.add_child(_viewport)
    _world = Node3D.new()
    _world.name = "CartridgeStage"
    _viewport.add_child(_world)
    var environment_node := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_CLEAR_COLOR
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("b8c0db")
    environment.ambient_light_energy = 0.48
    environment_node.environment = environment
    _world.add_child(environment_node)
    _camera = Camera3D.new()
    _camera.fov = 30.0
    _camera.near = 0.1
    _camera.far = 60.0
    _camera.current = true
    _world.add_child(_camera)
    _light(Vector3(-32, -28, 0), Color("eee6db"), 1.15)
    _light(Vector3(-16, 150, 0), Color("b3c8f0"), 0.65)
    _light(Vector3(25, 20, 0), Color("f5d8be"), 0.25)
    _build_shadow()
    for index in range(POOL_SIZE):
        var cartridge := CartridgeScene.instantiate() as Node3D
        cartridge.set("force_fallback", force_fallback_model)
        _world.add_child(cartridge)
        cartridge.visible = false
        _pool.append(cartridge)
    _fallback = VBoxContainer.new()
    _fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _fallback.add_theme_constant_override("separation", 8)
    _fallback.alignment = BoxContainer.ALIGNMENT_CENTER
    add_child(_fallback)
    for index in range(POOL_SIZE):
        var button := Button.new()
        button.custom_minimum_size.y = 36
        button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        button.pressed.connect(_activate_text_button.bind(button))
        _fallback.add_child(button)
        _fallback_buttons.append(button)
    _fallback.hide()
    resized.connect(_resize_view)
    focus_entered.connect(queue_redraw)
    focus_exited.connect(queue_redraw)
    _resize_view()
    _layout(false)


func set_games(entries: Array, preferred_id := "") -> void:
    var old_id := selected_id()
    games = entries
    _indices.clear()
    for index in range(games.size()):
        _indices[str((games[index] as Dictionary).get("id", ""))] = index
    if _indices.has(preferred_id):
        selected_index = int(_indices[preferred_id])
    elif _indices.has(old_id):
        selected_index = int(_indices[old_id])
    else:
        selected_index = clampi(selected_index, 0, games.size() - 1) if not games.is_empty() else -1
    if selected_id() != old_id:
        _reset_inspection()
    _layout(false, true)
    _emit_selection()


func selected_id() -> String:
    if selected_index < 0 or selected_index >= games.size():
        return ""
    return str((games[selected_index] as Dictionary).get("id", ""))


func select_id(game_id: String) -> bool:
    if not _indices.has(game_id):
        return false
    select_index(int(_indices[game_id]))
    return true


func select_index(index: int) -> void:
    if games.is_empty():
        return
    var next := clampi(index, 0, games.size() - 1)
    if next == selected_index:
        return
    selected_index = next
    _reset_inspection()
    _layout(not reduced_motion)
    _emit_selection()


func navigate(direction: int) -> void:
    select_index(selected_index + direction)


func set_presentation(motion_reduced: bool, quality_low: bool, show_text: bool) -> void:
    reduced_motion = motion_reduced
    low_quality = quality_low
    textual_view = show_text
    for item in _pool:
        item.call("set_motion_enabled", not reduced_motion)
    _resize_view()
    _layout(false, true)


func set_active(active: bool) -> void:
    if _active == active:
        return
    _active = active
    _held_direction = 0
    _repeat_remaining = REPEAT_DELAY
    _viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if active and not textual_view else SubViewport.UPDATE_DISABLED
    if not active:
        for item in _pool:
            item.call("set_pointer", Vector2.ZERO)


func refresh_artwork(game_id: String) -> void:
    labels.invalidate(game_id)
    _layout(false, true)


func active_model_count() -> int:
    var count := 0
    for item in _pool:
        if item.visible:
            count += 1
    return count


func pool_size() -> int:
    return _pool.size()


func _emit_selection() -> void:
    var game: Dictionary = games[selected_index] if selected_index >= 0 else {}
    selection_changed.emit(game, selected_index)
    queue_redraw()


func _layout(animate: bool, refresh := false) -> void:
    if _world == null or _fallback == null:
        return
    _container.visible = not textual_view
    _fallback.visible = textual_view
    _viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if _active and not textual_view else SubViewport.UPDATE_DISABLED
    var radius := 1 if low_quality or size.x < 760 else 3
    var first := maxi(0, selected_index - radius)
    var last := mini(games.size(), selected_index + radius + 1)
    if textual_view:
        for item in _pool:
            item.hide()
        # A bounded seven-row text view, not thousands of Control nodes.
        var rows := clampi(floori((size.y - 8) / 46.0), 1, POOL_SIZE)
        first = maxi(0, selected_index - int(rows / 2))
        last = mini(games.size(), first + rows)
        for slot in range(POOL_SIZE):
            var button := _fallback_buttons[slot]
            var index := first + slot
            button.visible = index < last
            if index >= last:
                continue
            var game: Dictionary = games[index]
            button.text = (">  " if index == selected_index else "    ") + str(game.get("title", "Untitled"))
            button.set_meta("index", index)
            button.tooltip_text = "Open details for " + str(game.get("title", "Untitled"))
        return
    var wanted: Dictionary = {}
    for index in range(first, last):
        wanted[str((games[index] as Dictionary).get("id", ""))] = index
    var kept: Dictionary = {}
    var free: Array[Node3D] = []
    for item in _pool:
        var id := str(item.get("game_id"))
        if wanted.has(id) and not kept.has(id):
            kept[id] = item
        else:
            item.hide()
            free.append(item)
    for index in range(first, last):
        var game: Dictionary = games[index]
        var id := str(game.get("id", ""))
        var item: Node3D = kept.get(id) as Node3D
        var rebound := item == null
        if rebound:
            item = free.pop_back()
        if rebound or refresh:
            item.call("bind_game", game, index, labels.texture_for(id, str(game.get("title", ""))))
        var distance := index - selected_index
        var absolute := absi(distance)
        var target := Vector3(distance * 3.65, -0.14 * absolute, -1.35 * absolute)
        var angle := Vector3(deg_to_rad(-3.0), deg_to_rad(-18.0 if distance == 0 else -signi(distance) * 23.0), 0)
        var scale_factor := 1.24 if distance == 0 else maxf(0.62, 0.88 - absolute * 0.065)
        item.call("place", target, angle, scale_factor, distance == 0, animate and not rebound)
        item.call("set_motion_enabled", not reduced_motion)
        item.call("set_pointer", Vector2.ZERO)
        if distance == 0:
            _hero = item
    _apply_inspection()


func _gui_input(event: InputEvent) -> void:
    if not _active:
        return
    if event is InputEventMouseButton:
        if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _zoom_by(WHEEL_ZOOM_STEP)
            accept_event()
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _zoom_by(-WHEEL_ZOOM_STEP)
            accept_event()
        elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
            navigate(-1 if event.button_index == MOUSE_BUTTON_WHEEL_LEFT else 1)
            accept_event()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                grab_focus()
                _drag_origin = event.position
                _drag_distance = 0.0
                _inspecting = selected_index >= 0 and _cartridge_index_at(event.position) == selected_index
                _dragging = not _inspecting
            elif _inspecting:
                _inspecting = false
                if _drag_distance < 14.0 and _cartridge_index_at(event.position) == selected_index:
                    game_activated.emit(selected_id())
            elif _dragging:
                _dragging = false
                if _drag_distance < 14.0:
                    _click_cartridge(event.position)
            accept_event()
    elif event is InputEventMouseMotion:
        if _inspecting:
            _drag_distance += absf(event.relative.x) + absf(event.relative.y)
            _inspect_target_yaw = wrapf(_inspect_target_yaw - event.relative.x * ROTATE_PER_PIXEL, -PI, PI)
            _inspect_target_pitch = clampf(_inspect_target_pitch - event.relative.y * PITCH_PER_PIXEL, -PITCH_LIMIT, PITCH_LIMIT)
            accept_event()
        elif _dragging:
            _drag_distance += absf(event.relative.x)
            var distance: float = event.position.x - _drag_origin.x
            if absf(distance) >= 65:
                navigate(-1 if distance > 0 else 1)
                _drag_origin = event.position
            accept_event()
        elif not reduced_motion:
            var normalized: Vector2 = (event.position / size.max(Vector2.ONE) - Vector2(0.5, 0.5)) * 2.0
            for item in _pool:
                item.call("set_pointer", normalized.clamp(Vector2(-1, -1), Vector2(1, 1)))
    elif event is InputEventPanGesture:
        _pan_distance += (event.delta.x if absf(event.delta.x) > absf(event.delta.y) else event.delta.y) * 16.0
        if absf(_pan_distance) >= 50:
            navigate(1 if _pan_distance > 0 else -1)
            _pan_distance = 0.0
        accept_event()
    elif event is InputEventMagnifyGesture:
        _zoom_by((event.factor - 1.0) * 1.2)
        accept_event()
    elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
        # Shift is the inspection modifier; a shifted key also matches this
        # plain action, so browsing must ignore it here.
        if event is InputEventKey and (event as InputEventKey).shift_pressed:
            accept_event()
            return
        var direction := -1 if event.is_action_pressed("ui_left") else 1
        navigate(direction)
        _held_direction = direction
        _repeat_remaining = REPEAT_DELAY
        accept_event()
    elif event.is_action_pressed("ui_accept") and not selected_id().is_empty():
        game_activated.emit(selected_id())
        accept_event()


func _process(delta: float) -> void:
    if not _active:
        _held_direction = 0
        return
    _idle_time += delta
    _step_inspection(delta)
    if not has_focus():
        _held_direction = 0
        return
    var shift_held := Input.is_key_pressed(KEY_SHIFT)
    var direction := 0 if shift_held else int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left"))
    if direction == 0:
        _held_direction = 0
        return
    if direction != _held_direction:
        _held_direction = direction
        _repeat_remaining = REPEAT_DELAY
        return
    _repeat_remaining -= minf(delta, 0.1)
    if _repeat_remaining <= 0.0:
        navigate(direction)
        _repeat_remaining += REPEAT_INTERVAL


func _step_inspection(delta: float) -> void:
    if has_focus():
        var rotate := Vector2(
            Input.get_action_strength("library_inspect_right") - Input.get_action_strength("library_inspect_left"),
            Input.get_action_strength("library_inspect_down") - Input.get_action_strength("library_inspect_up")
        )
        if rotate != Vector2.ZERO:
            _inspect_target_yaw = wrapf(_inspect_target_yaw - rotate.x * KEY_ROTATE_SPEED * delta, -PI, PI)
            _inspect_target_pitch = clampf(
                _inspect_target_pitch - rotate.y * KEY_PITCH_SPEED * delta, -PITCH_LIMIT, PITCH_LIMIT
            )
        var zoom := Input.get_action_strength("library_zoom_in") - Input.get_action_strength("library_zoom_out")
        if zoom != 0.0:
            _zoom_by(zoom * KEY_ZOOM_SPEED * delta)
        if Input.is_action_just_pressed("library_reset_view"):
            _reset_inspection()
    var weight := 1.0 if reduced_motion else 1.0 - exp(-INSPECT_DAMP * delta)
    _inspect_yaw = lerp_angle(_inspect_yaw, _inspect_target_yaw, weight)
    _inspect_pitch = lerpf(_inspect_pitch, _inspect_target_pitch, weight)
    _inspect_zoom = lerpf(_inspect_zoom, _inspect_target_zoom, weight)
    _apply_inspection()


func _apply_inspection() -> void:
    if _hero == null or not is_instance_valid(_hero) or not _hero.visible:
        return
    var yaw := _inspect_yaw
    var float_offset := 0.0
    if not reduced_motion and not _inspecting:
        yaw += sin(_idle_time * IDLE_SPEED) * IDLE_YAW_AMPLITUDE
        float_offset = sin(_idle_time * IDLE_SPEED * 1.37) * IDLE_BOB_AMPLITUDE
    _hero.call("set_inspection", yaw, _inspect_pitch, _inspect_zoom, float_offset)


func _zoom_by(step: float) -> void:
    _inspect_target_zoom = clampf(_inspect_target_zoom + step, ZOOM_MINIMUM, ZOOM_MAXIMUM)


func _reset_inspection() -> void:
    _inspect_target_yaw = 0.0
    _inspect_target_pitch = 0.0
    _inspect_target_zoom = 1.0
    if reduced_motion:
        _inspect_yaw = 0.0
        _inspect_pitch = 0.0
        _inspect_zoom = 1.0
    _apply_inspection()


func _cartridge_index_at(at: Vector2) -> int:
    if textual_view or _viewport.size.x <= 0:
        return -1
    var point := at * Vector2(_viewport.size) / size.max(Vector2.ONE)
    var best_index := -1
    var closest := INF
    for item in _pool:
        if not item.visible:
            continue
        var center := _camera.unproject_position(item.global_position)
        var edge := _camera.unproject_position(item.global_position + Vector3(1.6, 1.1, 0) * item.scale.x)
        var extent := (edge - center).abs().max(Vector2(20, 20))
        var relative := (point - center).abs() / extent
        var distance := point.distance_to(center)
        if relative.x <= 1.0 and relative.y <= 1.0 and distance < closest:
            closest = distance
            best_index = int(item.get("library_index"))
    return best_index


func _click_cartridge(at: Vector2) -> void:
    var best_index := _cartridge_index_at(at)
    if best_index < 0:
        return
    if best_index == selected_index:
        game_activated.emit(selected_id())
    else:
        select_index(best_index)


func _activate_text_button(button: Button) -> void:
    select_index(int(button.get_meta("index", 0)))
    game_activated.emit(selected_id())


func _resize_view() -> void:
    if _camera == null:
        return
    var ratio := maxf(size.x, 1.0) / maxf(size.y, 1.0)
    _camera.position = Vector3(0, 0.55, maxf(7.5, 7.0 / ratio))
    _camera.look_at(Vector3(0, -0.05, 0), Vector3.UP)
    var budget_shrink := maxi(1, ceili(maxf(size.x / 2560.0, size.y / 1440.0)))
    _container.stretch_shrink = maxi(2 if low_quality else 1, budget_shrink)
    _viewport.msaa_3d = Viewport.MSAA_DISABLED if low_quality else Viewport.MSAA_2X
    _layout(false)
    queue_redraw()


func _light(angles: Vector3, color: Color, energy: float) -> void:
    var light := DirectionalLight3D.new()
    light.rotation_degrees = angles
    light.light_color = color
    light.light_energy = energy
    light.shadow_enabled = false
    _world.add_child(light)


func _build_shadow() -> void:
    var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
    for y in range(64):
        for x in range(64):
            var distance := Vector2(x - 31.5, y - 31.5).length() / 32.0
            image.set_pixel(x, y, Color(0.0, 0.0, 0.0, pow(maxf(0.0, 1.0 - distance), 2.0) * 0.6))
    var material := StandardMaterial3D.new()
    material.albedo_texture = ImageTexture.create_from_image(image)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    var mesh := QuadMesh.new()
    mesh.size = Vector2(7, 2.5)
    var shadow := MeshInstance3D.new()
    shadow.mesh = mesh
    shadow.material_override = material
    shadow.rotation.x = -PI / 2.0
    shadow.position = Vector3(0, -1.18, 0.2)
    _world.add_child(shadow)


func _draw() -> void:
    if has_focus() and _active:
        # Focus belongs to the selected physical object, not a giant card frame.
        var center := size.x * 0.5
        draw_line(Vector2(center - 32, size.y - 7), Vector2(center + 32, size.y - 7), Color("b9a8e2"), 3.0, true)
