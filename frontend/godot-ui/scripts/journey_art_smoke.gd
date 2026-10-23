extends SceneTree

## Generated PNG/SVG fixtures only. Never reads the user's collection settings.
const Profiles = preload("res://scripts/workspace/collection_profiles.gd")
const Journal = preload("res://scripts/workspace/journey_panel.gd")
const CHAPTER_IDS := ["first_stage", "secret", "boss", "finale"]

class FixtureJournal extends "res://scripts/workspace/journey_panel.gd":
    var fixture_root := ""
    var requested_paths: Array[String] = []

    func _art_path(relative: String) -> String:
        requested_paths.append(relative)
        var path := fixture_root.path_join(relative)
        return path if FileAccess.file_exists(path) else ""


class FixtureBackend extends Node:
    var confirmations := 0
    var state: Dictionary

    func _init() -> void:
        state = supported_state()

    static func supported_state() -> Dictionary:
        var achievements: Array = []
        for index in CHAPTER_IDS.size():
            achievements.append({"id": CHAPTER_IDS[index], "title": ["Clear a stage on Yoshi's Island", "Discover a secret exit", "Defeat a Koopa Kid", "Rescue Peach"][index], "description": "Detected directly from the game.", "xp": 100, "earned": index == 1, "artIndex": index + 4})
        return {"seconds": 120, "achievements": achievements, "supported": true, "detectionStatus": "watching", "detectionMessage": "Watching for game events.", "legacyPreserved": false, "gameXp": 100, "totalXp": 100, "level": 1, "levelProgress": 100, "collected": 1, "totalRewards": 4}

    static func unsupported_state() -> Dictionary:
        return {"seconds": 0, "achievements": [], "supported": false, "detectionStatus": "unsupported", "detectionMessage": "Automatic rewards are not supported for this game yet.", "legacyPreserved": false, "gameXp": 0, "totalXp": 200, "level": 2, "levelProgress": 0, "collected": 0, "totalRewards": 0}

    func journey_state_json(_id: String) -> String:
        return JSON.stringify({"ok": true, "data": state})

    func journey_confirm_json(_id: String, _milestone: String, _done: bool) -> String:
        confirmations += 1
        return "{}"


