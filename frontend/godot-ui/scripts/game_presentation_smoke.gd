extends SceneTree

const Packs = preload("res://scripts/workspace/game_presentation.gd")
const Client = preload("res://scripts/workspace/screenscraper_client.gd")
const MediaPanel = preload("res://scripts/workspace/media_settings_panel.gd")
var _failures: Array[String] = []
var _checks := 0
var _temporary := ""
var _cancel_result: Dictionary = {}

class FixtureClient extends "res://scripts/workspace/screenscraper_client.gd":
    var responses: Array[Dictionary] = []
    var calls: Array[Dictionary] = []
    func _request(endpoint: String, _credentials: Dictionary, parameters: Dictionary, _limit: int) -> Dictionary:
        calls.append({"endpoint": endpoint, "parameters": parameters.duplicate(true)})
        await get_tree().process_frame
        return responses.pop_front() if not responses.is_empty() else {"ok": false, "error": "Fixture failure"}

class WaitingClient extends "res://scripts/workspace/screenscraper_client.gd":
    func _request(_endpoint: String, _credentials: Dictionary, _parameters: Dictionary, _limit: int) -> Dictionary:
        _active = HTTPRequest.new()
        add_child(_active)
        var result: Dictionary = await _network_done
        _active.queue_free()
        _active = null
        return result

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, description: String) -> void:
    _checks += 1
    if not condition:
        _failures.append(description)

