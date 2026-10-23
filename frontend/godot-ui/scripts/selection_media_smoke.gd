extends SceneTree

## Offline synthetic selection media only: generated silent WAV files, no game
## assets, network, native emulator, real preferences or external player launch.
const Packs = preload("res://scripts/workspace/game_presentation.gd")

class CatalogFixture:
    extends RefCounted
    var entries: Array = []

    func view(_system := "", _query := "", _offset := 0, _limit := 500) -> Dictionary:
        return {"ok": true, "data": {"revision": 1, "games": entries, "totalGames": entries.size(), "filteredGames": entries.size(), "hasMore": false, "systems": [{"id": "snes", "name": "Super Nintendo", "gameCount": entries.size()}]}}

    func details(id: String) -> Dictionary:
        for game in entries:
            if game.id == id:
                return {"ok": true, "data": game}
        return {"ok": false, "error": "Missing synthetic game."}

class GameplayFixture:
    extends Node
    var active_id := ""
    var launch_music_was_playing := false
    var music_player: AudioStreamPlayer

    func start_game(id: String, _title: String) -> Dictionary:
        launch_music_was_playing = music_player.playing
        active_id = id
        return {"ok": true}

    func active_session_id() -> String:
        return active_id

class LibraryFixture:
    extends "res://scripts/cartridge_library.gd"
    var external_requests: Array[String] = []
    var external_result := OK
    var fixture_media: Dictionary = {}

    func _ready() -> void:
        persist_preferences = false
        _fetch_collection_labels = false
        _ensure_input_actions()
        _build_shell()

    func _open_external_game_video(path: String) -> Error:
        external_requests.append(path)
        return external_result

    func _update_game_presentation(game: Dictionary, profile: Dictionary) -> void:
        var id := str(game.get("id", ""))
        if fixture_media.has(id):
            _presentation_cache[id] = fixture_media[id]
        super._update_game_presentation(game, profile)

