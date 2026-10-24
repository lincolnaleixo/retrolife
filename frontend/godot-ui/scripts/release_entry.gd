extends "res://scripts/cartridge_library.gd"

## Production release probe: normal trust checks without opening the game library.
var _release_verification := false


func _ready() -> void:
    if "--verify-updater-release" in OS.get_cmdline_user_args():
        _release_verification = true
        call_deferred("_verify_updater_release")
        return
    super._ready()


func _unhandled_input(event: InputEvent) -> void:
    if not _release_verification:
        super._unhandled_input(event)


func _verify_updater_release() -> void:
    # This does not import a ROM, bypass signatures or change updater settings.
    var result := {"available": false, "currentVersion": "", "assetMode": "public-neutral"}
    if _has_private_bundle_assets("res://assets"):
        result["assetMode"] = "private-assets-present"
    var extension_error := ExtensionLoader.ensure_loaded()
    if extension_error.is_empty():
        var backend := ClassDB.instantiate("RetroLifeBackend") as Node
        if backend != null:
            add_child(backend)
            if backend.has_method("update_command_json"):
                var parsed: Variant = JSON.parse_string(str(backend.call("update_command_json", "status")))
                if parsed is Dictionary and bool(parsed.get("ok", false)):
                    var data: Dictionary = parsed.get("data", {})
                    result["available"] = bool(data.get("available", false))
                    result["currentVersion"] = str(data.get("currentVersion", ""))
            backend.queue_free()
    print("RETROLIFE_UPDATE_RELEASE_CHECK " + JSON.stringify(result))
    get_tree().quit(0 if result["available"] else 2)


func _has_private_bundle_assets(path: String) -> bool:
    # Inspect only the app resource pack, never the linked owner collection.
    # Original RetroLife branding is the sole reviewed bundled artwork.
    for child in DirAccess.get_directories_at(path):
        if path == "res://assets" and child == "brand":
            continue
        if _has_private_bundle_assets(path.path_join(child)):
            return true
    return not DirAccess.get_files_at(path).is_empty()
