class_name GameRules
extends Node
## Game rules for a table: games, balls, ball save, bonus, tilt and high
## scores.
##
## The rules only talk to the table through its signals (`part_scored`,
## `ball_drained`, `ball_launched`, `tilt_warning`, `tilted`) and a few calls
## (`serve_ball`, `set_flippers_enabled`, `reset_tilt`), so the physics never
## depends on the rules.
## Timers count physics ticks, so the rules are deterministic in tests.

signal state_changed(state: State)
signal score_changed(score: int)
signal ball_started(ball_number: int)
signal ball_saved
signal ball_tilted
signal bonus_awarded(bonus: int, multiplier: int)
signal game_over(final_score: int, high_score_rank: int)
signal message(text: String)

enum State { ATTRACT, PLAYING, BALL_ENDING, GAME_OVER }

@export var table_path: NodePath
@export var balls_per_game := 3
## Ball save time after the ball leaves the shooter lane (s).
@export var ball_save_seconds := 8.0
## How long the end-of-ball bonus is shown before the next ball (s).
@export var bonus_display_seconds := 2.0
## How long the game over screen is shown before attract mode (s).
@export var game_over_seconds := 4.0
@export var max_multiplier := 5
@export var high_score_path := "user://high_scores.cfg"
@export var high_score_count := 5

@export_group("Awards")
@export var rollover_bonus := 100
@export var standup_bonus := 200
@export var drop_target_bonus := 300
@export var top_lanes_points := 2000
@export var standups_points := 5000

var state := State.ATTRACT
var score := 0
var ball_number := 0
var bonus := 0
var multiplier := 1
## Seconds of ball save left; > 0 means a drain gives the ball back.
var ball_save_left := 0.0
var high_scores: Array[int] = []
## The current ball is tilted: no scoring, no bonus, no ball save.
var tilted := false

var table: Node

var _state_time_left := 0.0
var _ball_in_play := false


func _ready() -> void:
	table = get_node_or_null(table_path)
	if table == null:
		push_error("GameRules needs a table_path")
		return
	table.set("respawn_delay", -1.0)
	table.connect("part_scored", _on_part_scored)
	table.connect("ball_drained", _on_ball_drained)
	table.connect("ball_launched", _on_ball_launched)
	if table.has_signal("tilted"):
		table.connect("tilt_warning", _on_tilt_warning)
		table.connect("tilted", _on_tilted)
	load_high_scores()
	_enter_attract()


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("start_game") and state != State.PLAYING \
			and state != State.BALL_ENDING:
		start_game()

	if ball_save_left > 0.0:
		ball_save_left = maxf(ball_save_left - delta, 0.0)

	if _state_time_left > 0.0:
		_state_time_left -= delta
		if _state_time_left <= 0.0:
			match state:
				State.BALL_ENDING:
					_finish_ball()
				State.GAME_OVER:
					_enter_attract()


func start_game() -> void:
	score = 0
	ball_number = 0
	score_changed.emit(score)
	_reset_table_lights()
	_set_state(State.PLAYING)
	_start_ball()


func _start_ball() -> void:
	ball_number += 1
	bonus = 0
	multiplier = 1
	ball_save_left = 0.0
	_ball_in_play = false
	tilted = false
	if table.has_method("reset_tilt"):
		table.call("reset_tilt")
	table.call("serve_ball")
	table.call("set_flippers_enabled", true)
	ball_started.emit(ball_number)
	message.emit("BALL %d" % ball_number)


func _on_ball_launched() -> void:
	if state == State.PLAYING and not _ball_in_play:
		_ball_in_play = true
		ball_save_left = ball_save_seconds


