extends SceneTree
## Phase 1 physics test suite. Run it with a fixed timestep, so every frame
## is exactly one physics tick and the run is as fast as the CPU allows:
##
##   godot --headless --fixed-fps 1000 --script res://tests/physics_test.gd
##
## Measures:
## - Tunneling: 1000 balls fired at 8–20 m/s into a 5 mm wall, at real scale
##   and scaled up ×10, with CCD on and off.
## - Rolling: a ball released on the sloped playfield must accelerate at
##   5/7 · g · sin(slope) (a solid sphere rolling without slipping) and its
##   spin must match its speed.
## - Resting penetration of the ball into the playfield.
##
## Real scale with CCD is asserted; the other variants are reported so we can
## compare them.

const BallScript := preload("res://table_parts/ball.gd")
const TuningScript := preload("res://physics/physics_tuning.gd")

const SHOTS := 1000
const SHOT_TICKS := 150
const WALL_THICKNESS := 0.005
const ROLL_WARMUP_TICKS := 200
const ROLL_MEASURE_TICKS := 1300
const SEED := 1234

var _failures: PackedStringArray = []


func _initialize() -> void:
	_print_jolt_settings()
	_run.call_deferred()


func _run() -> void:
	print("\n== Tunneling: %d shots at 8–20 m/s into a %.0f mm wall ==" % [
			SHOTS, WALL_THICKNESS * 1000.0])
	for scale: float in [1.0, 10.0]:
		for ccd: bool in [true, false]:
			var tunneled: int = await _tunneling_run(scale, ccd)
			print("scale ×%-4s CCD %-3s  tunneled: %d / %d" % [
					scale, "on" if ccd else "off", tunneled, SHOTS])
			if scale == 1.0 and ccd and tunneled > 0:
				_failures.append("%d balls tunneled at real scale with CCD" % tunneled)

	print("\n== Rolling on a %.1f° slope ==" % TuningScript.new().slope_degrees)
	for scale: float in [1.0, 10.0]:
		var result: Dictionary = await _rolling_run(scale)
		print(("scale ×%-4s accel: %.4f m/s² (expected %.4f, %+.1f%%)  "
				+ "spin/speed: %.3f  final speed: %.2f m/s  resting penetration: %.2f mm") % [
				scale, result.accel, result.expected,
				(result.accel / result.expected - 1.0) * 100.0,
				result.spin_ratio, result.speed, result.penetration_mm])
		if scale == 1.0:
			if absf(result.accel / result.expected - 1.0) > 0.1:
				_failures.append("rolling acceleration off by more than 10%% at real scale (%.4f vs %.4f)"
						% [result.accel, result.expected])
			if absf(result.spin_ratio - 1.0) > 0.1:
				_failures.append("ball is sliding instead of rolling at real scale (spin/speed %.3f)"
						% result.spin_ratio)

	print("")
	if _failures.is_empty():
		print("PHYSICS TEST OK")
		quit(0)
	else:
		for failure in _failures:
			printerr("PHYSICS TEST FAIL: ", failure)
		quit(1)


func _tunneling_run(scale: float, ccd: bool) -> int:
	var tuning: PhysicsTuning = TuningScript.new()
	tuning.world_scale = scale
	var radius := tuning.scaled_ball_radius()

	var arena := Node3D.new()
	root.add_child(arena)
	_add_box(arena, Vector3(8.0, 0.02, 8.0) * scale, Vector3(0.0, -0.01, 0.0) * scale)
	_add_box(arena, Vector3(8.0, 0.005, 8.0) * scale, Vector3(0.0, 0.06, 0.0) * scale)
	_add_box(arena, Vector3(6.0, 0.06, WALL_THICKNESS) * scale, Vector3(0.0, 0.03, 0.0) * scale)

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var balls: Array[Ball] = []
	for i in SHOTS:
		var ball: Ball = BallScript.new()
		ball.tuning = tuning
		ball.continuous_cd = ccd
		# Balls ignore each other so all shots can run at the same time.
		ball.collision_mask = BallScript.TABLE_LAYER
		ball.position = Vector3(
				rng.randf_range(-0.5, 0.5) * scale,
				radius,
				rng.randf_range(0.02, 0.1) * scale)
		var angle := deg_to_rad(rng.randf_range(-60.0, 60.0))
		var speed := rng.randf_range(8.0, 20.0) * scale
		ball.linear_velocity = Vector3(sin(angle), 0.0, -cos(angle)) * speed
		arena.add_child(ball)
		balls.append(ball)

	# The wall's center plane is z = 0. A ball center behind it has tunneled.
	var tunneled := {}
	for tick in SHOT_TICKS:
		await physics_frame
		for i in balls.size():
			if balls[i].position.z < 0.0:
				tunneled[i] = true

	arena.queue_free()
	await process_frame
	return tunneled.size()


func _rolling_run(scale: float) -> Dictionary:
	var tuning: PhysicsTuning = TuningScript.new()
	tuning.world_scale = scale
	var radius := tuning.scaled_ball_radius()

	var arena := Node3D.new()
	root.add_child(arena)
	_add_box(arena, Vector3(1.0, 0.02, 8.0) * scale, Vector3(0.0, -0.01, 0.0) * scale,
			tuning.playfield_friction)

	var ball: Ball = BallScript.new()
	ball.tuning = tuning
	ball.position = Vector3(0.0, radius, -3.5 * scale)
	arena.add_child(ball)

	for tick in ROLL_WARMUP_TICKS:
		await physics_frame
	var start_speed := ball.linear_velocity.z
	var penetration := radius - ball.position.y
	for tick in ROLL_MEASURE_TICKS:
		await physics_frame
	var end_speed := ball.linear_velocity.z
	var seconds := ROLL_MEASURE_TICKS / float(Engine.physics_ticks_per_second)

	var slope := deg_to_rad(tuning.slope_degrees)
	var result := {
		"accel": (end_speed - start_speed) / seconds,
		"expected": 5.0 / 7.0 * tuning.gravity * scale * sin(slope),
		"spin_ratio": ball.angular_velocity.length() * radius / maxf(ball.linear_velocity.length(), 0.0001),
		"speed": ball.linear_velocity.length() / scale,
		"penetration_mm": penetration / scale * 1000.0,
	}
	arena.queue_free()
	await process_frame
	return result


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, friction := 0.3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.0
	body.physics_material_override = material
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	box.margin = minf(0.001, size[size.min_axis_index()] * 0.1)
	shape_node.shape = box
	body.add_child(shape_node)
	parent.add_child(body)


func _print_jolt_settings() -> void:
	print("== Jolt settings ==")
	for property in ProjectSettings.get_property_list():
		var setting: String = property["name"]
		if setting.begins_with("physics/jolt"):
			print("  %s = %s" % [setting, ProjectSettings.get_setting(setting)])
