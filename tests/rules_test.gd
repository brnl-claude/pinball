extends SceneTree
## Phase 4 test suite for the game rules on the prototype table.
## Run with a fixed timestep (one frame = one physics tick):
##
##   godot --headless --fixed-fps 1000 --script res://tests/rules_test.gd

const TABLE_SCENE := "res://tables/proto_table/proto_table.tscn"
const RulesScript := preload("res://rules/game_rules.gd")
const HIGH_SCORE_PATH := "user://test_high_scores.cfg"

var _failures: PackedStringArray = []
var _table: Node3D
var _rules: GameRules
var _ball: Ball


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HIGH_SCORE_PATH))
	await _setup()

	_expect(_rules.state == GameRules.State.ATTRACT, "rules start in attract mode")
	_expect(not _table.get("left_flipper").enabled, "flippers are dead in attract mode")
	# Pulling the plunger before a game starts does nothing.
	var plunger: Plunger = _table.get("plunger")
	plunger.use_input = false
	plunger.pulled = true
	await _ticks(200)
	_expect(plunger.pull == 0.0, "the plunger does not move in attract mode (pull %.3f m)" % plunger.pull)
	plunger.pulled = false

	_rules.start_game()
	await _ticks(10)
	_expect(_rules.state == GameRules.State.PLAYING, "start_game enters PLAYING")
	_expect(_rules.ball_number == 1, "the game starts on ball 1")
	_expect(_table.get("left_flipper").enabled, "flippers work during play")
	plunger.pulled = true
	await _ticks(40)  # a short pull that keeps the ball in the lane
	_expect(plunger.pull > 0.003, "the plunger works during a game")
	plunger.pulled = false
	await _ticks(100)

	# Ball save: launch, drain right away → same ball, served again.
	await _launch()
	_expect(_rules.ball_save_left > 0.0, "ball save starts when the ball leaves the lane")
	await _drain()
	_expect(_rules.ball_number == 1 and _rules.state == GameRules.State.PLAYING,
			"a drain during ball save gives the ball back")

	# Top lanes: light all three → multiplier 2.
	for lane in ["TopLaneRollover1", "TopLaneRollover2", "TopLaneRollover3"]:
		await _roll_over(lane)
	_expect(_rules.multiplier == 2, "completing the top lanes advances the multiplier (got %d)" % _rules.multiplier)
	var bonus := _rules.bonus
	_expect(bonus >= 300, "rollovers add bonus (got %d)" % bonus)

	# End of ball 1 after the save expired: bonus × multiplier is awarded.
	await _launch()
	_rules.ball_save_left = 0.0
	var score_before := _rules.score
	await _drain()
	_expect(_rules.state == GameRules.State.BALL_ENDING, "a drain without save ends the ball")
	_expect(_rules.score - score_before == bonus * 2,
			"end-of-ball bonus is bonus × multiplier (%d vs %d)" % [_rules.score - score_before, bonus * 2])
	_expect(not _table.get("left_flipper").enabled, "flippers are dead during the bonus count")
	await _ticks(int(_rules.bonus_display_seconds * 1000) + 50)
	_expect(_rules.ball_number == 2 and _rules.state == GameRules.State.PLAYING,
			"the next ball starts after the bonus")
	_expect(_rules.multiplier == 1, "the multiplier resets per ball")

	# Balls 2 and 3 drain without save → game over with a high score.
	for i in 2:
		await _launch()
		_rules.ball_save_left = 0.0
		await _drain()
		await _ticks(int(_rules.bonus_display_seconds * 1000) + 50)
	_expect(_rules.state == GameRules.State.GAME_OVER, "game over after %d balls" % _rules.balls_per_game)
	_expect(_rules.high_scores.size() == 1 and _rules.high_scores[0] == _rules.score,
			"the final score is saved as a high score")
	await _ticks(int(_rules.game_over_seconds * 1000) + 50)
	_expect(_rules.state == GameRules.State.ATTRACT, "game over returns to attract mode")

	# High scores survive a reload.
	var reloaded: GameRules = RulesScript.new()
	reloaded.high_score_path = HIGH_SCORE_PATH
	reloaded.load_high_scores()
	_expect(reloaded.high_scores == _rules.high_scores, "high scores are persisted")
	reloaded.free()

	await _test_tilt()
	await _test_mode()
	await _test_multiball()

	print("Rules: final score %d, high scores %s" % [_rules.score, _rules.high_scores])
	print("")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HIGH_SCORE_PATH))
	if _failures.is_empty():
		print("RULES TEST OK")
		quit(0)
	else:
		for failure in _failures:
			printerr("RULES TEST FAIL: ", failure)
		quit(1)


