extends SceneTree
## Test suite for the prototype table's parts: flippers, plunger, drain,
## slingshots, bumpers, targets, rollovers, and the cabinet (nudge and tilt).
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
var _cabinet: Cabinet


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_flipper_stroke()
	await _test_plunger(1.0, true)
	await _test_plunger(0.1, false)
	await _test_flipper_shot()
	await _test_flipper_restitution()
	await _test_flipper_eos_give()
	await _test_cradle()
	await _test_outlane_drains()
	await _test_slingshot()
	await _test_pop_bumper()
	await _test_drop_target_bank()
	await _test_rollover()
	await _test_shooter_lane_hits_nothing()
	await _test_nudge_free_ball()
	await _test_nudge_cradled_ball()
	await _test_tilt()
	await _test_replay()
	await _test_ramp(1.0, false)
	await _test_ramp(2.2, true)
	await _test_ramp(3.0, true)
	await _test_ramp(4.0, true)
	await _test_ball_passes_under_ramp()
	await _test_ramp_from_right_flipper()
	await _test_top_left_corner_drains_into_lanes()
	await _test_saucer()
	await _test_spinner()

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
	_cabinet = _table.get("cabinet")
	_cabinet.use_input = false
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


## Unit normal of a flipper's upper (playfield) side at `fraction` along it.
func _flipper_normal(flipper: Flipper, fraction: float) -> Vector3:
	var surface := _beside_flipper(flipper, fraction, 0.0)
	var axis := flipper.to_global(Vector3(flipper.direction_sign() * flipper.length * fraction, 0.0, 0.0))
	var normal := surface - axis
	normal.y = 0.0
	return normal.normalized()


## Fires the ball straight at the bat and returns the coefficient of
## restitution (outgoing / incoming normal speed).
func _bounce_off_flipper(flipper: Flipper, fraction: float, speed: float) -> float:
	var normal := _flipper_normal(flipper, fraction)
	var touch := _beside_flipper(flipper, fraction, 0.0)
	_place_ball(touch + normal * 0.008)
	_ball.linear_velocity = -normal * speed
	var out := 0.0
	for i in 40:
		await physics_frame
		out = maxf(out, _ball.linear_velocity.dot(normal))
	return out / speed


## The rubber is lively for slow balls and deader for fast ones.
func _test_flipper_restitution() -> void:
	await _load_table()
	var slow: float = await _bounce_off_flipper(_left, 0.5, 0.5)
	await _load_table()
	var fast: float = await _bounce_off_flipper(_left, 0.5, 4.0)
	print("Flipper rubber: restitution %.2f at 0.5 m/s, %.2f at 4 m/s (model %.2f / %.2f)" % [
			slow, fast, _left.restitution_at(0.5), _left.restitution_at(4.0)])
	if slow < fast + 0.1:
		_failures.append("flipper restitution does not drop with impact speed (%.2f vs %.2f)" % [slow, fast])
	if fast < 0.3 or fast > 0.65:
		_failures.append("flipper restitution at 4 m/s out of range (%.2f)" % fast)


## A hard hit on a raised flipper pushes it back against the hold winding;
## the EOS switch then re-powers it and it comes back up.
func _test_flipper_eos_give() -> void:
	await _load_table()
	_left.energized = true
	await _ticks(150)
	var full := _left.stroke_angle
	var held_by_hold_winding := _left.is_eos_open()
	var normal := _flipper_normal(_left, 0.8)
	_place_ball(_beside_flipper(_left, 0.8, 0.0) + normal * 0.008)
	_ball.linear_velocity = -normal * 4.0
	var lowest := full
	for i in 200:
		await physics_frame
		lowest = minf(lowest, _left.stroke_angle)
	var give := rad_to_deg(full - lowest)
	print("Flipper EOS: held by the hold winding %s, a 4 m/s hit pushes it back %.1f°, back up: %s" % [
			held_by_hold_winding, give, _left.is_fully_up()])
	if not held_by_hold_winding:
		_failures.append("a raised flipper is not on the hold winding (EOS open)")
	if give < 0.5 or give > 20.0:
		_failures.append("a hard hit on a raised flipper gives %.1f° (expected 0.5–20°)" % give)
	if not _left.is_fully_up():
		_failures.append("the flipper does not come back up after a hit")
	_left.energized = false


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


