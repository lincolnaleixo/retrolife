extends RefCounted

## Only explicit, user-local PNG artwork is decoded. No network or ROM lookup.
const MAX_ENTRIES := 9
const MAX_FILE_BYTES := 8 * 1024 * 1024
const MAX_SOURCE_EDGE := 2048
const TEXTURE_EDGE := 1024
const DIRECTORY := "user://artwork"

var _textures: Dictionary = {}
var _order: Array[String] = []


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


func texture_for(game_id: String) -> Texture2D:
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
    _textures[game_id] = texture
    _order.append(game_id)
    while _order.size() > MAX_ENTRIES:
        _textures.erase(_order.pop_front())
    return texture


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
