@tool
class_name Ramp
extends StaticBody3D
## A plastic ramp: a floor with a wall on each side, swept along a smooth
## path. `points` is the track of the ball's lowest point (the top of the
## floor) through the ramp, in local coordinates; start the first point a
## millimetre below the playfield so the ball rolls on without a bump.
##
## Collision is one triangle mesh (floor and inner walls) that collides from
## both sides, so balls can also pass under or beside the ramp.

@export var points := PackedVector3Array():
	set(value):
		points = value
		_rebuild()
## Inner width between the walls (m). A ball is 27 mm wide.
@export var width := 0.04:
	set(value):
		width = value
		_rebuild()
## Wall height above the floor (m). In tight turns the ball's spin rubs it
## up the outer wall; walls that reach to within a ball radius of the glass
## keep it in.
@export var wall_height := 0.022:
	set(value):
		wall_height = value
		_rebuild()
## Width of the rolled lip along the top of each wall, pointing inward (m).
## With the gap between the lips narrower than the ball, a ball whose spin
## rubs it up the wall in a turn cannot jump out. 0 leaves the top open.
@export var lip := 0.008:
	set(value):
		lip = value
		_rebuild()
## Thickness of the plastic, for the visible mesh only (m).
@export var thickness := 0.003:
	set(value):
		thickness = value
		_rebuild()
@export var color := Color(0.75, 0.85, 1.0, 0.45):
	set(value):
		color = value
		_rebuild()
@export_range(0.0, 1.0) var friction := 0.2:
	set(value):
		friction = value
		_rebuild()
@export_range(0.0, 1.0) var bounce := 0.2:
	set(value):
		bounce = value
		_rebuild()
## Where the floor is lower than this above the playfield (m), the sides are
## closed down to the playfield, with a back wall where they end, so no ball
## gets wedged under the ramp. The default closes the whole underside; 0
## leaves it open.
@export var skirt_height := 1.0:
	set(value):
		skirt_height = value
		_rebuild()
## Sample spacing along the path (m); smaller is smoother.
@export var step := 0.005:
	set(value):
		step = maxf(value, 0.001)
		_rebuild()

var _shape_node: CollisionShape3D
var _mesh_node: MeshInstance3D


func _ready() -> void:
	_rebuild()


## The sampled path (ball bottom) through the ramp, in local coordinates.
func path() -> PackedVector3Array:
	return RampPath.sample(points, step)


func _rebuild() -> void:
	if not is_inside_tree() or points.size() < 2:
		return
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		add_child(_shape_node)
		_mesh_node = MeshInstance3D.new()
		add_child(_mesh_node)

	var samples := path()
	var basis_list := RampPath.frames(samples)
	var half := width * 0.5

	var faces := PackedVector3Array()
	faces.append_array(RampPath.ribbon_faces(samples, basis_list, Vector2(-half, 0.0), Vector2(half, 0.0)))
	faces.append_array(RampPath.ribbon_faces(samples, basis_list, Vector2(-half, 0.0), Vector2(-half, wall_height)))
	faces.append_array(RampPath.ribbon_faces(samples, basis_list, Vector2(half, 0.0), Vector2(half, wall_height)))
	if lip > 0.0:
		faces.append_array(RampPath.ribbon_faces(samples, basis_list, Vector2(-half, wall_height),
				Vector2(-half + lip, wall_height)))
		faces.append_array(RampPath.ribbon_faces(samples, basis_list, Vector2(half, wall_height),
				Vector2(half - lip, wall_height)))
	var skirts := _skirt_faces(samples, basis_list)
	faces.append_array(skirts)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	_shape_node.shape = shape

	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = bounce
	physics_material_override = material

	# A U-shaped slab of plastic.
	var outer := half + thickness
	var inner := half - maxf(lip, 0.0)
	var top := wall_height + (thickness if lip > 0.0 else 0.0)
	var profile := PackedVector2Array([
		Vector2(-half, wall_height), Vector2(-half, 0.0), Vector2(half, 0.0), Vector2(half, wall_height),
		Vector2(outer, top), Vector2(outer, -thickness), Vector2(-outer, -thickness), Vector2(-outer, top),
	])
	if lip > 0.0:
		profile = PackedVector2Array([
			Vector2(-inner, wall_height), Vector2(-half, wall_height), Vector2(-half, 0.0),
			Vector2(half, 0.0), Vector2(half, wall_height), Vector2(inner, wall_height),
			Vector2(inner, top), Vector2(outer, top), Vector2(outer, -thickness),
			Vector2(-outer, -thickness), Vector2(-outer, top), Vector2(-inner, top),
		])
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	RampPath.extrude(tool, samples, basis_list, profile, true, false)
	for i in range(0, skirts.size(), 3):
		var normal := (skirts[i + 1] - skirts[i]).cross(skirts[i + 2] - skirts[i]).normalized()
		RampPath._triangle(tool, [skirts[i], skirts[i + 1], skirts[i + 2]], [normal, normal, normal])
		RampPath._triangle(tool, [skirts[i], skirts[i + 1], skirts[i + 2]], [-normal, -normal, -normal])
	var mesh := tool.commit()
	mesh.surface_set_material(0, TableMaterials.make(TableMaterials.Finish.CLEAR_PLASTIC, color))
	_mesh_node.mesh = mesh


## Vertical side walls from the floor edges down to the playfield (local
## y = 0) where the floor is low, and a back wall across where they end.
func _skirt_faces(samples: PackedVector3Array, basis_list: Array[Basis]) -> PackedVector3Array:
	var faces := PackedVector3Array()
	if skirt_height <= 0.0:
		return faces
	var half := width * 0.5
	var last := -1
	for i in samples.size() - 1:
		if samples[i].y >= skirt_height or samples[i + 1].y >= skirt_height:
			break
		last = i + 1
		for side: float in [-half, half]:
			var a := samples[i] + basis_list[i].x * side
			var b := samples[i + 1] + basis_list[i + 1].x * side
			var a0 := Vector3(a.x, 0.0, a.z)
			var b0 := Vector3(b.x, 0.0, b.z)
			for vertex: Vector3 in [a, b, b0, a, b0, a0]:
				faces.append(vertex)
	if last > 0:
		var left := samples[last] - basis_list[last].x * half
		var right := samples[last] + basis_list[last].x * half
		var left0 := Vector3(left.x, 0.0, left.z)
		var right0 := Vector3(right.x, 0.0, right.z)
		for vertex: Vector3 in [left, right, right0, left, right0, left0]:
			faces.append(vertex)
	return faces