var _fixture_root := ""
var _errors: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    root.size = Vector2i(800, 800)
    _fixture_root = ProjectSettings.globalize_path("user://journey-art-smoke-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
    var mario_base := Profiles.asset_base(Profiles.for_game("Super Mario World", "snes"))
    var tetris_base := Profiles.asset_base(Profiles.for_game("Tetris", "game-boy"))
    var sonic_base := Profiles.asset_base(Profiles.for_game("Sonic the Hedgehog", "mega-drive"))
    _write_png(mario_base + "/journey/cover.png", Color("46b282"))
    for id in CHAPTER_IDS:
        _write_svg(mario_base + "/journey/chapters/%s.svg" % id, "#487bc7")
    for index in range(1, 9):
        _write_svg(mario_base + "/journey/rewards/%02d.svg" % index, "#d6a447")
    # This existing box preview must never be substituted for missing journal art.
    _write_png(tetris_base + "/box/hero.png", Color("ef3c62"))
    _write_svg(sonic_base + "/journey/chapters/first_stage.svg", "#845ac5")
    _write_text(sonic_base + "/journey/chapters/secret.svg", "not an SVG image")

    var backend := FixtureBackend.new()
    root.add_child(backend)
    var panel := FixtureJournal.new()
    panel.fixture_root = _fixture_root
    root.add_child(panel)
    panel.size = Vector2(340, 740)
    panel.configure(backend, "fixture-mario", "Super Mario World (USA) 2", "snes")
    await process_frame
    await process_frame
    _exercise_compact_layout(panel)
    _check(panel._profile.get("slug") == "super-mario-world", "A scoped region/dedup title must select its own journal profile")
    _check(panel._art.texture != null and panel._cover_frame.visible, "A dedicated PNG cover must display")
    _check(_color_matches(panel._art.texture, Color("46b282")), "The journal must display the pack's original cover pixels")
    _check(_texture_count(panel._chapter_textures) == 4, "All four chapter SVGs must load from stable milestone names")
    _check(_texture_count(panel._reward_textures) == 4, "Only the four event SVGs must load using their existing zero-padded filenames")
    _check(panel._chapter_statuses[1].text.contains("UNLOCKED") and panel._chapter_statuses[0].text.contains("WAITING"), "Achievement cards must reflect verified backend events")
    _check(panel._xp.value == 100 and panel._time.text.contains("active play"), "XP and active gameplay time must come from the backend")
    _check(not panel._unlock_notice.visible, "The initial summary must not announce previously earned rewards")
    _check(panel._detection.text == "Watching for game events.", "The detector status must come from the backend")
    _check(panel._collection_progress.value == 1 and panel._collection_progress.max_value == 4, "Only four verified event rewards belong in the collection")
    _assert_rendered_art(panel)
    var cover_id: int = panel._art.texture.get_instance_id() if panel._art.texture != null else 0
    var chapter_ids := _texture_ids(panel._chapter_textures)
    var reward_ids := _texture_ids(panel._reward_textures)
    var path_count := panel.requested_paths.size()
    panel.refresh()
    panel.refresh()
    _check(panel._art.texture != null and panel._art.texture.get_instance_id() == cover_id, "Progress polling must reuse the loaded cover")
    _check(_texture_ids(panel._chapter_textures) == chapter_ids and _texture_ids(panel._reward_textures) == reward_ids, "Progress polling must reuse chapter and reward textures")
    _check(panel.requested_paths.size() == path_count, "Progress polling must not reopen the external art pack")
    _check(backend.confirmations == 0, "Loading and refreshing art must never grant a reward")
    _exercise_read_only_updates(panel, backend)
    backend.state = FixtureBackend.unsupported_state()

    panel.configure(backend, "fixture-tetris", "Tetris", "game-boy")
    _check(panel._art.texture == null and not panel._cover_frame.visible, "Missing journal cover must clear the previous game's art, without box fallback")
    _check(_texture_count(panel._chapter_textures) == 0 and _texture_count(panel._reward_textures) == 0, "A game without a pack must clear all stale chapter and reward textures")
    _check(panel._profile.get("slug") == "tetris", "Missing optional art must not remove the game's personalized chapter text")
    _check(panel._reward_grid.get_child_count() == 0 and panel._gift_tab.text == "Collection · 0/0", "An unsupported game must have no invented rewards")
    _check(panel._detection.text.contains("not supported") and not panel._time.visible, "Unsupported detection must be explicit")
    _check(not panel._unlock_notice.visible, "Switching games must clear a previous unlock notice")

    _assert_rendered_art(panel)
    # Deliberately malformed input is expected to fail image decoding.
    var previous_errors := Engine.print_error_messages
    Engine.print_error_messages = false
    panel.configure(backend, "fixture-sonic", "Sonic the Hedgehog", "mega-drive")
    Engine.print_error_messages = previous_errors
    _check(panel._art.texture == null and _texture_count(panel._chapter_textures) == 1, "A partial art pack must load its available chapter without inventing a cover")
    _check(panel._chapter_textures[1] == null, "Malformed optional SVG must remain a neutral chapter placeholder")
    _check(_texture_count(panel._reward_textures) == 0, "Missing reward images must remain neutral")
    _assert_rendered_art(panel)

    backend.state = FixtureBackend.supported_state()
    panel.configure(backend, "fixture-mario", "Super Mario World", "snes")
    _check(panel._art.texture != null, "Returning to a known game must reload its own pack")
    backend.state = FixtureBackend.unsupported_state()
    panel.configure(backend, "fixture-unlisted", "Unlisted Fixture Adventure", "snes")
    _assert_neutral(panel, "An unknown game")
    panel.configure(backend, "fixture-wrong-system", "Super Mario World", "nes")
    _assert_neutral(panel, "A title on the wrong console")
    panel.configure(backend, "fixture-sequel", "Super Mario Bros. 2", "nes")
    _assert_neutral(panel, "An unmatched sequel")
    for path in panel.requested_paths:
        _check(not path.contains("/box/"), "A game journal must never read box artwork as a fallback")
    panel.free()
    backend.free()
    _remove_fixture_tree(_fixture_root)
    if _errors.is_empty():
        print("Journey art smoke passed: scoped PNG/SVG packs, neutral fallbacks, stale clearing, cached refresh, read-only automatic events and unsupported-game states.")
        quit(0)
    else:
        for error in _errors:
            push_error(error)
        quit(1)


func _exercise_read_only_updates(panel: Control, backend: FixtureBackend) -> void:
    _check(_checkbox_count(panel) == 0, "The live Journey must not contain manual checkboxes")
    var click := InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_LEFT
    click.pressed = true
    panel._chapter_cards[0].gui_input.emit(click)
    panel._gift_tab.pressed.emit()
    _check(panel._detection.visible and panel._detection.get_parent() != panel._quests, "Detection status must remain available in the collection tab")
    panel._quests_tab.pressed.emit()
    _check(backend.confirmations == 0 and backend.state.collected == 1, "Clicking cards and tabs must never write progress")
    backend.state.achievements[0].earned = true
    backend.state.collected = 2
    backend.state.gameXp = 200
    backend.state.totalXp = 200
    backend.state.level = 2
    backend.state.levelProgress = 0
    panel.refresh()
    _check(panel._chapter_statuses[0].text.contains("UNLOCKED") and panel._collection_progress.value == 2, "A new game event must update the visible achievement and collection")
    _check(panel._unlock_notice.visible and panel._unlock_notice.text.contains("Yoshi's Island"), "A newly earned live event must produce a compact notice")
    panel._notice_remaining = 0.0
    panel._unlock_notice.hide()
    panel.refresh()
    _check(not panel._unlock_notice.visible, "Repeated summaries must not repeat an unlock notice")
    backend.state.detectionStatus = "waiting"
    backend.state.detectionMessage = "Waiting for active gameplay."
    backend.state.legacyPreserved = true
    panel.refresh()
    _check(panel._legacy.visible and panel._detection.text == "Waiting for active gameplay.", "Preserved legacy entries and detector waiting state must be explained")
    _check(backend.confirmations == 0, "No automatic Journey interaction may invoke a mutation")
    var malformed := backend.state.duplicate(true)
    malformed.collected = 3
    panel._render_response({"ok": true, "data": malformed})
    _check(panel._error.visible and panel._collection_progress.value == 2, "Inconsistent responses must not fabricate collection progress")
    panel.refresh()
    _check(not panel._error.visible, "A valid subsequent snapshot must recover without mutation")


func _checkbox_count(node: Node) -> int:
    var count := 1 if node is CheckBox else 0
    for child in node.get_children():
        count += _checkbox_count(child)
    return count


func _assert_neutral(panel: Control, description: String) -> void:
    _check(panel._profile.is_empty(), description + " must use the neutral profile")
    _check(panel._art.texture == null and not panel._cover_frame.visible, description + " must not retain the prior cover")
    _check(_texture_count(panel._chapter_textures) == 0 and _texture_count(panel._reward_textures) == 0, description + " must not inherit another game's keepsakes")
    _assert_rendered_art(panel)


func _exercise_compact_layout(panel: Control) -> void:
    var summary: Label = panel._summary
    var row: Control = summary.get_parent()
    _check(is_equal_approx(panel.size.x, 340), "The compact journal fixture must exercise a 340-pixel panel")
    _check(summary.get_minimum_size().x > 0, "XP text must retain a nonzero intrinsic width")
    _check(summary.get_line_count() == 1 and summary.size.y < 30, "XP text must remain on one readable line in the compact journal")
    var expected_width := summary.get_theme_font("font").get_string_size(summary.text, HORIZONTAL_ALIGNMENT_LEFT, -1, summary.get_theme_font_size("font_size")).x
    _check(summary.size.x >= expected_width - 1, "The compact XP label must have room for its complete text")
    _check(row.get_global_rect().end.x <= panel.get_global_rect().end.x, "The level and XP row must not overflow the journal")


func _assert_rendered_art(panel: Control) -> void:
    for index in range(4):
        _check(panel._chapter_icons[index].texture == panel._chapter_textures[index], "Visible chapter art must match the newly loaded game pack")
        _check(panel._chapter_numbers[index].visible == (panel._chapter_textures[index] == null), "A chapter without art must display its neutral number")
    var available: int = panel._reward_grid.get_child_count()
    _check(available == 0 or available == 4, "The journal must contain four event rewards or no unsupported rewards")
    for index in range(available):
        var stamp: Control = panel._reward_grid.get_child(index).get_child(0).get_child(0)
        _check(stamp.artwork == panel._reward_textures[index + 4], "Event keepsakes must use their original event artwork, never time rewards")


func _texture_count(textures: Array) -> int:
    var count := 0
    for texture in textures:
        if texture != null:
            count += 1
    return count


func _texture_ids(textures: Array) -> Array:
    var ids: Array = []
    for texture in textures:
        ids.append(texture.get_instance_id() if texture != null else 0)
    return ids


func _color_matches(texture: Texture2D, expected: Color) -> bool:
    if texture == null:
        return false
    var image := texture.get_image()
    return image != null and image.get_pixel(0, 0).is_equal_approx(expected)


func _write_png(relative: String, color: Color) -> void:
    var path := _fixture_root.path_join(relative)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var image := Image.create(128, 80, false, Image.FORMAT_RGBA8)
    image.fill(color)
    _check(image.save_png(path) == OK, "The original PNG fixture must be created")


func _write_svg(relative: String, color: String) -> void:
    _write_text(relative, '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect x="8" y="8" width="48" height="48" rx="8" fill="%s"/></svg>' % color)


func _write_text(relative: String, content: String) -> void:
    var path := _fixture_root.path_join(relative)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(content)


func _remove_fixture_tree(path: String) -> void:
    var directory := DirAccess.open(path)
    if directory == null:
        return
    for child in directory.get_files():
        DirAccess.remove_absolute(path.path_join(child))
    for child in directory.get_directories():
        _remove_fixture_tree(path.path_join(child))
    DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
    if not condition and not _errors.has(message):
        _errors.append(message)
