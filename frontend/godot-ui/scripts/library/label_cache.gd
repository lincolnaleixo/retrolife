extends RefCounted

## Only explicit, user-local PNG artwork is decoded. No network or ROM lookup.
const MAX_ENTRIES := 9
const MAX_FILE_BYTES := 8 * 1024 * 1024
const MAX_SOURCE_EDGE := 2048
const TEXTURE_EDGE := 1024
const DIRECTORY := "user://artwork"
const COLLECTION_DIRECTORY := "res://assets/cartridges/labels"
const COLLECTION_INDEX := "index.json"

var _textures: Dictionary = {}
var _order: Array[String] = []
var _collection: Dictionary = {}
var _collection_loaded := false


static func path_for(game_id: String) -> String:
    return DIRECTORY.path_join(game_id.sha256_text() + ".png")


static func validate_png(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return "The artwork file could not be opened."
    if file.get_length() < 24 or file.get_length() > MAX_FILE_BYTES:
        return "Choose a PNG smaller than 8 MiB."
    var header := file.get_buffer(24)
    if header.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
        return "Artwork must be a PNG image."
    if header.slice(12, 16).get_string_from_ascii() != "IHDR":
        return "The PNG header is invalid."
    var width := _read_big_endian(header, 16)
    var height := _read_big_endian(header, 20)
    if width <= 0 or height <= 0 or width > MAX_SOURCE_EDGE or height > MAX_SOURCE_EDGE:
        return "Choose artwork no larger than 2048 by 2048 pixels."
    return ""


static func _read_big_endian(bytes: PackedByteArray, offset: int) -> int:
    return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])


func texture_for(game_id: String, title := "") -> Texture2D:
    if _textures.has(game_id):
        _order.erase(game_id)
        _order.append(game_id)
        return _textures[game_id] as Texture2D
    var texture: Texture2D = null
    var path := path_for(game_id)
    if FileAccess.file_exists(path) and validate_png(path).is_empty():
        var image := Image.new()
        if image.load(path) == OK:
            _fit_image(image)
            image.generate_mipmaps()
            texture = ImageTexture.create_from_image(image)
    if texture == null and not title.is_empty():
        texture = _collection_texture(title)
    _textures[game_id] = texture
    _order.append(game_id)
    while _order.size() > MAX_ENTRIES:
        _textures.erase(_order.pop_front())
    return texture


## Staged collection labels ship inside the build; matching runs locally on
## the game title and never consults the network.
func _collection_texture(title: String) -> Texture2D:
    _load_collection()
    for label_title in _collection:
        if not titles_match(title, str(label_title)):
            continue
        var entry: Dictionary = _collection[label_title]
        var full := COLLECTION_DIRECTORY.path_join(str(entry.get("front", "")))
        if not FileAccess.file_exists(full):
            return null
        var expected := str(entry.get("sha256", ""))
        if expected.is_empty() or FileAccess.get_sha256(full) != expected:
            # A modified or unverifiable label must never stand in for the
            # approved export; fall back to the neutral label instead.
            return null
        var image := Image.new()
        if image.load(full) != OK:
            return null
        _fit_image(image)
        image.generate_mipmaps()
        return ImageTexture.create_from_image(image)
    return null


func _load_collection() -> void:
    if _collection_loaded:
        return
    _collection_loaded = true
    var index_path := COLLECTION_DIRECTORY.path_join(COLLECTION_INDEX)
    if not FileAccess.file_exists(index_path):
        return
    var file := FileAccess.open(index_path, FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        return
    for entry in (parsed as Dictionary).get("labels", []):
        if entry is Dictionary:
            var entry_title := str(entry.get("title", ""))
            var front := str(entry.get("front", ""))
            var sha256 := str(entry.get("sha256", ""))
            if not entry_title.is_empty() and not front.is_empty():
                _collection[entry_title] = {"front": front, "sha256": sha256}


static func normalize_title(text: String) -> String:
    var cleaned := ""
    for character in text.to_lower():
        cleaned += character if (character >= "a" and character <= "z") or (character >= "0" and character <= "9") else " "
    var words: Array[String] = []
    var skipped_region := false
    for word in cleaned.split(" ", false):
        if word in ["usa", "us", "europe", "eu", "japan", "jp", "rev"]:
            skipped_region = true
            continue
        if skipped_region and word.is_valid_int():
            # Duplicate markers such as "(USA) 2" from the importer only
            # follow a region tag; a semantic sequel number such as
            # "Super Mario 2" has no preceding region tag and is preserved.
            skipped_region = false
            continue
        skipped_region = false
        words.append(word)
    return " ".join(words)


static func titles_match(game_title: String, label_title: String) -> bool:
    var game := normalize_title(game_title)
    if game.is_empty():
        return false
    return game == normalize_title(label_title)


func import_artwork(game_id: String, source: String) -> String:
    if game_id.is_empty():
        return "Select a game before choosing artwork."
    var error := validate_png(source)
    if not error.is_empty():
        return error
    var image := Image.new()
    if image.load(source) != OK:
        return "The PNG image could not be decoded."
    _fit_image(image)
    var destination := path_for(game_id)
    if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY)) != OK:
        return "The artwork directory could not be created."
    var temporary := destination + ".tmp.png"
    if image.save_png(temporary) != OK:
        return "Artwork could not be saved."
    var renamed := DirAccess.rename_absolute(
        ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(destination)
    )
    if renamed != OK:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
        return "The previous artwork was kept because the new file could not be installed."
    invalidate(game_id)
    return ""


func invalidate(game_id: String) -> void:
    _textures.erase(game_id)
    _order.erase(game_id)


func entry_count() -> int:
    return _textures.size()


static func _fit_image(image: Image) -> void:
    var longest := maxi(image.get_width(), image.get_height())
    if longest > TEXTURE_EDGE:
        var factor := float(TEXTURE_EDGE) / float(longest)
        image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
    image.convert(Image.FORMAT_RGBA8)
