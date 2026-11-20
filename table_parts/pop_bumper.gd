@tool
class_name PopBumper
extends StaticBody3D
## A pop bumper: when the ball touches the skirt, the ring pulls down and
## kicks the ball radially away.

signal scored(points: int)

@export var radius := 0.025:
	set(value):
		radius = value
		_rebuild()
@export var cap_radius := 0.036
@export var kick_speed := 2.0
@export var cooldown := 0.06
@export var points := 100
@export var cap_color := Color(0.9, 0.15, 0.2)

var _cap_material: StandardMaterial3D
var _shape_node: CollisionShape3D
var _body_mesh: MeshInstance3D
var _cap_mesh: MeshInstance3D
var _last_kick_ms := -100000
## False while the machine is tilted: the coil stays dead.
var enabled := true


func _ready() -> void:
	_rebuild()


func on_ball_hit(ball: Ball) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_kick_ms < cooldown * 1000.0:
		return
	_last_kick_ms = now
	var away := ball.global_position - global_position
	away.y = 0.0
	if away.length() < 0.0001:
		away = Vector3.BACK
	var direction := away.normalized()
	var outward := ball.linear_velocity.dot(direction)
	ball.linear_velocity += direction * (kick_speed - minf(outward, 0.0))
	scored.emit(points)
	SoundFx.play("bumper")
	LampFx.flash(self, _cap_material, cap_color.lightened(0.3))


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		add_child(_shape_node)
		_body_mesh = MeshInstance3D.new()
		add_child(_body_mesh)
		_cap_mesh = MeshInstance3D.new()
		add_child(_cap_mesh)

	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.04
	shape.margin = 0.001
	_shape_node.shape = shape
	_shape_node.position.y = 0.02

	var material := PhysicsMaterial.new()
	material.bounce = 0.3
	physics_material_override = material

	var body := CylinderMesh.new()
	body.top_radius = radius
	body.bottom_radius = radius
	body.height = 0.04
	var body_material := TableMaterials.make(TableMaterials.Finish.PLASTIC, Color(0.92, 0.92, 0.95))
	body.material = body_material
	_body_mesh.mesh = body
	_body_mesh.position.y = 0.02

	var cap := CylinderMesh.new()
	cap.top_radius = cap_radius * 0.85
	cap.bottom_radius = cap_radius
	cap.height = 0.012
	_cap_material = TableMaterials.make(TableMaterials.Finish.PLASTIC, cap_color)
	cap.material = _cap_material
	_cap_mesh.mesh = cap
	_cap_mesh.position.y = 0.046
