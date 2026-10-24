extends SceneTree

## Probe the resource boundary with original disposable fixtures, never owner art.
const ReleaseEntry = preload("res://scripts/release_entry.gd")


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    var probe := ReleaseEntry.new()
    var errors: Array[String] = []
    var temporary := "user://public-assets-smoke-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
    var nested := temporary.path_join("nested")
    DirAccess.make_dir_recursive_absolute(nested)
    if probe._has_private_bundle_assets(temporary):
        errors.append("Empty resource directories must be accepted")
    var fixture := nested.path_join("private-fixture.glb")
    var file := FileAccess.open(fixture, FileAccess.WRITE)
    file.store_string("Original boundary test fixture; not a model")
    file.close()
    if not probe._has_private_bundle_assets(temporary):
        errors.append("Nested non-brand resources must be rejected")
    if probe._has_private_bundle_assets("res://assets"):
        errors.append("Clean public source may contain only reviewed RetroLife branding")
    # The fixture above remains outside res:// and must not affect this result.
    DirAccess.remove_absolute(fixture)
    DirAccess.remove_absolute(nested)
    DirAccess.remove_absolute(temporary)
    probe.free()
    if errors.is_empty():
        print("Public asset probe passed: original branding, empty directories, nested private resource rejection and external collection isolation")
        quit(0)
    else:
        for error in errors:
            push_error(error)
        quit(1)
