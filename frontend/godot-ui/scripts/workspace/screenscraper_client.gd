extends Node

## Credentials exist only during a requested operation. Responses are reduced to
## public metadata; account objects and credential-bearing media URLs are discarded.
signal _network_done(result: Dictionary)
signal progress(message: String)
const Packs = preload("res://scripts/workspace/game_presentation.gd")
const API := "https://api.screenscraper.fr/api2/"
const SYSTEM_IDS := {"nes": "3", "snes": "4", "mega-drive": "1", "playstation-1": "57", "nintendo-64": "14", "game-boy": "9", "game-boy-advance": "12"}
var busy := false
var _cancelled := false
var _active: HTTPRequest

func cancel() -> void:
    _cancelled = true
    if is_instance_valid(_active):
        _active.cancel_request()
        _network_done.emit({"ok": false, "error": "Cancelled. Your current presentation was retained."})

static func credential_error(credentials: Dictionary) -> String:
    if str(credentials.get("devid", "")).strip_edges().is_empty() or str(credentials.get("devpassword", "")).is_empty():
        return "Enter your approved ScreenScraper developer ID and developer password."
    if str(credentials.get("ssid", "")).is_empty() != str(credentials.get("sspassword", "")).is_empty():
        return "Enter both user login and user password, or leave both empty."
    return ""

func search_games(credentials: Dictionary, system: String, title: String) -> Dictionary:
    if busy:
        return {"ok": false, "error": "Another request is still running."}
    var issue := credential_error(credentials)
    if not issue.is_empty() or not SYSTEM_IDS.has(system):
        return {"ok": false, "error": issue if not issue.is_empty() else "This console is not supported."}
    if title.strip_edges().length() < 2:
        return {"ok": false, "error": "Enter at least two characters of the game title."}
    busy = true
    _cancelled = false
    var response := await _request("jeuRecherche.php", credentials, {"systemeid": SYSTEM_IDS[system], "recherche": title.strip_edges().left(160)}, 4194304)
    busy = false
    if not response.ok:
        return response
    var parsed: Variant = Packs.parse_json(response.body.get_string_from_utf8())
    var candidates := parse_search(parsed, system)
    if candidates.is_empty():
        return {"ok": false, "error": "No matching game was returned for this console. Try a shorter title."}
    return {"ok": true, "games": candidates}

func fetch_game(credentials: Dictionary, system: String, slug: String, game_id: String, background := true, video := false, root_override := "") -> Dictionary:
    if busy:
        return {"ok": false, "error": "Another request is still running."}
    var issue := credential_error(credentials)
    var target := Packs.pack_directory(system, slug, root_override)
    if not issue.is_empty() or target.is_empty() or Packs.numeric_id(game_id).is_empty():
        return {"ok": false, "error": issue if not issue.is_empty() else "Select a game and connect your local collection folder first."}
    busy = true
    _cancelled = false
    progress.emit("Fetching the selected game's metadata…")
    var response := await _request("jeuInfos.php", credentials, {"systemeid": SYSTEM_IDS[system], "gameid": game_id}, 4194304)
    if not response.ok:
        busy = false
        return response
    var parsed: Variant = Packs.parse_json(response.body.get_string_from_utf8())
    var game := response_game(parsed)
    var document := parse_game(game, system, slug, game_id)
    if document.is_empty():
        busy = false
        return {"ok": false, "error": "The service returned a different game or console. Your current presentation was retained."}
    # Reuse cached media if a requested media type is unavailable. No stale API URLs.
    var previous := Packs.load_for_game(system, slug, root_override)
    document.media = previous.get("media", {}).duplicate(true)
    var notes: Array[String] = []
    for kind in ["background", "video"]:
        if (kind == "background" and not background) or (kind == "video" and not video):
            continue
        var media := choose_media(game, kind)
        if media.is_empty():
            notes.append("No %s is available for this game." % kind)
            continue
        progress.emit("Downloading %s…" % kind)
        var params := {"systemeid": SYSTEM_IDS[system], "jeuid": game_id, "media": media.selector}
        var endpoint := "mediaVideoJeu.php" if kind == "video" else "mediaJeu.php"
        if kind == "background":
            params["outputformat"] = "png"
            params["maxwidth"] = "2560"
            params["maxheight"] = "1440"
        var download := await _request(endpoint, credentials, params, Packs.MAX_VIDEO_BYTES if kind == "video" else Packs.MAX_IMAGE_BYTES)
        if not download.ok:
            busy = false
            return download
        var bytes: PackedByteArray = download.body
        # A media listed in metadata can disappear before download. ScreenScraper
        # documents this successful HTTP response; keep cached media in that case.
        if bytes.size() <= 64 and bytes.get_string_from_utf8().strip_edges() == "NOMEDIA":
            notes.append("No %s is available for this game. Existing media was retained." % kind)
            continue
        var extension := "mp4" if kind == "video" else "png"
        if kind == "background":
            var picture := Image.new()
            if not bounded_png(bytes) or picture.load_png_from_buffer(bytes) != OK:
                busy = false
                return {"ok": false, "error": "The service did not return a supported background image. Your current presentation was retained."}
        elif bytes.size() < 12 or bytes.slice(4, 8).get_string_from_ascii() != "ftyp":
            busy = false
            return {"ok": false, "error": "The service did not return an MP4 video. Your current presentation was retained."}
        var stored := Packs.write_media(target, kind, extension, bytes)
        if stored.is_empty():
            busy = false
            return {"ok": false, "error": "The downloaded media could not be saved. Your current presentation was retained."}
        stored.source = "ScreenScraper · game " + game_id + " · " + str(media.selector)
        document.media[kind] = stored
    busy = false
    if _cancelled:
        return {"ok": false, "error": "Cancelled. Your current presentation was retained."}
    if Packs.save_document(document, root_override) != OK:
        return {"ok": false, "error": "The presentation could not be saved. Your current presentation was retained."}
    return {"ok": true, "document": document, "message": "Saved for offline viewing." + (" " + " ".join(notes) if not notes.is_empty() else "")}

