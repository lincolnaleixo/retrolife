extends Control

## Presentation-only save browser. The launcher owns pause and all state operations.
signal save_requested(slot: int)
signal load_requested(slot: int)
signal close_requested

const PresentationTheme = preload("res://scripts/workspace/presentation_theme.gd")
const UiIcons = preload("res://scripts/workspace/ui_icons.gd")
const SLOT_COUNT := 8
const QUICK_SLOT := 6
const RECOVERY_SLOT := 7

var _slot_cards: Dictionary = {}
var _save_buttons: Dictionary = {}
var _load_buttons: Dictionary = {}
var _slots: Dictionary = {}
var _previews: Dictionary = {}
var _panel: PanelContainer
var _grid: GridContainer
var _scroll: ScrollContainer
var _game_title: Label
var _summary: Label
var _status: Label
var _close_button: Button
var _retry_button: Button
var _confirmation: PanelContainer
var _confirm_title: Label
var _confirm_description: Label
var _confirm_button: Button
var _cancel_button: Button
var _busy := false
var _snapshot_ready := false
var _supported := false
var _catalog_busy := false
var _can_resume := true
var _confirm_action := ""
var _confirm_slot := -1
var _last_action := ""
var _last_slot := -1
var _open_generation := 0
var _configured_title := "Your game"

func _ready() -> void:
    theme = PresentationTheme.make_theme()
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    offset_top = 80
    mouse_filter = Control.MOUSE_FILTER_STOP
    var dim := ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.008, 0.014, 0.024, 0.78)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    _panel = PanelContainer.new()
    _panel.mouse_filter = Control.MOUSE_FILTER_STOP
    _panel.add_theme_stylebox_override("panel", _style(Color("101b26"), Color("45616b"), 20, 20))
    add_child(_panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    _panel.add_child(column)
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 14)
    column.add_child(header)
    var mark := TextureRect.new()
    mark.texture = UiIcons.icon("save", PresentationTheme.ACCENT, 36)
    mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    mark.custom_minimum_size = Vector2(38, 38)
    mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
    header.add_child(mark)
    var heading := VBoxContainer.new()
    heading.add_theme_constant_override("separation", 2)
    heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(heading)
    var title := _label(heading, "Saved moments", 25)
    title.add_theme_font_override("font", PresentationTheme.heading_font())
    _game_title = _label(heading, _configured_title, 13, PresentationTheme.MUTED)
    _game_title.clip_text = true
    _game_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _close_button = Button.new()
    _close_button.icon = UiIcons.icon("close", PresentationTheme.INK, 20)
    _close_button.custom_minimum_size = Vector2(44, 44)
    _close_button.tooltip_text = "Close saved moments · Escape"
    _close_button.accessibility_name = "Close saved moments"
    _close_button.pressed.connect(request_close)
    header.add_child(_close_button)
    var introduction := HBoxContainer.new()
    introduction.add_theme_constant_override("separation", 12)
    column.add_child(introduction)
    var subtitle := _label(introduction, "Keep a moment. Pick up right where you left off.", 13, PresentationTheme.MUTED)
    subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _summary = _label(introduction, "Loading slots…", 12, PresentationTheme.ACCENT)
    _summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _scroll = ScrollContainer.new()
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _scroll.follow_focus = true
    column.add_child(_scroll)
    _grid = GridContainer.new()
    _grid.columns = 3
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _grid.add_theme_constant_override("h_separation", 12)
    _grid.add_theme_constant_override("v_separation", 12)
    _scroll.add_child(_grid)
    for slot in SLOT_COUNT:
        _build_slot(slot)
    _build_confirmation(column)
    var footer := HBoxContainer.new()
    footer.add_theme_constant_override("separation", 12)
    column.add_child(footer)
    _status = _label(footer, "Game paused. Save states are separate from in-game saves.", 12, PresentationTheme.MUTED)
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _retry_button = Button.new()
    _retry_button.text = "Retry"
    _retry_button.icon = UiIcons.icon("restore", PresentationTheme.ACCENT, 18)
    _retry_button.accessibility_name = "Retry the failed save-state operation"
    _retry_button.pressed.connect(_retry_operation)
    _retry_button.hide()
    footer.add_child(_retry_button)
    resized.connect(_layout)
    _refresh_slots()
    _layout()
    hide()

