extends SceneTree

## Presentation-only fixtures. No ROMs, commercial labels or user library reads.
const Carousel = preload("res://scripts/library/carousel.gd")
const Cartridge = preload("res://scripts/library/cartridge.gd")
const LabelCache = preload("res://scripts/library/label_cache.gd")

class FakeCatalog extends RefCounted:
    var entries: Array = []
    var page_calls := 0

    func _init(count := 10000) -> void:
        for index in range(count):
            entries.append({"id": "fixture-%05d" % index, "title": "Collection %05d" % index, "systemId": "snes", "systemName": "Super Nintendo", "playable": false})

    func view(_system := "", query := "", offset := 0, limit := 500) -> Dictionary:
        page_calls += 1
        var filtered: Array = []
        for entry in entries:
            if query.is_empty() or query.to_lower() in str(entry["title"]).to_lower():
                filtered.append(entry)
        return {"ok": true, "data": {"revision": entries.size(), "games": filtered.slice(offset, offset + limit), "totalGames": entries.size(), "filteredGames": filtered.size(), "hasMore": offset + limit < filtered.size(), "systems": [{"id": "snes", "name": "Super Nintendo", "gameCount": entries.size()}]}}

    func details(id: String) -> Dictionary:
        for entry in entries:
            if entry["id"] == id:
                return {"ok": true, "data": entry}
        return {"ok": false, "error": "Missing fixture"}

    func import_file(_path: String) -> Dictionary:
        var entry := {"id": "imported-fixture", "title": "A Newly Imported Game", "systemId": "snes", "systemName": "Super Nintendo", "playable": false}
        entries.push_front(entry)
        return {"ok": true, "data": entry}


