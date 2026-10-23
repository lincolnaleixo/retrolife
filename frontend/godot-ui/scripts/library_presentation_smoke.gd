extends SceneTree

## Original presentation fixtures only. No credentials, network, ROMs or workspace reads.
const Fixtures = preload("res://scripts/cartridge_library_smoke.gd")

class PresentationCatalog extends RefCounted:
    var entries: Array = [
        {"id": "rich-fixture", "title": "An Original Adventure with a Long Collection Title", "systemId": "snes", "systemName": "Super Nintendo", "playable": false},
        {"id": "neutral-fixture", "title": "A Neutral Fixture", "systemId": "snes", "systemName": "Super Nintendo", "playable": false},
    ]
    var rich := {"year": "1994", "genres": ["Adventure", "Platform"], "players": "2", "developer": "Fixture Studio", "description": "An original fixture description for a journey through a colorful world. Explore its forests, discover hidden paths, and collect treasures. ".repeat(4)}
    var revision := 1
    var detail_calls := 0

    func view(_system := "", query := "", offset := 0, limit := 500) -> Dictionary:
        var games := entries if query.is_empty() else []
        return {"ok": true, "data": {"revision": revision, "games": games.slice(offset, offset + limit), "totalGames": entries.size(), "filteredGames": games.size(), "hasMore": false, "systems": [{"id": "snes", "name": "Super Nintendo", "gameCount": entries.size()}]}}

    func details(id: String) -> Dictionary:
        detail_calls += 1
        return {"ok": true, "data": rich if id == "rich-fixture" else {}}


class ProgressBackend extends Node:
    var writes := 0

    func journey_state_json(_game_id: String) -> String:
        return JSON.stringify({"ok": true, "data": {"seconds": 0, "achievements": [], "supported": false, "detectionStatus": "unsupported", "detectionMessage": "Automatic achievements are not available for this game version yet.", "legacyPreserved": false, "collected": 0, "totalRewards": 0, "gameXp": 0, "totalXp": 0, "level": 1, "levelProgress": 0}})

    func journey_confirm_json(_game_id: String, _milestone: String, _done: bool) -> String:
        writes += 1
        return "{}"


