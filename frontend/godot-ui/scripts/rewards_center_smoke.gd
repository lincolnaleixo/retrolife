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
        {"id": "eight", "title": "Fixture Eight", "systemId": "snes"},
        {"id": "nine", "title": "Fixture Nine", "systemId": "snes"},
        {"id": "wrong-hash", "title": "Super Mario World", "systemId": "snes"},
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
        var supported := id in ["mario", "unknown", "five", "six", "seven", "eight", "nine"]
        var achievements: Array = []
        var ids := ["first_stage", "secret", "boss", "finale"]
        if supported:
            for index in ids.size():
                achievements.append({"id": ids[index], "title": "Event %d" % index, "description": "Detected in the game", "xp": 100, "earned": id == "mario" and index < 2, "artIndex": index + 4})
        return JSON.stringify({"schemaVersion": 1, "ok": true, "data": {"seconds": 600 if id == "mario" else 0, "achievements": achievements, "supported": supported, "detectionStatus": "waiting" if supported else "unsupported", "detectionMessage": "Waiting for game events." if supported else "Automatic rewards are not supported for this game yet.", "legacyPreserved": false, "collected": 2 if id == "mario" else 0, "totalRewards": 4 if supported else 0, "gameXp": 200 if id == "mario" else 0, "totalXp": 200, "level": 2, "levelProgress": 0}})

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
    var illustration := Image.create(128, 128, false, Image.FORMAT_RGBA8)
    illustration.fill(Color("f3a971"))
    _check(illustration.save_png(art_directory.path_join("05.png")) == OK, "The original PNG fixture must be saved")
    var theme_file := FileAccess.open(art_directory.get_base_dir().path_join("theme.json"), FileAccess.WRITE)
    theme_file.store_string(JSON.stringify({"version": 1, "artStyle": "pixel", "cards": {"first_stage": {"rewardName": "Fixture island diorama", "accent": "f3a971"}, "secret": {"rewardName": "Fixture hidden passage", "accent": "a892ed"}}}))
    theme_file.close()
    var backend := FixtureBackend.new()
    root.add_child(backend)
    var catalog := FixtureCatalog.new()
    var center := FixtureCenter.new()
    center.art_root = _fixture_root
    center.theme = preload("res://scripts/workspace/presentation_theme.gd").make_theme()
    root.add_child(center)
    center.configure(backend, catalog)
    await _settle(center)
    _check(catalog.calls == 5 and center._library_size == 10 and center._games.size() == 7, "The center must read every library page and keep only supported games")
    _check(center._game_filter.item_count == 8 and not center._states.has("wrong-hash") and not center._states.has("wrong-console") and not center._states.has("tetris"), "Unsupported games must not appear in sections, filters or totals, even with a matching title")
    _check(center._totals == {"collected": 2, "available": 28, "seconds": 600}, "Collection totals must sum actual per-game progress")
    _check(center._level.text == "Level 2" and center._xp.text == "200 total XP", "Global XP must be shown once, never summed across game summaries")
    _check(center._sections.get_child_count() == 6 and center._pager.visible, "Rendered game sections must remain bounded by a page")
    _check(center._next.disabled == false and center._previous.disabled, "Page navigation must reflect the visible page")
    _check(_art_count(center._sections.get_child(0)) == 4, "Matching title and console must load their own PNG and SVG rewards")
    var custom_grid := center._sections.get_child(0).get_node("KeepsakeGrid")
    var custom_column := custom_grid.get_child(0).get_child(0)
    _check(custom_column.get_child(1).pixel_art and custom_column.get_child(1).texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Pixel packs must preserve nearest filtering in the central collection")
    var displayed_art: Texture2D = custom_column.get_child(1).artwork
    _check(displayed_art != null and displayed_art.get_image().get_pixel(0, 0).is_equal_approx(Color("f3a971")), "The Rewards center must prefer the new PNG illustration over an older SVG")
    var secret_column := custom_grid.get_child(1).get_child(0)
    _check(custom_column.get_child(2).text == "Fixture island diorama" and secret_column.get_child(2).text == "Fixture hidden passage", "The Rewards center must use per-achievement custom names from the optional art theme")
    _check(custom_column.get_child(1).accent == Color("f3a971") and secret_column.get_child(1).accent == Color("a892ed"), "Each custom reward must use its own illustrated theme accent")
    _check(custom_column.get_child(1).custom_minimum_size.y == 160, "Custom illustrations need a prominent, readable display area")
    var basic_column := center._sections.get_child(1).get_node("KeepsakeGrid").get_child(0).get_child(0)
    _check(basic_column.get_child(2).text == "Event 0" and basic_column.get_child(1).accent == Color("91b1c5") and basic_column.get_child(1).custom_minimum_size.y == 60, "Supported games without art use backend achievement titles and compact neutral presentation")
    _check(_art_count(center._sections.get_child(1)) == 0 and _art_count(center._sections.get_child(3)) == 0, "Supported games without a custom art pack must stay neutral")
    for path in center.requested:
        _check(not path.contains("/box/"), "The center must not use box art as a journal fallback")
    _check(_card_count(center) == 24, "Only supported game rewards are rendered within the current page")
    _check(_checkbox_count(center) == 0, "The rewards center must have no manual achievement controls")
    var read_count := backend.reads.size()
    center._status_select.select(1)
    center._status_select.item_selected.emit(1)
    _check(center._sections.get_child_count() == 1 and _card_count(center) == 2, "Collected filter must show only earned keepsakes")
    center._game_filter.select(1)
    center._game_filter.item_selected.emit(1)
    _check(center._sections.get_child_count() == 1 and _card_count(center) == 2, "Game and collection filters must work together")
    center._status_select.select(2)
    center._status_select.item_selected.emit(2)
    _check(_card_count(center) == 2, "The remaining keepsakes must stay visibly locked")
    _check(backend.reads.size() == read_count and backend.writes == 0, "Filtering must not change progress or reread the backend")
    center._status_select.select(0)
    center._status_select.item_selected.emit(0)
    center._game_filter.select(0)
    center._game_filter.item_selected.emit(0)
    center._next.pressed.emit()
    _check(center._sections.get_child_count() == 1 and center._previous.disabled == false and center._next.disabled, "The last collection page must contain only its remaining games")
    center._previous.pressed.emit()
    await _exercise_layout(center)
    for index in range(1, 9):
        DirAccess.remove_absolute(art_directory.path_join("%02d.svg" % index))
    DirAccess.remove_absolute(art_directory.path_join("05.png"))
    center.refresh()
    await _settle(center)
    var without_art := center._sections.get_child(0).get_node("KeepsakeGrid").get_child(0).get_child(0)
    _check(without_art.get_child(1).artwork == null and without_art.get_child(2).text == "Event 0" and without_art.get_child(1).accent == Color("91b1c5"), "A theme file without its game artwork must fall back to basic presentation instead of inventing custom keepsakes")
    center.hide()
    backend.fail_id = "tetris"
    center.configure(backend, catalog)
    await _settle(center)
    _check(center._totals.is_empty() and center._collected.text == "—", "Failed progress must never be represented as zero or partial totals")
    _check(center._message.visible and center._message.text.contains("Tetris") and not center._refresh.disabled, "A failed game must be identified with a retry action")
    backend.fail_id = "never"
    catalog.entries = [{"id": "wrong-hash", "title": "Super Mario World", "systemId": "snes"}]
    center.configure(backend, catalog)
    await _settle(center)
    _check(center._sections.get_child_count() == 0 and center._totals == {"collected": 0, "available": 0, "seconds": 0}, "An unsupported-only library has no quests, reward cards or fabricated totals")
    _check(center._message.text.contains("None of your games have automatic rewards") and center._game_filter.disabled and center._status_select.disabled, "Unsupported-only libraries explain the empty collection without dead filters")
    catalog.entries.clear()
    center.configure(backend, catalog)
    await _settle(center)
    _check(center._collected.text == "0 / 0" and center._sections.get_child_count() == 0, "An empty library must show its actual empty collection")
    _check(center._level.text == "Level 2", "Removing library entries must not invent a reset of all-time XP")
    _check(center._message.text.contains("Import a supported game"), "The empty state must explain how to begin")
    _check(backend.writes == 0, "The rewards center must never confirm or undo a reward")
    center.free()
    backend.free()
    _remove_tree(_fixture_root)
    if _errors.is_empty():
        print("Rewards center smoke passed: support-only pagination and totals, global XP, scoped art, readonly filters, bounded cards, empty/error states and responsive layout.")
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


func _checkbox_count(node: Node) -> int:
    var count := 1 if node is CheckBox else 0
    for child in node.get_children():
        count += _checkbox_count(child)
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
