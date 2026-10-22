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
    var confirmations: Array[Dictionary] = []
    var reject_next := false
    var state := {"seconds": 120, "earnedTime": 1, "personal": ["secret"], "gameXp": 150, "totalXp": 150, "level": 1, "levelProgress": 150, "collected": 2, "totalRewards": 8}

    func journey_state_json(_id: String) -> String:
        return JSON.stringify({"ok": true, "data": state})

    func journey_confirm_json(id: String, milestone: String, done: bool) -> String:
        confirmations.append({"id": id, "milestone": milestone, "done": done})
        if reject_next:
            reject_next = false
            return JSON.stringify({"ok": false, "error": "Fixture save was rejected."})
        var personal: Array = state.personal
        if done and not personal.has(milestone):
            personal.append(milestone)
        elif not done:
            personal.erase(milestone)
        var xp := int(state.earnedTime) * 50 + personal.size() * 100
        state.gameXp = xp
        state.totalXp = xp
        state.level = 1 + xp / 200
        state.levelProgress = xp % 200
        state.collected = int(state.earnedTime) + personal.size()
        return journey_state_json(id)


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
    _check(_texture_count(panel._reward_textures) == 8, "All eight reward SVGs must load using zero-padded filenames")
    _check(panel._personal_buttons[1].button_pressed and not panel._personal_buttons[0].button_pressed, "Art must not change the backend's confirmed chapter state")
    _check(panel._xp.value == 150 and panel._quest_progress.value == 120 and panel._quest_progress.max_value == 600, "XP and session targets must still come from backend progress")
    _check(panel._collection_progress.value == 2 and panel._collection_progress.max_value == 8, "Reward artwork must retain the eight-item collection count")
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
    _check(backend.confirmations.is_empty(), "Loading and refreshing art must never grant a personal reward")
    _exercise_confirmations(panel, backend)

    panel.configure(backend, "fixture-tetris", "Tetris", "game-boy")
    _check(panel._art.texture == null and not panel._cover_frame.visible, "Missing journal cover must clear the previous game's art, without box fallback")
    _check(_texture_count(panel._chapter_textures) == 0 and _texture_count(panel._reward_textures) == 0, "A game without a pack must clear all stale chapter and reward textures")
    _check(panel._profile.get("slug") == "tetris", "Missing optional art must not remove the game's personalized chapter text")
    _check(panel._chapter_titles[0].text.contains("line"), "Switching games must replace the previous chapter captions")

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

    panel.configure(backend, "fixture-mario", "Super Mario World", "snes")
    _check(panel._art.texture != null, "Returning to a known game must reload its own pack")
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
        print("Journey art smoke passed: scoped PNG/SVG packs, neutral fallbacks, stale clearing, cached refresh and unchanged reward semantics.")
        quit(0)
    else:
        for error in _errors:
            push_error(error)
        quit(1)


func _exercise_confirmations(panel: Control, backend: FixtureBackend) -> void:
    var seconds := int(backend.state.seconds)
    var earned := int(backend.state.earnedTime)
    panel._personal_buttons[0].button_pressed = true
    _check(backend.confirmations.back() == {"id": "fixture-mario", "milestone": "first_stage", "done": true}, "A chapter check must retain the stable game and milestone identifiers")
    _check(backend.state.totalXp == 250 and panel._collection_progress.value == 3, "A confirmed chapter must remain worth 100 XP and one reward")
    backend.reject_next = true
    panel._personal_buttons[0].button_pressed = false
    _check(panel._personal_buttons[0].button_pressed and panel._error.visible, "Rejected changes must restore the committed chapter and show the failure")
    panel._personal_buttons[0].button_pressed = false
    _check(not panel._personal_buttons[0].button_pressed and backend.state.totalXp == 150, "A personal chapter check must remain reversible")
    _check(int(backend.state.seconds) == seconds and int(backend.state.earnedTime) == earned, "Personal artwork/checks must never add emulated time or session rewards")


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
    for button in panel._personal_buttons:
        var checked: Texture2D = button.get_theme_icon("checked")
        var unchecked: Texture2D = button.get_theme_icon("unchecked")
        _check(checked != null and unchecked != null and checked.get_width() >= 18 and unchecked.get_width() >= 18, "Chapter checks must have visible touchpoints")
        if checked != null and unchecked != null:
            _check(checked.get_image().get_data() != unchecked.get_image().get_data(), "Completed and incomplete chapters must have distinct check icons")


func _assert_rendered_art(panel: Control) -> void:
    for index in range(4):
        _check(panel._chapter_icons[index].texture == panel._chapter_textures[index], "Visible chapter art must match the newly loaded game pack")
        _check(panel._chapter_numbers[index].visible == (panel._chapter_textures[index] == null), "A chapter without art must display its neutral number")
    _check(panel._reward_grid.get_child_count() == 8, "Game switches must retain exactly eight reward cards")
    for index in range(panel._reward_grid.get_child_count()):
        var stamp: Control = panel._reward_grid.get_child(index).get_child(0).get_child(0)
        _check(stamp.artwork == panel._reward_textures[index], "Rendered keepsakes must not retain a previous game's image")


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
