@tool
class_name DropTarget
extends Wall
## A target that drops below the playfield when hit, until its bank resets.

signal scored(points: int)
signal dropped(target: DropTarget)

@export var points := 100

var is_down := false


func on_ball_hit(_ball: Ball) -> void:
	if is_down:
		return
	is_down = true
	# Changing collision state from inside a physics callback must be deferred.
	_shape_node.set_deferred("disabled", true)
	_mesh_node.visible = false
	scored.emit(points)
	dropped.emit(self)
	SoundFx.play("drop")


func reset() -> void:
	is_down = false
	_shape_node.set_deferred("disabled", false)
	_mesh_node.visible = show_mesh
