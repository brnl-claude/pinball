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

	_rules.start_game()
	await _ticks(10)
	_expect(_rules.state == GameRules.State.PLAYING, "start_game enters PLAYING")
	_expect(_rules.ball_number == 1, "the game starts on ball 1")
	_expect(_table.get("left_flipper").enabled, "flippers work during play")

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
	var radius := _ball.tuning.scaled_ball_radius()
	_ball.reset_to(Transform3D(Basis.IDENTITY, Vector3(-0.0275, radius, -0.35)))
	await _ticks(5)


func _drain() -> void:
	var radius := _ball.tuning.scaled_ball_radius()
	_ball.reset_to(Transform3D(Basis.IDENTITY, Vector3(-0.0275, radius, 0.5)))
	await _ticks(20)


func _roll_over(rollover_name: String) -> void:
	var rollover: Rollover = _table.get_node(rollover_name)
	var radius := _ball.tuning.scaled_ball_radius()
	_ball.reset_to(Transform3D(Basis.IDENTITY, rollover.position + Vector3(0.0, radius, -0.03)))
	_ball.linear_velocity = Vector3(0.0, 0.0, 0.5)
	await _ticks(150)


func _expect(condition: bool, text: String) -> void:
	if not condition:
		_failures.append(text)
