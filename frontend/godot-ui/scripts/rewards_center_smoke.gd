extends SceneTree

## Original fixtures only; never reads workspace.cfg, ROMs or personal progress.
class FixtureCenter extends "res://scripts/workspace/rewards_center.gd":
    var art_root := ""
    var requested: Array[String] = []

    func _art_path(relative: String) -> String:
        requested.append(relative)
        var path := art_root.path_join(relative)
        return path if FileAccess.file_exists(path) else ""


class FixtureCatalog extends RefCounted:
    var entries: Array = [
        {"id": "mario", "title": "Super Mario World (USA) 2", "systemId": "snes", "systemName": "Super Nintendo"},
        {"id": "tetris", "title": "Tetris", "systemId": "game-boy", "systemName": "Game Boy"},
        {"id": "unknown", "title": "An Original Fixture Adventure", "systemId": "snes", "systemName": "Super Nintendo"},
        {"id": "wrong-console", "title": "Super Mario World", "systemId": "nes", "systemName": "Nintendo Entertainment System"},
        {"id": "five", "title": "Fixture Five", "systemId": "snes"},
        {"id": "six", "title": "Fixture Six", "systemId": "snes"},
        {"id": "seven", "title": "Fixture Seven", "systemId": "snes"},
    ]
    var calls := 0

    func view(_system: String, _search: String, offset: int, _limit: int) -> Dictionary:
        calls += 1
        return {"ok": true, "data": {"games": entries.slice(offset, offset + 2), "revision": 1, "hasMore": offset + 2 < entries.size()}}


class FixtureBackend extends Node:
    var reads: Array[String] = []
    var writes := 0
    var fail_id := "never"

    func journey_state_json(id: String) -> String:
        reads.append(id)
        if id == fail_id:
            return JSON.stringify({"schemaVersion": 1, "ok": false, "error": "Fixture progress is unavailable."})
        var seconds := 600 if id == "mario" else (60 if id == "tetris" else (120 if id == "unknown" else 0))
        var earned := 2 if id == "mario" else (1 if id in ["tetris", "unknown"] else 0)
        var personal := ["secret"] if id == "mario" else []
        return JSON.stringify({"schemaVersion": 1, "ok": true, "data": {"seconds": seconds, "earnedTime": earned, "personal": personal, "collected": earned + personal.size(), "totalRewards": 8, "gameXp": earned * 50 + personal.size() * 100, "totalXp": 450, "level": 3, "levelProgress": 50}})

    func journey_confirm_json(_id: String, _milestone: String, _done: bool) -> String:
        writes += 1
        return "{}"


var _errors: Array[String] = []
var _fixture_root := ""

