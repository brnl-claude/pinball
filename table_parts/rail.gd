@tool
class_name Rail
extends Wall
## A wall defined by two endpoints on the playfield (table XZ coordinates),
## which is how table layouts are usually drawn.

@export var start := Vector2.ZERO:
	set(value):
		start = value
		_update_from_points()
@export var end := Vector2(0.1, 0.0):
	set(value):
		end = value
		_update_from_points()
@export var thickness := 0.005:
	set(value):
		thickness = value
		_update_from_points()
@export var rail_height := 0.04:
	set(value):
		rail_height = value
		_update_from_points()


func _ready() -> void:
	_update_from_points()
	super._ready()


func _update_from_points() -> void:
	var delta := end - start
	var length := maxf(delta.length(), 0.001)
	var mid := (start + end) * 0.5
	position = Vector3(mid.x, rail_height * 0.5, mid.y)
	# Local +X must point from start to end: (cos θ, 0, −sin θ) = (dx, 0, dz).
	rotation = Vector3(0.0, atan2(-delta.y, delta.x), 0.0)
	size = Vector3(length, rail_height, thickness)


## Unit normal of the rail in table XZ, on the left of start → end when
## looking down at the playfield.
func normal_2d() -> Vector2:
	var delta := (end - start).normalized()
	return Vector2(delta.y, -delta.x)
