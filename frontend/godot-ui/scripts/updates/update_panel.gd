extends PopupPanel

## Native Sparkle owns transfer progress, signature validation and installation.
## This panel is a settings/status surface, never a downloader or shell launcher.
var request: Callable
var _version: Label
var _status: Label
var _checked: Label
var _check: Button
var _auto_checks: CheckButton
var _auto_downloads: CheckButton
var _beta: CheckButton
var _poll: Timer


func _ready() -> void:
    name = "SoftwareUpdates"
    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 18)
    add_child(margin)
    var outer := VBoxContainer.new()
    outer.add_theme_constant_override("separation", 12)
    margin.add_child(outer)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.custom_minimum_size = Vector2(420, 350)
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    outer.add_child(scroll)
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 12)
    scroll.add_child(column)
    var heading := _label("Software updates", 24)
    column.add_child(heading)
    _version = _label("RetroLife", 15)
    column.add_child(_version)
    _status = _label("Loading update settings...", 14)
    _status.custom_minimum_size.y = 48
    column.add_child(_status)
    _checked = _label("", 12)
    column.add_child(_checked)
    _check = Button.new()
    _check.name = "CheckForUpdates"
    _check.text = "Check for Updates..."
    _check.pressed.connect(func(): _send("check"))
    column.add_child(_check)
    column.add_child(HSeparator.new())
    _auto_checks = _toggle("Check for updates automatically", "checks_on", "checks_off")
    _auto_downloads = _toggle("Download and install updates automatically", "downloads_on", "downloads_off")
    _beta = _toggle("Include beta versions", "beta_on", "beta_off")
    column.add_child(_auto_checks)
    column.add_child(_auto_downloads)
    column.add_child(_beta)
    var note := _label("Updates replace only the app, not your games or saves. Installation never interrupts an active game. Automatic installation is optional.", 12)
    column.add_child(note)
    var close := Button.new()
    close.name = "CloseUpdates"
    close.text = "Close"
    close.pressed.connect(hide)
    outer.add_child(close)
    _poll = Timer.new()
    _poll.wait_time = 0.5
    _poll.timeout.connect(refresh)
    add_child(_poll)
    popup_hide.connect(_poll.stop)
    window_input.connect(func(event: InputEvent):
        if event.is_action_pressed("ui_cancel"):
            hide()
            set_input_as_handled()
    )


func open_panel() -> void:
    refresh()
    popup_centered(Vector2i(520, mini(560, get_tree().root.size.y - 48)))
    _poll.start()
    if not _check.disabled:
        _check.call_deferred("grab_focus")


func refresh() -> void:
    _send("status")


func _send(command: String) -> void:
    var response: Dictionary = {}
    if request.is_valid():
        var raw: Variant = request.call(command)
        if raw is Dictionary:
            response = raw
    var data: Dictionary = response.get("data", {})
    var available := bool(data.get("available", false))
    var busy := bool(data.get("gameActive", false)) or bool(data.get("sessionInProgress", false)) or bool(data.get("installPending", false))
    _version.text = "RetroLife %s" % str(data.get("currentVersion", "development build"))
    _status.text = str(data.get("message", "Updates are available in installed, signed macOS releases."))
    if not bool(response.get("ok", false)) and response.get("error") != null:
        _status.text = str(response.get("error"))
    var checked := int(data.get("lastChecked", 0))
    _checked.text = "Last checked: %s UTC" % Time.get_datetime_string_from_unix_time(checked, true) if checked > 0 else "Not checked yet"
    _check.disabled = not available or not bool(data.get("canCheck", false))
    _auto_checks.disabled = not available or busy
    _auto_downloads.disabled = not available or busy
    _beta.disabled = not available or busy
    _auto_checks.set_pressed_no_signal(bool(data.get("automaticChecks", false)))
    _auto_downloads.set_pressed_no_signal(bool(data.get("automaticDownloads", false)))
    _beta.set_pressed_no_signal(bool(data.get("includeBeta", false)))


func _toggle(text: String, on: String, off: String) -> CheckButton:
    var button := CheckButton.new()
    button.text = text
    button.toggled.connect(func(enabled: bool): _send(on if enabled else off))
    return button


func _label(text: String, font_size: int) -> Label:
    var label := Label.new()
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", font_size)
    return label
