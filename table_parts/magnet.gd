@tool
class_name Magnet
extends Node3D
## A playfield magnet under an insert. While active it pulls balls within
## `radius` to its centre and holds them there (a spring with damping, so a
## fast ball is caught instead of swinging through). When it switches off it
## lets go with `release_velocity`, given in the magnet's local frame.
##
## Used as a magna-save in the left outlane: the player catches the ball and
## it is thrown back up the lane, with a chance to come down the inlane.

signal activated
signal released

@export var radius := 0.04
## Pull toward the centre per metre of distance (1/s²) and velocity damping
## (1/s). About critically damped.
@export var stiffness := 1500.0
@export var damping := 70.0
@export var max_hold_seconds := 1.5
@export var release_velocity := Vector3(0.25, 0.0, -0.9)
@export var lamp_color := Color(0.3, 0.6, 1.0)

var active := false
var _time_left := 0.0
var _insert_material: StandardMaterial3D


func _ready() -> void:
	_build()


## Switches the magnet on for `seconds` (at most `max_hold_seconds`).
func activate(seconds := -1.0) -> void:
	_time_left = max_hold_seconds if seconds < 0.0 else minf(seconds, max_hold_seconds)
	if not active:
		active = true
		LampFx.set_lit(_insert_material, lamp_color, true)
		activated.emit()
		SoundFx.play("kicker")


func release() -> void:
	if not active:
		return
	active = false
	_time_left = 0.0
	LampFx.set_lit(_insert_material, lamp_color, false)
	var throw := global_basis * release_velocity
	for ball in _balls_in_reach(radius * 0.5):
		ball.linear_velocity = throw
		ball.angular_velocity = Vector3.ZERO
	released.emit()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not active:
		return
	for ball in _balls_in_reach(radius):
		var offset := global_position - ball.global_position
		offset.y = 0.0
		var velocity := ball.linear_velocity
		velocity.y = 0.0
		ball.apply_central_force(ball.mass * (offset * stiffness - velocity * damping))
	_time_left -= delta
	if _time_left <= 0.0:
		release()


func _balls_in_reach(reach: float) -> Array[Ball]:
	var result: Array[Ball] = []
	for node in get_tree().get_nodes_in_group("balls"):
		var ball := node as Ball
		if ball == null or ball.freeze:
			continue
		var offset := ball.global_position - global_position
		if Vector2(offset.x, offset.z).length() < reach and offset.y < 0.03:
			result.append(ball)
	return result


func _build() -> void:
	var insert := MeshInstance3D.new()
	var insert_mesh := CylinderMesh.new()
	insert_mesh.top_radius = 0.011
	insert_mesh.bottom_radius = 0.011
	insert_mesh.height = 0.001
	_insert_material = TableMaterials.make(TableMaterials.Finish.PLASTIC, lamp_color.darkened(0.6))
	insert_mesh.material = _insert_material
	insert.mesh = insert_mesh
	insert.position.y = 0.0004
	add_child(insert)
