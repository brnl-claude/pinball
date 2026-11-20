extends Camera3D
## Simple camera that looks at a point on the table.
##
## Cameras are deliberately decoupled from game logic: the layout profiles
## (9:16, 16:9, 32:9) and possibly a VR rig will live here later.

@export var look_target := Vector3.ZERO


func _ready() -> void:
	look_at(look_target, Vector3.UP)