var _temporary := ""
var _failure := ""
var _checks := 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _temporary = OS.get_environment("TMPDIR").path_join("retrolife-selection-media-%d" % Time.get_ticks_usec())
    if not _temporary.is_absolute_path():
        _temporary = "/tmp/retrolife-selection-media-%d" % Time.get_ticks_usec()
    DirAccess.make_dir_recursive_absolute(_temporary)
    var first_pack := _make_pack("example-one", 8000)
    var second_pack := _make_pack("example-two", 11025)
    _exercise_pack_validation(first_pack)
    _exercise_music_import(first_pack)
    root.size = Vector2i(1280, 800)
    var shell := LibraryFixture.new()
    shell.settings_path = _temporary.path_join("library-ui.cfg")
    shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var catalog := CatalogFixture.new()
    catalog.entries = [
        {"id": "example-one", "title": "Example One", "systemId": "snes", "systemName": "Super Nintendo", "playable": true},
        {"id": "example-two", "title": "Example Two", "systemId": "snes", "systemName": "Super Nintendo", "playable": true},
        {"id": "no-media", "title": "No Media", "systemId": "snes", "systemName": "Super Nintendo", "playable": true},
    ]
    shell._catalog = catalog
    root.add_child(shell)
    shell.set_process(false)
    shell.fixture_media = {"example-one": first_pack, "example-two": second_pack, "no-media": {}}
    shell._current_games = catalog.entries
    shell._at_console_home = false
    shell._console_home.hide()
    shell._carousel.show()
    shell._carousel.set_games(catalog.entries)
    var gameplay := GameplayFixture.new()
    gameplay.music_player = shell._selection_music
    root.add_child(gameplay)
    shell._gameplay = gameplay
    _select(shell, catalog.entries[0], 0)
    await process_frame
    _check(not shell._selection_music_enabled and not shell._selection_music.playing, "Background music is opt-in and silent by default")
    _check(shell.external_requests.is_empty() and not shell._video_panel.visible and not shell._video_player.is_playing(), "Selecting a game never launches its video automatically")
    _check(shell._media_button.visible, "An available local trailer has a discoverable explicit action")
    shell.persist_preferences = true
    shell._set_selection_music_enabled(true)
    shell._sync_selection_music()
    _check(shell._selection_music.playing and shell._selection_music_path == first_pack.music_path, "Enabling music starts the selected game's own local track")
    shell._set_selection_music_volume(0.2)
    _check(is_equal_approx(db_to_linear(shell._selection_music.volume_db), 0.2), "Selection music volume controls the actual player")
    var config := ConfigFile.new()
    _check(config.load(shell.settings_path) == OK and config.get_value("media", "selection_music_enabled", false) == true, "Music opt-in persists in the isolated library preferences")
    _check(is_equal_approx(float(config.get_value("media", "selection_music_volume", 0.0)), 0.2), "Selection music volume persists independently")
    _check(not FileAccess.file_exists(shell.settings_path + ".tmp"), "Atomic music preference save leaves no temporary file")
    var stream_one := shell._selection_music.stream
    _select(shell, catalog.entries[1], 1)
    _check(shell._selection_music.playing and shell._selection_music_path == second_pack.music_path and shell._selection_music.stream != stream_one, "Changing games replaces the old stream with the new game's music")
    _select(shell, catalog.entries[2], 2)
    _check(not shell._selection_music.playing and shell._selection_music_path.is_empty(), "A game without music immediately stops the previous game's track")
    _check(not shell._media_button.visible and shell._game_backdrop.texture == null, "Missing assets keep the selection neutral without a stale trailer or backdrop")
    _select(shell, catalog.entries[0], 0)
    shell._video_panel.show()
    shell._sync_selection_music()
    _check(not shell._selection_music.playing, "An in-app video preview suppresses selection music")
    shell._video_panel.hide()
    shell._sync_selection_music()
    _check(shell._selection_music.playing, "Closing an in-app preview restores the selected track when enabled")
    shell._media_button.emit_signal("pressed")
    _check(shell.external_requests == [first_pack.video_path] and shell._external_preview_active, "The trailer action explicitly opens only the selected local MP4")
    shell._sync_selection_music()
    _check(not shell._selection_music.playing, "External previews keep background music stopped to prevent overlapping audio")
    _select(shell, catalog.entries[1], 1)
    _check(not shell._selection_music.playing, "Browsing another game cannot overlap a still-open external preview")
    shell._return_from_external_preview()
    shell._sync_selection_music()
    _check(not shell._external_preview_active and shell._selection_music.playing and shell._selection_music_path == second_pack.music_path, "Explicit return from preview restores the currently selected game's music")
    shell._show_console_home()
    shell._sync_selection_music()
    _check(not shell._selection_music.playing, "Console selection does not retain music from a game")
    shell._open_console("snes")
    await process_frame
    await process_frame
    _select(shell, catalog.entries[0], 0)
    shell._sync_selection_music()
    _check(shell._selection_music.playing, "Returning to the game collection restores eligible music")
    shell._return_game_id = "example-one"
    shell._play_selected_game()
    _check(gameplay.active_id == "example-one" and not gameplay.launch_music_was_playing, "Music stops before handing off to gameplay, without even one overlap frame")
    shell._sync_selection_music()
    _check(not shell._selection_music.playing, "A live emulator session cannot restart library music")
    gameplay.active_id = ""
    shell._sync_selection_music()
    _check(shell._selection_music.playing, "Returning from gameplay may resume opted-in music")
    shell._set_selection_music_enabled(false)
    _check(not shell._selection_music.playing, "Disabling background music stops playback immediately")
    shell._set_selection_music_enabled(true)
    shell.external_result = ERR_CANT_OPEN
    shell._show_game_video()
    _check(not shell._external_preview_active, "An external player launch failure cannot leave stale preview ownership")
    shell._sync_selection_music()
    _check(shell._selection_music.playing, "Failed external launch does not leave collection music permanently muted")
    shell._set_selection_music_volume(0.2)
    var fresh := LibraryFixture.new()
    fresh.settings_path = shell.settings_path
    fresh.persist_preferences = true
    fresh._load_preferences()
    _check(fresh._selection_music_enabled and is_equal_approx(fresh._selection_music_volume, 0.2), "A fresh library restores opt-in and volume")
    fresh.free()
    config.load(shell.settings_path)
    config.set_value("media", "selection_music_volume", "not-a-number")
    config.save(shell.settings_path)
    fresh = LibraryFixture.new()
    fresh.settings_path = shell.settings_path
    fresh.persist_preferences = true
    fresh._load_preferences()
    _check(is_finite(fresh._selection_music_volume) and fresh._selection_music_volume >= 0.0 and fresh._selection_music_volume <= 1.0, "Malformed saved volume cannot become an invalid audio gain")
    fresh.free()
    shell._stop_selection_music()
    stream_one = null
    await create_timer(0.15).timeout
    shell.persist_preferences = false
    shell._gameplay = null
    shell.free()
    gameplay.free()
    await create_timer(0.15).timeout
    await process_frame
    _remove_tree(_temporary)
    if _failure.is_empty():
        print("Selection media smoke passed: %d checks; bounded offline packs, explicit preview ownership, opt-in music lifecycle and persisted volume." % _checks)
        quit(0)
    else:
        push_error(_failure)
        quit(1)

