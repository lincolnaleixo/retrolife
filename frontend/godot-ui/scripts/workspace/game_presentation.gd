extends RefCounted

## External presentation packs contain data and media, never executable resources.
const Preferences = preload("res://scripts/workspace/preferences.gd")
const SYSTEMS := ["nes", "snes", "mega-drive", "playstation-1", "nintendo-64", "game-boy", "game-boy-advance"]
const MAX_METADATA_BYTES := 262144
const MAX_IMAGE_BYTES := 16777216
const MAX_VIDEO_BYTES := 134217728
const MAX_MUSIC_BYTES := 33554432
const FIELDS := {"title": 256, "description": 6000, "developer": 160, "publisher": 160, "year": 4, "genre": 160, "players": 48}

static func valid_slug(value: String) -> bool:
    if value.is_empty() or value.length() > 128 or value.begins_with("-"):
        return false
    for character in value:
        if not character in "abcdefghijklmnopqrstuvwxyz0123456789-":
            return false
    return true

static func pack_directory(system: String, slug: String, root_override := "") -> String:
    if not system in SYSTEMS or not valid_slug(slug):
        return ""
    var base := root_override if not root_override.is_empty() else Preferences.read_value("collection_root")
    if base.is_empty() or not base.is_absolute_path() or not DirAccess.dir_exists_absolute(base):
        return ""
    return base.path_join("reproductions/%s/%s/presentation" % [system, slug])

static func load_for_game(system: String, slug: String, root_override := "") -> Dictionary:
    var directory := pack_directory(system, slug, root_override)
    if directory.is_empty():
        return {}
    var document := read_document(directory.path_join("metadata.json"), system, slug)
    if document.is_empty():
        return {}
    var result := document.duplicate(true)
    result["title"] = str(document.game.title)
    result["source_name"] = str(document.source.provider)
    result["source_url"] = str(document.source.url)
    result["background_path"] = local_media_path(directory, document.media.get("background", {}), "background")
    result["video_path"] = local_media_path(directory, document.media.get("video", {}), "video")
    result["video_playable"] = str(result.video_path).get_extension().to_lower() == "ogv"
    result["music_path"] = local_media_path(directory, document.media.get("music", {}), "music")
    return result

static func read_document(path: String, system: String, slug: String) -> Dictionary:
    var handle := FileAccess.open(path, FileAccess.READ)
    if handle == null or handle.get_length() > MAX_METADATA_BYTES:
        return {}
    var parsed: Variant = parse_json(handle.get_as_text())
    return clean_document(parsed, system, slug)

static func parse_json(text: String) -> Variant:
    # JSON.parse_string logs fragments of invalid input. Provider responses may
    # contain account data, so use the non-logging parser and discard its error.
    var parser := JSON.new()
    return parser.data if parser.parse(text) == OK else null

static func clean_document(value: Variant, system: String, slug: String) -> Dictionary:
    if not value is Dictionary:
        return {}
    var version: Variant = value.get("schemaVersion", 0)
    if not (version is int or version is float) or version != 1:
        return {}
    var game: Variant = value.get("game", {})
    if not game is Dictionary or not game.get("system") is String or not game.get("slug") is String:
        return {}
    if game.system != system or game.slug != slug:
        return {}
    if not system in SYSTEMS or not valid_slug(slug):
        return {}
    var result := {"schemaVersion": 1, "game": {"system": system, "slug": slug, "title": plain(game.get("title", ""), 256)}, "media": {}, "source": {}}
    for field in FIELDS:
        if field != "title":
            result[field] = plain(value.get(field, ""), FIELDS[field])
    if not str(result.year).is_empty() and (not str(result.year).is_valid_int() or int(result.year) < 1900 or int(result.year) > 2100):
        result.year = ""
    var source: Variant = value.get("source", {})
    if source is Dictionary:
        result.source = {"provider": plain(source.get("provider", "Local metadata"), 80), "gameId": numeric_id(source.get("gameId", "")), "systemId": numeric_id(source.get("systemId", "")), "retrievedAt": plain(source.get("retrievedAt", ""), 48), "url": public_url(str(source.get("url", "")))}
    else:
        result.source = {"provider": "Local metadata", "gameId": "", "systemId": "", "retrievedAt": "", "url": ""}
    var media: Variant = value.get("media", {})
    if media is Dictionary:
        for kind in ["background", "video", "music"]:
            if not media.has(kind):
                continue
            var entry: Variant = media.get(kind, {})
            if not entry is Dictionary or not valid_media_name(str(entry.get("path", "")), kind):
                return {}
            var hash_value := str(entry.get("sha256", "")).to_lower()
            if not hash_value.is_empty() and not valid_hash(hash_value):
                return {}
            result.media[kind] = {"path": str(entry.path), "sha256": hash_value, "source": plain(entry.get("source", "Local media"), 160)}
    return result

