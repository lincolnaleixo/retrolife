extends Node

const EXTENSION_PATH := "res://retrolife_launch.gdextension"
const USER_CONFIGURATION_PATH := "user://launch-config.json"

var _launcher: Node
var _details_overlay: Control
var _launch_button: Button
var _cancel_button: Button
var _status_label: Label
var _progress_bar: ProgressBar
var _initialized := false
var _details_was_visible := false
var _current_game_id := ""
var _active_operation_id := ""
var _configuration_loaded := false
var _available := false


func _ready() -> void:
    set_process(false)
    set_process_input(true)
    call_deferred("_initialize")


func _initialize() -> void:
    await get_tree().process_frame
    await get_tree().process_frame

    var load_error := GDExtensionManager.load_extension(EXTENSION_PATH)
    if load_error != OK and load_error != ERR_ALREADY_EXISTS:
        _install_unavailable_controls(
            "Launch extension could not be loaded: %s" % error_string(load_error)
        )
        return
    if not ClassDB.class_exists("RetroLifeLauncher"):
        _install_unavailable_controls("RetroLifeLauncher was not registered by the extension.")
        return

    _launcher = ClassDB.instantiate("RetroLifeLauncher") as Node
    if _launcher == null:
        _install_unavailable_controls("RetroLifeLauncher could not be instantiated.")
        return
    add_child(_launcher)
    _launcher.connect("launch_updated", Callable(self, "_on_launch_updated"))
    _launcher.connect("launch_terminal", Callable(self, "_on_launch_terminal"))

    if not _build_controls():
        push_warning("RetroLife launch controls could not find the game-details container.")
        return

    reload_launch_configuration()
    _initialized = true
    set_process(true)


func _process(_delta: float) -> void:
    if not _initialized or _launcher == null:
        return
    _launcher.call("drain_launch_events_json")

    var details_visible := _details_overlay != null and _details_overlay.visible
    if details_visible and not _details_was_visible:
        _current_game_id = _parent_game_id()
        _refresh_availability()
        if _active_operation_id.is_empty():
            if _available:
                _launch_button.call_deferred("grab_focus")
            else:
                var back := get_parent().find_child("DetailsBackButton", true, false) as Button
                if back != null:
                    back.call_deferred("grab_focus")
    elif not details_visible and _details_was_visible:
        _current_game_id = ""
    _details_was_visible = details_visible


func _input(event: InputEvent) -> void:
    if _active_operation_id.is_empty():
        return
    if event.is_action_pressed("ui_cancel"):
        _request_cancel()
        get_viewport().set_input_as_handled()


func reload_launch_configuration() -> Dictionary:
    if _launcher == null:
        return {"ok": false, "error": {"message": "Launch backend is unavailable."}}

    var candidates: Array[String] = []
    var environment_path := OS.get_environment("RETROLIFE_LAUNCH_CONFIG_PATH").strip_edges()
    if not environment_path.is_empty():
        candidates.append(environment_path)
    if FileAccess.file_exists(USER_CONFIGURATION_PATH):
        candidates.append(USER_CONFIGURATION_PATH)

    if candidates.is_empty():
        _configuration_loaded = false
        _status("Launch is not configured on this device.")
        _refresh_availability()
        return {"ok": false, "error": {"message": "No launch configuration was found."}}

    var path := candidates[0]
    if not FileAccess.file_exists(path):
        _configuration_loaded = false
        _status("Launch configuration does not exist: %s" % path)
        _refresh_availability()
        return {"ok": false, "error": {"message": "Launch configuration does not exist."}}

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        _configuration_loaded = false
        _status("Launch configuration could not be opened: %s" % path)
        _refresh_availability()
        return {"ok": false, "error": {"message": "Launch configuration could not be opened."}}

    var response := _decode(
        _launcher.call("load_launch_configuration_json", file.get_as_text())
    )
    _configuration_loaded = bool(response.get("ok", false))
    if _configuration_loaded:
        var data: Dictionary = response.get("data", {})
        _status(
            "Launch configuration ready: %s games, %s launchers"
            % [data.get("gameCount", 0), data.get("launcherCount", 0)]
        )
    else:
        _status("Launch configuration rejected: %s" % _error_message(response))
    _refresh_availability()
    return response


func active_operation_id() -> String:
    return _active_operation_id


func current_game_id() -> String:
    return _current_game_id


func _build_controls() -> bool:
    _details_overlay = get_parent().find_child("DetailsOverlay", true, false) as Control
    var back_button := get_parent().find_child("DetailsBackButton", true, false) as Button
    if _details_overlay == null or back_button == null or back_button.get_parent() == null:
        return false

    var container := VBoxContainer.new()
    container.name = "LaunchControls"
    container.add_theme_constant_override("separation", 8)
    back_button.get_parent().add_child(container)
    back_button.get_parent().move_child(container, back_button.get_index())

    _status_label = Label.new()
    _status_label.name = "LaunchStatus"
    _status_label.text = "Launch configuration pending"
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label.add_theme_font_size_override("font_size", 15)
    container.add_child(_status_label)

    _progress_bar = ProgressBar.new()
    _progress_bar.name = "LaunchProgress"
    _progress_bar.min_value = 0
    _progress_bar.max_value = 100
    _progress_bar.value = 0
    _progress_bar.show_percentage = true
    _progress_bar.visible = false
    container.add_child(_progress_bar)

    var actions := HBoxContainer.new()
    actions.name = "LaunchActions"
    actions.add_theme_constant_override("separation", 10)
    container.add_child(actions)

    _launch_button = Button.new()
    _launch_button.name = "LaunchButton"
    _launch_button.text = "Launch game"
    _launch_button.custom_minimum_size = Vector2(220, 52)
    _launch_button.disabled = true
    _launch_button.pressed.connect(_queue_launch)
    actions.add_child(_launch_button)

    _cancel_button = Button.new()
    _cancel_button.name = "LaunchCancelButton"
    _cancel_button.text = "Cancel launch"
    _cancel_button.custom_minimum_size = Vector2(220, 52)
    _cancel_button.visible = false
    _cancel_button.pressed.connect(_request_cancel)
    actions.add_child(_cancel_button)
    return true