## A tilted ball scores nothing, gets no bonus or ball save, and the next
## ball starts with working flippers.
func _test_tilt() -> void:
	var messages: Array[String] = []  # an Array, so the lambda appends to this one
	_rules.message.connect(func(text: String): messages.append(text))
	_rules.start_game()
	await _launch()
	var cabinet: Cabinet = _table.get("cabinet")
	cabinet.use_input = false
	_ball.freeze = true
	var period_ticks := int(TAU * sqrt(cabinet.bob_length / 9.81) * Engine.physics_ticks_per_second)
	for i in 12:
		if _rules.tilted:
			break
		cabinet.nudge(Vector3.RIGHT)
		await _ticks(period_ticks)
	_ball.freeze = false
	_expect(_rules.tilted, "nudging in step with the bob tilts the ball")
	_expect(messages.has("DANGER") and messages.has("TILT"), "the rules show DANGER and TILT (%s)" % ", ".join(PackedStringArray(messages)))
	_expect(not _table.get("left_flipper").enabled, "a tilt kills the flippers")
	_expect(_rules.ball_save_left == 0.0, "a tilt cancels ball save")

	var score_before := _rules.score
	await _roll_over("TopLaneRollover1")
	_expect(_rules.score == score_before, "a tilted ball scores nothing")
	await _drain()
	_expect(_rules.state == GameRules.State.BALL_ENDING and _rules.ball_number == 1,
			"a tilted ball drains without ball save")
	_expect(_rules.score == score_before, "a tilted ball gets no bonus")
	await _ticks(int(_rules.bonus_display_seconds * 1000) + 50)
	_expect(_rules.ball_number == 2 and not _rules.tilted, "the next ball is not tilted")
	_expect(_table.get("left_flipper").enabled and not cabinet.is_tilted,
			"the next ball has working flippers")


## The saucer starts a mode when the lock is not lit; the mode's shots score
## extra until its timer runs out.
func _test_mode() -> void:
	_rules.start_game()
	await _launch()
	await _into_saucer()
	_expect(_rules.mode == 0, "the saucer starts the first mode (mode %d)" % _rules.mode)
	await _ticks(int(_saucer().hold_seconds * 1000) + 50)
	_expect(_saucer().held == null, "the saucer kicks the ball out after starting a mode")
	_make_ramp()
	_expect(_rules.mode_total == GameRules.MODES[0]["points"],
			"a ramp during %s scores the mode award (total %d)" % [GameRules.MODES[0]["name"], _rules.mode_total])
	var ended: Array[String] = []
	_rules.mode_ended.connect(func(mode_name: String, _total: int): ended.append(mode_name), CONNECT_ONE_SHOT)
	_rules.mode_time_left = 0.005
	await _ticks(10)
	_expect(_rules.mode == -1 and ended.size() == 1 and ended[0] == GameRules.MODES[0]["name"], "the mode ends when its timer runs out")
	_expect(_rules.next_mode == 1, "the next saucer starts the next mode")


