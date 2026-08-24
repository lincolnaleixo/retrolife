extends SceneTree

const EXTENSION_PATH := "res://retrolife_launch.gdextension"
const TERMINAL_STATES := ["completed", "failed", "cancelled"]

var _failed := false
var _root_path := ""
var _content_path := ""
var _fixture_path := ""


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    _fixture_path = OS.get_environment("RETROLIFE_LAUNCH_FIXTURE").strip_edges()
    if _fixture_path.is_empty() or not FileAccess.file_exists(_fixture_path):
        _fail("RETROLIFE_LAUNCH_FIXTURE does not point to the built fixture executable.")
        return

    _root_path = ProjectSettings.globalize_path("user://phase4-launch-smoke")
    _content_path = _root_path.path_join("content/chrono-trigger.sfc")
    DirAccess.make_dir_recursive_absolute(_content_path.get_base_dir())
    var content := FileAccess.open(_content_path, FileAccess.WRITE)
    if content == null:
        _fail("Could not create the fixture content file.")
        return
    content.store_string("RetroLife deterministic fixture content")

    var load_error := GDExtensionManager.load_extension(EXTENSION_PATH)
    if load_error != OK and load_error != ERR_ALREADY_EXISTS:
        _fail("Could not load launch extension: %s" % error_string(load_error))
        return
    var launcher := ClassDB.instantiate("RetroLifeLauncher") as Node
    if launcher == null:
        _fail("RetroLifeLauncher could not be instantiated.")
        return
    root.add_child(launcher)

    await _verify_success(launcher)
    if _failed:
        return
    await _verify_nonzero_failure(launcher)
    if _failed:
        return
    await _verify_missing_content(launcher)
    if _failed:
        return
    await _verify_cancellation(launcher)
    if _failed:
        return
    await _verify_bounded_queue(launcher)
    if _failed:
        return

    var shutdown := _decode(launcher.call("shutdown_launch_runtime_json"))
    if not bool(shutdown.get("ok", false)):
        _fail("Launch runtime shutdown failed: %s" % _error_message(shutdown))
        return
    var rejected := _decode(launcher.call("queue_game_launch_json", "chrono-trigger"))
    if bool(rejected.get("ok", true)):
        _fail("A stopped launch runtime accepted new work.")
        return

    launcher.queue_free()
    print(
        "RETROLIFE_LAUNCH_SMOKE_OK plan=true profile=true spawn=true failure=true cancel=true bounded=true return=true"
    )
    quit(0)


func _verify_success(launcher: Node) -> void:
    if not _load_configuration(launcher, 60, 0, _content_path):
        return
    var availability := _decode(launcher.call("launch_availability_json", "chrono-trigger"))
    if not bool(availability.get("ok", false)) \
        or not bool((availability.get("data", {}) as Dictionary).get("available", false)):
        _fail("Chrono Trigger was not available after loading the fixture configuration.")
        return

    var receipt := _decode(launcher.call("queue_game_launch_json", "chrono-trigger"))
    if not bool(receipt.get("ok", false)):
        _fail("Success launch could not be queued: %s" % _error_message(receipt))
        return
    var operation_id := str((receipt.get("data", {}) as Dictionary).get("operationId", ""))
    var terminal := await _await_terminal(launcher, operation_id, 600)
    if _failed:
        return
    if str(terminal.get("state", "")) != "completed":
        _fail("Successful fixture launch did not complete: %s" % terminal)
        return
    var result: Dictionary = terminal.get("result", {})
    if int(result.get("exitCode", -1)) != 0:
        _fail("Successful fixture launch returned the wrong exit code.")
        return
    var observed_path := str(result.get("observedLaunchPath", ""))
    if observed_path.is_empty() or not FileAccess.file_exists(observed_path):
        _fail("The fixture did not write observed-launch.json.")
        return
    var observed_file := FileAccess.open(observed_path, FileAccess.READ)
    var observed: Variant = JSON.parse_string(observed_file.get_as_text())
    if typeof(observed) != TYPE_DICTIONARY:
        _fail("The fixture observed launch is invalid JSON.")
        return
    var data: Dictionary = observed
    if str(data.get("gameId", "")) != "chrono-trigger" \
        or int(data.get("inputProfileCount", 0)) != 1 \
        or str(data.get("environmentGameId", "")) != "chrono-trigger" \
        or str(data.get("environmentSystemId", "")) != "snes":
        _fail("The child process did not observe the expected plan and input profile.")


