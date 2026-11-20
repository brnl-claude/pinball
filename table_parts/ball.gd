class_name Ball
extends RigidBody3D
## A steel pinball. Builds its own collision shape and mesh from a
## PhysicsTuning resource.
##
## Gravity is applied as a constant force (gravity_scale = 0), so the table
## slope lives in the tuning, and the cabinet's acceleration during a nudge
## adds to it (see `set_frame_acceleration`).

const TABLE_LAYER := 1
const BALL_LAYER := 2
## How far (m) a contact point may be from the ball's surface and still count
## as a real touch. Jolt also reports speculative contacts up to 2 cm away,
## which must not trigger switches (e.g. through the shooter lane wall).
const TOUCH_TOLERANCE := 0.001

@export var tuning: PhysicsTuning

var _shape_node: CollisionShape3D
var _mesh_node: MeshInstance3D
## Instance ids of parts the ball is touching right now.
var _touching := {}
## Parts touched for the first time in the last physics step.
var _new_hits: Array[Object] = []
## Acceleration of the playfield (the physics frame), e.g. during a nudge.
var _frame_acceleration := Vector3.ZERO


func _init() -> void:
	can_sleep = false
	continuous_cd = true
	collision_layer = BALL_LAYER
	collision_mask = TABLE_LAYER | BALL_LAYER
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	# Report contacts so table parts (slingshots, bumpers, targets) can react.
	contact_monitor = true
	max_contacts_reported = 4


func _ready() -> void:
	if tuning == null:
		tuning = PhysicsTuning.new()
	apply_tuning()
	add_to_group("balls")


## Finds parts that the ball really touches (not just speculative contacts)
## and remembers the ones it starts touching in this step.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var radius := tuning.scaled_ball_radius() if tuning else 0.0135
	var center := state.transform.origin
	var touching_now := {}
	for i in state.get_contact_count():
		var collider := state.get_contact_collider_object(i)
		if collider == null or not collider.has_method("on_ball_hit"):
			continue
		var point := state.get_contact_collider_position(i)
		if point.distance_to(center) > radius + TOUCH_TOLERANCE:
			continue
		var id := collider.get_instance_id()
		touching_now[id] = true
		if not _touching.has(id):
			_new_hits.append(collider)
	_touching = touching_now


## Tells table parts that the ball hit them. Parts opt in by implementing
## `on_ball_hit(ball: Ball)`. Runs at the start of the next physics tick, so
## parts can safely change the ball's velocity.
func _physics_process(_delta: float) -> void:
	if _new_hits.is_empty():
		return
	var hits := _new_hits
	_new_hits = []
	for part in hits:
		if is_instance_valid(part):
			part.call("on_ball_hit", self)


func apply_tuning() -> void:
	mass = tuning.ball_mass
	gravity_scale = 0.0
	_update_constant_force()

	var material := PhysicsMaterial.new()
	material.friction = tuning.ball_friction
	material.bounce = tuning.ball_bounce
	physics_material_override = material

	var radius := tuning.scaled_ball_radius()
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		add_child(_shape_node)
		_mesh_node = MeshInstance3D.new()
		add_child(_mesh_node)

	var shape := SphereShape3D.new()
	shape.radius = radius
	_shape_node.shape = shape

	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	mesh.material = TableMaterials.chrome()
	_mesh_node.mesh = mesh


## The playfield accelerates (a nudge); the ball feels the inertial force
## -m·a on top of gravity.
func set_frame_acceleration(value: Vector3) -> void:
	if value == _frame_acceleration:
		return
	_frame_acceleration = value
	_update_constant_force()


func _update_constant_force() -> void:
	constant_force = mass * (tuning.gravity_vector() - _frame_acceleration)


func speed() -> float:
	return linear_velocity.length()


## Teleports the ball to a transform and stops it.
func reset_to(target: Transform3D) -> void:
	_touching.clear()
	_new_hits.clear()
	global_transform = target
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
