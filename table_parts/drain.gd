@tool
class_name Drain
extends Area3D
## Detects balls that leave play (below the flippers).

signal ball_drained(ball: Ball)

@export var size := Vector3(0.45, 0.05, 0.06):
	set(value):
		size = value
		_rebuild()

var _shape_node: CollisionShape3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = Ball.BALL_LAYER
	monitorable = false
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Ball:
		ball_drained.emit(body)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		add_child(_shape_node)
	var box := BoxShape3D.new()
	box.size = size
	_shape_node.shape = box
