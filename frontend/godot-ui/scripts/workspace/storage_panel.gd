extends PopupPanel

signal changed
const Preferences = preload("res://scripts/workspace/preferences.gd")
var owner_ui: Control
var _roms: Label
var _assets: Label
var _status: Label
var _picker: FileDialog
var _operation := ""
var _busy := false

func _ready() -> void:
    var popup_theme := Theme.new()
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color("141b27")
    panel_style.border_color = Color("3b5061")
    panel_style.set_border_width_all(1)
    panel_style.set_corner_radius_all(18)
    popup_theme.set_stylebox("panel", "PopupPanel", panel_style)
    theme = popup_theme
    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 24)
    add_child(margin)
    var column := VBoxContainer.new()
    column.custom_minimum_size.x = 580
    column.add_theme_constant_override("separation", 14)
    margin.add_child(column)
    _label(column, "Storage & local 3D assets", 25)
    _label(column, "ROM library", 17)
    _roms = _label(column, "", 14)
    _label(column, "New imports go into a console folder here. Existing saves stay in application data and keep their game identity.", 13)
    _button(column, "Copy collection to another folder…", _pick.bind("copy"))
    _button(column, "Use an existing ROM folder…", _pick.bind("existing"))
    _button(column, "Reveal ROM folder", func(): OS.shell_open(Preferences.library_root()))
    column.add_child(HSeparator.new())
    _label(column, "Your private 3D collection", 17)
    _assets = _label(column, "", 14)
    _label(column, "Choose the collection folder containing controllers, consoles and reproductions. Files stay local and are not uploaded or included in app releases.", 13)
    _button(column, "Link a 3D collection folder…", _pick.bind("assets"))
    _status = _label(column, "", 14)
    _button(column, "Done", hide)
    _picker = FileDialog.new()
    _picker.access = FileDialog.ACCESS_FILESYSTEM
    _picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
    _picker.use_native_dialog = true
    _picker.mode_overrides_title = false
    _picker.dir_selected.connect(_selected)
    _picker.canceled.connect(func(): popup())
    add_child(_picker)
    about_to_popup.connect(refresh)

func refresh() -> void:
    var path := Preferences.library_root()
    _roms.text = path + ("\nConnected · New SNES imports → snes/" if DirAccess.dir_exists_absolute(path) else "\nOffline · Reconnect this drive to play or import")
    var collection := Preferences.read_value("collection_root")
    _assets.text = "No local collection linked" if collection.is_empty() else collection + ("\nConnected" if DirAccess.dir_exists_absolute(collection) else "\nOffline")

func _pick(operation: String) -> void:
    if _busy:
        return
    _operation = operation
    _picker.title = "Choose your local 3D collection" if operation == "assets" else ("Copy your library to a folder" if operation == "copy" else "Choose your ROM library")
    var directory := Preferences.read_value("collection_root") if operation == "assets" else Preferences.library_root()
    if directory.is_empty() or not DirAccess.dir_exists_absolute(directory):
        directory = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
    if directory.is_empty() or not DirAccess.dir_exists_absolute(directory):
        directory = OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
    _picker.current_file = ""
    _picker.current_dir = directory
    _picker.popup_centered_clamped(Vector2i(880, 560), 0.9)

func _selected(path: String) -> void:
    # A native dialog takes focus away from the embedded storage popup.
    popup()
    if _busy or owner_ui == null:
        return
    if _operation == "assets":
        if not DirAccess.dir_exists_absolute(path.path_join("controllers")) or not DirAccess.dir_exists_absolute(path.path_join("consoles")):
            _status.text = "Select the collection root containing controllers/ and consoles/."
            return
        if Preferences.write_value("collection_root", path) != OK:
            _status.text = "The collection setting could not be saved."
            return
        _status.text = "Local 3D collection linked."
        refresh()
        changed.emit()
        return
    if owner_ui._backend == null:
        _status.text = "The native backend must be available before changing storage."
        return
    if _operation == "existing" and not FileAccess.file_exists(path.path_join("library.json")):
        _status.text = "This is not a managed library. Use Copy collection to create one."
        return
    _busy = true
    _status.text = "Copying and verifying every ROM. Originals will be retained."
    await get_tree().process_frame
    if _operation == "copy":
        var response: Variant = JSON.parse_string(str(owner_ui._backend.call("copy_library_json", path)))
        if not response is Dictionary or not bool(response.get("ok", false)):
            _status.text = str(response.get("error", "The library could not be copied.")) if response is Dictionary else "Invalid copy response."
            _busy = false
            return
    var previous := Preferences.library_root()
    if Preferences.write_value("rom_root", path) != OK:
        _status.text = "The storage setting could not be saved. Your original library is still active."
        _busy = false
        return
    var error: String = owner_ui._configure_backend_paths()
    if not error.is_empty():
        Preferences.write_value("rom_root", previous)
        owner_ui._configure_backend_paths()
        _status.text = error
        _busy = false
        return
    owner_ui._reconnect_library()
    _status.text = "Library connected. Originals were retained as a safety copy." if _operation == "copy" else "Library connected."
    _busy = false
    refresh()
    changed.emit()

func _label(parent: Node, text: String, font_size: int) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    parent.add_child(label)
    return label

func _button(parent: Node, text: String, action: Callable) -> void:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size.y = 38
    button.pressed.connect(action)
    parent.add_child(button)
