extends SceneTree

const LOD0 := preload("res://scenes/SnesNaCartridge.tscn")
const LOD1 := preload("res://scenes/SnesNaCartridgeLod1.tscn")


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var asset := LOD0.instantiate()
    root.add_child(asset)
    await process_frame
    await process_frame

    _require(str(asset.get_meta("asset_id", "")) == "retrolife.snes.na-cartridge.m2.v1", "asset id")
    _require(str(asset.get_meta("license", "")) == "CC0-1.0", "CC0 license")
    _require(str(asset.get_meta("source", "")) == "original-parametric", "original source")
    _require(str(asset.get_meta("system_id", "")) == "snes", "SNES system")
    _require(not bool(asset.get_meta("console_visible", true)), "console exclusion")
    _require(asset.find_child("Console", true, false) == null, "no console node")

    var shell := asset.find_child("Shell", true, false) as MeshInstance3D
    var details := asset.find_child("Details", true, false) as MeshInstance3D
    var label := asset.find_child("LabelSurface", true, false) as MeshInstance3D
    var screws := asset.find_child("Screws", true, false) as MeshInstance3D
    var contacts := asset.find_child("Contacts", true, false) as MeshInstance3D
    _require(shell != null and shell.mesh != null, "shell mesh")
    _require(details != null and details.mesh != null, "detail mesh")
    _require(label != null and label.mesh != null, "label mesh")
    _require(screws != null and screws.mesh != null, "screw mesh")
    _require(contacts != null and contacts.mesh != null, "contact mesh")

    var shell_bounds := shell.get_aabb().size
    _require(absf(shell_bounds.x - 0.135) < 0.003, "width")
    _require(absf(shell_bounds.y - 0.0864) < 0.003, "height")
    _require(absf(shell_bounds.z - 0.0202) < 0.003, "depth")

    var label_arrays := label.mesh.surface_get_arrays(0)
    var label_uvs: PackedVector2Array = label_arrays[Mesh.ARRAY_TEX_UV]
    _require(not label_uvs.is_empty(), "label UV")
    var minimum_uv := Vector2(100.0, 100.0)
    var maximum_uv := Vector2(-100.0, -100.0)
    for uv in label_uvs:
        minimum_uv = minimum_uv.min(uv)
        maximum_uv = maximum_uv.max(uv)
    _require(minimum_uv.x <= 0.001 and minimum_uv.y <= 0.001, "UV minimum")
    _require(maximum_uv.x >= 0.999 and maximum_uv.y >= 0.999, "UV maximum")
    _require(str(label.get_meta("m3_texture_slot", "")) == "snes-front-label", "M3 texture slot")

    for anchor_name in ["DockPivot", "CenterOfMass", "LabelAnchor", "ConnectorAnchor"]:
        _require(asset.find_child(anchor_name, true, false) != null, "anchor %s" % anchor_name)

    var lod0_triangles := 0
    for node_name in ["Shell", "Details", "LabelSurface", "Screws", "Contacts"]:
        var instance := asset.find_child(node_name, true, false) as MeshInstance3D
        lod0_triangles += int(instance.get_meta("triangle_count", 0))
    _require(lod0_triangles >= 1500 and lod0_triangles <= 18000, "LOD0 triangle budget")

    var reduced := LOD1.instantiate()
    root.add_child(reduced)
    await process_frame
    await process_frame
    _require(int(reduced.get_meta("lod", -1)) == 1, "LOD1 metadata")
    _require(reduced.find_child("Screws", true, false) == null, "LOD1 screw reduction")
    _require(reduced.find_child("Contacts", true, false) == null, "LOD1 contact reduction")
    var lod1_triangles := 0
    for node_name in ["Shell", "Details", "LabelSurface"]:
        var instance := reduced.find_child(node_name, true, false) as MeshInstance3D
        _require(instance != null and instance.mesh != null, "LOD1 %s" % node_name)
        lod1_triangles += int(instance.get_meta("triangle_count", 0))
    _require(lod1_triangles > 0 and lod1_triangles < lod0_triangles and lod1_triangles <= 5000, "LOD1 triangle budget")

    print(
        "RETROLIFE_M2_SNES_PROCEDURAL_OK "
        + "lod0_triangles=%d lod1_triangles=%d uv=true pivot=true console=false license=CC0"
        % [lod0_triangles, lod1_triangles]
    )
    quit(0)


func _require(condition: bool, label_name: String) -> void:
    if condition:
        return
    push_error("RETROLIFE_M2_SNES_PROCEDURAL_FAILED: %s" % label_name)
    quit(1)