## Fires the ball at a point with the given velocity, from `distance` meters
## back along the velocity.
func _fire_at(target: Vector3, velocity: Vector3, distance := 0.03) -> void:
	var radius := _ball.tuning.scaled_ball_radius()
	var from := target - velocity.normalized() * distance
	_place_ball(Vector3(from.x, radius, from.z))
	_ball.linear_velocity = velocity


func _test_slingshot() -> void:
	await _load_table()
	var sling: Slingshot = _table.get_node("LeftSlingshot")
	var n2 := sling.normal_2d() * sling.kick_side
	var normal := Vector3(n2.x, 0.0, n2.y)
	var face := Vector3((sling.start.x + sling.end.x) * 0.5, 0.0, (sling.start.y + sling.end.y) * 0.5)
	var radius := _ball.tuning.scaled_ball_radius()
	_fire_at(face + normal * (sling.thickness * 0.5 + radius), -normal * 0.6)
	var best := 0.0
	for i in 150:
		await physics_frame
		best = maxf(best, _ball.linear_velocity.dot(normal))
	print("Slingshot: peak speed away from the rubber %.2f m/s, score %d" % [best, _table.get("score")])
	if best < 1.5:
		_failures.append("slingshot kick too weak (%.2f m/s)" % best)


func _test_pop_bumper() -> void:
	await _load_table()
	var bumper: PopBumper = _table.get_node("PopBumper3")
	var radius := _ball.tuning.scaled_ball_radius()
	var contact := bumper.position + Vector3(bumper.radius + radius, 0.0, 0.0)
	_fire_at(contact, Vector3(-0.6, 0.0, 0.0))
	var best := 0.0
	for i in 150:
		await physics_frame
		var away := _ball.position - bumper.position
		away.y = 0.0
		best = maxf(best, _ball.linear_velocity.dot(away.normalized()))
	print("Pop bumper: peak speed away from the bumper %.2f m/s, score %d" % [best, _table.get("score")])
	if best < 1.5:
		_failures.append("pop bumper kick too weak (%.2f m/s)" % best)


func _test_drop_target_bank() -> void:
	await _load_table()
	var bank: DropTargetBank = _table.get_node("DropTargetBank")
	var radius := _ball.tuning.scaled_ball_radius()
	for target in bank.targets:
		var face := target.global_position - Vector3(target.size.x * 0.5 + radius, 0.0, 0.0)
		_fire_at(face, Vector3(1.0, 0.0, 0.0))
		await _ticks(120)
	var all_down := bank.all_down()
	var score: int = _table.get("score")
	await _ticks(1300)
	var reset := not bank.all_down() and not bank.targets.any(func(t): return t.is_down)
	print("Drop targets: all down %s, score %d, reset after delay %s" % [all_down, score, reset])
	if not all_down:
		_failures.append("not all drop targets went down")
	if score < 1300:
		_failures.append("drop target bank did not award its points (score %d)" % score)
	if not reset:
		_failures.append("drop target bank did not reset")


func _test_rollover() -> void:
	await _load_table()
	var rollover: Rollover = _table.get_node("TopLaneRollover2")
	_fire_at(rollover.position, Vector3(0.0, 0.0, 0.5), 0.04)
	await _ticks(300)
	print("Rollover: lit %s, score %d" % [rollover.lit, _table.get("score")])
	if not rollover.lit:
		_failures.append("top lane rollover did not trigger")


