@tool
class_name StandupTarget
extends Wall
## A fixed target. Hitting it scores and lights its insert.

signal scored(points: int)
signal target_hit(target: StandupTarget)

@export var points := 50
@export var lamp_color := Color(0.3, 0.9, 1.0)

var lit := false


func on_ball_hit(_ball: Ball) -> void:
	lit = true
	LampFx.set_lit(surface_material, lamp_color, true)
	scored.emit(points)
	target_hit.emit(self)
	SoundFx.play("target")


func reset() -> void:
	lit = false
	LampFx.set_lit(surface_material, lamp_color, false)