func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    root.size = Vector2i(1280, 800)
    root.gui_embed_subwindows = true
    _fixture_root = ProjectSettings.globalize_path("user://rewards-center-smoke-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
    var art_directory := _fixture_root.path_join("reproductions/snes/super-mario-world/journey/rewards")
    DirAccess.make_dir_recursive_absolute(art_directory)
    for index in range(1, 9):
        var file := FileAccess.open(art_directory.path_join("%02d.svg" % index), FileAccess.WRITE)
        file.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><circle cx="32" cy="32" r="24" fill="#7799bb"/></svg>')
    var backend := FixtureBackend.new()
    root.add_child(backend)
    var catalog := FixtureCatalog.new()
    var center := FixtureCenter.new()
    center.art_root = _fixture_root
    center.theme = preload("res://scripts/workspace/presentation_theme.gd").make_theme()
    root.add_child(center)
    center.configure(backend, catalog)
    await _settle(center)
    _check(catalog.calls == 4 and center._games.size() == 7, "The center must read every library page")
    _check(center._totals == {"collected": 5, "available": 56, "seconds": 780}, "Collection totals must sum actual per-game progress")
    _check(center._level.text == "Level 3" and center._xp.text == "450 total XP", "Global XP must be shown once, never summed across game summaries")
    _check(center._sections.get_child_count() == 6 and center._pager.visible, "Rendered game sections must remain bounded by a page")
    _check(center._next.disabled == false and center._previous.disabled, "Page navigation must reflect the visible page")
    _check(_art_count(center._sections.get_child(0)) == 8, "Matching title and console must load their own reward SVGs")
    _check(_art_count(center._sections.get_child(1)) == 0 and _art_count(center._sections.get_child(3)) == 0, "Missing art and wrong-console titles must stay neutral")
    for path in center.requested:
        _check(not path.contains("/box/"), "The center must not use box art as a journal fallback")
    var read_count := backend.reads.size()
    center._status_select.select(1)
    center._status_select.item_selected.emit(1)
    _check(center._sections.get_child_count() == 3 and _card_count(center) == 5, "Collected filter must show only earned keepsakes")
    center._game_filter.select(1)
    center._game_filter.item_selected.emit(1)
    _check(center._sections.get_child_count() == 1 and _card_count(center) == 3, "Game and collection filters must work together")
    center._status_select.select(2)
    center._status_select.item_selected.emit(2)
    _check(_card_count(center) == 5, "The remaining keepsakes must stay visibly locked")
    _check(backend.reads.size() == read_count and backend.writes == 0, "Filtering must not change progress or reread the backend")
    center._status_select.select(0)
    center._status_select.item_selected.emit(0)
    center._game_filter.select(0)
    center._game_filter.item_selected.emit(0)
    center._next.pressed.emit()
    _check(center._sections.get_child_count() == 1 and center._previous.disabled == false and center._next.disabled, "The last collection page must contain only its remaining games")
    center._previous.pressed.emit()
    await _exercise_layout(center)
    center.hide()
    backend.fail_id = "tetris"
    center.configure(backend, catalog)
    await _settle(center)
    _check(center._totals.is_empty() and center._collected.text == "—", "Failed progress must never be represented as zero or partial totals")
    _check(center._message.visible and center._message.text.contains("Tetris") and not center._refresh.disabled, "A failed game must be identified with a retry action")
    backend.fail_id = "never"
    catalog.entries.clear()
    center.configure(backend, catalog)
    await _settle(center)
    _check(center._collected.text == "0 / 0" and center._sections.get_child_count() == 0, "An empty library must show its actual empty collection")
    _check(center._level.text == "Level 3", "Removing library entries must not invent a reset of all-time XP")
    _check(center._message.text.contains("Import a game"), "The empty state must explain how to begin")
    _check(backend.writes == 0, "The rewards center must never confirm or undo a reward")
    center.free()
    backend.free()
    _remove_tree(_fixture_root)
    if _errors.is_empty():
        print("Rewards center smoke passed: paginated totals, global XP, scoped art, readonly filters, bounded cards, empty/error states and responsive layout.")
        quit(0)
    else:
        for error in _errors:
            push_error(error)
        quit(1)


func _exercise_layout(center: PopupPanel) -> void:
    for dimensions in [Vector2i(900, 600), Vector2i(1280, 800)]:
        root.size = dimensions
        await center.open_centered(dimensions - Vector2i(48, 48))
        for _frame in 5:
            await process_frame
        _check(center.size.x <= dimensions.x and center.size.y <= dimensions.y, "The collection must fit within the host window")
        _check(center._scroll.size.y >= 160, "Compact layouts must retain a useful scrollable collection area")
        _check(center._close.get_global_rect().end.x <= center.size.x, "The Close action must remain on screen")
        _check(center._close.has_focus(), "Opening the collection must offer a focused close action")
        for section in center._sections.get_children():
            var grid: GridContainer = section.get_node("KeepsakeGrid")
            _check(grid.columns >= 3 and grid.columns <= 4, "Collection cards must adapt their columns to the available width")
            _check(grid.size.x <= center._scroll.size.x, "The keepsake grid must not overflow horizontally")


func _art_count(section: Control) -> int:
    var count := 0
    for card in section.get_node("KeepsakeGrid").get_children():
        var stamp: Control = card.get_child(0).get_child(1)
        if stamp.artwork != null:
            count += 1
    return count


func _card_count(center: PopupPanel) -> int:
    var count := 0
    for section in center._sections.get_children():
        count += section.get_node("KeepsakeGrid").get_child_count()
    return count


func _settle(center: PopupPanel) -> void:
    for _frame in range(1000):
        if not center._refresh.disabled:
            break
        await process_frame
    await process_frame
    _check(not center._refresh.disabled, "Collection loading must finish")


func _remove_tree(path: String) -> void:
    var directory := DirAccess.open(path)
    if directory == null:
        return
    for name in directory.get_files():
        DirAccess.remove_absolute(path.path_join(name))
    for name in directory.get_directories():
        _remove_tree(path.path_join(name))
    DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
    if not condition and not _errors.has(message):
        _errors.append(message)