func _build_slot(slot: int) -> void:
    var card := PanelContainer.new()
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.add_theme_stylebox_override("panel", _style(Color("172631"), Color("344b59"), 12, 10))
    _grid.add_child(card)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 7)
    card.add_child(column)
    var heading := HBoxContainer.new()
    column.add_child(heading)
    var title := _label(heading, _slot_name(slot), 15)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_override("font", PresentationTheme.heading_font())
    var tag := _label(heading, "AUTO" if slot == RECOVERY_SLOT else ("QUICK" if slot == QUICK_SLOT else "%02d" % (slot + 1)), 10, PresentationTheme.ACCENT)
    tag.tooltip_text = "Preserved before you load another moment." if slot == RECOVERY_SLOT else ("A dedicated slot for quick saving." if slot == QUICK_SLOT else "Manual save slot")
    var preview_frame := PanelContainer.new()
    preview_frame.custom_minimum_size.y = 112
    preview_frame.add_theme_stylebox_override("panel", _style(Color("0a121c"), Color("253a47"), 6, 0))
    column.add_child(preview_frame)
    var preview := TextureRect.new()
    preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    preview.custom_minimum_size.y = 112
    preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    preview_frame.add_child(preview)
    var empty := VBoxContainer.new()
    empty.alignment = BoxContainer.ALIGNMENT_CENTER
    empty.add_theme_constant_override("separation", 7)
    empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
    preview_frame.add_child(empty)
    var empty_icon := TextureRect.new()
    empty_icon.texture = UiIcons.icon("restore" if slot == RECOVERY_SLOT else "save", Color("577f88"), 30)
    empty_icon.custom_minimum_size.y = 30
    empty_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    empty_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    empty_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    empty.add_child(empty_icon)
    var empty_label := _label(empty, "Created before loading" if slot == RECOVERY_SLOT else "Your next checkpoint", 12, Color("8aa5af"))
    empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var saved := _label(column, "No saved moment", 12, PresentationTheme.MUTED)
    saved.clip_text = true
    saved.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    var actions := HBoxContainer.new()
    actions.add_theme_constant_override("separation", 7)
    column.add_child(actions)
    if slot != RECOVERY_SLOT:
        var save_button := _action_button(actions, "Save here", "save")
        save_button.accessibility_name = "Save current moment to " + _slot_name(slot)
        save_button.pressed.connect(func(): _request_action("save", slot))
        _save_buttons[slot] = save_button
    var load_button := _action_button(actions, "Load", "play")
    load_button.accessibility_name = "Load " + _slot_name(slot)
    load_button.pressed.connect(func(): _request_action("load", slot))
    _load_buttons[slot] = load_button
    _slot_cards[slot] = {"panel": card, "preview": preview, "empty": empty, "empty_label": empty_label, "saved": saved, "tag": tag}

func _build_confirmation(parent: Node) -> void:
    _confirmation = PanelContainer.new()
    _confirmation.add_theme_stylebox_override("panel", _style(Color("233137"), Color("739e95"), 12, 12))
    parent.add_child(_confirmation)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 14)
    _confirmation.add_child(row)
    var message := VBoxContainer.new()
    message.add_theme_constant_override("separation", 4)
    message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(message)
    _confirm_title = _label(message, "Load this moment?", 15)
    _confirm_title.add_theme_font_override("font", PresentationTheme.heading_font())
    _confirm_description = _label(message, "", 12, PresentationTheme.MUTED)
    _confirm_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var actions := VBoxContainer.new()
    actions.add_theme_constant_override("separation", 6)
    actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(actions)
    _confirm_button = _action_button(actions, "Load moment", "play")
    _confirm_button.custom_minimum_size.x = 156
    _confirm_button.pressed.connect(_confirm_operation)
    _cancel_button = _action_button(actions, "Cancel", "back")
    _cancel_button.pressed.connect(_cancel_confirmation)
    _confirmation.hide()

func configure(game_title: String) -> void:
    _configured_title = game_title.strip_edges() if not game_title.strip_edges().is_empty() else "Your game"
    if is_instance_valid(_game_title):
        _game_title.text = _configured_title

func set_snapshot(data: Dictionary, previews: Dictionary = {}) -> void:
    _slots.clear()
    var entries: Variant = data.get("slots", [])
    if entries is Array:
        for entry in entries:
            if entry is Dictionary:
                var slot := int(entry.get("slot", -1))
                if slot >= 0 and slot < SLOT_COUNT:
                    _slots[slot] = entry.duplicate(true)
    elif entries is Dictionary:
        for key in entries:
            var slot := int(key)
            if slot >= 0 and slot < SLOT_COUNT and entries[key] is Dictionary:
                _slots[slot] = entries[key].duplicate(true)
    _previews = previews.duplicate()
    _supported = bool(data.get("supported", false))
    _catalog_busy = bool(data.get("busy", false))
    _can_resume = bool(data.get("canResume", true))
    _snapshot_ready = data.has("supported") and data.has("slots") and (entries is Array or entries is Dictionary)
    if is_instance_valid(_grid):
        _refresh_slots()
        if not _can_resume:
            set_status("")

