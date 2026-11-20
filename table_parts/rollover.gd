@tool
class_name Rollover
extends Area3D
## A rollover switch in a lane. Rolling over it scores and lights its insert.

signal scored(points: int)
signal rolled_over(rollover: Rollover)

@export var points := 25
@export var lamp_color := Color(1.0, 0.6, 0.2)

var lit := false

var _insert_material: StandardMaterial3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = Ball.BALL_LAYER
	monitorable = false
	_build()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Ball:
		lit = true
		LampFx.set_lit(_insert_material, lamp_color, true)
		scored.emit(points)
		rolled_over.emit(self)
		SoundFx.play("rollover")


func reset() -> void:
	lit = false
	LampFx.set_lit(_insert_material, lamp_color, false)


func _build() -> void:
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.012, 0.01, 0.02)
	shape_node.shape = box
	shape_node.position.y = 0.005
	add_child(shape_node)

	var insert := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.009
	mesh.bottom_radius = 0.009
	mesh.height = 0.001
	_insert_material = TableMaterials.make(TableMaterials.Finish.PLASTIC, lamp_color.darkened(0.6))
	mesh.material = _insert_material
	insert.mesh = mesh
	insert.position.y = 0.0006
	add_child(insert)