var _errors: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    root.size = Vector2i(1280, 800)
    root.gui_embed_subwindows = true
    var catalog := PresentationCatalog.new()
    var backend := ProgressBackend.new()
    root.add_child(backend)
    var shell := Fixtures.TestShell.new()
    shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shell._catalog = catalog
    shell._backend = backend
    root.add_child(shell)
    shell._open_console("snes")
    await _settle(shell)
    var carousel: Control = shell._carousel
    carousel.select_id("rich-fixture")
    await process_frame
    _check(shell._game_facts.text == "1994  ·  Adventure / Platform  ·  2 players", "Facts must come from actual catalog metadata")
    _check(not shell._carousel.allow_local_art, "Isolated library views never load private box artwork")
    _check(shell._game_source.text == "Fixture Studio" and not shell._game_description.text.is_empty(), "Developer and description must use the selected game's metadata")
    _check(shell._game_backdrop.texture == null and not shell._media_button.visible, "Missing background and video must remain neutral")
    var detail_calls := catalog.detail_calls
    shell._on_cartridge_selected(catalog.entries[0], 0)
    _check(catalog.detail_calls == detail_calls, "Repeated selection must reuse presentation metadata")
    catalog.rich.year = "1995"
    catalog.rich.description = "Updated fixture metadata after a catalog revision."
    catalog.revision += 1
    await shell._refresh_library("rich-fixture")
    await _settle(shell)
    _check(shell._game_facts.text.begins_with("1995") and shell._game_description.text == catalog.rich.description, "A new catalog revision must refresh metadata for the same selected game")
    _check(catalog.detail_calls == detail_calls + 1, "A new catalog revision must reread the selected game's details once")
    catalog.rich.description = "Updated metadata after saving an external presentation pack."
    shell._media_settings.presentation_changed.emit()
    _check(shell._game_description.text == catalog.rich.description, "Saving presentation media must invalidate the selected game's cache even without a catalog revision")

    catalog.rich.description = "Metadata after changing the linked collection. sentinel"
    shell._refresh_workspace_assets()
    await shell._refresh_library("rich-fixture")
    await _settle(shell)
    _check(shell._game_description.text == "Metadata after changing the linked collection." and shell._presentation.description == catalog.rich.description, "Changing collection refreshes the concise summary while preserving the complete description for Details")

    shell.set_process(false)
    shell._inline_still.texture = ImageTexture.create_from_image(Image.create(16, 12, false, Image.FORMAT_RGBA8))
    shell._inline_preview.show()
    shell._music_controls.show()
    for dimensions in [Vector2i(900, 600), Vector2i(1024, 720), Vector2i(1280, 800)]:
        root.size = dimensions
        for _frame in 5:
            await process_frame
        _check(carousel.size.x >= 280 and carousel.size.y >= 180, "Metadata must leave a usable 3D stage in compact windows")
        _check(shell._game_info.get_global_rect().end.x <= carousel.global_position.x, "Game information must not overlap the artwork")
        _check(shell._game_info.get_global_rect().end.y <= shell.size.y, "Game information must remain inside the window")
        _check(shell._header.get_global_rect().end.x <= shell.size.x, "Integrated header actions must fit inside the window")

    shell._inline_still.texture = null
    shell._inline_preview.hide()
    shell._music_controls.hide()
    shell.set_process(true)
    root.size = Vector2i(1024, 640)
    for _frame in 3:
        await process_frame
    shell._header.configure_page(false, true, true)
    shell._header.set_search_query("WWWWWWWWWWWWWWWW")
    for _frame in 3:
        await process_frame
    _check(shell._header.get_global_rect().end.x <= root.size.x - 28, "All header actions and a long search query must fit the minimum window width")
    _check(shell._header._search.tooltip_text.contains("WWWWWWWWWWWWWWWW"), "The complete search query must remain discoverable in the tooltip")
    shell._header.set_search_query("")

    # Simulate the previous game's visual state, then verify every optional field clears.
    shell._game_backdrop.texture = ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGBA8))
    shell._game_backdrop.show()
    shell._media_button.show()
    carousel.select_id("neutral-fixture")
    await process_frame
    _check(shell._game_backdrop.texture == null and not shell._game_backdrop.visible, "Switching to an unknown game must clear the previous backdrop")
    _check(shell._game_description.text.is_empty() and not shell._game_description.visible, "Unknown games must not inherit another game's description")
    _check(shell._game_facts.text.is_empty() and shell._game_source.text.is_empty() and not shell._media_button.visible, "Unknown games must clear facts, developer and video actions")

    shell._header._rewards.pressed.emit()
    for _frame in 6:
        await process_frame
    _check(shell._rewards_panel.visible and shell._rewards_panel._collected.text == "0 / 0", "Header Rewards must show no invented rewards for unsupported library games")
    _check(shell._rewards_panel._close.has_focus(), "The collection must expose a keyboard focused Close action")
    _check(shell._carousel._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Opening Rewards must suspend the 3D stage")
    shell._rewards_panel.hide()
    for _frame in 3:
        await process_frame
    _check(carousel.has_focus(), "Closing Rewards must restore library focus")
    _check(backend.writes == 0, "Browsing Rewards must not confirm or undo any milestone")

    shell._header._menu.grab_focus()
    shell._on_header_action("media")
    for _frame in 4:
        await process_frame
    _check(shell._media_settings.gui_get_focus_owner() is LineEdit, "Opening media from Menu must focus an editable field")
    _check(shell._media_settings.visible and shell._media_settings._query.text == "A Neutral Fixture", "Media settings must target the selected game")
    _check(shell._media_settings._system == "snes" and shell._media_settings._slug == "neutral-fixture", "Unknown titles must retain their own console and stable game identity")
    _check(shell._media_settings._status.text.contains("No requests"), "Opening media settings must not make a remote request")
    for field in shell._media_settings._credentials.values():
        _check(field.text.is_empty(), "Media settings must begin without persisted credentials")
    shell._media_settings.hide()
    for _frame in 3:
        await process_frame
    _check(carousel.has_focus(), "Closing media settings must restore library focus")

    shell._on_search_changed("no result")
    await create_timer(0.18).timeout
    await _settle(shell)
    _check(shell._presentation_identity().is_empty() and shell._game_backdrop.texture == null, "An empty search must not expose a stale game's media identity")
    shell._show_media_settings()
    _check(not shell._media_settings.visible, "Media settings must not open without a selected game")
    shell.queue_free()
    backend.queue_free()
    await process_frame
    if _errors.is_empty():
        print("Library presentation smoke passed: truthful metadata, revision invalidation, neutral switching, responsive split, Rewards integration, media scope, no requests and focus restoration.")
        quit(0)
    else:
        for error in _errors:
            push_error(error)
        quit(1)


func _settle(shell: Control) -> void:
    for _frame in 1000:
        if not shell._refreshing:
            break
        await process_frame
    await process_frame


func _check(condition: bool, message: String) -> void:
    if not condition and not _errors.has(message):
        _errors.append(message)
