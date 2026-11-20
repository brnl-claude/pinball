@tool
class_name Spinner
extends Area3D
## A spinner: a flat plate hanging on a horizontal axle across a lane. The
## ball flips it as it passes and it keeps spinning, scoring once per
## revolution, until axle friction stops it. The plate is light, so the
## ball only loses a little speed.
##
## The lane runs along the spinner's local Z axis; the axle along X.

signal scored(points: int)

@export var width := 0.04
## Plate height below the axle (m).
@export var plate_height := 0.026
## Axle height above the playfield (m).
@export var axle_height := 0.034
## Share of the ball's speed that goes into the plate's edge speed.
@export var spin_transfer := 0.6
## Viscous damping of the spin (1/s) and dry axle friction (rad/s²).
@export var damping := 0.5
@export var friction := 5.0
## Share of the ball's speed along the lane that it loses to the plate.
@export var speed_loss := 0.05
@export var points := 50
@export var plate_color := Color(0.85, 0.85, 0.9)

## Spin rate (rad/s, signed) and plate angle (rad) of the plate.
var spin := 0.0
var angle := 0.0
var revolutions := 0

var _pivot: Node3D
var _plate_material: StandardMaterial3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = Ball.BALL_LAYER
	monitorable = false
	_build()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var ball := body as Ball
	if ball == null:
		return
	var lane := global_basis.z.normalized()
	var along := ball.linear_velocity.dot(lane)
	# The plate's edge takes on part of the ball's speed; a plate already
	# spinning the same way only speeds up.
	var kick := spin_transfer * along / (plate_height * 0.5)
	spin = kick if absf(kick) > absf(spin) or signf(kick) != signf(spin) else spin
	ball.linear_velocity -= lane * along * speed_loss


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or spin == 0.0:
		return
	var slowdown := (damping * absf(spin) + friction) * delta
	spin = 0.0 if slowdown >= absf(spin) else spin - signf(spin) * slowdown
	var before := floori(angle / TAU)
	angle += spin * delta
	var after := floori(angle / TAU)
	if after != before:
		revolutions += 1
		scored.emit(points)
		SoundFx.play("spinner")
		LampFx.flash(self, _plate_material, plate_color, 0.08)
	if spin == 0.0:
		# Hang straight down again.
		angle = roundf(angle / TAU) * TAU
	_pivot.rotation.x = angle


func _build() -> void:
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 0.03, 0.006)
	shape_node.shape = box
	shape_node.position.y = 0.015
	add_child(shape_node)

	_pivot = Node3D.new()
	_pivot.position.y = axle_height
	add_child(_pivot)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(width * 0.9, plate_height, 0.0015)
	_plate_material = TableMaterials.make(TableMaterials.Finish.METAL, plate_color)
	plate_mesh.material = _plate_material
	plate.mesh = plate_mesh
	plate.position.y = -plate_height * 0.5
	_pivot.add_child(plate)

	var axle := MeshInstance3D.new()
	var axle_mesh := CylinderMesh.new()
	axle_mesh.top_radius = 0.0012
	axle_mesh.bottom_radius = 0.0012
	axle_mesh.height = width + 0.01
	axle_mesh.material = TableMaterials.make(TableMaterials.Finish.METAL, Color(0.8, 0.8, 0.82))
	axle.mesh = axle_mesh
	axle.rotation.z = PI * 0.5
	axle.position.y = axle_height
	add_child(axle)
