extends PopupPanel

signal presentation_changed
const Packs = preload("res://scripts/workspace/game_presentation.gd")
const PresentationTheme = preload("res://scripts/workspace/presentation_theme.gd")
const ScreenScraper = preload("res://scripts/workspace/screenscraper_client.gd")
var _client: Node
var _system := ""
var _slug := ""
var _game_title := ""
var _generation := 0
var _heading: Label
var _query: LineEdit
var _credentials: Dictionary = {}
var _search: Button
var _fetch: Button
var _import: Button
var _music_import: Button
var _results: OptionButton
var _background: CheckBox
var _video: CheckBox
var _status: Label
var _scroll: ScrollContainer
var _picker: FileDialog
var _music_picker: FileDialog
var _games: Array = []

func _ready() -> void:
    title = "Game media · ScreenScraper"
    theme = PresentationTheme.make_theme()
    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 12)
    add_child(margin)
    _scroll = ScrollContainer.new()
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    margin.add_child(_scroll)
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 10)
    _scroll.add_child(column)
    _heading = _label(column, "Game media", 23)
    _label(column, "Find game information, backgrounds and preview videos. Saved media stays in your local collection and works offline.", 14)
    _label(column, "ScreenScraper credentials · this session only", 17)
    _label(column, "Use the developer credentials approved for your app. Your ScreenScraper user login is a separate account. All fields are cleared when this window closes.", 13)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 12)
    grid.add_theme_constant_override("v_separation", 8)
    column.add_child(grid)
    for field in [["devid", "Developer ID", false], ["devpassword", "Developer password", true], ["ssid", "User login (optional)", false], ["sspassword", "User password", true]]:
        _label(grid, str(field[1]), 14)
        var input := LineEdit.new()
        input.secret = bool(field[2])
        input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        input.custom_minimum_size.x = 260
        input.max_length = 256
        grid.add_child(input)
        _credentials[str(field[0])] = input
    _button(column, "Open official API setup instructions", func(): OS.shell_open("https://www.screenscraper.fr/webapi2.php"))
    column.add_child(HSeparator.new())
    _label(column, "1. Search this console", 17)
    _query = LineEdit.new()
    _query.placeholder_text = "Game title"
    _query.max_length = 160
    column.add_child(_query)
    _search = _button(column, "Search ScreenScraper", _search_pressed)
    _label(column, "2. Choose the exact game", 17)
    _results = OptionButton.new()
    _results.fit_to_longest_item = false
    _results.text = "Search results appear here"
    _results.disabled = true
    _results.item_selected.connect(func(_index): _fetch.disabled = false)
    column.add_child(_results)
    _background = CheckBox.new()
    _background.text = "Download background (fanart or screenshot)"
    _background.button_pressed = true
    column.add_child(_background)
    _video = CheckBox.new()
    _video.text = "Also download an MP4 preview video (up to 128 MB)"
    column.add_child(_video)
    _label(column, "MP4 previews open in your video player. An imported OGV preview can play inside RetroLife. Existing media is retained when the provider has no replacement.", 12)
    _fetch = _button(column, "Save selected game's media", _fetch_pressed)
    _fetch.disabled = true
    column.add_child(HSeparator.new())
    _import = _button(column, "Import an offline metadata.json pack…", _pick_pack)
    _music_import = _button(column, "Add local selection music…", _pick_music)
    _label(column, "Optional OGG, MP3 or WAV · up to 32 MB. Game music is off until you enable it on the selection screen. ScreenScraper provides game previews, not soundtrack downloads.", 12)
    _status = _label(column, "No requests are made until you choose Search or Save.", 13)
    _button(column, "Done", _close)
    _client = ScreenScraper.new()
    add_child(_client)
    _client.progress.connect(func(message): _status.text = message)
    _picker = FileDialog.new()
    _picker.access = FileDialog.ACCESS_FILESYSTEM
    _picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _picker.filters = PackedStringArray(["*.json ; Presentation metadata"])
    _picker.file_selected.connect(_import_pack)
    add_child(_picker)
    _music_picker = FileDialog.new()
    _music_picker.access = FileDialog.ACCESS_FILESYSTEM
    _music_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _music_picker.filters = PackedStringArray(["*.ogg,*.mp3,*.wav ; Game selection music"])
    _music_picker.file_selected.connect(_import_music)
    add_child(_music_picker)
    popup_hide.connect(_clear_session)
    close_requested.connect(_close)

