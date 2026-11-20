extends SceneTree
## Phase 2 test suite for flippers, plunger and drain on the prototype table.
## Run with a fixed timestep (one frame = one physics tick):
##
##   godot --headless --fixed-fps 1000 --script res://tests/table_test.gd

const TABLE_SCENE := "res://tables/proto_table/proto_table.tscn"

var _failures: PackedStringArray = []
var _table: Node3D
var _ball: Ball
var _left: Flipper
var _right: Flipper
var _plunger: Plunger


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_flipper_stroke()
	await _test_plunger(1.0, true)
	await _test_plunger(0.1, false)
	await _test_flipper_shot()
	await _test_cradle()
	await _test_outlane_drains()

	print("")
	if _failures.is_empty():
		print("TABLE TEST OK")
		quit(0)
	else:
		for failure in _failures:
			printerr("TABLE TEST FAIL: ", failure)
		quit(1)


## Loads a fresh table with input disabled, so the tests drive the parts.
func _load_table() -> void:
	if _table:
		_table.queue_free()
		await process_frame
	_table = (load(TABLE_SCENE) as PackedScene).instantiate()
	_table.set("respawn_delay", -1.0)
	root.add_child(_table)
	_ball = _table.get_node("Ball")
	_left = _table.get_node("LeftFlipper")
	_right = _table.get_node("RightFlipper")
	_plunger = _table.get_node("Plunger")
	for flipper in [_left, _right]:
		flipper.use_input = false
		flipper.energized = false
	_plunger.use_input = false
	await _ticks(50)


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


func _place_ball(pos: Vector3) -> void:
	_ball.reset_to(Transform3D(Basis.IDENTITY, pos))


## A point next to a flipper, `fraction` along its length, on the upper
## (playfield) side, in table coordinates.
func _beside_flipper(flipper: Flipper, fraction: float, gap := 0.002) -> Vector3:
	var radius := _ball.tuning.scaled_ball_radius()
	var along := lerpf(flipper.base_radius, flipper.tip_radius, fraction)
	var local := Vector3(flipper.direction_sign() * flipper.length * fraction, 0.0,
			-(along + radius + gap))
	var world := flipper.to_global(local)
	return Vector3(world.x, radius, world.z)


func _test_flipper_stroke() -> void:
	await _load_table()
	_left.energized = true
	var ticks := 0
	while not _left.is_fully_up() and ticks < 500:
		await physics_frame
		ticks += 1
	var up_ms := ticks * 1000.0 / Engine.physics_ticks_per_second
	_left.energized = false
	ticks = 0
	while _left.stroke_angle > 0.0 and ticks < 1000:
		await physics_frame
		ticks += 1
	var down_ms := ticks * 1000.0 / Engine.physics_ticks_per_second
	print("Flipper stroke: up %.0f ms, down %.0f ms" % [up_ms, down_ms])
	if up_ms < 20.0 or up_ms > 60.0:
		_failures.append("flipper up-stroke takes %.0f ms (expected 20–60 ms)" % up_ms)


func _test_plunger(strength: float, should_exit_lane: bool) -> void:
	await _load_table()
	_table.call("serve_ball")
	await _ticks(100)
	_plunger.pulled = true
	var pull_ticks := int(ceil(_plunger.max_pull * strength / _plunger.pull_speed
			* Engine.physics_ticks_per_second))
	await _ticks(pull_ticks)
	_plunger.pulled = false
	var min_z := INF
	var left_lane := false
	for i in 2500:
		await physics_frame
		min_z = minf(min_z, _ball.position.z)
		if _ball.position.x < 0.2:
			left_lane = true
	print("Plunger %3.0f%%: ball reached z = %.3f m, left the shooter lane: %s" % [
			strength * 100.0, min_z, left_lane])
	if left_lane != should_exit_lane:
		_failures.append("plunger at %.0f%%: expected the ball %s the shooter lane" % [
				strength * 100.0, "to leave" if should_exit_lane else "to stay in"])


func _test_flipper_shot() -> void:
	await _load_table()
	_place_ball(_beside_flipper(_left, 0.45))
	await _ticks(60)
	_left.energized = true
	var best_speed := 0.0
	var best_velocity := Vector3.ZERO
	for i in 150:
		await physics_frame
		var speed := _ball.linear_velocity.length()
		if speed > best_speed:
			best_speed = speed
			best_velocity = _ball.linear_velocity
	_left.energized = false
	print("Flipper shot: peak ball speed %.2f m/s, velocity %s" % [best_speed, best_velocity])
	if best_speed < 2.5 or best_velocity.z > -1.0:
		_failures.append("flipper shot too weak or wrong direction (%.2f m/s, %s)" % [
				best_speed, best_velocity])


func _test_cradle() -> void:
	await _load_table()
	_left.energized = true
	await _ticks(100)
	_place_ball(_beside_flipper(_left, 0.85, 0.004))
	await _ticks(3000)
	var speed := _ball.linear_velocity.length()
	var distance := Vector2(_ball.position.x - _left.position.x,
			_ball.position.z - _left.position.z).length()
	var drained: int = _table.get("drained_count")
	print("Cradle: speed after 3 s %.3f m/s, %.3f m from the pivot, drained: %d" % [
			speed, distance, drained])
	if drained > 0 or speed > 0.05 or distance > 0.06:
		_failures.append("ball does not settle in a cradle on the raised flipper")
	_left.energized = false


func _test_outlane_drains() -> void:
	await _load_table()
	var radius := _ball.tuning.scaled_ball_radius()
	_place_ball(Vector3(-0.239, radius, 0.22))
	await _ticks(3000)
	var drained: int = _table.get("drained_count")
	print("Outlane: drained %d time(s)" % drained)
	if drained != 1:
		_failures.append("ball in the left outlane did not drain")
