@tool
class_name Plunger
extends AnimatableBody3D
## Spring-loaded plunger in the shooter lane.
##
## While the action is held the rod retracts toward the player (+Z). On
## release it springs forward with a speed proportional to how far it was
## pulled (spring energy ∝ x², so speed ∝ x) and pushes the ball up the lane.
## Analog input (a gamepad stick) can drive `pull_target` directly later.

@export var input_action := &"plunger"
@export var size := Vector3(0.03, 0.02, 0.02):
	set(value):
		size = value
		_rebuild()
## Maximum retraction in meters.
@export var max_pull := 0.05
## Retraction speed while held (m/s).
@export var pull_speed := 0.12
## Forward speed at full pull (m/s).
@export var max_release_speed := 4.0

## When false, `pulled` is driven by code (tests).
var use_input := true
var pulled := false
## When false the rod cannot be pulled (attract mode, game over).
var enabled := true
## Current retraction in meters.
var pull := 0.0
var release_speed := 0.0

var _rest_position := Vector3.ZERO
var _shape_node: CollisionShape3D
var _mesh_node: MeshInstance3D


func _ready() -> void:
	_rest_position = position
	_rebuild()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if use_input:
		pulled = Input.is_action_pressed(input_action)
	step(delta)


## Puts the rod at a retraction directly (replay playback).
func set_pull(value: float) -> void:
	pull = clampf(value, 0.0, max_pull)
	position = _rest_position + Vector3(0.0, 0.0, pull)


func step(delta: float) -> void:
	if not enabled:
		pulled = false
	if pulled:
		release_speed = 0.0
		pull = minf(pull + pull_speed * delta, max_pull)
	elif pull > 0.0:
		if release_speed == 0.0:
			release_speed = max_release_speed * pull / max_pull
			SoundFx.play("plunger")
		pull = maxf(pull - release_speed * delta, 0.0)
		if pull == 0.0:
			release_speed = 0.0
	position = _rest_position + Vector3(0.0, 0.0, pull)


## Where a ball of the given radius rests against the plunger tip.
func ball_rest_position(ball_radius: float) -> Vector3:
	var tip := global_position - global_transform.basis.z * (size.z * 0.5 + ball_radius + 0.001)
	return Vector3(tip.x, ball_radius, tip.z)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		add_child(_shape_node)
		_mesh_node = MeshInstance3D.new()
		add_child(_mesh_node)
	var box := BoxShape3D.new()
	box.size = size
	box.margin = 0.001
	_shape_node.shape = box
	var mesh := BoxMesh.new()
	mesh.size = size
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color(0.75, 0.75, 0.78)
	surface.metallic = 1.0
	surface.roughness = 0.25
	mesh.material = surface
	_mesh_node.mesh = mesh