func _on_ball_drained() -> void:
	if state != State.PLAYING:
		return
	if tilted:
		# A tilted ball ends without bonus; the next ball starts normally.
		_set_state(State.BALL_ENDING)
		_state_time_left = bonus_display_seconds
		return
	if ball_save_left > 0.0:
		ball_save_left = 0.0
		_ball_in_play = false
		table.call("serve_ball")
		ball_saved.emit()
		message.emit("BALL SAVED")
		return
	# End of ball: dead flippers, then count the bonus.
	table.call("set_flippers_enabled", false)
	var total := bonus * multiplier
	_add_score(total)
	bonus_awarded.emit(bonus, multiplier)
	message.emit("BONUS %d × %d" % [bonus, multiplier])
	_set_state(State.BALL_ENDING)
	_state_time_left = bonus_display_seconds


func _finish_ball() -> void:
	if ball_number >= balls_per_game:
		_end_game()
	else:
		_set_state(State.PLAYING)
		_start_ball()


func _end_game() -> void:
	var rank := record_high_score(score)
	_set_state(State.GAME_OVER)
	_state_time_left = game_over_seconds
	game_over.emit(score, rank)
	message.emit("NEW HIGH SCORE" if rank == 1 else "GAME OVER")


func _enter_attract() -> void:
	table.call("set_flippers_enabled", false)
	_set_state(State.ATTRACT)
	message.emit("PRESS START")


func _on_tilt_warning(warnings_left: int) -> void:
	if state != State.PLAYING or tilted:
		return
	message.emit("DANGER" if warnings_left > 0 else "DANGER  DANGER")


func _on_tilted() -> void:
	if state != State.PLAYING:
		return
	tilted = true
	ball_save_left = 0.0
	table.call("set_flippers_enabled", false)
	ball_tilted.emit()
	message.emit("TILT")


func _on_part_scored(points: int, part: Node) -> void:
	if state != State.PLAYING or tilted:
		return
	_add_score(points)
	if part is Rollover:
		bonus += rollover_bonus
		_check_top_lanes()
	elif part is StandupTarget:
		bonus += standup_bonus
		_check_standups()
	elif part is DropTarget:
		bonus += drop_target_bonus


## All three top lanes lit: advance the bonus multiplier and relight.
func _check_top_lanes() -> void:
	var lanes := _top_lane_rollovers()
	if lanes.is_empty() or lanes.any(func(r): return not r.lit):
		return
	for lane in lanes:
		lane.reset()
	multiplier = mini(multiplier + 1, max_multiplier)
	_add_score(top_lanes_points)
	message.emit("BONUS %d×" % multiplier)


func _check_standups() -> void:
	var targets: Array = table.call("parts_of", StandupTarget)
	if targets.is_empty() or targets.any(func(t): return not t.lit):
		return
	for target in targets:
		target.reset()
	_add_score(standups_points)
	message.emit("TARGETS COMPLETE")


func _top_lane_rollovers() -> Array:
	var lanes: Array = []
	for rollover in table.call("parts_of", Rollover):
		if String(rollover.name).begins_with("TopLane"):
			lanes.append(rollover)
	return lanes


func _reset_table_lights() -> void:
	for type: Variant in [Rollover, StandupTarget]:
		for part in table.call("parts_of", type):
			part.reset()


func _add_score(points: int) -> void:
	if points == 0:
		return
	score += points
	score_changed.emit(score)


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)


# --- High scores -----------------------------------------------------------

func load_high_scores() -> void:
	high_scores.clear()
	var config := ConfigFile.new()
	if config.load(high_score_path) == OK:
		for value in config.get_value("scores", "values", []):
			high_scores.append(int(value))
	high_scores.sort()
	high_scores.reverse()


## Adds a score to the table and returns its rank (1 = best), or 0 when it
## did not make the list.
func record_high_score(value: int) -> int:
	if value <= 0:
		return 0
	high_scores.append(value)
	high_scores.sort()
	high_scores.reverse()
	if high_scores.size() > high_score_count:
		high_scores.resize(high_score_count)
	var rank := high_scores.find(value) + 1
	var config := ConfigFile.new()
	config.set_value("scores", "values", high_scores)
	config.save(high_score_path)
	return rank


func state_name() -> String:
	return State.keys()[state]