func _install_unavailable_controls(message: String) -> void:
    if _build_controls():
        _configuration_loaded = false
        _launch_button.disabled = true
        _status(message)
    else:
        push_warning(message)


func _refresh_availability() -> void:
    if _launch_button == null:
        return
    if not _configuration_loaded or _launcher == null:
        _available = false
        _launch_button.disabled = true
        return
    if not _active_operation_id.is_empty():
        _launch_button.disabled = true
        return

    var game_id := _current_game_id
    if game_id.is_empty():
        game_id = _parent_game_id()
    if game_id.is_empty():
        _available = false
        _launch_button.disabled = true
        return

    var response := _decode(_launcher.call("launch_availability_json", game_id))
    if not bool(response.get("ok", false)):
        _available = false
        _launch_button.disabled = true
        _status("Launch availability failed: %s" % _error_message(response))
        return
    var data: Dictionary = response.get("data", {})
    _available = bool(data.get("available", false))
    _launch_button.disabled = not _available
    _status(str(data.get("reason", "Launch availability is unknown.")))


func _queue_launch() -> void:
    if _launcher == null or not _active_operation_id.is_empty():
        return
    var game_id := _current_game_id
    if game_id.is_empty():
        game_id = _parent_game_id()
    var response := _decode(_launcher.call("queue_game_launch_json", game_id))
    if not bool(response.get("ok", false)):
        _status("Launch request failed: %s" % _error_message(response))
        _launch_button.call_deferred("grab_focus")
        return
    var data: Dictionary = response.get("data", {})
    _active_operation_id = str(data.get("operationId", ""))
    _launch_button.disabled = true
    _cancel_button.visible = true
    _cancel_button.disabled = false
    _progress_bar.visible = true
    _progress_bar.value = 0
    _status("Launch queued for %s" % game_id)
    _cancel_button.call_deferred("grab_focus")


func _request_cancel() -> void:
    if _launcher == null or _active_operation_id.is_empty():
        return
    var response := _decode(
        _launcher.call("cancel_game_launch_json", _active_operation_id)
    )
    if not bool(response.get("ok", false)):
        _status("Launch cancellation failed: %s" % _error_message(response))
        return
    _cancel_button.disabled = true
    _status("Cancellation requested. Waiting for the child process to stop.")


func _on_launch_updated(snapshot_json: String) -> void:
    var snapshot: Variant = JSON.parse_string(snapshot_json)
    if typeof(snapshot) != TYPE_DICTIONARY:
        return
    _apply_snapshot(snapshot)


func _on_launch_terminal(snapshot_json: String) -> void:
    var snapshot: Variant = JSON.parse_string(snapshot_json)
    if typeof(snapshot) != TYPE_DICTIONARY:
        return
    _apply_snapshot(snapshot)


func _apply_snapshot(snapshot: Dictionary) -> void:
    var operation_id := str(snapshot.get("operationId", ""))
    if operation_id.is_empty() or operation_id != _active_operation_id:
        return

    var progress: Dictionary = snapshot.get("progress", {})
    _progress_bar.visible = true
    _progress_bar.value = float(progress.get("percent", 0))
    var state := str(snapshot.get("state", "unknown"))
    _status("%s: %s" % [state.capitalize(), progress.get("message", "")])

    var terminal := state in ["completed", "failed", "cancelled"]
    _cancel_button.visible = not terminal and bool(snapshot.get("cancellable", false))
    if not terminal:
        return

    if state == "completed":
        _status("Game session ended normally. RetroLife is ready.")
    elif state == "cancelled":
        _status("Launch cancelled. RetroLife is ready.")
    else:
        var failure: Dictionary = snapshot.get("error", {})
        _status("Launch failed: %s" % failure.get("message", "Unknown launch error"))

    _active_operation_id = ""
    _cancel_button.visible = false
    _launch_button.disabled = not _available
    if _details_overlay != null and _details_overlay.visible:
        if _available:
            _launch_button.call_deferred("grab_focus")
        else:
            var back := get_parent().find_child("DetailsBackButton", true, false) as Button
            if back != null:
                back.call_deferred("grab_focus")


func _parent_game_id() -> String:
    var value: Variant = get_parent().get("_return_game_id")
    if value == null:
        return ""
    return str(value).strip_edges()


func _status(message: String) -> void:
    if _status_label != null:
        _status_label.text = message


static func _decode(raw_json: Variant) -> Dictionary:
    var parsed: Variant = JSON.parse_string(str(raw_json))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {
            "schemaVersion": 1,
            "ok": false,
            "error": {"code": "invalidBridgeJson", "message": "Invalid bridge JSON"},
        }
    return parsed


static func _error_message(response: Dictionary) -> String:
    var error: Variant = response.get("error", {})
    if typeof(error) == TYPE_DICTIONARY:
        return str((error as Dictionary).get("message", "Unknown launch error"))
    return str(error)
