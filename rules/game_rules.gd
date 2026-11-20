class_name GameRules
extends Node
## Game rules for a table: games, balls, ball save, bonus, tilt, high
## scores, ball lock and multiball, and timed modes.
##
## Ball lock (virtual): making a ramp lights the lock at the saucer. A ball
## that stops in a lit saucer is locked: it leaves play and a new ball is
## served. Once `locks_for_multiball` balls are locked, the next lock starts
## multiball instead: the saucer kicks the ball out and the locked balls are
## auto-plunged. During multiball every ramp scores a jackpot that grows.
##
## Modes: the saucer starts the next mode in `MODES` when the lock is not
## lit and no mode runs. For `mode_seconds` the mode's shots score extra.
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
signal lock_lit_changed(lit: bool)
signal ball_locked(locked: int)
signal multiball_started(ball_count: int)
signal multiball_ended
signal jackpot_scored(points: int)
signal mode_started(mode_name: String)
signal mode_ended(mode_name: String, total: int)

enum State { ATTRACT, PLAYING, BALL_ENDING, GAME_OVER }

## Timed modes, started in turn at the saucer. `shot` is the part kind that
## scores `points` extra while the mode runs (see `_shot_kind`).
const MODES: Array[Dictionary] = [
	{"name": "RAMP FRENZY", "shot": "ramp", "points": 10000},
	{"name": "SPINNER SPREE", "shot": "spinner", "points": 1000},
	{"name": "BUMPER BLAST", "shot": "bumper", "points": 2500},
]

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

@export_group("Multiball")
## Balls to lock; the lock after them starts multiball with them all.
@export var locks_for_multiball := 2
@export var lock_points := 5000
## How long a ball sits in the saucer before it is locked (s).
@export var lock_hold_seconds := 1.0
## Ball save at the start of multiball (s): drained balls are auto-plunged again.
@export var multiball_save_seconds := 10.0
@export var jackpot_start := 25000
@export var jackpot_step := 10000

@export_group("Modes")
@export var mode_seconds := 30.0
@export var mode_start_points := 2500

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
var saucer: Saucer

var lock_lit := false
## Balls locked toward the next multiball.
var locked := 0
var multiball := false
var jackpot := 0
## Index into MODES of the running mode, or -1.
var mode := -1
var mode_time_left := 0.0
var mode_total := 0
var next_mode := 0

var _state_time_left := 0.0
var _ball_in_play := false
## Seconds until the ball in the saucer is locked; > 0 while one waits.
var _lock_time_left := 0.0


func _ready() -> void:
	add_to_group("rules")
	table = get_node_or_null(table_path)
	if table == null:
		push_error("GameRules needs a table_path")
		return
	var settings := get_node_or_null("/root/GameSettings")
	if settings:
		apply_settings(settings)
	table.set("respawn_delay", -1.0)
	table.connect("part_scored", _on_part_scored)
	table.connect("ball_drained", _on_ball_drained)
	table.connect("ball_launched", _on_ball_launched)
	if table.has_signal("tilted"):
		table.connect("tilt_warning", _on_tilt_warning)
		table.connect("tilted", _on_tilted)
	if table.has_signal("ball_lost"):
		table.connect("ball_lost", _on_ball_lost)
	var saucers: Array = table.call("parts_of", Saucer)
	if not saucers.is_empty():
		saucer = saucers[0]
		saucer.ball_captured.connect(_on_saucer_captured)
	load_high_scores()
	_enter_attract()


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("start_game") and state != State.PLAYING \
			and state != State.BALL_ENDING:
		start_game()

	if ball_save_left > 0.0:
		ball_save_left = maxf(ball_save_left - delta, 0.0)

	if _lock_time_left > 0.0:
		_lock_time_left -= delta
		if _lock_time_left <= 0.0:
			_resolve_lock()

	if mode >= 0 and state == State.PLAYING:
		mode_time_left -= delta
		if mode_time_left <= 0.0:
			_end_mode()

	if _state_time_left > 0.0:
		_state_time_left -= delta
		if _state_time_left <= 0.0:
			match state:
				State.BALL_ENDING:
					_finish_ball()
				State.GAME_OVER:
					_enter_attract()


## Applies the game settings (GameSettings autoload): balls per game and
## the difficulty's ball save time.
func apply_settings(settings: Node) -> void:
	balls_per_game = settings.get("balls_per_game")
	ball_save_seconds = settings.call("preset")["ball_save_seconds"]


