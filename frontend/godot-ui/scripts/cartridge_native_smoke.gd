extends "res://scripts/local_library_smoke.gd"

## The full existing native regression plus the real carousel-to-core round trip.
## The backend and ROM remain in the parent smoke's isolated temporary directory.
const Fixtures = preload("res://scripts/cartridge_library_smoke.gd")
const NativeCatalog = preload("res://scripts/catalog_client.gd")


func _execute() -> String:
    var baseline_failure: String = await super._execute()
    if not baseline_failure.is_empty():
        return baseline_failure
    root.size = Vector2i(1280, 720)
    var shell := Fixtures.TestShell.new()
    shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shell.set("_catalog", NativeCatalog.new(_backend))
    shell.set("_backend", _backend)
    shell.set("_gameplay", _gameplay)
    root.add_child(shell)
    _gameplay.configure(_backend, shell)
    _gameplay.game_exited.connect(shell._on_game_exited)
    var failure: String = await _exercise_native_library(shell)
    shell.queue_free()
    await process_frame
    if failure.is_empty():
        print("RetroLife native cartridge round trip passed: real managed import, details, core start, render suspension, saved stop and selection restoration")
    return failure


func _exercise_native_library(shell: Control) -> String:
    await shell._on_files_selected(PackedStringArray([_source_rom]))
    for _frame in range(60):
        if not bool(shell.get("_refreshing")):
            break
        await process_frame
    var carousel: Control = shell.get("_carousel")
    var game_id: String = carousel.selected_id()
    if game_id.is_empty() or carousel.games.size() != 1:
        return "the real managed import did not populate the cartridge library"
    if not bool((carousel.games[0] as Dictionary).get("playable", false)):
        return "the real cartridge library marked the generated ROM unplayable"
    shell._open_details(game_id)
    if not (shell.get("_details_overlay") as Control).visible:
        return "real game details did not open from the cartridge browser"
    if (shell.get("_details_play_button") as Button).disabled:
        return "the real imported cartridge has no enabled Play action"
    shell._play_selected_game()
    var start_failure: String = await _wait_for_status("running")
    if not start_failure.is_empty():
        _backend.call("stop_emulation_json")
        return start_failure
    await process_frame
    if (carousel.get("_viewport") as SubViewport).render_target_update_mode != SubViewport.UPDATE_DISABLED:
        _gameplay._stop_session()
        await _wait_for_stopped()
        return "the cartridge stage kept rendering behind native gameplay"
    _gameplay._stop_session()
    var stop_failure: String = await _wait_for_stopped()
    if not stop_failure.is_empty():
        return stop_failure
    for _frame in range(60):
        await process_frame
        if _gameplay.active_session_id().is_empty() and carousel.has_focus():
            break
    if not _gameplay.active_session_id().is_empty():
        return "native gameplay did not finish the stop/save acknowledgement"
    if carousel.selected_id() != game_id or not carousel.has_focus():
        return "the carousel did not restore selection and focus after native gameplay"
    if (shell.get("_details_overlay") as Control).visible:
        return "details remained open after the native gameplay round trip"
    return ""