class TestShell extends "res://scripts/cartridge_library.gd":
    func _ready() -> void:
        persist_preferences = false
        _ensure_input_actions()
        _build_shell()


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    var errors: Array[String] = []
    var shell := TestShell.new()
    shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shell.set("_catalog", FakeCatalog.new())
    root.add_child(shell)
    await shell._refresh_library()
    await process_frame
    var carousel: Control = shell.get("_carousel")
    _check(carousel.games.size() == 10000, "All pages, not only the first 500 games, must be visible", errors)
    _check(carousel.pool_size() == 7, "The scene pool must have seven entries", errors)
    carousel.select_id("fixture-05000")
    _check(carousel.selected_id() == "fixture-05000", "Select by stable game ID", errors)
    _check(carousel.active_model_count() <= 7, "Bound active models", errors)
    var before := OS.get_static_memory_usage()
    var timings: Array[int] = []
    for index in range(300):
        var start := Time.get_ticks_usec()
        carousel.navigate(1 if index < 150 else -1)
        timings.append(Time.get_ticks_usec() - start)
        if index % 10 == 0:
            await process_frame
        _check(carousel.active_model_count() <= 7, "Rapid input must keep the scene pool bounded", errors)
        _check(carousel.labels.entry_count() <= 9, "Artwork cache must remain bounded", errors)
    await process_frame
    _check(carousel.selected_id() == "fixture-05000", "Rapid navigation must not drop or reorder input", errors)
    _check(OS.get_static_memory_usage() - before < 96 * 1024 * 1024, "Navigation memory growth exceeded 96 MiB", errors)
    timings.sort()
    print("Cartridge navigation CPU p95 (microseconds): ", timings[int(timings.size() * 0.95)])
    _check(timings[int(timings.size() * 0.95)] < 250000, "Navigation CPU p95 exceeded 250 ms on the test host", errors)
    shell._open_details(carousel.selected_id())
    _check((shell.get("_details_overlay") as Control).visible, "Details must open", errors)
    shell._close_details()
    await process_frame
    _check(carousel.selected_id() == "fixture-05000", "Details round trip must preserve selection", errors)
    shell._on_filter_pressed("snes")
    await _settle(shell)
    carousel.select_id("fixture-02000")
    shell._on_filter_pressed("")
    await _settle(shell)
    _check(carousel.selected_id() == "fixture-05000", "Restore selection per system view", errors)
    carousel.select_index(-200)
    _check(carousel.selected_index == 0, "Clamp the beginning of the collection", errors)
    carousel.select_index(50000)
    _check(carousel.selected_index == 9999, "Clamp the end of the collection", errors)
    shell._on_game_exited("fixture-04200")
    await process_frame
    _check(carousel.selected_id() == "fixture-04200", "Gameplay round trip must restore the selected game", errors)
    shell._on_search_changed("Collection 000")
    await create_timer(0.18).timeout
    await _settle(shell)
    _check(carousel.games.size() == 100, "Debounced search must filter the collection", errors)
    await shell._on_files_selected(PackedStringArray(["synthetic-import.sfc"]))
    await _settle(shell)
    _check(carousel.selected_id() == "imported-fixture", "A new import must be revealed even from an active search", errors)
    carousel.set_presentation(true, true, false)
    _check(carousel.active_model_count() <= 3, "Low-power view must render at most three models", errors)
    carousel.set_presentation(true, false, true)
    _check(carousel.active_model_count() == 0, "Text view must stop 3D rendering", errors)
    carousel.set_active(false)
    _check(int((carousel.get("_viewport") as SubViewport).render_target_update_mode) == SubViewport.UPDATE_DISABLED, "Inactive library rendering must stop", errors)
    carousel.set_active(true)
    carousel.set_presentation(false, false, false)
    var fallback := Cartridge.new()
    fallback.force_fallback = true
    root.add_child(fallback)
    fallback.bind_game({"id": "missing-model", "title": "Neutral Label", "systemId": "snes"}, 0, null)
    _check(fallback.uses_fallback, "Missing models must have a procedural fallback", errors)
    _check(not bool(fallback.get("_artwork_present")), "Missing artwork must display neutral metadata", errors)
    fallback.queue_free()
    var imported := Cartridge.new()
    root.add_child(imported)
    if ResourceLoader.exists(Cartridge.MODEL_PATH):
        _check(not imported.uses_fallback, "The staged GLB must actually instantiate", errors)
    imported.queue_free()
    await _exercise_artwork(errors)
    carousel.set_games([])
    _check(carousel.selected_index == -1 and carousel.active_model_count() == 0, "Empty libraries must not leave stale cartridges", errors)
    shell.queue_free()
    await process_frame
    if errors.is_empty():
        print("RetroLife cartridge library smoke passed: 10000 entries, bounded pool/cache, navigation, filters, search, import, details, return, fallbacks and PNG validation")
        quit(0)
    else:
        for error in errors:
            push_error(error)
        quit(1)


func _exercise_artwork(errors: Array[String]) -> void:
    var id := "artwork-smoke-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
    var directory := "user://" + id
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
    var source := directory.path_join("source.png")
    var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
    image.fill(Color("786694"))
    image.save_png(source)
    var cache := LabelCache.new()
    _check(cache.import_artwork(id, source).is_empty(), "Import a valid local PNG", errors)
    _check(cache.texture_for(id) != null, "Imported artwork must load as a texture", errors)
    var invalid := directory.path_join("invalid.png")
    var file := FileAccess.open(invalid, FileAccess.WRITE)
    file.store_string("not a PNG")
    file.close()
    _check(not cache.validate_png(invalid).is_empty(), "Reject malformed artwork before decoding", errors)
    var oversized := directory.path_join("oversized.png")
    file = FileAccess.open(oversized, FileAccess.WRITE)
    file.store_buffer(PackedByteArray([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,32,0,0,0,32,0]))
    file.close()
    _check(not cache.validate_png(oversized).is_empty(), "Reject oversized PNG dimensions before decoding", errors)
    for path in [source, invalid, oversized, LabelCache.path_for(id)]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
    await process_frame


func _settle(shell: Control) -> void:
    for _frame in range(1000):
        if not bool(shell.get("_refreshing")):
            break
        await process_frame
    await process_frame


func _check(condition: bool, message: String, errors: Array[String]) -> void:
    if not condition and not errors.has(message):
        errors.append(message)