static func plain(value: Variant, limit: int) -> String:
    if not value is String and not value is int and not value is float:
        return ""
    var text := str(value).replace("\r", "").strip_edges()
    var result := ""
    for character in text:
        if character.unicode_at(0) >= 32 or character == "\n" or character == "\t":
            result += character
        if result.length() >= limit:
            break
    return result

static func numeric_id(value: Variant) -> String:
    var text := plain(value, 16)
    return text if text.is_valid_int() and int(text) > 0 else ""

static func public_url(value: String) -> String:
    # Never persist API query strings, usernames, passwords or opaque tokens.
    if not value.begins_with("https://") or "@" in value or value.length() > 2048:
        return ""
    return value.split("?", true, 1)[0].split("#", true, 1)[0]

static func valid_hash(value: String) -> bool:
    if value.length() != 64:
        return false
    for character in value:
        if not character in "0123456789abcdef":
            return false
    return true

static func valid_media_name(value: String, kind: String) -> bool:
    if value.is_empty() or value.length() > 160 or value != value.get_file() or ".." in value or ":" in value or "\\" in value:
        return false
    var extension := value.get_extension().to_lower()
    match kind:
        "background": return extension in ["png", "jpg", "jpeg", "webp"]
        "video": return extension in ["ogv", "mp4"]
        "music": return extension in ["ogg", "mp3", "wav"]
    return false

static func media_size_limit(kind: String) -> int:
    match kind:
        "background": return MAX_IMAGE_BYTES
        "video": return MAX_VIDEO_BYTES
        "music": return MAX_MUSIC_BYTES
    return 0

static func local_media_path(directory: String, entry: Variant, kind: String) -> String:
    if not entry is Dictionary or not valid_media_name(str(entry.get("path", "")), kind):
        return ""
    var path := directory.path_join(str(entry.path))
    var handle := FileAccess.open(path, FileAccess.READ)
    if handle == null or handle.get_length() <= 0 or handle.get_length() > media_size_limit(kind):
        return ""
    var expected := str(entry.get("sha256", ""))
    if not expected.is_empty() and (not valid_hash(expected) or FileAccess.get_sha256(path) != expected):
        return ""
    return path

static func save_document(document: Dictionary, root_override := "") -> Error:
    var game: Variant = document.get("game", {})
    if not game is Dictionary:
        return ERR_INVALID_DATA
    var clean := clean_document(document, str(game.get("system", "")), str(game.get("slug", "")))
    if clean.is_empty():
        return ERR_INVALID_DATA
    var directory := pack_directory(str(game.system), str(game.slug), root_override)
    if directory.is_empty():
        return ERR_FILE_BAD_PATH
    var created := DirAccess.make_dir_recursive_absolute(directory)
    if created != OK:
        return created
    var temporary := directory.path_join("metadata-%s.tmp" % Time.get_ticks_usec())
    var handle := FileAccess.open(temporary, FileAccess.WRITE)
    if handle == null:
        return FileAccess.get_open_error()
    var serialized := JSON.stringify(clean, "  ") + "\n"
    handle.store_string(serialized)
    handle.close()
    if FileAccess.get_file_as_string(temporary) != serialized:
        DirAccess.remove_absolute(temporary)
        return ERR_FILE_CANT_WRITE
    var result := DirAccess.rename_absolute(temporary, directory.path_join("metadata.json"))
    if result != OK:
        DirAccess.remove_absolute(temporary)
    return result

static func write_media(directory: String, kind: String, extension: String, bytes: PackedByteArray) -> Dictionary:
    if not valid_media_name("file." + extension, kind) or bytes.is_empty() or bytes.size() > media_size_limit(kind):
        return {}
    var hash_value := _sha256(bytes)
    var filename := "%s-%s.%s" % [kind, hash_value.substr(0, 20), extension]
    if DirAccess.make_dir_recursive_absolute(directory) != OK:
        return {}
    var path := directory.path_join(filename)
    if FileAccess.file_exists(path):
        if FileAccess.get_sha256(path) != hash_value:
            return {}
        return {"path": filename, "sha256": hash_value, "source": "Local media"}
    var temp_path := path + ".%s.tmp" % Time.get_ticks_usec()
    var handle := FileAccess.open(temp_path, FileAccess.WRITE)
    if handle == null:
        return {}
    handle.store_buffer(bytes)
    handle.close()
    if FileAccess.get_sha256(temp_path) != hash_value:
        DirAccess.remove_absolute(temp_path)
        return {}
    if DirAccess.rename_absolute(temp_path, path) != OK:
        DirAccess.remove_absolute(temp_path)
        return {}
    return {"path": filename, "sha256": hash_value, "source": "Local media"}