func _verify_nonzero_failure(launcher: Node) -> void:
    if not _load_configuration(launcher, 30, 7, _content_path):
        return
    var receipt := _decode(launcher.call("queue_game_launch_json", "chrono-trigger"))
    if not bool(receipt.get("ok", false)):
        _fail("Nonzero fixture launch could not be queued.")
        return
    var operation_id := str((receipt.get("data", {}) as Dictionary).get("operationId", ""))
    var terminal := await _await_terminal(launcher, operation_id, 600)
    if _failed:
        return
    var error: Dictionary = terminal.get("error", {})
    if str(terminal.get("state", "")) != "failed" \
        or str(error.get("code", "")) != "launchExitedNonZero":
        _fail("A nonzero child exit did not produce the typed failure.")


func _verify_missing_content(launcher: Node) -> void:
    var missing := _root_path.path_join("content/missing.sfc")
    if not _load_configuration(launcher, 20, 0, missing):
        return
    var receipt := _decode(launcher.call("queue_game_launch_json", "chrono-trigger"))
    if not bool(receipt.get("ok", false)):
        _fail("Missing-content launch could not be queued for preparation.")
        return
    var operation_id := str((receipt.get("data", {}) as Dictionary).get("operationId", ""))
    var terminal := await _await_terminal(launcher, operation_id, 600)
    if _failed:
        return
    var error: Dictionary = terminal.get("error", {})
    if str(terminal.get("state", "")) != "failed" \
        or str(error.get("code", "")) != "launchPreparationFailed":
        _fail("Missing content did not fail during Rust preparation.")


func _verify_cancellation(launcher: Node) -> void:
    if not _load_configuration(launcher, 3_000, 0, _content_path):
        return
    var receipt := _decode(launcher.call("queue_game_launch_json", "chrono-trigger"))
    if not bool(receipt.get("ok", false)):
        _fail("Cancellable fixture launch could not be queued.")
        return
    var operation_id := str((receipt.get("data", {}) as Dictionary).get("operationId", ""))
    var running := await _await_state(launcher, operation_id, "running", 600)
    if not running:
        return
    var cancel := _decode(launcher.call("cancel_game_launch_json", operation_id))
    if not bool(cancel.get("ok", false)) \
        or not bool((cancel.get("data", {}) as Dictionary).get("cancellationRequested", false)):
        _fail("Cancellation request was rejected.")
        return
    var terminal := await _await_terminal(launcher, operation_id, 600)
    if _failed:
        return
    if str(terminal.get("state", "")) != "cancelled":
        _fail("Cancelled child process did not reach the cancelled terminal state.")


func _verify_bounded_queue(launcher: Node) -> void:
    if not _load_configuration(launcher, 3_000, 0, _content_path, 6):
        return
    var accepted: Array[String] = []
    var queue_full := false
    for index in range(6):
        var game_id := "fixture-%s" % index
        var receipt := _decode(launcher.call("queue_game_launch_json", game_id))
        if bool(receipt.get("ok", false)):
            accepted.append(str((receipt.get("data", {}) as Dictionary).get("operationId", "")))
        elif str((receipt.get("error", {}) as Dictionary).get("code", "")) == "launchQueueFull":
            queue_full = true
    if not queue_full:
        _fail("The bounded launch queue never reported launchQueueFull.")
        return
    for operation_id in accepted:
        launcher.call("cancel_game_launch_json", operation_id)
    for operation_id in accepted:
        await _await_terminal(launcher, operation_id, 800)
        if _failed:
            return