## Regression: the drop targets sit right behind the shooter lane wall, and
## Jolt's speculative contacts (up to 2 cm) used to drop them while the ball
## was still in the lane.
func _test_shooter_lane_hits_nothing() -> void:
	await _load_table()
	var bank: DropTargetBank = _table.get_node("DropTargetBank")
	_table.call("serve_ball")
	await _ticks(100)
	_plunger.pulled = true
	await _ticks(int(ceil(_plunger.max_pull / _plunger.pull_speed * Engine.physics_ticks_per_second)))
	_plunger.pulled = false
	var dropped_in_lane := false
	var score_in_lane := 0
	for i in 2000:
		await physics_frame
		if _ball.position.x < 0.2:
			break
		dropped_in_lane = dropped_in_lane or bank.targets.any(func(t): return t.is_down)
		score_in_lane = _table.get("score")
	print("Shooter lane: drop target hit while in the lane: %s, score in the lane: %d" % [
			dropped_in_lane, score_in_lane])
	if dropped_in_lane or score_in_lane > 0:
		_failures.append("parts behind the shooter lane wall react to the ball in the lane")


## A shove from the left jolts the cabinet right; a free ball lags behind,
## so relative to the table it moves left. The cabinet settles back.
func _test_nudge_free_ball() -> void:
	await _load_table()
	var radius := _ball.tuning.scaled_ball_radius()
	_place_ball(Vector3(-0.0275, radius, 0.05))
	await _ticks(5)
	var vx0 := _ball.linear_velocity.x
	_cabinet.nudge(Vector3.RIGHT)
	var lowest := 0.0
	for i in 60:
		await physics_frame
		lowest = minf(lowest, _ball.linear_velocity.x - vx0)
	await _ticks(1500)
	print("Nudge: free ball jolts %.2f m/s sideways, cabinet back to %.2f mm, warnings %d" % [
			lowest, _cabinet.offset.length() * 1000.0, _cabinet.warnings])
	if lowest > -0.1:
		_failures.append("a nudge barely moves a free ball (%.2f m/s)" % lowest)
	if _cabinet.offset.length() > 0.001:
		_failures.append("the cabinet does not settle after a nudge")
	if _cabinet.warnings > 0:
		_failures.append("a single nudge gives a tilt warning")


## A ball cradled on a raised flipper is carried by the flipper when the
## cabinet is shoved forward, and leaves it up the table as the cabinet settles.
func _test_nudge_cradled_ball() -> void:
	await _load_table()
	_left.energized = true
	await _ticks(100)
	_place_ball(_beside_flipper(_left, 0.85, 0.004))
	await _ticks(1500)
	var z0 := _ball.position.z
	_cabinet.nudge(Vector3.FORWARD)
	var lowest_vz := 0.0
	for i in 300:
		await physics_frame
		lowest_vz = minf(lowest_vz, _ball.linear_velocity.z)
	print("Nudge: cradled ball leaves the flipper at %.2f m/s up the table (moved %.1f mm)" % [
			-lowest_vz, (z0 - _ball.position.z) * 1000.0])
	if lowest_vz > -0.1:
		_failures.append("a forward nudge does not move a cradled ball (%.2f m/s)" % lowest_vz)
	_left.energized = false


## Nudging in step with the tilt bob builds up its swing: warnings first,
## then a tilt that kills the flippers and coils. reset_tilt restores them.
func _test_tilt() -> void:
	await _load_table()
	_ball.freeze = true
	var period_ticks := int(TAU * sqrt(_cabinet.bob_length / 9.81) * Engine.physics_ticks_per_second)
	# Lambdas capture locals by value, so count in an array.
	var warnings_seen := [0]
	_cabinet.tilt_warning.connect(func(_left_count: int): warnings_seen[0] += 1)
	var nudges := 0
	while not _cabinet.is_tilted and nudges < 12:
		_cabinet.nudge(Vector3.RIGHT)
		nudges += 1
		await _ticks(period_ticks)
	var sling: Slingshot = _table.get_node("LeftSlingshot")
	var bumper: PopBumper = _table.get_node("PopBumper1")
	print("Tilt: %d warning(s), tilted after %d nudges in step with the bob" % [warnings_seen[0], nudges])
	if not _cabinet.is_tilted:
		_failures.append("nudging in step with the bob never tilts")
	if warnings_seen[0] != _cabinet.warnings_allowed:
		_failures.append("expected %d tilt warnings, got %d" % [_cabinet.warnings_allowed, warnings_seen[0]])
	if _left.enabled or sling.enabled or bumper.enabled:
		_failures.append("a tilt leaves flippers or coils working")
	_table.call("reset_tilt")
	if _cabinet.is_tilted or not (_left.enabled and sling.enabled and bumper.enabled):
		_failures.append("reset_tilt does not restore the machine")
	_ball.freeze = false


