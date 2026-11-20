@tool
class_name Drain
extends Area3D
## Detects balls that leave play (below the flippers).
##
## A drained ball can bounce around inside the drain area and re-enter it,
## so each ball is reported once until it is re-armed (served again).

signal ball_drained(ball: Ball)

@export var size := Vector3(0.45, 0.05, 0.06):
	set(value):
		size = value
		_rebuild()

var _shape_node: CollisionShape3D
var _drained_balls := {}


func _ready() -> void:
	collision_layer = 0
	collision_mask = Ball.BALL_LAYER
	monitorable = false
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Ball and not _drained_balls.has(body):
		_drained_balls[body] = true
		ball_drained.emit(body)


## Allows a ball to drain again, e.g. after it was served back into play.
func rearm(ball: Ball) -> void:
	_drained_balls.erase(ball)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		add_child(_shape_node)
	var box := BoxShape3D.new()
	box.size = size
	_shape_node.shape = box
