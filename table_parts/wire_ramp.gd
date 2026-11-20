@tool
class_name WireRamp
extends StaticBody3D
## A wire ramp (habitrail): the ball rolls on two steel wires, with a guard
## wire on each side. `points` is the track of the ball's lowest point, in
## local coordinates, as for `Ramp`. The ball rolls off the wire ends and
## drops onto the playfield; keep the wires above ball height (27 mm) where
## a ball on the playfield can get under them, or it gets wedged.
##
## Each wire is a chain of capsules. Their rounded ends overlap at every
## joint, so the ball rolls over the joints without bumps.

@export var points := PackedVector3Array():
	set(value):
		points = value
		_rebuild()
## Radius of the steel wire (m); 3/16" wire is about 4.8 mm thick.
@export var wire_radius := 0.0024:
	set(value):
		wire_radius = value
		_rebuild()
## The ball the wires are spaced for (m).
@export var ball_radius := 0.0135:
	set(value):
		ball_radius = value
		_rebuild()
## Gap between the ball and each guard wire (m).
@export var guard_clearance := 0.002:
	set(value):
		guard_clearance = value
		_rebuild()
## Height of the guard wires above the ball's centre (m).
@export var guard_height := 0.004:
	set(value):
		guard_height = value
		_rebuild()
## At the entrance the guard wires start this much wider (m) and close in
## over `flare_length`, so a ball riding a ramp wall into the wire ramp is
## funnelled in instead of hitting the guard wire's end head-on.
@export var entry_flare := 0.008:
	set(value):
		entry_flare = value
		_rebuild()
@export var flare_length := 0.05:
	set(value):
		flare_length = value
		_rebuild()
@export var guards := true:
	set(value):
		guards = value
		_rebuild()
@export var color := Color(0.85, 0.85, 0.88):
	set(value):
		color = value
		_rebuild()
@export_range(0.0, 1.0) var friction := 0.15:
	set(value):
		friction = value
		_rebuild()
@export_range(0.0, 1.0) var bounce := 0.25:
	set(value):
		bounce = value
		_rebuild()
## Sample spacing along the path (m), also the capsule length.
@export var step := 0.01:
	set(value):
		step = maxf(value, 0.002)
		_rebuild()

var _parts: Array[Node] = []


func _ready() -> void:
	_rebuild()


## The sampled path (ball bottom) along the wires, in local coordinates.
func path() -> PackedVector3Array:
	return RampPath.sample(points, step)


## Wire positions in the path frame: (side, up) from the ball's lowest point.
func wire_offsets() -> PackedVector2Array:
	var reach := ball_radius + wire_radius
	var below := reach * cos(PI / 4.0)
	var offsets := PackedVector2Array([
		Vector2(-reach * sin(PI / 4.0), ball_radius - below),
		Vector2(reach * sin(PI / 4.0), ball_radius - below),
	])
	if guards:
		var guard := reach + guard_clearance
		offsets.append(Vector2(-guard, ball_radius + guard_height))
		offsets.append(Vector2(guard, ball_radius + guard_height))
	return offsets


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for part in _parts:
		part.queue_free()
	_parts.clear()
	if points.size() < 2:
		return

	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = bounce
	physics_material_override = material

	var samples := path()
	var basis_list := RampPath.frames(samples)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var distance := PackedFloat32Array([0.0])
	for i in range(1, samples.size()):
		distance.append(distance[i - 1] + samples[i].distance_to(samples[i - 1]))
	var offsets := wire_offsets()
	for k in offsets.size():
		var offset := offsets[k]
		var is_guard := k >= 2
		var wire := PackedVector3Array()
		for i in samples.size():
			var side := offset.x
			if is_guard and flare_length > 0.0:
				side += signf(side) * entry_flare * (1.0 - smoothstep(0.0, flare_length, distance[i]))
			wire.append(samples[i] + basis_list[i].x * side + basis_list[i].y * offset.y)
		_add_capsules(wire)
		RampPath.extrude(tool, wire, RampPath.frames(wire), RampPath.circle(wire_radius, 8), true, true)

	var mesh_node := MeshInstance3D.new()
	var mesh := tool.commit()
	mesh.surface_set_material(0, TableMaterials.make(TableMaterials.Finish.METAL, color))
	mesh_node.mesh = mesh
	add_child(mesh_node)
	_parts.append(mesh_node)


func _add_capsules(wire: PackedVector3Array) -> void:
	for i in wire.size() - 1:
		var from := wire[i]
		var to := wire[i + 1]
		var segment := to - from
		if segment.length() < 1e-5:
			continue
		var capsule := CapsuleShape3D.new()
		capsule.radius = wire_radius
		capsule.height = segment.length() + 2.0 * wire_radius
		var shape_node := CollisionShape3D.new()
		shape_node.shape = capsule
		shape_node.transform = Transform3D(Basis(Quaternion(Vector3.UP, segment.normalized())),
				(from + to) * 0.5)
		add_child(shape_node)
		_parts.append(shape_node)
