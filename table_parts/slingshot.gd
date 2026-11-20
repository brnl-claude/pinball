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
## Minimum ball speed into the rubber face that triggers the switch (m/s);
## a ball grazing along the face does not.
@export var min_hit_speed := 0.15
## Only the middle part of the rubber, this share of its length, deflects
## enough to close the switch. Hits near the corner posts just bounce.
@export_range(0.1, 1.0) var active_fraction := 0.6
@export var cooldown := 0.12
@export var points := 10
@export var lamp_color := Color(1.0, 0.85, 0.4)

var _last_kick_ms := -100000
## False while the machine is tilted: the coil stays dead.
var enabled := true


func on_ball_hit(ball: Ball) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_kick_ms < cooldown * 1000.0 or not is_face_hit(ball):
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


## True when the ball hit the rubber face from the playfield side, in the
## middle part of the rubber, moving into it (or bouncing off it) fast
## enough. Contact with the ends or a grazing touch is not a hit.
func is_face_hit(ball: Ball) -> bool:
	var parent := get_parent_node_3d()
	var local := parent.to_local(ball.global_position) if parent else ball.global_position
	var p := Vector2(local.x, local.z)
	var along := end - start
	var length := along.length()
	if length < 0.001:
		return false
	var t := (p - start).dot(along) / (length * length)
	if absf(t - 0.5) > active_fraction * 0.5:
		return false
	var n := normal_2d() * kick_side
	if (p - start).dot(n) <= 0.0:
		return false
	var velocity := ball.linear_velocity
	if parent:
		velocity = parent.global_basis.inverse() * velocity
	# The contact is reported a tick late, so the ball may already be
	# bouncing away: count speed along the normal either way.
	return absf(Vector2(velocity.x, velocity.z).dot(n)) >= min_hit_speed