func _make_pack(slug: String, rate: int) -> Dictionary:
    var directory := Packs.pack_directory("snes", slug, _temporary)
    DirAccess.make_dir_recursive_absolute(directory)
    var audio := AudioStreamWAV.new()
    audio.format = AudioStreamWAV.FORMAT_16_BITS
    audio.mix_rate = rate
    var samples := PackedByteArray()
    samples.resize(rate * 2 * 4)
    audio.data = samples
    var source := _temporary.path_join(slug + ".wav")
    _check(audio.save_to_wav(source) == OK, "Generated silent WAV fixture is valid")
    var music := Packs.write_media(directory, "music", "wav", FileAccess.get_file_as_bytes(source))
    var video := Packs.write_media(directory, "video", "mp4", PackedByteArray([0, 0, 0, 12, 102, 116, 121, 112, 105, 115, 111, 109]))
    var document := {"schemaVersion": 1, "game": {"system": "snes", "slug": slug, "title": slug}, "media": {"music": music, "video": video}, "source": {"provider": "Synthetic test fixture", "url": ""}}
    _check(Packs.save_document(document, _temporary) == OK, "Music and video pack saves locally")
    var loaded := Packs.load_for_game("snes", slug, _temporary)
    _check(not str(loaded.get("music_path", "")).is_empty(), "Valid music pack returns a verified local path")
    return loaded

func _exercise_pack_validation(pack: Dictionary) -> void:
    var directory := str(pack.music_path).get_base_dir()
    for invalid_path in ["../track.wav", "/tmp/track.wav", "https://example.invalid/song.mp3", "sub/track.ogg", "sub\\track.ogg", "track.gd"]:
        _check(not Packs.valid_media_name(invalid_path, "music"), "Music cannot escape its pack or reference executable/remote content")
        var malformed := pack.duplicate(true)
        malformed.media.music.path = invalid_path
        _check(Packs.clean_document(malformed, "snes", "example-one").is_empty(), "Untrusted music declarations reject the pack")
    _check(Packs.valid_media_name("track.ogg", "music") and Packs.valid_media_name("track.mp3", "music") and Packs.valid_media_name("track.wav", "music"), "Music allowlist includes supported local audio formats")
    _check(not Packs.valid_media_name("track.wav", "background"), "Audio cannot masquerade as a background")
    var bad_hash: Dictionary = pack.media.music.duplicate(true)
    bad_hash.sha256 = "0".repeat(64)
    _check(Packs.local_media_path(directory, bad_hash, "music").is_empty(), "A mismatched music checksum cannot play")
    _check(Packs.local_media_path(directory, {"path": "missing.wav"}, "music").is_empty(), "Missing music falls back to silence")
    var oversized := directory.path_join("oversized.wav")
    var file := FileAccess.open(oversized, FileAccess.WRITE)
    file.seek(Packs.MAX_MUSIC_BYTES)
    file.store_8(0)
    file.close()
    _check(Packs.local_media_path(directory, {"path": "oversized.wav"}, "music").is_empty(), "Oversized audio is rejected before decoding")
    DirAccess.remove_absolute(oversized)
    _check(Packs.load_for_game("snes", "unknown-game", _temporary).is_empty(), "Another game never inherits this music pack")

func _exercise_music_import(pack: Dictionary) -> void:
    var source := _temporary.path_join("example-one.wav")
    var imported := Packs.import_music(source, "snes", "example-one", "Replacement title", _temporary)
    var document_path := str(pack.music_path).get_base_dir().path_join("metadata.json")
    var document := Packs.read_document(document_path, "snes", "example-one")
    _check(imported.ok and document.media.video == pack.media.video and document.game.title == pack.game.title, "Importing music preserves existing game identity and trailer metadata")
    _check(not str(Packs.load_for_game("snes", "example-one", _temporary).get("music_path", "")).is_empty(), "Imported music remains locally decodable and checksum verified")
    var before := FileAccess.get_file_as_string(document_path)
    var invalid := _temporary.path_join("invalid.wav")
    var file := FileAccess.open(invalid, FileAccess.WRITE)
    file.store_string("This is not an audio file")
    file.close()
    var rejected := Packs.import_music(invalid, "snes", "example-one", "", _temporary)
    _check(not rejected.ok and FileAccess.get_file_as_string(document_path) == before, "Invalid audio import retains all existing presentation bytes")

func _select(shell: Control, game: Dictionary, index: int) -> void:
    shell._on_cartridge_selected(game, index)
    shell._sync_selection_music()

func _check(condition: bool, description: String) -> void:
    _checks += 1
    if not condition and _failure.is_empty():
        _failure = description

func _remove_tree(path: String) -> void:
    var directory := DirAccess.open(path)
    if directory == null:
        return
    for child in directory.get_files():
        directory.remove(child)
    for child in directory.get_directories():
        _remove_tree(path.path_join(child))
    DirAccess.remove_absolute(path)
