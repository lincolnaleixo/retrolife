extends SceneTree

## Exercise navigation and modal ownership with original geometry and an
## in-memory catalog. Never read ROMs, personal preferences or private artwork.
const Fixtures = preload("res://scripts/cartridge_library_smoke.gd")

class FlowShell extends Fixtures.TestShell:
    func _ready() -> void:
        persist_preferences = false
        _fetch_collection_labels = false
        _ensure_input_actions()
        _build_shell()


class GameplayFixture extends Node:
    var started_ids: Array[String] = []
    var active_id := ""

    func start_game(id: String, _title: String) -> Dictionary:
        started_ids.append(id)
        active_id = id
        return {"ok": true}

    func active_session_id() -> String:
        return active_id


var _errors: Array[String] = []
var _checks := 0


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    root.size = Vector2i(1280, 800)
    root.gui_embed_subwindows = true
    var catalog := Fixtures.FakeCatalog.new(5)
    for game in catalog.entries:
        game["playable"] = true
    var gameplay := GameplayFixture.new()
    root.add_child(gameplay)
    var shell := FlowShell.new()
    shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shell._catalog = catalog
    shell._gameplay = gameplay
    root.add_child(shell)
    await shell._refresh_library()
    await _settle(shell)
    var carousel: Control = shell._carousel

    _check(shell._at_console_home and not shell._at_game_details, "Startup begins at console selection")
    _check(not carousel.is_visible_in_tree(), "Cartridges remain hidden until a console is selected")
    _check(shell._console_home._available == ["snes"], "Console selection contains only the populated console")
    shell._console_home.selected.emit("snes")
    await _settle(shell)
    _check(not shell._at_console_home and not shell._at_game_details, "Selecting a console opens its collection overview")
    _check(carousel.is_visible_in_tree() and not shell._info_panel.visible, "Overview presents cartridges without the full metadata page")
    _check(shell._collection_footer.visible and shell._previous_game.visible and shell._next_game.visible, "A collection exposes its title and both navigation arrows")
    _check(not shell._header._box.visible and not shell._header._details.visible, "Game-specific header actions stay out of the collection overview")

    carousel.select_id("fixture-00002")
    await _settle(shell)
    _check(carousel.active_model_count() >= 3, "The selected cartridge has neighboring games in the collection")
    var selected: String = carousel.selected_id()
    carousel.game_activated.emit(selected)
    await _settle(shell)
    _check(shell._at_game_details and shell._info_panel.visible, "Activating a collection cartridge opens its presentation")
    _check(carousel.active_model_count() == 1, "The detail stage contains only its selected cartridge even without box artwork")
    _check(gameplay.started_ids.is_empty(), "Opening a game presentation never launches emulation")
    _check(not shell._collection_footer.visible and not shell._previous_game.visible and not shell._next_game.visible, "The detail stage does not retain collection navigation furniture")
    _check(shell._header._back.accessibility_name == "Back to collection", "The detail Back action names its actual destination")

    shell._header._back.pressed.emit()
    await _settle(shell)
    _check(not shell._at_console_home and not shell._at_game_details, "Back from game presentation returns to the collection")
    _check(carousel.selected_id() == selected and carousel.has_focus(), "Returning to the collection preserves selection and keyboard focus")
    _check(shell._header._back.accessibility_name == "Back to consoles", "Collection Back names the console destination")
    shell._header._back.pressed.emit()
    await _settle(shell)
    _check(shell._at_console_home and shell._console_home.visible, "Back from the collection returns to console selection")
    shell._console_home.selected.emit("snes")
    await _settle(shell)
    _check(not shell._at_game_details and carousel.selected_id() == selected, "Reopening a console restores its collection and selected cartridge")

    carousel.game_activated.emit(selected)
    await _settle(shell)
    carousel.game_activated.emit(selected)
    _check(gameplay.started_ids == [selected] and gameplay.active_id == selected, "Only the second activation, inside game presentation, launches the selected game")
    shell._open_game_presentation("fixture-00001")
    _check(carousel.selected_id() == selected, "Library navigation cannot change the selection during gameplay")
    gameplay.active_id = ""
    shell._on_game_exited(selected)
    await _settle(shell)
    _check(shell._at_game_details and carousel.selected_id() == selected, "Ending gameplay returns to the same game presentation")

    # Escape/B mirrors the visible Back action and does not skip the collection.
    var back := InputEventAction.new()
    back.action = "ui_cancel"
    back.pressed = true
    shell._unhandled_input(back)
    await _settle(shell)
    _check(not shell._at_console_home and not shell._at_game_details and carousel.selected_id() == selected, "Escape from game presentation returns one step to the selected collection cartridge")

    # Unknown games retain neutral presentation and never reuse another game's art.
    shell._game_backdrop.texture = ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGBA8))
    shell._game_backdrop.show()
    carousel.game_activated.emit("fixture-00003")
    await _settle(shell)
    _check(shell._at_game_details and carousel.selected_id() == "fixture-00003", "An unknown game can still open its own detail page")
    _check(carousel.active_model_count() == 1, "Neutral detail fallback cannot retain collection neighbors")
    _check(shell._game_backdrop.texture == null and shell._box_path.is_empty(), "Unknown games clear artwork and box identity")
    _check(not shell._header._box.visible and not shell._inline_preview.visible and not shell._music_controls.visible, "Unavailable optional media does not expose stale controls")
    _check(gameplay.started_ids == [selected], "Inspecting an unknown game does not accidentally launch it")
    shell._open_game_presentation("missing-game")
    _check(carousel.selected_id() == "fixture-00003", "An unknown ID cannot replace the selected presentation")

    var box_path := OS.get_cache_dir().path_join("retrolife-flow-box-%d.glb" % OS.get_process_id())
    _check(_make_box(box_path), "Original box fixture exports successfully")
    shell._box_path = box_path
    carousel.box_activated.emit(carousel.selected_id())
    _check(shell._box_panel.visible and not carousel._active, "Box activation synchronously opens inspection and suspends library input")
    await _settle(shell)
    _check(shell._box_view.model != null and shell._box_done.has_focus(), "Box inspection loads its model and focuses the Done action")
    _check(gameplay.started_ids == [selected], "Box inspection never launches the selected game")
    var inspector_model: Node3D = shell._box_view.model
    shell._restore_carousel_focus()
    await _settle(shell)
    _check(shell._box_panel.gui_get_focus_owner() == shell._box_done and not carousel._active, "Deferred library focus restoration cannot escape an open box inspector")
    _check(carousel._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "The library stage remains suspended while the box inspector is open")
    shell._box_done.pressed.emit()
    await _settle(shell)
    _check(not shell._box_panel.visible and shell._box_view.model == null and not is_instance_valid(inspector_model), "Closing inspection releases its duplicate model")
    _check(shell._at_game_details and carousel.has_focus() and carousel._active, "Closing inspection resumes the same game presentation with library focus")

    shell._return_to_collection()
    await _settle(shell)
    var before_box: String = carousel.selected_id()
    carousel.box_activated.emit(before_box)
    _check(not shell._box_panel.visible, "Collection overview cannot open a hidden box through a stale activation")
    catalog.entries.clear()
    await shell._refresh_library()
    await _settle(shell)
    _check(carousel.games.is_empty() and carousel.active_model_count() == 0, "An empty collection clears all cartridge models")
    _check(not shell._collection_footer.visible and not shell._header._details.visible and not shell._header._box.visible, "Empty results remove stale selected-game controls")
    _check(gameplay.started_ids == [selected], "Navigation and modal round trips produce exactly one intentional launch")

    shell.queue_free()
    gameplay.queue_free()
    await process_frame
    DirAccess.remove_absolute(box_path)
    if _errors.is_empty():
        print("Collection flow smoke passed: %d checks for console → cartridges → game presentation, launch separation, Back, retained selection, neutral/empty fallback and modal focus ownership." % _checks)
        quit(0)
    else:
        for error in _errors:
            push_error(error)
        quit(1)


func _make_box(path: String) -> bool:
    var fixture := Node3D.new()
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(0.18, 0.128, 0.03)
    mesh.mesh = box
    fixture.add_child(mesh)
    mesh.owner = fixture
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    var result := document.append_from_scene(fixture, state) == OK and document.write_to_filesystem(state, path) == OK
    fixture.free()
    return result


func _settle(shell: Control) -> void:
    for _frame in 1000:
        if not shell._refreshing:
            break
        await process_frame
    for _frame in 5:
        await process_frame


func _check(condition: bool, message: String) -> void:
    _checks += 1
    if not condition and not _errors.has(message):
        _errors.append(message)
