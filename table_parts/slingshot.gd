@tool
class_name Slingshot
extends Rail
## The kicking rubber of a slingshot. When the ball touches it, a coil kicks
## the ball away along the rail's normal.

signal scored(points: int)

## Which side of the rail the playfield is on (+1 = left of start → end).
@export_range(-1, 1, 2) var kick_side := 1
## Speed added to the ball along the normal (m/s).
@export var kick_speed := 2.2
## Minimum ball speed that triggers the switch (m/s).
@export var min_hit_speed := 0.1
@export var cooldown := 0.12
@export var points := 10
@export var lamp_color := Color(1.0, 0.85, 0.4)

var _last_kick_ms := -100000


func on_ball_hit(ball: Ball) -> void:
	var now := Time.get_ticks_msec()
	if ball.linear_velocity.length() < min_hit_speed or now - _last_kick_ms < cooldown * 1000.0:
		return
	_last_kick_ms = now
	var n := normal_2d() * kick_side
	var direction := Vector3(n.x, 0.0, n.y)
	# Remove any velocity into the rubber, then add the kick.
	var into := ball.linear_velocity.dot(direction)
	ball.linear_velocity -= direction * minf(into, 0.0)
	ball.linear_velocity += direction * kick_speed
	scored.emit(points)
	SoundFx.play("slingshot")
	LampFx.flash(self, surface_material, lamp_color)