static func bounded_png(bytes: PackedByteArray) -> bool:
    # Check IHDR before image decoding can allocate a large pixel buffer.
    if bytes.size() < 33 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) or bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
        return false
    var width := (int(bytes[16]) << 24) | (int(bytes[17]) << 16) | (int(bytes[18]) << 8) | int(bytes[19])
    var height := (int(bytes[20]) << 24) | (int(bytes[21]) << 16) | (int(bytes[22]) << 8) | int(bytes[23])
    return width > 0 and height > 0 and width <= 8192 and height <= 8192 and width * height <= 16777216

func _request(endpoint: String, credentials: Dictionary, parameters: Dictionary, limit: int) -> Dictionary:
    if _cancelled:
        return {"ok": false, "error": "Cancelled. Your current presentation was retained."}
    var query := {"devid": str(credentials.get("devid", "")), "devpassword": str(credentials.get("devpassword", "")), "softname": "RetroLife", "output": "json"}
    for key in ["ssid", "sspassword"]:
        if not str(credentials.get(key, "")).is_empty():
            query[key] = str(credentials[key])
    query.merge(parameters)
    var parts: Array[String] = []
    for key in query:
        parts.append(str(key).uri_encode() + "=" + str(query[key]).uri_encode())
    _active = HTTPRequest.new()
    _active.timeout = 45.0
    _active.body_size_limit = limit
    # Never forward credentials to a redirect target or use URLs from API JSON.
    _active.max_redirects = 0
    add_child(_active)
    _active.request_completed.connect(_completed)
    var started := _active.request(API + endpoint + "?" + "&".join(parts))
    query.clear()
    parts.clear()
    if started != OK:
        _active.queue_free()
        _active = null
        return {"ok": false, "error": "The secure connection could not be started. Check your connection and try again."}
    var result: Dictionary = await _network_done
    if is_instance_valid(_active):
        _active.queue_free()
    _active = null
    return result