static func _sha256(bytes: PackedByteArray) -> String:
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(bytes)
    return context.finish().hex_encode()

static func import_pack(source_json: String, system: String, slug: String, root_override := "") -> Dictionary:
    var document := read_document(source_json, system, slug)
    var target := pack_directory(system, slug, root_override)
    if document.is_empty() or target.is_empty():
        return {"ok": false, "error": "Select a metadata.json pack for this game and connect the collection folder."}
    var copied := {}
    for kind in document.media:
        var entry: Dictionary = document.media[kind]
        var media_path := local_media_path(source_json.get_base_dir(), entry, kind)
        if media_path.is_empty():
            return {"ok": false, "error": "The local media is missing, too large or does not match its checksum. Your current presentation was retained."}
        var stored := write_media(target, kind, media_path.get_extension().to_lower(), FileAccess.get_file_as_bytes(media_path))
        if stored.is_empty():
            return {"ok": false, "error": "The media could not be copied. Your current presentation was retained."}
        stored.source = entry.source
        copied[kind] = stored
    document.media = copied
    if save_document(document, root_override) != OK:
        return {"ok": false, "error": "The presentation could not be saved. Your current presentation was retained."}
    return {"ok": true, "document": document}


static func load_music_stream(path: String) -> AudioStream:
    if not valid_media_name(path.get_file(), "music"):
        return null
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null or file.get_length() <= 12 or file.get_length() > MAX_MUSIC_BYTES:
        return null
    var header := file.get_buffer(12)
    file.close()
    var stream: AudioStream
    match path.get_extension().to_lower():
        "ogg":
            if header.slice(0, 4).get_string_from_ascii() != "OggS":
                return null
            stream = AudioStreamOggVorbis.load_from_file(path)
        "mp3":
            var mp3_header := header.slice(0, 3).get_string_from_ascii() == "ID3" or (header[0] == 0xff and (header[1] & 0xe0) == 0xe0)
            if not mp3_header:
                return null
            var mp3 := AudioStreamMP3.new()
            mp3.data = FileAccess.get_file_as_bytes(path)
            stream = mp3
        "wav":
            if header.slice(0, 4).get_string_from_ascii() != "RIFF" or header.slice(8, 12).get_string_from_ascii() != "WAVE":
                return null
            stream = AudioStreamWAV.load_from_file(path)
    if stream == null or not is_finite(stream.get_length()) or stream.get_length() <= 0.0:
        return null
    if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
        stream.loop = true
    elif stream is AudioStreamWAV:
        stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
        stream.loop_begin = 0
        stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
    return stream

static func import_music(source_audio: String, system: String, slug: String, game_title := "", root_override := "") -> Dictionary:
    var directory := pack_directory(system, slug, root_override)
    if directory.is_empty():
        return {"ok": false, "error": "Connect the collection folder before adding game music."}
    if load_music_stream(source_audio) == null:
        return {"ok": false, "error": "Choose a valid OGG, MP3 or WAV track up to 32 MB. The current music was retained."}
    var document_path := directory.path_join("metadata.json")
    var document := read_document(document_path, system, slug)
    if document.is_empty():
        if FileAccess.file_exists(document_path):
            return {"ok": false, "error": "The existing metadata could not be read. It was retained without changes."}
        document = clean_document({"schemaVersion": 1, "game": {"system": system, "slug": slug, "title": game_title}, "media": {}, "source": {"provider": "Local metadata"}}, system, slug)
    var stored := write_media(directory, "music", source_audio.get_extension().to_lower(), FileAccess.get_file_as_bytes(source_audio))
    if stored.is_empty():
        return {"ok": false, "error": "The music could not be copied. The current presentation was retained."}
    stored.source = "Local music import"
    document.media.music = stored
    if save_document(document, root_override) != OK:
        return {"ok": false, "error": "The presentation could not be saved. The current presentation was retained."}
    return {"ok": true, "document": document, "message": "Game music imported. Enable Game music on the selection screen to listen."}
