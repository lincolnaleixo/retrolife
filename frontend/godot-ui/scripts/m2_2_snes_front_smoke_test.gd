extends SceneTree

const FRONT := preload("res://scenes/SnesNaCartridgeFrontM2_2.tscn")


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var asset := FRONT.instantiate()
    root.add_child(asset)
    await process_frame
    await process_frame

    _require(str(asset.get_meta("asset_id", "")) == "retrolife.snes.na-cartridge.m2.2.front.v1", "asset id")
    _require(str(asset.get_meta("license", "")) == "CC0-1.0", "license")
    _require(str(asset.get_meta("source", "")) == "original-parametric-clean-rebuild", "source")
    _require(not bool(asset.get_meta("console_visible", true)), "console exclusion")
    _require(not bool(asset.get_meta("physical_calibration_complete", true)), "calibration honesty")
    _require(not bool(asset.get_meta("may_approve_final_geometry", true)), "approval gate")
    _require(bool(asset.get_meta("may_start_m2_3_blockout", false)), "M2.3 blockout gate")
    _require(not bool(asset.get_meta("may_start_m3", true)), "M3 gate")
    _require(asset.find_child("Console", true, false) == null, "no console node")

    for node_name in ["FrontShell", "FrontFeatures", "FrontGrooves", "LabelSurface", "ScrewWells"]:
        var instance := asset.find_child(node_name, true, false) as MeshInstance3D
        _require(instance != null and instance.mesh != null, "mesh %s" % node_name)
        _require(int(instance.get_meta("triangle_count", 0)) > 0, "triangles %s" % node_name)

    var shell := asset.find_child("FrontShell", true, false) as MeshInstance3D
    var shell_size := shell.get_aabb().size
    _require(absf(shell_size.x - 0.136) <= 0.0011, "width")
    _require(absf(shell_size.y - 0.088) <= 0.0011, "height")
    _require(absf(shell_size.z - 0.0104) <= 0.0008, "front depth")

    var label := asset.find_child("LabelSurface", true, false) as MeshInstance3D
    var arrays := label.mesh.surface_get_arrays(0)
    var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
    _require(not uvs.is_empty(), "label UVs")
    var minimum_uv := Vector2(100.0, 100.0)
    var maximum_uv := Vector2(-100.0, -100.0)
    for uv in uvs:
        minimum_uv = minimum_uv.min(uv)
        maximum_uv = maximum_uv.max(uv)
    _require(minimum_uv.x <= 0.001 and minimum_uv.y <= 0.001, "UV minimum")
    _require(maximum_uv.x >= 0.999 and maximum_uv.y >= 0.999, "UV maximum")
    _require(str(label.get_meta("m3_texture_slot", "")) == "snes-front-label", "M3 texture slot")

    for anchor_name in ["DockPivot", "CenterOfMass", "LabelAnchor", "ConnectorAnchor", "BrowseFocusedAnchor", "DockApproachAnchor"]:
        _require(asset.find_child(anchor_name, true, false) != null, "anchor %s" % anchor_name)

    print("RETROLIFE_M2_2_FRONT_GODOT_OK asset=true meshes=5 grooves=5 uv=true pivot=true console=false physical_calibrated=false final_approval=false m3=false")
    quit(0)


func _require(condition: bool, label_name: String) -> void:
    if condition:
        return
    push_error("RETROLIFE_M2_2_FRONT_GODOT_FAILED: %s" % label_name)
    quit(1)