func open_for_game(system: String, slug: String, game_title: String) -> void:
    _clear_session()
    _system = system
    _slug = slug
    _game_title = game_title
    _heading.text = "Game media · " + game_title
    _query.text = game_title
    _status.text = "No requests are made until you choose Search or Save."
    _games.clear()
    _results.clear()
    _results.text = "Search results appear here"
    _results.disabled = true
    _fetch.disabled = true
    _set_busy(false)
    var host := get_parent().get_window()
    var target := Vector2i(mini(720, int(host.size.x * 0.92)), mini(780, int(host.size.y * 0.9)))
    _scroll.custom_minimum_size = Vector2(maxi(320, target.x - 68), maxi(200, target.y - 68))
    var generation := _generation
    popup_centered(target)
    await get_tree().process_frame
    await get_tree().process_frame
    if generation != _generation or not visible:
        return
    size = target
    position = (host.size - size) / 2
    if not is_embedded():
        position += host.position
    if str(_credentials.devid.text).is_empty():
        _credentials.devid.grab_focus.call_deferred()
    else:
        _query.grab_focus.call_deferred()

func _session_credentials() -> Dictionary:
    var result := {}
    for key in _credentials:
        result[key] = str(_credentials[key].text)
    return result

func _search_pressed() -> void:
    if _client.busy:
        return
    var generation := _generation
    var credentials := _session_credentials()
    _set_busy(true)
    _status.text = "Searching only the selected console…"
    var response: Dictionary = await _client.search_games(credentials, _system, _query.text)
    credentials.clear()
    if generation != _generation:
        return
    _set_busy(false)
    _games.clear()
    _results.clear()
    if not response.ok:
        _status.text = str(response.error)
        _results.disabled = true
        _fetch.disabled = true
        return
    _games = response.games
    for game in _games:
        _results.add_item(str(game.title) + (" · " + str(game.year) if not str(game.year).is_empty() else "") + " · #" + str(game.id))
    _results.select(-1)
    _results.text = "Choose the matching game…"
    _results.disabled = false
    _fetch.disabled = true
    _status.text = "Choose the exact game before saving. Nothing has been changed yet."

func _fetch_pressed() -> void:
    if _client.busy or _results.selected < 0 or _results.selected >= _games.size():
        return
    var generation := _generation
    var credentials := _session_credentials()
    var game: Dictionary = _games[_results.selected]
    _set_busy(true)
    var response: Dictionary = await _client.fetch_game(credentials, _system, _slug, str(game.id), _background.button_pressed, _video.button_pressed)
    credentials.clear()
    if generation != _generation:
        return
    _set_busy(false)
    _status.text = str(response.get("message", "Saved for offline viewing.")) if response.ok else str(response.error)
    if response.ok:
        presentation_changed.emit()

func _pick_pack() -> void:
    if not _client.busy:
        _picker.title = "Import the presentation pack for this game"
        _picker.popup_centered_ratio(0.75)

func _import_pack(path: String) -> void:
    if _client.busy:
        return
    var response := Packs.import_pack(path, _system, _slug)
    _status.text = "Local presentation imported. No network request was made." if response.ok else str(response.error)
    if response.ok:
        presentation_changed.emit()

func _pick_music() -> void:
    if not _client.busy:
        _music_picker.title = "Choose local music for " + _game_title
        _music_picker.popup_centered_ratio(0.75)

func _import_music(path: String) -> void:
    if _client.busy:
        return
    var response := Packs.import_music(path, _system, _slug, _game_title)
    _status.text = str(response.get("message", "Game music imported.")) if response.ok else str(response.error)
    if response.ok:
        presentation_changed.emit()

func _set_busy(value: bool) -> void:
    _search.disabled = value
    _import.disabled = value
    _music_import.disabled = value
    _query.editable = not value
    _background.disabled = value
    _video.disabled = value
    _results.disabled = value or _games.is_empty()
    _fetch.disabled = value or _results.selected < 0 or _games.is_empty()
    for input in _credentials.values():
        input.editable = not value

func _close() -> void:
    _clear_session()
    hide()

func _clear_session() -> void:
    _generation += 1
    if is_instance_valid(_client):
        _client.cancel()
    for input in _credentials.values():
        input.text = ""
    if is_instance_valid(_picker):
        _picker.hide()
    if is_instance_valid(_music_picker):
        _music_picker.hide()

func _label(parent: Node, text: String, size: int) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", size)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(label)
    return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size.y = 34
    button.pressed.connect(callback)
    parent.add_child(button)
    return button
