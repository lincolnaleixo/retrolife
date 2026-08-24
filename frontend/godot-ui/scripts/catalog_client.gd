extends RefCounted

const DEFAULT_PAGE_LIMIT := 500
const USER_SNAPSHOT_PATH := "user://catalog.json"

var _backend: Node


func _init(backend: Node) -> void:
    _backend = backend


func reset_reference() -> Dictionary:
    return _decode(_backend.call("reset_reference_catalog_json"))


func status() -> Dictionary:
    return _decode(_backend.call("catalog_status_json"))


func view(system_id := "", search := "", offset := 0, limit := DEFAULT_PAGE_LIMIT) -> Dictionary:
    return _decode(
        _backend.call(
            "catalog_view_json",
            str(system_id),
            str(search),
            int(offset),
            int(limit)
        )
    )


func details(game_id: String) -> Dictionary:
    return _decode(_backend.call("game_details_json", game_id))


func load_server_snapshot_text(snapshot_json: String) -> Dictionary:
    return _decode(_backend.call("load_server_catalog_snapshot_json", snapshot_json))


func load_startup_snapshot() -> Dictionary:
    var candidates: Array[String] = []
    var environment_path := OS.get_environment("RETROLIFE_CATALOG_PATH").strip_edges()
    if not environment_path.is_empty():
        candidates.append(environment_path)
    if FileAccess.file_exists(USER_SNAPSHOT_PATH):
        candidates.append(USER_SNAPSHOT_PATH)

    for path in candidates:
        if not FileAccess.file_exists(path):
            return {
                "loaded": false,
                "path": path,
                "error": "Catalog snapshot does not exist: %s" % path,
            }
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null:
            return {
                "loaded": false,
                "path": path,
                "error": "Catalog snapshot could not be opened: %s" % path,
            }
        var response := load_server_snapshot_text(file.get_as_text())
        if not bool(response.get("ok", false)):
            return {
                "loaded": false,
                "path": path,
                "error": str(response.get("error", "Catalog snapshot was rejected.")),
            }
        return {
            "loaded": true,
            "path": path,
            "error": "",
            "data": response.get("data", {}),
        }

    return {"loaded": false, "path": "", "error": ""}


static func _decode(raw_json: Variant) -> Dictionary:
    var parsed: Variant = JSON.parse_string(str(raw_json))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {
            "schemaVersion": 1,
            "ok": false,
            "error": "The Rust bridge returned invalid JSON.",
        }
    var response: Dictionary = parsed
    if int(response.get("schemaVersion", -1)) != 1:
        return {
            "schemaVersion": 1,
            "ok": false,
            "error": "Unsupported Rust bridge response schema.",
        }
    return response