## The replay records every tick, survives a save and load, and playback
## puts the ball exactly where the recording says.
func _test_replay() -> void:
	await _load_table()
	var replay: Replay = _table.get("replay")
	_place_ball(_beside_flipper(_left, 0.45))
	replay.clear()
	await _ticks(100)
	_left.energized = true
	await _ticks(200)
	_left.energized = false
	var recorded := replay.frames()
	var path := "user://test_replay.pbr"
	replay.save_to_file(path)
	var loaded := Replay.load_file(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var same := loaded.size() == recorded.size() and not loaded.is_empty() \
			and loaded[0] == recorded[0] and loaded[-1] == recorded[-1]
	var coil_frames := loaded.filter(func(f: PackedFloat32Array): return int(f[Replay.FIELD_INPUTS]) & 1 != 0).size()

	# Where the ball is when playback hands it back to physics.
	var end_position := [Vector3.INF]
	replay.playback_finished.connect(func(): end_position[0] = _ball.position, CONNECT_ONE_SHOT)
	replay.play(loaded)
	await _ticks(loaded.size() + 2)
	var last: PackedFloat32Array = loaded[-1]
	var expected := Vector3(last[Replay.FIELD_POSITION], last[Replay.FIELD_POSITION + 1], last[Replay.FIELD_POSITION + 2])
	var error: float = end_position[0].distance_to(expected)
	print("Replay: %d frames recorded (%d with the left coil on), save/load identical: %s, playback ends %.2f mm from the recording" % [
			recorded.size(), coil_frames, same, error * 1000.0])
	if recorded.size() < 295 or recorded.size() > 305:
		_failures.append("the replay recorded %d frames for 300 ticks" % recorded.size())
	if not same:
		_failures.append("a saved replay does not load back identically")
	if coil_frames < 150:
		_failures.append("the replay did not record the flipper coil")
	if error > 0.0005 or replay.is_playing or _ball.freeze:
		_failures.append("playback does not reproduce the recording (%.2f mm off)" % (error * 1000.0))


## Rolls the ball straight into the left ramp. A strong enough shot goes up,
## around the hairpin, down the wire return and onto the playfield in the
## left inlane; a weak one rolls back out of the entrance.
func _test_ramp(speed: float, should_make: bool) -> void:
	await _load_table()
	var ramp: Ramp = _table.get_node("LeftRamp")
	var made_switch: BallSwitch = _table.get_node("LeftRampMade")
	var radius := _ball.tuning.scaled_ball_radius()
	var entrance := ramp.points[0]
	var axis := ramp.points[1] - entrance
	axis.y = 0.0
	axis = axis.normalized()
	_place_ball(Vector3(entrance.x, radius, entrance.z) - axis * 0.05)
	_ball.linear_velocity = axis * speed
	_ball.angular_velocity = Vector3.UP.cross(axis) * (speed / radius)
	var top := 0.0
	var landed := Vector3.INF
	var made_tick := -1
	var trace := PackedStringArray()
	for i in 4000:
		await physics_frame
		top = maxf(top, _ball.position.y)
		if i % 50 == 0 and i <= 1000:
			trace.append("%d:(%.3f,%.3f,%.3f)" % [i, _ball.position.x, _ball.position.y, _ball.position.z])
		if made_tick < 0 and made_switch.hits > 0:
			made_tick = i
		if made_tick >= 0 and _ball.position.z > 0.1 and _ball.position.y < radius + 0.001:
			landed = _ball.position
			break
		if made_tick < 0 and not should_make and i > 1500:
			break
	# Touching the glass on a hard shot is fine; passing through it is not.
	var glass_clearance := 0.095 + 0.001 - (top + radius)
	print("Ramp at %.1f m/s: made %s (switch %d) after %.2f s, highest ball top %.3f m, landed at %s, score %d" % [
			speed, made_tick >= 0, made_switch.hits, made_tick / 1000.0, top + radius, landed, _table.get("score")])
	if should_make and made_tick < 0:
		print("  trace: ", " ".join(trace))
	if should_make:
		if made_tick < 0:
			_failures.append("ramp shot at %.1f m/s did not make the ramp" % speed)
		elif landed == Vector3.INF:
			_failures.append("ramp shot at %.1f m/s did not come back onto the playfield" % speed)
		elif landed.x < -0.225 or landed.x > -0.175 or landed.z > 0.3:
			_failures.append("ramp shot at %.1f m/s landed outside the left inlane (%s)" % [speed, landed])
		if made_switch.hits != 1 or _table.get("score") < 1000:
			_failures.append("ramp switch did not score exactly once (%d hits)" % made_switch.hits)
	else:
		if made_tick >= 0:
			_failures.append("a weak ramp shot (%.1f m/s) made the ramp" % speed)
		if _ball.position.z < entrance.z or _ball.position.y > radius + 0.002:
			_failures.append("a weak ramp shot did not roll back out (%s)" % _ball.position)
	if glass_clearance < 0.0:
		_failures.append("the ball went through the glass on the ramp (%.3f m)" % glass_clearance)


## The lane along the left wall runs under the wire return. A ball rolling
## up it passes under the wires, stops against the closed end of the ramp
## and rolls back down; it never gets wedged.
func _test_ball_passes_under_ramp() -> void:
	await _load_table()
	var radius := _ball.tuning.scaled_ball_radius()
	_place_ball(Vector3(-0.232, radius, 0.0))
	_ball.linear_velocity = Vector3(0.0, 0.0, -1.6)
	_ball.angular_velocity = Vector3(1.6 / radius, 0.0, 0.0)
	var highest_z := 0.0
	var top := 0.0
	var lowest := radius
	var lowest_at := Vector3.ZERO
	for i in 1500:
		await physics_frame
		highest_z = minf(highest_z, _ball.position.z)
		top = maxf(top, _ball.position.y)
		if _ball.position.y < lowest:
			lowest = _ball.position.y
			lowest_at = _ball.position
	print("Under the wire ramp: got up to z %.3f, centre between %.4f (at %s) and %.4f m, ended at %s, speed %.2f m/s" % [
			highest_z, lowest, lowest_at, top, _ball.position, _ball.speed()])
	# A wedged ball is pressed into the playfield and stops; a hard landing
	# only dips briefly.
	if lowest < radius - 0.003 or (_ball.speed() < 0.02 and _ball.position.y < radius - 0.0005):
		_failures.append("ball got wedged under the wire ramp (centre at %.4f m)" % lowest)
	if top > radius + 0.004:
		_failures.append("ball under the wire ramp bounced up (%.4f m)" % top)
	if _ball.position.z < highest_z + 0.1:
		_failures.append("ball under the wire ramp did not roll back down (%s)" % _ball.position)


## A slow ball settles in the saucer, is held, and is kicked out toward the
## bumpers; a fast ball rolls over it.
func _test_saucer() -> void:
	await _load_table()
	var saucer: Saucer = _table.get_node("RightSaucer")
	var radius := _ball.tuning.scaled_ball_radius()
	_place_ball(saucer.position + Vector3(0.04, radius, 0.0))
	_ball.linear_velocity = Vector3(-0.6, 0.0, 0.0)
	_ball.angular_velocity = Vector3(0.0, 0.0, 0.6 / radius)
	await _ticks(300)
	var held := saucer.held == _ball
	var held_at := _ball.position
	var ejected_velocity := Vector3.ZERO
	for i in 1500:
		await physics_frame
		if saucer.held == null and not _ball.freeze:
			ejected_velocity = _ball.linear_velocity
			break
	print("Saucer: held %s at %s, kicked out at %s m/s, score %d" % [
			held, held_at, ejected_velocity, _table.get("score")])
	if not held:
		_failures.append("a slow ball did not settle in the saucer")
	if ejected_velocity.length() < 1.2 or ejected_velocity.x > -0.5:
		_failures.append("saucer did not kick the ball out toward the bumpers (%s)" % ejected_velocity)

	await _load_table()
	saucer = _table.get_node("RightSaucer")
	_place_ball(saucer.position + Vector3(0.05, radius, 0.0))
	_ball.linear_velocity = Vector3(-2.5, 0.0, 0.0)
	await _ticks(200)
	print("Saucer: a fast ball was captured %d time(s)" % saucer.captures)
	if saucer.captures != 0:
		_failures.append("a fast ball got caught in the saucer")


## A ball through the spinner sets it spinning; it scores per revolution and
## stops after a while, and the ball keeps most of its speed.
func _test_spinner() -> void:
	await _load_table()
	var spinner: Spinner = _table.get_node("LeftRampSpinner")
	var radius := _ball.tuning.scaled_ball_radius()
	_place_ball(Vector3(spinner.position.x, radius, spinner.position.z + 0.06))
	_ball.linear_velocity = Vector3(0.0, 0.0, -2.0)
	_ball.angular_velocity = Vector3(-2.0 / radius, 0.0, 0.0)
	await _ticks(3000)
	var revolutions := spinner.revolutions
	await _ticks(7000)
	print("Spinner: %d revolutions after 3 s, %d in total, still spinning %s, score %d" % [
			revolutions, spinner.revolutions, spinner.spin != 0.0, _table.get("score")])
	if revolutions < 5 or revolutions > 80:
		_failures.append("spinner made %d revolutions for a 2 m/s ball" % revolutions)
	if spinner.spin != 0.0:
		_failures.append("spinner never stopped")


## Nothing may trap a ball above the ramp's hairpin: a ball dropped in the
## top left corner rolls down into the top lanes.
func _test_top_left_corner_drains_into_lanes() -> void:
	await _load_table()
	var radius := _ball.tuning.scaled_ball_radius()
	_place_ball(Vector3(-0.15, radius, -0.49))
	var escaped_at := Vector3.INF
	for i in 2500:
		await physics_frame
		if _ball.position.x > -0.12 or _ball.position.z > -0.36:
			escaped_at = _ball.position
			break
	print("Top left corner: ball got out at %s" % escaped_at)
	if escaped_at == Vector3.INF:
		_failures.append("a ball in the top left corner got stuck at %s" % _ball.position)


## The left ramp must be makeable from the right flipper the way a player
## shoots: a ball rolls down the right inlane onto the flipper and the
## player times the flip. Sweeps the timing and needs a window that works.
func _test_ramp_from_right_flipper() -> void:
	var made := PackedStringArray()
	var report := PackedStringArray()
	for delay_ms in range(0, 260, 10):
		await _load_table()
		var radius := _ball.tuning.scaled_ball_radius()
		var made_switch: BallSwitch = _table.get_node("LeftRampMade")
		_place_ball(Vector3(0.144, radius, 0.26))
		_ball.linear_velocity = Vector3(0.0, 0.0, 0.3)
		# The delay counts from when the ball reaches the flipper's base.
		for i in 2000:
			await physics_frame
			if _ball.position.z > 0.37:
				break
		await _ticks(delay_ms)
		_right.energized = true
		var crossing := Vector3.INF
		var crossing_speed := 0.0
		for i in 2500:
			await physics_frame
			if i == 400:
				_right.energized = false
			if crossing == Vector3.INF and _ball.position.z < -0.03:
				crossing = _ball.position
				crossing_speed = _ball.speed()
			if made_switch.hits > 0:
				break
		if made_switch.hits > 0:
			made.append(str(delay_ms))
		report.append("%d ms after the ball reached the flipper: %s" % [delay_ms, "MADE" if made_switch.hits > 0 else (
				"crossed x %.3f at %.1f m/s" % [crossing.x, crossing_speed] if crossing != Vector3.INF
				else "did not get up")])
	print("Right flipper to left ramp: made at %s ms\n  %s" % [", ".join(made), "\n  ".join(report)])
	if made.size() < 2:
		_failures.append("the left ramp cannot be made from the right flipper (made at %d timings)" % made.size())
