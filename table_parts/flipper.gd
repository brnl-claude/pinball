@tool
class_name Flipper
extends AnimatableBody3D
## A flipper bat driven by a simple coil/motor model.
##
## The node's origin is the pivot. The bat extends along +X (left flipper)
## or −X (right flipper) and rotates around Y. Every physics tick the motor
## accelerates the bat toward the end of its stroke while energized and back
## to rest when released; Jolt then sees a kinematic body with the matching
## angular velocity, so the ball gets the right surface speed (ω × r) wherever
## it is hit.

enum Side { LEFT, RIGHT }

const SEGMENTS := 16

@export var side := Side.LEFT:
	set(value):
		side = value
		_rebuild()
@export var input_action := &"flipper_left"

@export_group("Geometry")
@export var length := 0.076:
	set(value):
		length = value
		_rebuild()
@export var base_radius := 0.0125:
	set(value):
		base_radius = value
		_rebuild()
@export var tip_radius := 0.0065:
	set(value):
		tip_radius = value
		_rebuild()
@export var height := 0.022:
	set(value):
		height = value
		_rebuild()

@export_group("Motion")
## Rest angle in degrees; negative points the bat down toward the drain.
@export var rest_angle_degrees := -30.0:
	set(value):
		rest_angle_degrees = value
		_apply_angle()
@export var stroke_degrees := 50.0
## Angular acceleration while energized (rad/s²).
@export var up_acceleration := 1600.0
@export var up_max_speed := 60.0
## Angular acceleration of the return spring (rad/s²).
@export var down_acceleration := 900.0
@export var down_max_speed := 35.0
## Fraction of angular speed kept (reversed) when hitting an end stop.
@export_range(0.0, 1.0) var end_stop_bounce := 0.15

@export_group("Rubber")
@export_range(0.0, 1.0) var friction := 0.6:
	set(value):
		friction = value
		_rebuild()
@export_range(0.0, 1.0) var bounce := 0.55:
	set(value):
		bounce = value
		_rebuild()

## When false, `energized` is driven by code (tests, attract mode, tilt).
var use_input := true
var energized := false
## Current angle from rest in radians (0 … stroke).
var stroke_angle := 0.0
## Angular speed in rad/s; positive moves toward the end of the stroke.
var angular_speed := 0.0

var _was_energized := false
var _shape_node: CollisionShape3D
var _mesh_node: MeshInstance3D


func _ready() -> void:
	_rebuild()
	_apply_angle()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if use_input:
		energized = Input.is_action_pressed(input_action)
	if energized and not _was_energized:
		SoundFx.play("flipper")
	_was_energized = energized
	step(delta)


## Advances the motor model by one tick.
func step(delta: float) -> void:
	var max_angle := deg_to_rad(stroke_degrees)
	if energized:
		angular_speed = minf(angular_speed + up_acceleration * delta, up_max_speed)
	else:
		angular_speed = maxf(angular_speed - down_acceleration * delta, -down_max_speed)

	stroke_angle += angular_speed * delta
	if stroke_angle >= max_angle:
		stroke_angle = max_angle
		if angular_speed > 0.0:
			angular_speed = -angular_speed * end_stop_bounce
	elif stroke_angle <= 0.0:
		stroke_angle = 0.0
		if angular_speed < 0.0:
			angular_speed = -angular_speed * end_stop_bounce
	_apply_angle()


func is_fully_up() -> bool:
	return stroke_angle >= deg_to_rad(stroke_degrees) * 0.99


## +1 for a left flipper, −1 for a right flipper.
func direction_sign() -> float:
	return 1.0 if side == Side.LEFT else -1.0


func _apply_angle() -> void:
	rotation.y = direction_sign() * (deg_to_rad(rest_angle_degrees) + stroke_angle)


## The bat's outline in the XZ plane: the convex hull of the base and tip
## circles.
func outline() -> PackedVector2Array:
	var points := PackedVector2Array()
	var tip := Vector2(direction_sign() * length, 0.0)
	for i in SEGMENTS:
		var angle := TAU * i / SEGMENTS
		var unit := Vector2(cos(angle), sin(angle))
		points.append(unit * base_radius)
		points.append(tip + unit * tip_radius)
	var hull := Geometry2D.convex_hull(points)
	hull.remove_at(hull.size() - 1)  # convex_hull repeats the first point
	return hull


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		add_child(_shape_node)
		_mesh_node = MeshInstance3D.new()
		add_child(_mesh_node)

	var hull := outline()
	var bottom := 0.001
	var top := height

	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for p in hull:
		points.append(Vector3(p.x, bottom, p.y))
		points.append(Vector3(p.x, top, p.y))
	shape.points = points
	shape.margin = 0.001
	_shape_node.shape = shape

	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = bounce
	physics_material_override = material

	_mesh_node.mesh = _build_mesh(hull, bottom, top)


func _build_mesh(hull: PackedVector2Array, bottom: float, top: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := hull.size()
	for i in range(1, n - 1):
		for y: float in [bottom, top]:
			st.set_normal(Vector3.UP if y == top else Vector3.DOWN)
			for p in [hull[0], hull[i], hull[i + 1]]:
				st.add_vertex(Vector3(p.x, y, p.y))
	var center := Vector2.ZERO
	for p in hull:
		center += p
	center /= n
	for i in n:
		var a := hull[i]
		var b := hull[(i + 1) % n]
		var mid := (a + b) * 0.5
		var normal_2d := (mid - center).normalized()
		st.set_normal(Vector3(normal_2d.x, 0.0, normal_2d.y))
		for v in [Vector3(a.x, bottom, a.y), Vector3(b.x, bottom, b.y), Vector3(b.x, top, b.y),
				Vector3(a.x, bottom, a.y), Vector3(b.x, top, b.y), Vector3(a.x, top, a.y)]:
			st.add_vertex(v)
	var mesh := st.commit()
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color(0.95, 0.95, 0.92)
	surface.roughness = 0.35
	surface.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, surface)
	return mesh
