extends SceneTree

const FRONT := preload("res://scenes/SnesNaCartridgeFrontM2_2.tscn")
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var asset := FRONT.instantiate()
    root.add_child(asset)
    await process_frame
    await process_frame
    _require(str(asset.get_meta("asset_id", "")) == "retrolife.snes.na-cartridge.m2.2.front.v3", "asset id")
    _require(str(asset.get_meta("prior_asset_id", "")) == "retrolife.snes.na-cartridge.m2.2.front.v2", "prior asset id")
    _require(str(asset.get_meta("source", "")) == "original-parametric-multi-section-loft-rebuild", "source")
    _require(str(asset.get_meta("surface_model", "")) == "multi-section-loft-with-molded-front-patch", "surface model")
    _require(not bool(asset.get_meta("height_field_only", true)), "not height-field-only")
    _require(not bool(asset.get_meta("console_visible", true)), "console exclusion")
    _require(not bool(asset.get_meta("physical_calibration_complete", true)), "calibration honesty")
    _require(not bool(asset.get_meta("external_geometry_copied", true)), "external geometry boundary")
    _require(not bool(asset.get_meta("prior_geometry_accepted", true)), "prior geometry rejection")
    _require(not bool(asset.get_meta("may_approve_final_geometry", true)), "approval gate")
    _require(not bool(asset.get_meta("may_start_m2_3_blockout", true)), "M2.3 gate")
    _require(not bool(asset.get_meta("may_start_m3", true)), "M3 gate")
    var shell := asset.find_child("ContinuousShell", true, false) as MeshInstance3D
    _require(shell != null and shell.mesh != null, "continuous shell")
    _require(str(shell.get_meta("surface_topology", "")) == "single-connected-watertight-shell", "watertight metadata")
    _require(int(shell.get_meta("triangle_count", 0)) > 10000, "triangle budget")
    var shell_size := shell.get_aabb().size
    _require(absf(shell_size.x - 0.136) <= 0.0012, "width")
    _require(absf(shell_size.y - 0.088) <= 0.0012, "height")
    _require(absf(shell_size.z - 0.0104) <= 0.0010, "front depth")
    var label := asset.find_child("LabelSurface", true, false) as MeshInstance3D
    _require(label != null and label.mesh != null, "label surface")
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
    print("RETROLIFE_M2_2_FRONT_GODOT_OK asset=v3 loft=true height_field_only=false watertight=true uv=true console=false physical_calibrated=false final_approval=false m2_3=false m3=false")
    quit(0)
func _require(condition: bool, label_name: String) -> void:
    if condition:
        return
    push_error("RETROLIFE_M2_2_FRONT_GODOT_FAILED: %s" % label_name)
    quit(1)
