extends SceneTree

const Fixtures = preload("res://scripts/cartridge_library_smoke.gd")

class FakeUpdater extends Node:
    var commands: Array[String] = []
    var malformed := false
    var data := {"available": true, "currentVersion": "0.1.0-beta.3", "message": "Ready to check for updates.", "state": "idle", "canCheck": true, "automaticChecks": true, "automaticDownloads": false, "includeBeta": true, "sessionInProgress": false, "gameActive": false, "lastChecked": 0}
    func update_command_json(command: String) -> String:
        commands.append(command)
        if malformed:
            return "[]"
        if command == "check":
            data["state"] = "checking"
            data["canCheck"] = false
            data["sessionInProgress"] = true
            data["message"] = "Checking for updates..."
        elif command == "checks_off":
            data["automaticChecks"] = false
            data["automaticDownloads"] = false
        elif command == "downloads_on":
            data["automaticChecks"] = true
            data["automaticDownloads"] = true
        elif command == "beta_off":
            data["includeBeta"] = false
        return JSON.stringify({"schemaVersion": 1, "ok": true, "data": data})


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    root.size = Vector2i(720, 540)
    var shell := Fixtures.TestShell.new()
    shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(shell)
    var backend := FakeUpdater.new()
    root.add_child(backend)
    shell.set("_backend", backend)
    shell._show_updates()
    await process_frame
    await process_frame
    var panel: PopupPanel = shell.get("_updates_panel")
    var failure := ""
    if not panel.visible or (panel.get("_check") as Button).disabled:
        failure = "Updates panel did not open with a functional check action"
    if not "beta.3" in (panel.get("_version") as Label).text:
        failure = "Updates panel does not show the real release identity"
    (panel.get("_check") as Button).pressed.emit()
    if not "check" in backend.commands or not (panel.get("_auto_checks") as CheckButton).disabled:
        failure = "Manual check was not dispatched or busy preferences stayed writable"
    backend.data["sessionInProgress"] = false
    backend.data["canCheck"] = true
    panel.refresh()
    (panel.get("_auto_downloads") as CheckButton).toggled.emit(true)
    if not bool(backend.data["automaticDownloads"]):
        failure = "Automatic download setting did not reach the backend"
    (panel.get("_auto_checks") as CheckButton).toggled.emit(false)
    if bool(backend.data["automaticChecks"]) or bool(backend.data["automaticDownloads"]):
        failure = "Disabling checks did not disable automatic downloads"
    (panel.get("_beta") as CheckButton).toggled.emit(false)
    if bool(backend.data["includeBeta"]):
        failure = "Stable-only channel was not applied"
    backend.data["gameActive"] = true
    backend.data["canCheck"] = false
    panel.refresh()
    if not (panel.get("_check") as Button).disabled or not (panel.get("_beta") as CheckButton).disabled:
        failure = "Active gameplay did not disable updater controls"
    backend.malformed = true
    panel.refresh()
    if not "invalid response" in (panel.get("_status") as Label).text:
        failure = "Malformed native updater responses were not surfaced"
    shell.set("_backend", null)
    panel.refresh()
    if not (panel.get("_check") as Button).disabled:
        failure = "Unsupported build offered an installation action"
    if panel.size.x > 720 or panel.size.y > 540:
        failure = "Update settings do not fit the supported narrow window"
    var close: Button = panel.find_child("CloseUpdates", true, false)
    if close == null or close.get_global_rect().end.y > panel.size.y:
        failure = "Close action must remain visible without scrolling"
    panel.hide()
    shell.queue_free()
    backend.queue_free()
    await process_frame
    if failure.is_empty():
        print("RetroLife updater UI smoke passed: manual check, preferences, channel, gameplay guard, errors and unsupported builds")
        quit(0)
    else:
        push_error(failure)
        quit(1)