func _write(path: String, text: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(text)
    file.close()

func _fixture() -> Dictionary:
    return {"id": "123", "systeme": {"id": "4"}, "noms": [{"region": "jp", "text": "Japanese title"}, {"region": "us", "text": "Example Game"}], "synopsis": [{"langue": "fr", "text": "French"}, {"langue": "en", "text": "English description"}], "developpeur": {"text": "Example Studio"}, "editeur": {"text": "Example Publisher"}, "dates": [{"region": "us", "text": "1991-08-23"}], "genres": [{"noms": [{"langue": "en", "text": "Platform"}]}], "joueurs": {"text": "1-2"}, "medias": [{"type": "fanart", "region": "us", "url": "https://untrusted.invalid/?devpassword=never-persist"}, {"type": "video", "region": "wor", "url": "https://untrusted.invalid/video"}]}

func _run() -> void:
    _temporary = OS.get_environment("TMPDIR").path_join("retrolife-presentation-smoke-%s" % Time.get_ticks_usec())
    if not _temporary.is_absolute_path():
        _temporary = "/tmp/retrolife-presentation-smoke-%s" % Time.get_ticks_usec()
    DirAccess.make_dir_recursive_absolute(_temporary)
    var doc := Client.parse_game(_fixture(), "snes", "example-game", "123")
    _check(doc.game.title == "Example Game" and doc.description == "English description", "US title and English synopsis")
    _check(doc.genre == "Platform" and doc.year == "1991" and doc.players == "1-2", "Metadata normalization")
    _check(not "never-persist" in JSON.stringify(doc) and not "untrusted.invalid" in JSON.stringify(doc), "API media URLs are discarded")
    _check(Client.parse_game(_fixture(), "nes", "example-game", "123").is_empty(), "Wrong console rejected")
    _check(Client.parse_game(_fixture(), "snes", "example-game", "124").is_empty(), "Wrong exact game rejected")
    _check(Client.parse_search({"response": {"jeux": [_fixture(), {"id": "2", "systeme": {"id": "3"}, "noms": [{"region": "us", "text": "Other console"}]}]}}, "snes").size() == 1, "Search filters by console")
    _check(Client.choose_media(_fixture(), "background").selector == "fanart(us)", "Fanart chosen from allowlisted media")
    _check(Client.choose_media(_fixture(), "video").selector == "video(wor)", "Video selector")
    _exercise_video_selection()
    _check(Client.localized([{ "langue": "fr", "text": "French"}], "langue", ["en"]).is_empty(), "No foreign-language synopsis fallback")
    _check(not Client.credential_error({}).is_empty(), "Developer credentials required")
    _check(not Client.credential_error({"devid": "fixture", "devpassword": "fixture", "ssid": "user"}).is_empty(), "Partial user credentials rejected")
    _check("quota" in Client.status_error(430) and "not forwarded" in Client.status_error(302), "Quota and redirects have safe messages")
    for invalid in [null, [], "text", {"schemaVersion": {}}, {"schemaVersion": 1, "game": []}, {"schemaVersion": 1, "game": {"system": "snes", "slug": "../elsewhere"}}]:
        _check(Packs.clean_document(invalid, "snes", "example-game").is_empty(), "Malformed metadata safely rejected")
    _check(Packs.pack_directory("snes", "../escape", _temporary).is_empty(), "Slug traversal rejected")
    _check(not Packs.valid_media_name("../background.png", "background") and not Packs.valid_media_name("https://x/image.png", "background"), "Media paths confined to basenames")
    _check(Packs.public_url("https://provider.example/game?key=secret#token") == "https://provider.example/game", "Source URL queries stripped")
    _check(Packs.public_url("https://user:secret@example.org/").is_empty(), "Source URL userinfo rejected")
    doc.source.provider = "Nintendo"
    _check(Packs.save_document(doc, _temporary) == OK, "External provider saved")
    var read := Packs.load_for_game("snes", "example-game", _temporary)
    _check(read.source_name == "Nintendo" and read.background_path.is_empty(), "Offline metadata loads without media")
    _check(Packs.load_for_game("snes", "other-game", _temporary).is_empty(), "No cross-game fallback")
    var picture := Image.create(8, 8, false, Image.FORMAT_RGB8)
    picture.fill(Color("346867"))
    var image_bytes := picture.save_png_to_buffer()
    _check(Client.bounded_png(image_bytes) and not Client.bounded_png("not an image".to_utf8_buffer()), "PNG dimensions checked before decode")
    var oversized := image_bytes.duplicate()
    oversized[16] = 127
    _check(not Client.bounded_png(oversized), "Oversized image dimensions rejected")
    var invalid_media := doc.duplicate(true)
    invalid_media.media.background = {"path": "../elsewhere.png"}
    _check(Packs.clean_document(invalid_media, "snes", "example-game").is_empty(), "Invalid declared media rejects the pack")
    var directory := Packs.pack_directory("snes", "example-game", _temporary)
    var media := Packs.write_media(directory, "background", "png", image_bytes)
    _check(not media.is_empty(), "Content-addressed image written")
    doc.media.background = media
    _check(Packs.save_document(doc, _temporary) == OK, "Media metadata saved")
    read = Packs.load_for_game("snes", "example-game", _temporary)
    _check(not read.background_path.is_empty(), "Media checksum verified")
    var broken := media.duplicate()
    broken.sha256 = "0".repeat(64)
    _check(Packs.local_media_path(directory, broken, "background").is_empty(), "Digest mismatch rejected")
    var original := FileAccess.get_file_as_string(directory.path_join("metadata.json"))
    var imported := doc.duplicate(true)
    imported.media.background.path = "missing.png"
    _write(_temporary.path_join("invalid.json"), JSON.stringify(imported))
    var failed := Packs.import_pack(_temporary.path_join("invalid.json"), "snes", "example-game", _temporary)
    _check(not failed.ok and FileAccess.get_file_as_string(directory.path_join("metadata.json")) == original, "Failed import preserves current presentation")
    var client := FixtureClient.new()
    root.add_child(client)
    var credentials := {"devid": "fixture-only", "devpassword": "fixture-only"}
    client.responses = [{"ok": true, "body": JSON.stringify({"response": {"jeu": _fixture(), "ssuser": {"password": "do-not-save"}}}).to_utf8_buffer()}, {"ok": true, "body": image_bytes}]
    var fetched := await client.fetch_game(credentials, "snes", "example-game", "123", true, false, _temporary)
    _check(fetched.ok and client.calls.size() == 2, "Explicit metadata and image fetch transaction")
    _check(client.calls[0].parameters.has("gameid") and not client.calls[0].parameters.has("jeuid"), "Exact-game endpoint uses gameid")
    _check(client.calls[1].endpoint == "mediaJeu.php" and client.calls[1].parameters.jeuid == "123", "Media request reconstructed using jeuid")
    _check(not "do-not-save" in FileAccess.get_file_as_string(directory.path_join("metadata.json")), "Account data not persisted")
    original = FileAccess.get_file_as_string(directory.path_join("metadata.json"))
    client.responses = [{"ok": true, "body": JSON.stringify({"response": {"jeu": _fixture()}}).to_utf8_buffer()}, {"ok": false, "error": "Fixture quota reached"}]
    failed = await client.fetch_game(credentials, "snes", "example-game", "123", true, false, _temporary)
    _check(not failed.ok and FileAccess.get_file_as_string(directory.path_join("metadata.json")) == original, "Download failure preserves metadata")
    var existing := Packs.read_document(directory.path_join("metadata.json"), "snes", "example-game")
    existing.media.music = Packs.write_media(directory, "music", "wav", "Synthetic owned metadata-only fixture".to_utf8_buffer())
    existing.media.video = Packs.write_media(directory, "video", "mp4", PackedByteArray([0, 0, 0, 12, 102, 116, 121, 112, 105, 115, 111, 109]))
    _check(Packs.save_document(existing, _temporary) == OK, "Synthetic prior video fixture saved without decoding or playback")
    var refreshed := _fixture()
    refreshed.synopsis = [{"langue": "en", "text": "Updated metadata without replacing local media."}]
    client.responses = [
        {"ok": true, "body": JSON.stringify({"response": {"jeu": refreshed}}).to_utf8_buffer()},
        {"ok": true, "body": "NOMEDIA".to_utf8_buffer()},
        {"ok": true, "body": "NOMEDIA\n".to_utf8_buffer()},
    ]
    var no_media := await client.fetch_game(credentials, "snes", "example-game", "123", true, true, _temporary)
    var retained := Packs.read_document(directory.path_join("metadata.json"), "snes", "example-game")
    _check(no_media.ok and retained.description == refreshed.synopsis[0].text, "NOMEDIA still saves fresh game metadata")
    _check(retained.media.background == existing.media.background and retained.media.video == existing.media.video and retained.media.music == existing.media.music, "NOMEDIA preserves prior background, video and local music")
    client.responses = [{"ok": true, "body": JSON.stringify({"response": {"jeu": refreshed}}).to_utf8_buffer()}, {"ok": true, "body": image_bytes}]
    var with_background := await client.fetch_game(credentials, "snes", "example-game", "123", true, false, _temporary)
    retained = Packs.read_document(directory.path_join("metadata.json"), "snes", "example-game")
    _check(with_background.ok and retained.media.music == existing.media.music, "Successful metadata and artwork refresh also retains imported music")
    _check("No background" in str(no_media.get("message", "")) and "No video" in str(no_media.get("message", "")), "NOMEDIA explains unavailable optional assets without claiming a download")
    client.responses = [{"ok": true, "body": "bad response containing devpassword=never-echo".to_utf8_buffer()}]
    var malformed := await client.search_games(credentials, "snes", "Example")
    _check(not malformed.ok and not "never-echo" in str(malformed), "Malformed response cannot echo secrets")
    var quota: Array = []
    client._network_done.connect(func(value): quota.append(value))
    client._completed(HTTPRequest.RESULT_SUCCESS, 430, PackedStringArray(), "devpassword=never-echo".to_utf8_buffer())
    _check(quota.size() == 1 and "quota" in str(quota[0]) and not "never-echo" in str(quota[0]), "Quota response cannot echo secrets")
    client.queue_free()
    var waiting := WaitingClient.new()
    root.add_child(waiting)
    _run_cancel_search(waiting)
    await process_frame
    waiting.cancel()
    await process_frame
    _check(not waiting.busy and not _cancel_result.get("ok", true), "Cancellation releases pending operation")
    waiting.queue_free()
    var panel := MediaPanel.new()
    root.add_child(panel)
    root.size = Vector2i(1024, 640)
    panel.open_for_game("snes", "example-game", "Example Game")
    await process_frame
    await process_frame
    await process_frame
    _check(panel.size.y <= 600, "Media popup fits a 640-pixel-high window")
    _check(not panel._results.fit_to_longest_item, "Long result titles cannot widen popup")
    _check(panel._credentials.devid.has_focus(), "Opening media settings focuses developer ID")
    panel._credentials.devpassword.text = "fixture-password"
    panel._credentials.sspassword.text = "fixture-user-password"
    panel._close()
    _check(panel._credentials.devpassword.text.is_empty() and panel._credentials.sspassword.text.is_empty(), "Closing settings clears both passwords")
    panel.queue_free()
    await process_frame
    _remove_tree(_temporary)
    if _failures.is_empty():
        print("Presentation smoke passed: %s checks; no network or user credentials used." % _checks)
        quit(0)
    else:
        for failure in _failures:
            push_error(failure)
        quit(1)

func _run_cancel_search(client: Node) -> void:
    _cancel_result = await client.search_games({"devid": "fixture", "devpassword": "fixture"}, "snes", "Example")

func _exercise_video_selection() -> void:
    var regular := {"type": "video", "region": "us", "format": "mp4", "size": "128"}
    var normalized := {"type": "video-normalized", "region": "wor", "format": "MP4", "size": "256"}
    _check(Client.choose_media({"medias": [regular, normalized]}, "video").get("selector") == "video-normalized(wor)", "Normalized MP4 takes priority over an ordinary regional video")
    for invalid_size in ["0", "-1", "not-a-size", str(Packs.MAX_VIDEO_BYTES + 1)]:
        var invalid := normalized.duplicate()
        invalid.size = invalid_size
        _check(Client.choose_media({"medias": [invalid, regular]}, "video").get("selector") == "video(us)", "Invalid normalized video size falls back to a bounded ordinary MP4")
    normalized.format = "webm"
    _check(Client.choose_media({"medias": [normalized, regular]}, "video").get("selector") == "video(us)", "Unsupported normalized video format falls back to MP4")
    _check(Client.choose_media({"medias": [{"type": "video-normalized", "region": "us"}]}, "video").get("selector") == "video-normalized(us)", "A missing optional format/size advertisement does not hide a valid selector")
    _check(Client.choose_media(_fixture(), "music").is_empty() and Client.choose_media(_fixture(), "unsupported").is_empty(), "Unknown media kinds never resolve to a background or invented music API")

func _remove_tree(path: String) -> void:
    var directory := DirAccess.open(path)
    if directory == null:
        return
    for child in directory.get_files():
        directory.remove(child)
    for child in directory.get_directories():
        _remove_tree(path.path_join(child))
    DirAccess.remove_absolute(path)
