@tool
class_name Flipper
extends AnimatableBody3D
## A flipper bat driven by a coil model with an end-of-stroke (EOS) switch.
##
## The node's origin is the pivot. The bat extends along +X (left flipper)
## or −X (right flipper) and rotates around Y. Every physics tick the coil
## accelerates the bat toward the end of its stroke while energized and the
## return spring pulls it back when released; Jolt then sees a kinematic body
## with the matching angular velocity, so the ball gets the right surface
## speed (ω × r) wherever it is hit.
##
## Like a real flipper, the strong power winding only drives the stroke. Near
## the end of the stroke the EOS switch opens and the weaker hold winding
## takes over, so a hard hit on a raised flipper pushes it back a little
## before the hold winding brings it up again.
##
## The rubber's restitution depends on the impact speed: slow balls bounce
## lively, fast balls are damped. Every tick the flipper looks at the nearest
## ball's approach speed and sets its bounce for Jolt's contact solver.

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
## The EOS switch opens at this fraction of the stroke; above it only the
## hold winding pulls (rad/s²).
@export_range(0.5, 1.0) var eos_fraction := 0.92
@export var hold_acceleration := 500.0
## Effective moment of inertia of bat, crank and coil plunger (kg·m²); sets
## how far a ball hit pushes the bat back.
@export var effective_inertia := 0.004

@export_group("Rubber")
@export_range(0.0, 1.0) var friction := 0.6:
	set(value):
		friction = value
		_rebuild()
## Restitution for a very slow impact.
@export_range(0.0, 1.0) var bounce := 0.75:
	set(value):
		bounce = value
		_rebuild()
## How fast restitution drops with impact speed (s/m):
## e = bounce / (1 + bounce_falloff · impact speed).
@export var bounce_falloff := 0.12
## Balls farther than this from the bat (m) are ignored for restitution.
@export var restitution_lookahead := 0.03

## When false, `energized` is driven by code (tests, attract mode, tilt).
var use_input := true
## When false the coil is dead (game over, end of ball, tilt).
var enabled := true
var energized := false
## Current angle from rest in radians (0 … stroke).
var stroke_angle := 0.0
## Angular speed in rad/s; positive moves toward the end of the stroke.
var angular_speed := 0.0

var _was_energized := false
var _shape_node: CollisionShape3D
var _mesh_node: MeshInstance3D
var _physics_material: PhysicsMaterial


func _ready() -> void:
	_rebuild()
	_apply_angle()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if use_input:
		energized = Input.is_action_pressed(input_action)
	if not enabled:
		energized = false
	if energized and not _was_energized:
		SoundFx.play("flipper")
	_was_energized = energized
	step(delta)
	_update_restitution()


## Advances the motor model by one tick.
func step(delta: float) -> void:
	var max_angle := deg_to_rad(stroke_degrees)
	if energized:
		var push := up_acceleration if not is_eos_open() else hold_acceleration
		angular_speed = minf(angular_speed + push * delta, up_max_speed)
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


## The EOS switch is open near the end of the stroke: only the hold winding
## is powered.
func is_eos_open() -> bool:
	return stroke_angle >= deg_to_rad(stroke_degrees) * eos_fraction


## Restitution of the rubber for an impact at the given normal speed (m/s).
func restitution_at(impact_speed: float) -> float:
	return bounce / (1.0 + bounce_falloff * absf(impact_speed))


## Velocity of the bat's surface at a point (world space), from its rotation.
func surface_velocity_at(point: Vector3) -> Vector3:
	var r := point - global_position
	r.y = 0.0
	var omega := Vector3(0.0, direction_sign() * angular_speed, 0.0)
	return omega.cross(r)


## Closest point on the bat's centre line to `point`, and the bat's radius
## there (the bat is a tapered capsule from pivot to tip).
func _closest_on_bat(point: Vector3) -> Array:
	var local := to_local(point)
	var t := clampf(local.x * direction_sign() / length, 0.0, 1.0)
	var axis_point := to_global(Vector3(direction_sign() * length * t, local.y, 0.0))
	return [axis_point, lerpf(base_radius, tip_radius, t)]


## Sets the rubber's bounce for the nearest approaching ball, so Jolt's
## contact solver uses the restitution that fits its impact speed.
func _update_restitution() -> void:
	if _physics_material == null:
		return
	var best_gap := INF
	var impact_speed := 0.0
	for node in get_tree().get_nodes_in_group("balls"):
		var ball := node as RigidBody3D
		if ball == null:
			continue
		var closest: Array = _closest_on_bat(ball.global_position)
		var axis_point: Vector3 = closest[0]
		var offset := ball.global_position - axis_point
		offset.y = 0.0
		var distance := offset.length()
		var radius: float = ball.get("tuning").scaled_ball_radius() if ball.get("tuning") else 0.0135
		var gap := distance - closest[1] - radius
		if gap > restitution_lookahead or gap >= best_gap or distance < 0.0001:
			continue
		best_gap = gap
		var normal := offset / distance
		var contact := axis_point + normal * float(closest[1])
		var relative := ball.linear_velocity - surface_velocity_at(contact)
		impact_speed = maxf(-relative.dot(normal), 0.0)
	var target := restitution_at(impact_speed)
	if not is_equal_approx(_physics_material.bounce, target):
		_physics_material.bounce = target


## Called by the ball when it starts touching the bat. A hit on a raised
## bat pushes it back against the weaker hold winding.
func on_ball_hit(ball: Ball) -> void:
	if stroke_angle <= 0.0:
		return
	var impulse := ball.mass * (ball.linear_velocity - ball.impact_velocity)
	impulse.y = 0.0
	var r := ball.global_position - global_position
	r.y = 0.0
	# The ball pushes the bat with -impulse; torque around Y is (r × F).y.
	var force := -impulse
	var torque_y := r.z * force.x - r.x * force.z
	angular_speed += direction_sign() * torque_y / effective_inertia


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

	_physics_material = PhysicsMaterial.new()
	_physics_material.friction = friction
	_physics_material.bounce = bounce
	physics_material_override = _physics_material

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
