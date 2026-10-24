extends Node3D

## One external closed box, retained only while its game is selected.
## Reuse the inspection viewer's validated GLB loading and texture treatment.
const ModelView = preload("res://scripts/workspace/model_view.gd")
const MAXIMUM_EXTENT := Vector2(2.9, 2.6)

var source_path := ""
var _model: Node3D
var _pivot: Node3D
var _bounds := AABB()


func _ready() -> void:
    _pivot = Node3D.new()
    _pivot.name = "BoxInspectionPivot"
    add_child(_pivot)
    hide()


func load_model(path: String) -> bool:
    if path == source_path:
        return _model != null
    clear()
    source_path = path
    if path.is_empty():
        return false
    # The existing viewer owns all GLB validation, embedded-resource checks,
    # UV correction, transmission conversion and mipmap generation. Borrow
    # its model, then dispose of its unused preview stage immediately.
    var loader := ModelView.new()
    loader.hide()
    add_child(loader)
    var loaded: bool = loader.load_model(path)
    if loaded:
        _model = loader.model
        var bounds: AABB = loader._mesh_bounds(_model)
        _model.get_parent().remove_child(_model)
        loader.model = null
        _pivot.add_child(_model)
        var factor := minf(MAXIMUM_EXTENT.x / maxf(bounds.size.x, 0.001), MAXIMUM_EXTENT.y / maxf(bounds.size.y, 0.001))
        _model.scale *= factor
        _model.position = (_model.position - bounds.get_center()) * factor
        _bounds = AABB(-bounds.size * factor * 0.5, bounds.size * factor)
    loader.free()
    visible = loaded
    return loaded


func clear() -> void:
    if is_instance_valid(_model):
        _model.free()
    _model = null
    _bounds = AABB()
    source_path = ""
    hide()


func set_inspection(yaw: float, pitch: float, zoom: float, float_offset: float) -> void:
    _pivot.rotation = Vector3(pitch, yaw, 0)
    _pivot.scale = Vector3.ONE * zoom
    _pivot.position.y = float_offset


func world_bounds() -> AABB:
    return _pivot.global_transform * _bounds
