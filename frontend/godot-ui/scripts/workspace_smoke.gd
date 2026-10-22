extends SceneTree

const Bindings = preload("res://scripts/workspace/bindings.gd")

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var main := preload("res://scripts/main.gd").new()
    main._ensure_input_actions()
    var defaults := Bindings.snapshot()
    Bindings.defaults = defaults
    var gameplay := preload("res://scripts/launch_integration.gd").new()
    var key := InputEventKey.new()
    key.keycode = KEY_F7
    key.pressed = true
    assert(Bindings.assign("south", key).is_empty())
    assert(gameplay._event_logical_action(key) == "south")
    var old_key := InputEventKey.new()
    old_key.keycode = KEY_X
    assert(gameplay._event_logical_action(old_key).is_empty())
    assert(not Bindings.assign("east", key).is_empty())
    var test_path := "user://workspace-bindings-smoke-%d.cfg" % OS.get_process_id()
    assert(Bindings.save(test_path) == OK)
    Bindings.restore(defaults)
    assert(gameplay._event_logical_action(key).is_empty())
    Bindings.load_saved(test_path)
    assert(gameplay._event_logical_action(key) == "south")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
    var panel := preload("res://scripts/workspace/controller_panel.gd").new()
    root.add_child(panel)
    panel._start_guided()
    assert(Bindings.caption("south", true) == "Not mapped")
    panel._cancel()
    assert(Bindings.caption("south", true) != "Not mapped")
    assert(gameplay._event_logical_action(key) == "south")
    panel._start_guided()
    panel._process(16)
    assert(panel._pending.is_empty())
    assert(Bindings.caption("south", true) != "Not mapped")
    Bindings.restore(defaults)
    panel.free()
    gameplay.free()
    main.free()
    var profiles = preload("res://scripts/workspace/collection_profiles.gd")
    assert(profiles.GAMES.size() == 7)
    for profile in profiles.GAMES:
        assert(profiles.for_game(profile.title, profile.system).slug == profile.slug)
        assert(profile.quests.size() == 4 and profile.gifts.size() == 8)
        assert(profiles.for_game(profile.title, "unrelated-system").is_empty())
    assert(profiles.for_game("Super Mario World (USA) 2", "snes").slug == "super-mario-world")
    assert(profiles.for_game("Super Mario Bros. 2", "nes").is_empty())
    assert(profiles.for_game("Crash Bandicoot 2", "playstation-1").is_empty())
    assert(profiles.for_game("Unlisted Game").is_empty())
    print("Workspace mapping smoke passed: live remap routing, duplicate rejection, save/reload, guided cancellation and timeout rollback.")
    quit()