func _completed(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    if result != HTTPRequest.RESULT_SUCCESS:
        _network_done.emit({"ok": false, "error": "The request timed out, exceeded its size limit or could not connect securely. Try again when the service is available."})
    elif status != 200:
        _network_done.emit({"ok": false, "error": status_error(status)})
    else:
        _network_done.emit({"ok": true, "body": body})

static func status_error(status: int) -> String:
    match status:
        401, 403: return "ScreenScraper rejected the credentials. Check the developer and user fields."
        404: return "ScreenScraper did not find this game or media."
        423: return "ScreenScraper is temporarily closed. Try again later."
        426: return "ScreenScraper requires an approved, current developer client. Check your developer account."
        429, 430, 431: return "ScreenScraper's request or daily quota has been reached. Try again later; no automatic retries were made."
        301, 302, 303, 307, 308: return "ScreenScraper requested a redirect. Credentials were not forwarded; the request was stopped."
        _: return "ScreenScraper could not complete this request (HTTP %s)." % status

static func response_game(value: Variant) -> Dictionary:
    if value is Dictionary and value.get("response") is Dictionary and value.response.get("jeu") is Dictionary:
        return value.response.jeu
    return {}

static func text_value(value: Variant) -> String:
    return Packs.plain(value.get("text", value.get("nom", "")), 6000) if value is Dictionary else Packs.plain(value, 6000)

static func localized(value: Variant, key: String, preference: Array) -> String:
    if not value is Array:
        return text_value(value)
    for locale in preference:
        for entry in value:
            if entry is Dictionary and str(entry.get(key, "")) == locale and not text_value(entry).is_empty():
                return text_value(entry)
    # Never silently substitute a foreign-language synopsis for the selected English UI.
    return ""

static func parse_search(value: Variant, system: String) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if not value is Dictionary or not value.get("response") is Dictionary:
        return result
    var games: Variant = value.response.get("jeux", [])
    if not games is Array:
        return result
    for game in games.slice(0, 30):
        if not game is Dictionary or not game.get("systeme") is Dictionary or str(game.systeme.get("id", "")) != str(SYSTEM_IDS.get(system, "")):
            continue
        var game_id := Packs.numeric_id(game.get("id", ""))
        var title := localized(game.get("noms", []), "region", ["us", "wor", "eu", "ss", "jp"])
        if not game_id.is_empty() and not title.is_empty():
            result.append({"id": game_id, "title": title.left(256), "year": localized(game.get("dates", []), "region", ["us", "wor", "eu", "jp"]).left(4)})
    return result

static func parse_game(game: Dictionary, system: String, slug: String, expected_id: String) -> Dictionary:
    if game.is_empty() or not game.get("systeme") is Dictionary or str(game.systeme.get("id", "")) != str(SYSTEM_IDS.get(system, "")) or Packs.numeric_id(game.get("id", "")) != expected_id:
        return {}
    var genres: Array[String] = []
    var genre_values: Variant = game.get("genres", [])
    if genre_values is Array:
        for entry in genre_values:
            if entry is Dictionary:
                var name := localized(entry.get("noms", []), "langue", ["en"])
                if not name.is_empty() and not name in genres:
                    genres.append(name)
    var document := {"schemaVersion": 1, "game": {"system": system, "slug": slug, "title": localized(game.get("noms", []), "region", ["us", "wor", "eu", "ss", "jp"])}, "description": localized(game.get("synopsis", []), "langue", ["en"]), "developer": text_value(game.get("developpeur", "")), "publisher": text_value(game.get("editeur", "")), "year": localized(game.get("dates", []), "region", ["us", "wor", "eu", "jp"]).left(4), "genre": ", ".join(genres), "players": text_value(game.get("joueurs", "")), "media": {}, "source": {"provider": "ScreenScraper", "gameId": expected_id, "systemId": str(SYSTEM_IDS.get(system, "")), "retrievedAt": Time.get_datetime_string_from_system(true) + "Z", "url": "https://www.screenscraper.fr/"}}
    return Packs.clean_document(document, system, slug)

static func choose_media(game: Dictionary, kind: String) -> Dictionary:
    # The public API documents image/video downloads, not a soundtrack endpoint.
    # Unknown kinds must never silently resolve to a background image.
    if not kind in ["background", "video"]:
        return {}
    var media: Variant = game.get("medias", [])
    if not media is Array:
        return {}
    var types := ["video-normalized", "video"] if kind == "video" else ["fanart", "ss", "sstitle"]
    for type in types:
        for region in ["us", "wor", "eu", "jp", ""]:
            for entry in media:
                if entry is Dictionary and str(entry.get("type", "")) == type and str(entry.get("region", "")) == region:
                    if kind == "video":
                        var format := str(entry.get("format", "")).to_lower()
                        var size := str(entry.get("size", ""))
                        # Skip unusable advertised candidates so a normal MP4 can
                        # still be selected when the normalized version is invalid.
                        if not format.is_empty() and format != "mp4":
                            continue
                        if not size.is_empty() and (not size.is_valid_int() or int(size) <= 0 or int(size) > Packs.MAX_VIDEO_BYTES):
                            continue
                    return {"selector": type + ("(" + region + ")" if not region.is_empty() else "")}
    return {}
