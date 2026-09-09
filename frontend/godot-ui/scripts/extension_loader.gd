extends RefCounted

const EXTENSION_PATH := "res://retrolife.gdextension"
const BACKEND_CLASS := "RetroLifeBackend"


static func ensure_loaded() -> String:
    if ClassDB.class_exists(BACKEND_CLASS):
        return ""

    var status := GDExtensionManager.load_extension(EXTENSION_PATH)
    if status != GDExtensionManager.LOAD_STATUS_OK \
        and status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
        return "Could not load %s; GDExtension status=%s" % [EXTENSION_PATH, status]

    if not ClassDB.class_exists(BACKEND_CLASS):
        return "%s loaded without registering %s" % [EXTENSION_PATH, BACKEND_CLASS]

    return ""
