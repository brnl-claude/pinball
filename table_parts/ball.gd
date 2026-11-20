class_name Ball
extends RigidBody3D
## A steel pinball. Builds its own collision shape and mesh from a
## PhysicsTuning resource.
##
## Gravity is applied as a constant force (gravity_scale = 0), so the table
## slope lives in the tuning and nudging can later add to it per ball.

const TABLE_LAYER := 1
const BALL_LAYER := 2

@export var tuning: PhysicsTuning

var _shape_node: CollisionShape3D
var _mesh_node: MeshInstance3D


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
	body_entered.connect(_on_body_entered)


## Tells a table part that the ball hit it. Parts opt in by implementing
## `on_ball_hit(ball: Ball)`.
func _on_body_entered(body: Node) -> void:
	if body.has_method("on_ball_hit"):
		body.call("on_ball_hit", self)


func apply_tuning() -> void:
	mass = tuning.ball_mass
	gravity_scale = 0.0
	constant_force = mass * tuning.gravity_vector()

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
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.85, 0.85, 0.88)
	chrome.metallic = 1.0
	chrome.roughness = 0.08
	mesh.material = chrome
	_mesh_node.mesh = mesh


func speed() -> float:
	return linear_velocity.length()


## Teleports the ball to a transform and stops it.
func reset_to(target: Transform3D) -> void:
	global_transform = target
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