## Ramp lights the lock, two locks, the third lock starts 3-ball multiball
## with auto-plunged balls; jackpots, multiball ball save, and the end of
## multiball when one ball is left.
func _test_multiball() -> void:
	_rules.start_game()
	await _ticks(10)
	_expect(not _rules.lock_lit and _saucer().auto_eject, "the lock is not lit at the start of a game")
	for lock in 2:
		await _launch()
		_make_ramp()
		_expect(_rules.lock_lit and not _saucer().auto_eject, "a ramp lights the lock")
		await _into_saucer()
		await _ticks(int(_rules.lock_hold_seconds * 1000) + 50)
		_expect(_rules.locked == lock + 1, "lock %d: the saucer locks the ball (locked %d)" % [lock + 1, _rules.locked])
		_expect(_saucer().held == null and _table.call("balls_in_play") == 1,
				"lock %d: the locked ball leaves play" % (lock + 1))
		var served: Ball = _table.get("ball")
		_expect(served.position.x > 0.2, "lock %d: a new ball is served to the shooter lane" % (lock + 1))
	await _launch()
	_make_ramp()
	await _into_saucer()
	await _ticks(int(_rules.lock_hold_seconds * 1000) + 50)
	_expect(_rules.multiball and _rules.locked == 0, "the third lock starts multiball")
	# The locked balls are auto-plunged one after another.
	var all_in := false
	for i in 6000:
		await physics_frame
		if _table.call("balls_in_play") == 3 and _table.call("_lane_clear") and _table.get("_launch_queue") == 0:
			all_in = true
			print("Multiball: 3 balls in play %d ms after the lock" % i)
			break
	_expect(all_in, "multiball auto-plunges the locked balls onto the playfield (in play %d)" % _table.call("balls_in_play"))

	var score_before := _rules.score
	_make_ramp()
	_expect(_rules.score - score_before >= _rules.jackpot_start, "a ramp during multiball scores the jackpot (+%d)" % (_rules.score - score_before))
	_expect(_rules.jackpot == _rules.jackpot_start + _rules.jackpot_step, "the jackpot grows")

	_expect(_rules.ball_save_left > 0.0, "multiball starts with ball save")
	await _drain()
	_expect(_table.call("balls_in_play") == 3, "a drain during multiball ball save auto-plunges a new ball (in play %d)" % _table.call("balls_in_play"))
	_rules.ball_save_left = 0.0
	var ball_number := _rules.ball_number
	for i in 10:
		if _table.call("balls_in_play") <= 1:
			break
		await _drain()
	_expect(_table.call("balls_in_play") == 1 and not _rules.multiball, "multiball ends with one ball left")
	_expect(_rules.state == GameRules.State.PLAYING and _rules.ball_number == ball_number,
			"the last multiball ball plays on as the same ball")
	_expect(_table.get("ball").is_inside_tree(), "the table's ball is one in play")


func _saucer() -> Saucer:
	return _table.get_node("RightSaucer")


func _make_ramp() -> void:
	var ramp_switch: BallSwitch = _table.get_node("LeftRampMade")
	ramp_switch.scored.emit(ramp_switch.points)


## Drops the ball into the saucer slowly, so it is captured.
func _into_saucer() -> void:
	_ball = _table.get("ball")
	var radius := _ball.tuning.scaled_ball_radius()
	_ball.reset_to(Transform3D(Basis.IDENTITY, _saucer().global_position + Vector3(0.0, radius, 0.0)))
	await _ticks(5)
	_expect(_saucer().held != null, "the ball is captured by the saucer")


func _setup() -> void:
	_table = (load(TABLE_SCENE) as PackedScene).instantiate()
	root.add_child(_table)
	_rules = RulesScript.new()
	_rules.high_score_path = HIGH_SCORE_PATH
	_rules.table_path = _table.get_path()
	root.add_child(_rules)
	_ball = _table.get("ball")
	await _ticks(20)


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


## Moves the ball out of the shooter lane, as a plunger shot would.
func _launch() -> void:
	_ball = _table.get("ball")
	var radius := _ball.tuning.scaled_ball_radius()
	_ball.reset_to(Transform3D(Basis.IDENTITY, Vector3(-0.0275, radius, -0.35)))
	await _ticks(5)


func _drain() -> void:
	_ball = _table.get("ball")
	var radius := _ball.tuning.scaled_ball_radius()
	_ball.reset_to(Transform3D(Basis.IDENTITY, Vector3(-0.0275, radius, 0.5)))
	await _ticks(20)


func _roll_over(rollover_name: String) -> void:
	_ball = _table.get("ball")
	var rollover: Rollover = _table.get_node(rollover_name)
	var radius := _ball.tuning.scaled_ball_radius()
	_ball.reset_to(Transform3D(Basis.IDENTITY, rollover.position + Vector3(0.0, radius, -0.03)))
	_ball.linear_velocity = Vector3(0.0, 0.0, 0.5)
	await _ticks(150)


func _expect(condition: bool, text: String) -> void:
	if not condition:
		_failures.append(text)
