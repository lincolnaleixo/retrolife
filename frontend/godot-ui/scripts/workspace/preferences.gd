extends RefCounted

const PATH := "user://workspace.cfg"

static func read_value(key: String, fallback := "") -> String:
    var config := ConfigFile.new()
    if config.load(PATH) != OK:
        return fallback
    return str(config.get_value("workspace", key, fallback))

static func write_value(key: String, value: String) -> Error:
    var config := ConfigFile.new()
    var loaded := config.load(PATH)
    if loaded != OK and loaded != ERR_FILE_NOT_FOUND:
        return loaded
    config.set_value("workspace", key, value)
    var error := config.save(PATH + ".tmp")
    if error != OK:
        return error
    return DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH + ".tmp"), ProjectSettings.globalize_path(PATH))

static func library_root() -> String:
    return read_value("rom_root", OS.get_user_data_dir().path_join("library"))

static func asset(relative: String) -> String:
    var root := read_value("collection_root")
    if root.is_empty() or not DirAccess.dir_exists_absolute(root):
        return ""
    var path := root.path_join(relative)
    return path if FileAccess.file_exists(path) else ""

static func image(relative: String) -> Texture2D:
    var path := asset(relative)
    if path.is_empty():
        return null
    var loaded := Image.load_from_file(path)
    return null if loaded == null else ImageTexture.create_from_image(loaded)