func start_game() -> void:
	score = 0
	ball_number = 0
	locked = 0
	next_mode = 0
	jackpot = jackpot_start
	_set_lock_lit(false)
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
	_lock_time_left = 0.0
	multiball = false
	tilted = false
	if table.has_method("reset_tilt"):
		table.call("reset_tilt")
	table.call("serve_ball")
	table.call("set_flippers_enabled", true)
	_set_plunger_enabled(true)
	ball_started.emit(ball_number)
	message.emit("BALL %d" % ball_number)


func _on_ball_launched() -> void:
	if state == State.PLAYING and not _ball_in_play:
		_ball_in_play = true
		ball_save_left = ball_save_seconds


func _on_ball_drained() -> void:
	if state != State.PLAYING:
		return
	multiball = false
	if mode >= 0 and (tilted or ball_save_left <= 0.0):
		_end_mode()
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
	_set_plunger_enabled(false)
	var rank := record_high_score(score)
	_set_state(State.GAME_OVER)
	_state_time_left = game_over_seconds
	game_over.emit(score, rank)
	message.emit("NEW HIGH SCORE" if rank == 1 else "GAME OVER")


func _enter_attract() -> void:
	if mode >= 0:
		_end_mode()
	_set_lock_lit(false)
	table.call("set_flippers_enabled", false)
	_set_plunger_enabled(false)
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


## The plunger only works while a game is running.
func _set_plunger_enabled(value: bool) -> void:
	if table.has_method("set_plunger_enabled"):
		table.call("set_plunger_enabled", value)


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
	var kind := _shot_kind(part)
	if mode >= 0 and kind == MODES[mode]["shot"]:
		var extra: int = MODES[mode]["points"]
		mode_total += extra
		_add_score(extra)
	if kind == "ramp":
		_on_ramp_made()


## What kind of shot a part is, for modes and the lock: "ramp" (a ramp's
## made switch), "spinner", "bumper", or "".
static func _shot_kind(part: Node) -> String:
	if part is Spinner:
		return "spinner"
	if part is PopBumper:
		return "bumper"
	if part is BallSwitch and String(part.name).contains("Ramp"):
		return "ramp"
	return ""


# --- Ball lock and multiball -------------------------------------------------

func _on_ramp_made() -> void:
	if multiball:
		_add_score(jackpot)
		jackpot_scored.emit(jackpot)
		message.emit("JACKPOT %d" % jackpot)
		jackpot += jackpot_step
	elif not lock_lit and saucer:
		_set_lock_lit(true)
		message.emit("LOCK IS LIT")


## A lit saucer keeps its ball, so the rules decide what happens to it.
func _set_lock_lit(value: bool) -> void:
	lock_lit = value
	if saucer:
		saucer.auto_eject = not value
	lock_lit_changed.emit(value)


func _on_saucer_captured(_ball: Ball) -> void:
	if lock_lit:
		# The saucer keeps the ball; `_resolve_lock` locks or ejects it.
		_lock_time_left = lock_hold_seconds
		return
	if state != State.PLAYING or tilted:
		return
	if mode < 0 and not multiball:
		_start_mode()


func _resolve_lock() -> void:
	if saucer == null or saucer.held == null:
		return
	if state != State.PLAYING or tilted:
		saucer.eject()
		return
	_set_lock_lit(false)
	_add_score(lock_points)
	if locked >= locks_for_multiball:
		_start_multiball()
		return
	locked += 1
	var held := saucer.take_ball()
	table.call("lock_ball", held)
	table.call("serve_ball")
	_ball_in_play = false
	ball_locked.emit(locked)
	message.emit("BALL %d LOCKED" % locked)


func _start_multiball() -> void:
	var extra: int = table.call("add_ball", locked)
	locked = 0
	multiball = true
	saucer.eject()
	ball_save_left = multiball_save_seconds
	multiball_started.emit(extra + 1)
	message.emit("MULTIBALL")


## A ball drained while others are still in play.
func _on_ball_lost(balls_left: int) -> void:
	if state != State.PLAYING or not multiball:
		return
	if ball_save_left > 0.0 and not tilted:
		table.call("add_ball", 1)
		ball_saved.emit()
		message.emit("BALL SAVED")
		return
	if balls_left <= 1:
		multiball = false
		multiball_ended.emit()
		message.emit("MULTIBALL OVER")


# --- Modes -------------------------------------------------------------------

func _start_mode() -> void:
	mode = next_mode
	next_mode = (next_mode + 1) % MODES.size()
	mode_time_left = mode_seconds
	mode_total = 0
	_add_score(mode_start_points)
	mode_started.emit(MODES[mode]["name"])
	message.emit(MODES[mode]["name"])


func _end_mode() -> void:
	var mode_name: String = MODES[mode]["name"]
	mode = -1
	mode_time_left = 0.0
	mode_ended.emit(mode_name, mode_total)
	message.emit("%s TOTAL %d" % [mode_name, mode_total])


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