func _load_configuration(
    launcher: Node,
    sleep_ms: int,
    exit_code: int,
    content_path: String,
    extra_games := 0
) -> bool:
    var games: Array = [{
        "gameId": "chrono-trigger",
        "systemId": "snes",
        "contentPath": content_path,
        "launcherId": "fixture",
    }]
    for index in range(extra_games):
        games.append({
            "gameId": "fixture-%s" % index,
            "systemId": "snes",
            "contentPath": content_path,
            "launcherId": "fixture",
        })
    var configuration := {
        "schemaVersion": 1,
        "saveRoot": _root_path.path_join("saves"),
        "sessionRoot": _root_path.path_join("sessions"),
        "launchers": [{
            "id": "fixture",
            "systemIds": ["snes"],
            "executable": _fixture_path,
            "arguments": [
                "--game-id", "{gameId}",
                "--content", "{contentPath}",
                "--save-dir", "{saveDir}",
                "--session-dir", "{sessionDir}",
                "--input-profile", "{inputProfilePath}",
                "--sleep-ms", str(sleep_ms),
                "--exit-code", str(exit_code),
            ],
            "workingDirectory": "{sessionDir}",
            "environment": {
                "RETROLIFE_GAME_ID": "{gameId}",
                "RETROLIFE_SYSTEM_ID": "{systemId}",
            },
            "timeoutMs": 10_000,
            "maxOutputBytes": 16_384,
            "returnPolicy": "waitForExit",
        }],
        "games": games,
        "inputProfiles": [_input_profile()],
    }
    var response := _decode(
        launcher.call("load_launch_configuration_json", JSON.stringify(configuration))
    )
    if not bool(response.get("ok", false)):
        _fail("Fixture launch configuration was rejected: %s" % _error_message(response))
        return false
    return true


func _input_profile() -> Dictionary:
    var bindings: Array = []
    var actions := ["up", "down", "left", "right", "south", "east", "start"]
    for index in range(actions.size()):
        bindings.append({
            "action": actions[index],
            "input": {"kind": "button", "code": index},
        })
    return {
        "id": "fixture-snes-player-1",
        "systemId": "snes",
        "player": 1,
        "glyphFamily": "generic",
        "controller": {
            "stableId": "fixture-controller",
            "displayName": "Fixture Controller",
        },
        "bindings": bindings,
    }


func _await_state(
    launcher: Node,
    operation_id: String,
    expected_state: String,
    maximum_frames: int
) -> bool:
    for _frame in range(maximum_frames):
        launcher.call("drain_launch_events_json")
        var status := _decode(launcher.call("launch_status_json", operation_id))
        if bool(status.get("ok", false)):
            var snapshot: Dictionary = status.get("data", {})
            var state := str(snapshot.get("state", ""))
            if state == expected_state:
                return true
            if state in TERMINAL_STATES:
                _fail("Operation became %s before reaching %s." % [state, expected_state])
                return false
        await process_frame
    _fail("Operation did not reach %s within the frame budget." % expected_state)
    return false


func _await_terminal(
    launcher: Node,
    operation_id: String,
    maximum_frames: int
) -> Dictionary:
    for _frame in range(maximum_frames):
        launcher.call("drain_launch_events_json")
        var status := _decode(launcher.call("launch_status_json", operation_id))
        if bool(status.get("ok", false)):
            var snapshot: Dictionary = status.get("data", {})
            if str(snapshot.get("state", "")) in TERMINAL_STATES:
                return snapshot
        await process_frame
    _fail("Launch operation did not reach a terminal state within the frame budget.")
    return {}


static func _decode(raw_json: Variant) -> Dictionary:
    var parsed: Variant = JSON.parse_string(str(raw_json))
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func _error_message(response: Dictionary) -> String:
    var error: Dictionary = response.get("error", {})
    return str(error.get("message", "Unknown launch error"))


func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    push_error("RETROLIFE_LAUNCH_SMOKE_FAILED: %s" % message)
    quit(1)
