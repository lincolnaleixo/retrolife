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
        print("RetroLife native cartridge round trip passed: real managed import, header details, direct artwork launch, core start, render suspension, saved stop, selection restoration and live ZIP folder discovery/removal")
    return failure


func _exercise_native_library(shell: Control) -> String:
    shell._open_console("snes")
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
    shell._header._details.pressed.emit()
    if not (shell.get("_details_overlay") as Control).visible:
        return "real game details did not open from the integrated header"
    if (shell.get("_details_play_button") as Button).disabled:
        return "the real imported cartridge has no enabled Play action"
    shell._close_details()
    await process_frame
    await process_frame
    carousel.game_activated.emit("missing-game")
    if not _gameplay.active_session_id().is_empty():
        return "an unknown artwork identity started native gameplay"
    _click_selected_cartridge(carousel)
    await process_frame
    await process_frame
    if not bool(shell.get("_at_game_details")) or not _gameplay.active_session_id().is_empty():
        return "the collection artwork must open its game page without starting emulation"
    _click_selected_cartridge(carousel)
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
    return await _exercise_folder_changes(shell)


func _click_selected_cartridge(carousel: Control) -> void:
    var hero: Node3D = carousel.get("_hero")
    var camera: Camera3D = carousel.get("_camera")
    var viewport: SubViewport = carousel.get("_viewport")
    var local_point := camera.unproject_position(hero.global_position) * Vector2(carousel.size) / Vector2(viewport.size).max(Vector2.ONE)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = local_point
    carousel._gui_input(press)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.position = local_point
    carousel._gui_input(release)


func _exercise_folder_changes(shell: Control) -> String:
    # The baseline intentionally tries a duplicate import. Start this scenario
    # with a collection-loading warning instead of that legitimate import notice.
    shell._import_warning = ""
    shell._show_nonfatal_error("The collection could not be loaded.")
    var directory := _smoke_root.path_join("library/snes")
    var original_id: String = shell._carousel.selected_id()
    var original_revision: Variant = shell._presentation_revision
    var bytes := FileAccess.get_file_as_bytes(_source_rom)
    bytes[bytes.size() - 1] = (int(bytes[bytes.size() - 1]) + 1) % 256
    var archive_path := directory.path_join("Added in Finder.zip")
    var archive := ZIPPacker.new()
    if archive.open(archive_path) != OK or archive.start_file("Fixture.sfc") != OK:
        return "could not create the isolated folder fixture"
    archive.write_file(bytes)
    archive.close_file()
    archive.close()
    shell._folder_watch_enabled = true
    var failure := await _wait_for_folder_count(shell, 2)
    if not failure.is_empty():
        return failure
    if shell._carousel.selected_id() != original_id:
        return "automatic folder discovery changed the selected game"
    if shell._presentation_revision == original_revision:
        return "automatic folder discovery did not update the revision"
    if not shell._warning_label.text.is_empty():
        return "a resolved library warning remained visible"
    var renamed := directory.path_join("Readable renamed game.zip")
    DirAccess.rename_absolute(archive_path, renamed)
    # The same payload is still one game after a filesystem rename.
    for tick in range(6):
        shell._poll_rom_folder(2.1)
        await create_timer(0.03).timeout
    if shell._carousel.games.size() != 2:
        return "renaming an archive duplicated or removed its game"
    DirAccess.remove_absolute(renamed)
    failure = await _wait_for_folder_count(shell, 1)
    shell._folder_watch_enabled = false
    if not failure.is_empty():
        return failure
    await shell._on_files_selected(PackedStringArray([directory.path_join("Missing.zip")]))
    var warning: String = shell._warning_label.text
    if warning.is_empty():
        return "a failed import lost its warning during the catalog refresh"
    await shell._refresh_library()
    if shell._warning_label.text != warning:
        return "a subsequent collection refresh erased the failed-import notice"
    return ""


func _wait_for_folder_count(shell: Control, count: int) -> String:
    for tick in range(100):
        shell._poll_rom_folder(2.1)
        await create_timer(0.03).timeout
        if shell._carousel.games.size() == count:
            return ""
    return "the collection did not automatically reflect a folder change"
