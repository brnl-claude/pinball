@tool
class_name Saucer
extends Node3D
## A saucer (kicker hole): a shallow cup in the playfield. A ball that rolls
## in slowly enough settles in the cup; after `hold_seconds` a kicker throws
## it out along `eject_direction`. A fast ball rolls over the cup.
##
## Rules can keep the ball (`auto_eject = false`, e.g. for a ball lock) and
## let it go later with `eject()`. Timers count physics ticks.

signal scored(points: int)
signal ball_captured(ball: Ball)
signal ball_ejected(ball: Ball)

## Ball centres within this horizontal distance can fall into the cup (m).
@export var capture_radius := 0.014
## Balls faster than this roll over the cup (m/s).
@export var capture_speed := 1.3
@export var hold_seconds := 1.0
@export var auto_eject := true
## Direction of the kick in the saucer's local XZ plane.
@export var eject_direction := Vector3(-1.0, 0.0, 0.3)
@export var eject_speed := 1.6
## How deep the ball sits in the cup (m).
@export var cup_depth := 0.004
@export var points := 500
@export var lamp_color := Color(0.3, 1.0, 0.5)

## The ball in the cup, if any.
var held: Ball
var captures := 0

var _hold_left := 0.0
var _ignore: Ball
var _ignore_left := 0.0
var _insert_material: StandardMaterial3D


func _ready() -> void:
	_build()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_ignore_left = maxf(_ignore_left - delta, 0.0)
	if held:
		_keep_holding(delta)
		return
	for node in get_tree().get_nodes_in_group("balls"):
		var ball := node as Ball
		if ball and _can_capture(ball):
			_capture(ball)
			return


func _can_capture(ball: Ball) -> bool:
	if ball.freeze or (ball == _ignore and _ignore_left > 0.0):
		return false
	var offset := ball.global_position - global_position
	var radius := ball.tuning.scaled_ball_radius() if ball.tuning else 0.0135
	return Vector2(offset.x, offset.z).length() < capture_radius \
			and offset.y < radius + 0.003 and ball.speed() < capture_speed


func _capture(ball: Ball) -> void:
	held = ball
	captures += 1
	_hold_left = hold_seconds
	ball.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	ball.freeze = true
	ball.global_position = _rest_position(ball)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	LampFx.set_lit(_insert_material, lamp_color, true)
	scored.emit(points)
	ball_captured.emit(ball)
	SoundFx.play("saucer")


func _keep_holding(delta: float) -> void:
	# Someone else moved the ball (served again, replay): let go.
	if not is_instance_valid(held) or not held.freeze \
			or held.global_position.distance_to(_rest_position(held)) > 0.005:
		_release(held)
		return
	if auto_eject:
		_hold_left -= delta
		if _hold_left <= 0.0:
			eject()


## Kicks the held ball out of the cup.
func eject() -> void:
	if held == null:
		return
	var ball := held
	_release(ball)
	var direction := (global_basis * eject_direction).normalized()
	direction.y = 0.0
	ball.linear_velocity = direction.normalized() * eject_speed
	ball.angular_velocity = Vector3.ZERO
	ball_ejected.emit(ball)
	SoundFx.play("kicker")


## Lets go of the held ball without kicking it, e.g. to lock it, and
## returns it.
func take_ball() -> Ball:
	var ball := held
	if ball:
		_release(ball)
	return ball


func _release(ball: Ball) -> void:
	held = null
	LampFx.set_lit(_insert_material, lamp_color, false)
	if is_instance_valid(ball):
		ball.freeze = false
		_ignore = ball
		_ignore_left = 0.3


func _rest_position(ball: Ball) -> Vector3:
	var radius := ball.tuning.scaled_ball_radius() if ball.tuning else 0.0135
	return global_position + Vector3(0.0, radius - cup_depth, 0.0)


func _build() -> void:
	var cup := MeshInstance3D.new()
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = 0.019
	cup_mesh.bottom_radius = 0.012
	cup_mesh.height = 0.0012
	cup_mesh.material = TableMaterials.make(TableMaterials.Finish.METAL, Color(0.25, 0.25, 0.27))
	cup.mesh = cup_mesh
	cup.position.y = 0.0006
	add_child(cup)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.019
	ring_mesh.outer_radius = 0.022
	ring_mesh.material = TableMaterials.make(TableMaterials.Finish.METAL, Color(0.85, 0.85, 0.88))
	ring.mesh = ring_mesh
	ring.scale = Vector3(1.0, 0.3, 1.0)
	add_child(ring)

	var insert := MeshInstance3D.new()
	var insert_mesh := CylinderMesh.new()
	insert_mesh.top_radius = 0.008
	insert_mesh.bottom_radius = 0.008
	insert_mesh.height = 0.001
	_insert_material = TableMaterials.make(TableMaterials.Finish.PLASTIC, lamp_color.darkened(0.6))
	insert_mesh.material = _insert_material
	insert.mesh = insert_mesh
	insert.position = Vector3(0.0, 0.0006, 0.035)
	add_child(insert)
