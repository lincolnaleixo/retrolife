extends SceneTree

const SCENE := preload("res://scenes/SnesNaCartridgeFrontM2_2.tscn")
const EXPECTED_ASSET := "retrolife.snes.na-cartridge.m2.2.front.v4"

func _initialize() -> void:
    var instance := SCENE.instantiate()
    root.add_child(instance)
    await process_frame
    var failures: Array[String] = []
    _require(instance.get_meta("asset_id", "") == EXPECTED_ASSET, "asset id", failures)
    _require(instance.get_meta("source", "") == "original-cadquery-opencascade-brep-rebuild", "source", failures)
    _require(instance.get_meta("step_exported", false), "STEP export", failures)
    _require(not instance.get_meta("height_field_only", true), "height field rejected", failures)
    _require(not instance.get_meta("multi_section_loft_only", true), "loft-only rejected", failures)
    _require(not instance.get_meta("external_geometry_copied", true), "external geometry boundary", failures)
    _require(not instance.get_meta("external_media_embedded", true), "external media boundary", failures)
    _require(not instance.get_meta("physical_calibration_complete", true), "calibration honesty", failures)
    _require(not instance.get_meta("may_approve_final_geometry", true), "approval gate", failures)
    _require(not instance.get_meta("may_start_m2_3_blockout", true), "M2.3 gate", failures)
    _require(not instance.get_meta("may_start_m3", true), "M3 gate", failures)
    var shell := instance.get_node_or_null("VisualRoot/CadShell") as MeshInstance3D
    var label := instance.get_node_or_null("VisualRoot/LabelSurface") as MeshInstance3D
    _require(shell != null and shell.mesh != null, "CAD shell mesh", failures)
    _require(label != null and label.mesh != null, "label mesh", failures)
    for marker_name in ["DockPivot", "CenterOfMass", "LabelAnchor", "ConnectorAnchor", "BrowseFocusedAnchor", "DockApproachAnchor"]:
        _require(instance.get_node_or_null(marker_name) != null, marker_name, failures)
    if failures.is_empty():
        print("RETROLIFE_M2_2_FRONT_GODOT_OK asset=v4 cad=opencascade step=true")
        quit(0)
        return
    for failure in failures:
        push_error("RETROLIFE_M2_2_FRONT_GODOT_FAILED: " + failure)
    quit(1)

func _require(condition: bool, label: String, failures: Array[String]) -> void:
    if not condition:
        failures.append(label)
