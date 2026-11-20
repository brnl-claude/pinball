@tool
class_name Wall
extends StaticBody3D
## A box-shaped static table part (playfield, walls, guides, glass).
## Builds its collision shape and mesh from `size`, also in the editor.

@export var size := Vector3(0.1, 0.05, 0.02):
	set(value):
		size = value
		_rebuild()
@export var show_mesh := true:
	set(value):
		show_mesh = value
		_rebuild()
@export var color := Color(0.55, 0.55, 0.6):
	set(value):
		color = value
		_rebuild()
@export_range(0.0, 1.0) var friction := 0.3:
	set(value):
		friction = value
		_rebuild()
@export_range(0.0, 1.0) var bounce := 0.4:
	set(value):
		bounce = value
		_rebuild()

var _shape_node: CollisionShape3D
var _mesh_node: MeshInstance3D


func _ready() -> void:
	_rebuild()


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
	# Keep the convex radius tiny: the default (4 cm) would round off thin
	# walls and make the 13.5 mm ball bounce off invisible corners.
	box.margin = minf(0.001, size[size.min_axis_index()] * 0.1)
	_shape_node.shape = box

	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = bounce
	physics_material_override = material

	_mesh_node.visible = show_mesh
	var mesh := BoxMesh.new()
	mesh.size = size
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.roughness = 0.6
	mesh.material = surface
	_mesh_node.mesh = mesh
