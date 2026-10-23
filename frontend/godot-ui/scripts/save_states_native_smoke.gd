extends "res://scripts/local_library_smoke.gd"

## A real bridge/core round trip using only the original make-test-rom.py ROM.
## This suite creates its own managed library/save root and never reads user UI
## preferences. The exact fixture hash prevents accidental commercial-ROM use.
const ORIGINAL_FIXTURE_SHA256 := "a0d5a8fdca6bd50fe2cadc5fd08062447c8bfb3cfc5e67cc3109cace09f579e3"
const NATIVE_TIMEOUT_MS := 6000

func _execute() -> String:
    _source_rom = OS.get_environment("RETROLIFE_TEST_ROM")
    if _source_rom.is_empty():
        _source_rom = ProjectSettings.globalize_path("res://../../.cache/test.sfc")
    if not FileAccess.file_exists(_source_rom) or FileAccess.get_sha256(_source_rom) != ORIGINAL_FIXTURE_SHA256:
        return "run make-test-rom.py and provide that exact original fixture through RETROLIFE_TEST_ROM"
    _core_path = OS.get_environment("RETROLIFE_CORE_PATH")
    if _core_path.is_empty():
        _core_path = ProjectSettings.globalize_path("res://bin/" + ("bsnes-jg_libretro.dylib" if OS.get_name() == "macOS" else "bsnes-jg_libretro.so"))
    if not FileAccess.file_exists(_core_path):
        return "the pinned development core is missing"
    var parent := OS.get_environment("RETROLIFE_SMOKE_ROOT")
    if parent.is_empty():
        parent = ProjectSettings.globalize_path("res://../../.cache/godot-ui-smoke")
    _smoke_root = parent.path_join("states-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()])
    if DirAccess.make_dir_recursive_absolute(_smoke_root) != OK:
        return "could not create the isolated native state directory"
    var library := _smoke_root.path_join("library")
    var saves := _smoke_root.path_join("saves")
    var failure := _create_backend(library, saves)
    if not failure.is_empty():
        return failure
    var imported := _decode(_backend.call("library_import_json", _source_rom))
    if not imported.get("ok", false):
        return "synthetic fixture import failed: " + str(imported.get("error", ""))
    var game_id := str(imported.get("data", {}).get("id", ""))
    if game_id.is_empty():
        return "synthetic fixture has no managed identity"
    root.size = Vector2i(1280, 800)
    root.gui_embed_subwindows = true
    _gameplay = preload("res://scripts/launch_integration.gd").new()
    _gameplay.persist_preferences = false
    root.add_child(_gameplay)
    _gameplay.configure(_backend, null)
    var started: Dictionary = _gameplay.start_game(game_id, "Original state fixture")
    if not started.get("ok", false):
        return "native state fixture did not start: " + str(started.get("error", ""))
    failure = await _await_status("running")
    if not failure.is_empty():
        return failure
    failure = await _await_video()
    if not failure.is_empty():
        return failure
    var journey_before := _decode(_backend.call("journey_state_json", game_id))
    if not _unsupported_journey(journey_before):
        return "the original fixture exposed achievements before state operations"

    _gameplay._open_save_states()
    failure = await _await_status("paused")
    if not failure.is_empty():
        return failure
    _gameplay._poll_save_states(true)
    var snapshot := _snapshot()
    if not snapshot.get("supported", false) or snapshot.get("busy", true):
        return "the real core did not expose ready save-state capability"
    if not _gameplay.is_paused() or not _gameplay._states_panel.visible:
        return "the native state browser did not own a real pause"
    _gameplay._states_panel.request_slot_action("save", 0)
    var operation := int(_gameplay._states_operation_id)
    if operation <= 0:
        return "saving empty manual slot did not return an operation identity"
    failure = await _await_operation(operation)
    if not failure.is_empty():
        return failure
    snapshot = _snapshot()
    var slot := _slot(snapshot, 0)
    if not slot.get("occupied", false) or not slot.get("compatible", false) or int(slot.get("createdAt", 0)) <= 0 or int(slot.get("stateBytes", 0)) <= 0:
        return "the completed native save did not expose usable metadata"
    var captured: PackedByteArray = _backend.call("save_state_preview_rgba", 0)
    var preview_width := int(slot.get("previewWidth", 0))
    var preview_height := int(slot.get("previewHeight", 0))
    if preview_width <= 0 or preview_height <= 0 or captured.size() != preview_width * preview_height * 4:
        return "saved preview RGBA does not match its advertised dimensions"
    if _gameplay._states_panel._slot_cards[0].preview.texture == null:
        return "the real save browser did not display the saved preview"
    var state_directory := saves.path_join("snes").path_join(game_id).path_join("states").path_join(ORIGINAL_FIXTURE_SHA256)
    if not FileAccess.file_exists(state_directory.path_join("slot-0.rts")):
        return "the acknowledged native state did not reach its isolated durable file"
    var saved_sequence := _frame_sequence()
    _gameplay._close_save_states()
    failure = await _await_status("running")
    if not failure.is_empty():
        return failure
    failure = await _await_new_frame(saved_sequence)
    if not failure.is_empty():
        return failure

    _gameplay._open_save_states()
    failure = await _await_status("paused")
    if not failure.is_empty():
        return failure
    _gameplay._poll_save_states(true)
    var before_load_sequence := _frame_sequence()
    var before_discontinuity := int(_snapshot().get("discontinuity", 0))
    _gameplay._states_panel.request_slot_action("load", 0)
    if int(_gameplay._states_operation_id) != 0 or not _gameplay._states_panel._confirm_button.is_visible_in_tree():
        return "native loading began before its required confirmation"
    _gameplay._states_panel._confirm_button.emit_signal("pressed")
    operation = int(_gameplay._states_operation_id)
    if operation <= 0:
        return "confirmed native restore did not return an operation identity"
    failure = await _await_operation(operation)
    if not failure.is_empty():
        return failure
    snapshot = _snapshot()
    if int(snapshot.get("discontinuity", 0)) <= before_discontinuity:
        return "a completed native restore did not mark its gameplay discontinuity"
    if not _slot(snapshot, 7).get("occupied", false) or not FileAccess.file_exists(state_directory.path_join("slot-7.rts")):
        return "native restore did not preserve the prior position in Recovery"
    if not _gameplay.is_paused() or _frame_sequence() <= before_load_sequence:
        return "restore did not immediately publish a new frame while remaining paused"
    var texture: Texture2D = _gameplay._frame.texture
    if texture == null or texture.get_size() != Vector2(preview_width, preview_height) or texture.get_image().get_data() != captured:
        return "the restored UI frame differs from the raw saved position"
    var paused_sequence := _frame_sequence()
    await create_timer(0.1).timeout
    if _frame_sequence() != paused_sequence:
        return "the real core advanced frames behind the state browser"
    if not _unsupported_journey(_decode(_backend.call("journey_state_json", game_id))):
        return "state restoration granted an unsupported fixture an achievement"
    _gameplay._close_save_states()
    failure = await _await_status("running")
    if not failure.is_empty():
        return failure
    await _gameplay._stop_session()
    failure = await _await_status("stopped")
    if not failure.is_empty():
        return failure
    if not _gameplay.active_session_id().is_empty():
        return "stopping did not clear the gameplay session"

    # A fresh bridge forces disk reload instead of trusting cached slot entries.
    _backend.free()
    _backend = null
    failure = _create_backend(library, saves)
    if not failure.is_empty():
        return failure
    _gameplay.configure(_backend, null)
    started = _gameplay.start_game(game_id, "Original state fixture reloaded")
    if not started.get("ok", false):
        return "the restarted synthetic fixture did not launch"
    failure = await _await_status("running")
    if not failure.is_empty():
        return failure
    _gameplay._open_save_states()
    failure = await _await_status("paused")
    if not failure.is_empty():
        return failure
    _gameplay._poll_save_states(true)
    snapshot = _snapshot()
    if not _slot(snapshot, 0).get("occupied", false) or not _slot(snapshot, 7).get("occupied", false):
        return "manual and recovery slots did not survive a fresh native bridge"
    if _backend.call("save_state_preview_rgba", 0) != captured:
        return "saved RGBA did not survive the storage reload"
    if not _unsupported_journey(_decode(_backend.call("journey_state_json", game_id))):
        return "persisted state slots invented a Journey for the original fixture"
    _gameplay._close_save_states()
    await _gameplay._stop_session()
    failure = await _await_status("stopped")
    if not failure.is_empty():
        return failure
    print("Save states native smoke passed: original ROM, real core serialization, slot RGBA, confirmed restoration, Recovery, paused frame delivery, fresh bridge persistence and no invented rewards.")
    return ""

func _create_backend(library: String, saves: String) -> String:
    _backend = ClassDB.instantiate("RetroLifeBackend") as Node
    if _backend == null:
        return "the native bridge could not be instantiated"
    for method in ["save_states_json", "save_state_json", "load_state_json", "save_state_preview_rgba"]:
        if not _backend.has_method(method):
            return "rebuild the native bridge; missing " + method
    var configured := _decode(_backend.call("configure_paths_json", library, saves, _core_path))
    return "" if configured.get("ok", false) else str(configured.get("error", "isolated path configuration failed"))

func _snapshot() -> Dictionary:
    return _decode(_backend.call("save_states_json")).get("data", {})

func _slot(snapshot: Dictionary, slot: int) -> Dictionary:
    for entry in snapshot.get("slots", []):
        if int(entry.get("slot", -1)) == slot:
            return entry
    return {}

func _frame_sequence() -> int:
    return int(_decode(_backend.call("emulation_status_json")).get("data", {}).get("frameSequence", 0))

func _await_status(expected: String) -> String:
    var deadline := Time.get_ticks_msec() + NATIVE_TIMEOUT_MS
    while Time.get_ticks_msec() < deadline:
        var status := _decode(_backend.call("emulation_status_json"))
        var data: Dictionary = status.get("data", {})
        if not status.get("ok", false):
            return str(status.get("error", "native status polling failed"))
        if data.get("status", "") == expected:
            return ""
        if data.get("status", "") == "failed":
            return str(data.get("lastError", "native session failed"))
        await create_timer(0.01).timeout
    return "native session did not reach " + expected

func _await_video() -> String:
    var deadline := Time.get_ticks_msec() + NATIVE_TIMEOUT_MS
    while Time.get_ticks_msec() < deadline:
        if _gameplay._frame.texture != null:
            return ""
        await create_timer(0.01).timeout
    return "the native session did not deliver its first frame"

func _await_new_frame(previous: int) -> String:
    var deadline := Time.get_ticks_msec() + NATIVE_TIMEOUT_MS
    while Time.get_ticks_msec() < deadline:
        if _frame_sequence() > previous:
            return ""
        await create_timer(0.01).timeout
    return "resuming the native game did not advance frames"

func _await_operation(expected: int) -> String:
    var deadline := Time.get_ticks_msec() + NATIVE_TIMEOUT_MS
    while Time.get_ticks_msec() < deadline:
        _gameplay._poll_save_states(true)
        var operation: Dictionary = _snapshot().get("operation", {})
        if int(operation.get("id", 0)) == expected:
            if operation.get("status", "") == "failed":
                return str(operation.get("error", "native state operation failed"))
            if operation.get("status", "") == "complete" and not _gameplay._states_busy():
                return ""
        await create_timer(0.01).timeout
    return "native state operation was not acknowledged before the deadline"

func _unsupported_journey(response: Dictionary) -> bool:
    var data: Dictionary = response.get("data", {})
    return response.get("ok", false) and not data.get("supported", true) and int(data.get("gameXp", -1)) == 0 and int(data.get("totalRewards", -1)) == 0 and data.get("achievements", [1]).is_empty()
