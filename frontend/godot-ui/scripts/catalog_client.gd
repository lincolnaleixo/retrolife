extends RefCounted

## The Godot UI talks only to the local library contract.  There is no
## snapshot, account, HTTP, or reference-catalog fallback in the shipped UI.
const DEFAULT_PAGE_LIMIT := 500
const RESPONSE_SCHEMA_VERSION := 1

var _backend: Node


func _init(backend: Node) -> void:
    _backend = backend


func status() -> Dictionary:
    return _call_first(["library_status_json", "local_library_status_json"], [])


func view(system_id := "", search := "", offset := 0, limit := DEFAULT_PAGE_LIMIT) -> Dictionary:
    return _call_first(
        ["library_view_json", "local_library_view_json"],
        [str(system_id), str(search), int(offset), int(limit)]
    )


func details(game_id: String) -> Dictionary:
    return _call_first(
        ["library_game_details_json", "game_details_json"],
        [game_id]
    )


func import_file(source_path: String) -> Dictionary:
    return _call_first(
        ["library_import_json", "import_local_game_json", "import_game_json"],
        [source_path]
    )


func remove_game(game_id: String) -> Dictionary:
    return _call_first(
        ["library_remove_json", "remove_local_game_json", "remove_game_json"],
        [game_id]
    )


func _call_first(methods: Array[String], arguments: Array) -> Dictionary:
    if _backend == null:
        return _error("The Rust bridge is unavailable.")
    for method in methods:
        if _backend.has_method(method):
            return _decode(_backend.callv(method, arguments))
    return _error("The local library backend is not available in this build.")


static func _decode(raw_json: Variant) -> Dictionary:
    if raw_json is Dictionary:
        var dictionary: Dictionary = raw_json
        return dictionary if int(dictionary.get("schemaVersion", -1)) == RESPONSE_SCHEMA_VERSION else _error("Unsupported Rust bridge response schema.")

    var parsed: Variant = JSON.parse_string(str(raw_json))
    if typeof(parsed) != TYPE_DICTIONARY:
        return _error("The Rust bridge returned invalid JSON.")
    var response: Dictionary = parsed
    if int(response.get("schemaVersion", -1)) != RESPONSE_SCHEMA_VERSION:
        return _error("Unsupported Rust bridge response schema.")
    return response


static func _error(message: String) -> Dictionary:
    return {
        "schemaVersion": RESPONSE_SCHEMA_VERSION,
        "ok": false,
        "error": message,
    }
