extends RefCounted

static func packed_scene(path: String) -> PackedScene:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null or file.get_length() < 20 or file.get_length() > 80 * 1024 * 1024:
        return null
    if file.get_32() != 0x46546c67 or file.get_32() != 2:
        return null
    file.get_32()
    var length := file.get_32()
    if file.get_32() != 0x4e4f534a or length > 4 * 1024 * 1024:
        return null
    var data: Variant = JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
    if not data is Dictionary:
        return null
    for entry in data.get("images", []) + data.get("buffers", []):
        if entry.has("uri"):
            return null
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    if document.append_from_file(path, state) != OK:
        return null
    var model := document.generate_scene(state)
    if model == null:
        return null
    var packed := PackedScene.new()
    var error := packed.pack(model)
    model.free()
    return packed if error == OK else null