func open_panel() -> void:
    _open_generation += 1
    _clear_confirmation()
    _last_action = ""
    _last_slot = -1
    _busy = false
    _catalog_busy = false
    _can_resume = true
    _supported = false
    _snapshot_ready = false
    _slots.clear()
    _previews.clear()
    _scroll.scroll_vertical = 0
    set_status("")
    show()
    _refresh_slots()
    _layout()
    _focus_slot.call_deferred(0, _open_generation)

func dismiss() -> void:
    _open_generation += 1
    hide()
    _clear_confirmation()
    _busy = false
    _catalog_busy = false
    _can_resume = true
    _snapshot_ready = false
    _supported = false
    _slots.clear()
    _previews.clear()
    if is_instance_valid(_grid):
        _refresh_slots()

func set_busy(busy: bool, message: String = "") -> void:
    _busy = busy
    if not busy:
        _catalog_busy = false
    if busy:
        _clear_confirmation()
        _retry_button.hide()
        set_status(message if not message.is_empty() else "Working on your saved moment…")
    elif not message.is_empty():
        set_status(message)
    _refresh_slots()

func set_error(message: String) -> void:
    _busy = false
    _catalog_busy = false
    _clear_confirmation()
    _status.text = _unsafe_session_message() if not _can_resume else (message if not message.is_empty() else "This moment could not be saved or loaded. Please try again.")
    _status.add_theme_color_override("font_color", Color("ffbd9f"))
    _retry_button.visible = _can_request(_last_action, _last_slot)
    _refresh_slots()
    if is_visible_in_tree() and _retry_button.visible:
        _focus_retry.call_deferred(_open_generation)

func set_status(message: String) -> void:
    _status.text = _unsafe_session_message() if not _can_resume else ("Game paused. Save states are separate from in-game saves." if message.is_empty() else message)
    _status.add_theme_color_override("font_color", PresentationTheme.MUTED if _can_resume else Color("ffbd9f"))
    _retry_button.hide()

func request_slot_action(action: String, slot: int) -> void:
    _request_action(action, slot)

func cancel_or_close() -> void:
    request_close()

func request_close() -> void:
    if _is_busy():
        return
    if not _confirm_action.is_empty():
        _cancel_confirmation()
        return
    close_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
    if not is_visible_in_tree():
        return
    if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
        get_viewport().set_input_as_handled()
        request_close()

func _request_action(action: String, slot: int) -> void:
    if _is_busy() or not _can_request(action, slot):
        return
    _retry_button.hide()
    if action == "load" or _occupied(slot):
        _confirm_action = action
        _confirm_slot = slot
        _confirm_title.text = ("Replace %s?" if action == "save" else "Load %s?") % _slot_name(slot)
        _confirm_description.text = "This replaces the saved moment in this slot with your current point." if action == "save" else "This replaces your current moment. Your current point will be preserved as Recovery before loading."
        _confirm_button.text = "Replace save" if action == "save" else "Load moment"
        _confirm_button.icon = UiIcons.icon("save" if action == "save" else "play", PresentationTheme.ACCENT, 18)
        _confirmation.show()
        _scroll.ensure_control_visible(_slot_cards[slot].panel)
        _refresh_slots()
        _cancel_button.grab_focus()
    else:
        _emit_operation(action, slot)

func _confirm_operation() -> void:
    if _is_busy() or not _can_request(_confirm_action, _confirm_slot):
        return
    _emit_operation(_confirm_action, _confirm_slot)

func _cancel_confirmation() -> void:
    if _is_busy():
        return
    var slot := _confirm_slot
    _clear_confirmation()
    _refresh_slots()
    _focus_slot.call_deferred(slot, _open_generation)

func _clear_confirmation() -> void:
    _confirm_action = ""
    _confirm_slot = -1
    if is_instance_valid(_confirmation):
        _confirmation.hide()

func _retry_operation() -> void:
    if not _is_busy() and _can_request(_last_action, _last_slot):
        _emit_operation(_last_action, _last_slot)

func _emit_operation(action: String, slot: int) -> void:
    _last_action = action
    _last_slot = slot
    set_busy(true, ("Saving %s…" if action == "save" else "Loading %s…") % _slot_name(slot))
    if action == "save":
        save_requested.emit(slot)
    else:
        load_requested.emit(slot)

func _can_request(action: String, slot: int) -> bool:
    if not _snapshot_ready or not _supported or not _can_resume or _catalog_busy or slot < 0 or slot >= SLOT_COUNT:
        return false
    if action == "save":
        return slot != RECOVERY_SLOT
    return action == "load" and _occupied(slot) and bool(_slots.get(slot, {}).get("compatible", true))

func _unsafe_session_message() -> String:
    return "This session cannot safely resume. Stop the game; your Recovery save remains available."

func _is_busy() -> bool:
    return _busy or _catalog_busy

func _occupied(slot: int) -> bool:
    return bool(_slots.get(slot, {}).get("occupied", false))

func _refresh_slots() -> void:
    var occupied_count := 0
    for slot in SLOT_COUNT:
        var card: Dictionary = _slot_cards[slot]
        var occupied := _occupied(slot)
        var compatible := bool(_slots.get(slot, {}).get("compatible", true))
        occupied_count += 1 if occupied else 0
        var preview: Variant = _previews.get(slot, _previews.get(str(slot)))
        card.preview.texture = preview if occupied and preview is Texture2D else null
        card.empty.visible = card.preview.texture == null
        card.empty_label.text = "Preview unavailable" if occupied else ("Created before loading" if slot == RECOVERY_SLOT else "Your next checkpoint")
        card.saved.text = _slot_caption(slot) if occupied else ("Preserves the point you leave" if slot == RECOVERY_SLOT else "Ready for your first save")
        card.saved.tooltip_text = _slot_caption(slot)
        card.tag.add_theme_color_override("font_color", Color("ffc59c") if occupied and not compatible else PresentationTheme.ACCENT)
        card.panel.add_theme_stylebox_override("panel", _style(Color("172631") if occupied else Color("121f2b"), Color("6d978b") if slot == _confirm_slot else Color("344b59"), 12, 10))
        if _save_buttons.has(slot):
            _save_buttons[slot].text = "Save" if occupied else "Save here"
            _save_buttons[slot].disabled = _is_busy() or not _can_request("save", slot)
            _save_buttons[slot].tooltip_text = "Replace this slot with your current moment." if occupied else "Save your current moment in this empty slot."
        _load_buttons[slot].disabled = _is_busy() or not _can_request("load", slot)
        _load_buttons[slot].tooltip_text = "This state cannot be loaded with the current game or core." if occupied and not compatible else ("Return to this saved moment." if occupied else "Save a moment here first.")
    _summary.text = "Loading slots…"
    if _snapshot_ready and not _catalog_busy:
        _summary.text = "%d / 8 saved" % occupied_count if _supported else "Not available for this core"
    _close_button.disabled = _is_busy()
    _confirm_button.disabled = _is_busy()
    _cancel_button.disabled = _is_busy()
    _retry_button.disabled = _is_busy()
    _retry_button.visible = _retry_button.visible and _can_request(_last_action, _last_slot)

func _slot_caption(slot: int) -> String:
    var entry: Dictionary = _slots.get(slot, {})
    if not bool(entry.get("compatible", true)):
        return "Unavailable for this game or core"
    var timestamp: Variant = entry.get("createdAt", entry.get("timestamp_unix", 0))
    var saved_at := str(entry.get("saved_at", "")).strip_edges()
    if timestamp is int or timestamp is float:
        if is_finite(float(timestamp)) and float(timestamp) > 0.0:
            saved_at = Time.get_datetime_string_from_unix_time(int(timestamp)).replace("T", " ") + " UTC"
    if saved_at.is_empty():
        saved_at = "Saved moment"
    return saved_at

func _slot_name(slot: int) -> String:
    if slot == QUICK_SLOT:
        return "Quick save"
    if slot == RECOVERY_SLOT:
        return "Recovery"
    return "Slot %d" % (slot + 1)

func _focus_slot(slot: int, generation: int) -> void:
    if generation != _open_generation or not is_visible_in_tree():
        return
    # Containers need one layout pass before focus can scroll a whole card into view.
    await get_tree().process_frame
    if generation != _open_generation or not is_visible_in_tree() or _is_busy() or not _confirm_action.is_empty():
        return
    var target: Button = _save_buttons.get(slot, _load_buttons.get(slot, _close_button))
    if not target.disabled:
        target.grab_focus()
        if _slot_cards.has(slot):
            _scroll.ensure_control_visible(_slot_cards[slot].panel)

func _focus_retry(generation: int) -> void:
    if generation == _open_generation and is_visible_in_tree() and not _is_busy() and _retry_button.visible:
        _retry_button.grab_focus()

func _layout() -> void:
    if not is_instance_valid(_panel):
        return
    var dimensions := Vector2(minf(960.0, maxf(0.0, size.x - 32.0)), maxf(0.0, size.y - 24.0))
    _panel.size = dimensions
    _panel.position = (size - dimensions) / 2.0
    _grid.columns = 3 if dimensions.x >= 850.0 else 2

func _action_button(parent: Node, text: String, icon_name: String) -> Button:
    var button := Button.new()
    button.text = text
    button.icon = UiIcons.icon(icon_name, PresentationTheme.ACCENT, 17)
    button.add_theme_font_size_override("font_size", 13)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.custom_minimum_size.y = 36
    parent.add_child(button)
    return button

func _label(parent: Node, text: String, font_size: int, color := Color("f0f4f5")) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label

func _style(background: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = background
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    style.set_content_margin_all(margin)
    return style
