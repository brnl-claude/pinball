extends Node3D
## Prototype table: the physical side of the machine. It serves the ball into
## the shooter lane, reports drains and launches, and relays every part's
## `scored` signal with the part that scored. Game rules live separately in
## `GameRules`; without rules attached the table simply re-serves the ball
## after a drain (sandbox play). Backspace re-serves the ball by hand.
## The table owns a `Cabinet` for nudging and the tilt bob, and a `Replay`
## that records every physics tick (K saves, L plays back).
##
## Multiball: `add_ball()` auto-plunges extra balls through the shooter
## lane, `lock_ball()` takes a ball out of play (a virtual lock). While more
## than one ball is in play a drained ball only emits `ball_lost`;
## `ball_drained` means the last ball is gone. The main ball (`ball`, from
## the scene) always stays in play: when it leaves play while extra balls
## remain, it takes over the state of an extra ball, which is removed.

signal ball_drained
signal ball_launched
## A ball drained while others are still in play.
signal ball_lost(balls_left: int)
signal score_changed(score: int)
signal part_scored(points: int, part: Node)
signal tilt_warning(warnings_left: int)
signal tilted

## Seconds before re-serving after a drain; negative disables auto re-serve.
@export var respawn_delay := 1.0
## Balls with x above this are in the shooter lane.
@export var shooter_lane_x := 0.2
## Most balls in play at once (the main ball plus extras).
@export var max_balls := 4
## Settle time in the shooter lane before an auto-plunge (s).
@export var auto_plunge_delay := 0.3

@onready var ball: Ball = $Ball
@onready var plunger: Plunger = $Plunger
@onready var drain: Drain = $Drain
@onready var left_flipper: Flipper = $LeftFlipper
@onready var right_flipper: Flipper = $RightFlipper

var cabinet: Cabinet
var replay: Replay
var drained_count := 0
## Raw points from all parts since the table loaded (rules keep the game score).
var score := 0
var _in_play: Array[Ball] = []
var _extra_count := 0
## Per ball: whether it was in the shooter lane last tick.
var _in_lane := {}
var _launch_queue := 0
var _auto_plunging: Ball
var _auto_plunge_left := 0.0


func _ready() -> void:
	add_to_group("table")
	cabinet = Cabinet.new()
	cabinet.name = "Cabinet"
	add_child(cabinet)
	cabinet.tilt_warning.connect(tilt_warning.emit)
	cabinet.tilted.connect(_on_tilted)
	replay = Replay.new()
	replay.name = "Replay"
	replay.table = self
	add_child(replay)
	# Deferred: balls leave the table on a drain, which must not happen while
	# the physics server is flushing area queries.
	drain.ball_drained.connect(_on_ball_drained, CONNECT_DEFERRED)
	for node in find_children("*", "", true, false):
		if node.has_signal("scored"):
			node.connect("scored", _on_scored.bind(node))
	serve_ball()


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("reset_ball"):
		serve_ball()
	for b in _in_play:
		var in_lane := b.position.x > shooter_lane_x
		if _in_lane.get(b, false) and not in_lane:
			ball_launched.emit()
		_in_lane[b] = in_lane
	_step_auto_plunge(delta)


## Ends multiball and puts the main ball in the shooter lane for the player.
func serve_ball() -> void:
	_launch_queue = 0
	_auto_plunging = null
	for b in _in_play.duplicate():
		if b != ball:
			_remove_extra(b)
	_in_play = [ball]
	_place_in_lane(ball)


## Balls in play, counting the ones waiting to be auto-plunged.
func balls_in_play() -> int:
	return _in_play.size() + _launch_queue


## Auto-plunges `count` extra balls into play, one at a time through the
## shooter lane, up to `max_balls` in play. Returns how many were added.
func add_ball(count := 1) -> int:
	count = clampi(count, 0, max_balls - balls_in_play())
	_launch_queue += count
	return count


## Takes a ball out of play (a virtual ball lock). The last ball in play
## stays where it is; serve it again with `serve_ball()`.
func lock_ball(locked: Ball) -> void:
	if locked != null and _in_play.has(locked) and _in_play.size() > 1:
		_take_out_of_play(locked)


func _place_in_lane(b: Ball) -> void:
	var radius := b.tuning.scaled_ball_radius() if b.tuning else 0.0135
	b.freeze = false
	b.reset_to(Transform3D(Basis.IDENTITY, plunger.ball_rest_position(radius)))
	drain.rearm(b)
	_in_lane[b] = true


## Removes a ball from play while others remain. The main ball is kept:
## it takes over the position and motion of an extra ball instead.
func _take_out_of_play(b: Ball) -> void:
	if b != ball:
		_remove_extra(b)
		return
	var other: Ball = null
	for candidate in _in_play:
		if candidate != ball:
			other = candidate
			break
	ball.freeze = false
	ball.reset_to(other.global_transform)
	ball.linear_velocity = other.linear_velocity
	ball.angular_velocity = other.angular_velocity
	drain.rearm(ball)
	_in_lane[ball] = _in_lane.get(other, false)
	if _auto_plunging == other:
		_auto_plunging = ball
	_remove_extra(other)


func _remove_extra(b: Ball) -> void:
	_in_play.erase(b)
	_in_lane.erase(b)
	drain.rearm(b)
	if _auto_plunging == b:
		_auto_plunging = null
	b.queue_free()


func _lane_clear() -> bool:
	for b in _in_play:
		if b.position.x > shooter_lane_x:
			return false
	return true


func _step_auto_plunge(delta: float) -> void:
	if _auto_plunging:
		if not _in_play.has(_auto_plunging) or _auto_plunging.position.x <= shooter_lane_x:
			_auto_plunging = null
		else:
			_auto_plunge_left -= delta
			if _auto_plunge_left <= 0.0 and plunger.pull == 0.0:
				plunger.fire()
				# Fire again if the ball rolled back down the lane.
				_auto_plunge_left = 1.5
		return
	if _launch_queue <= 0 or not _lane_clear() or plunger.pull > 0.0:
		return
	_launch_queue -= 1
	if not _in_play.has(ball):
		_in_play.append(ball)
		_place_in_lane(ball)
		_auto_plunging = ball
		_auto_plunge_left = auto_plunge_delay
		return
	_extra_count += 1
	var extra := Ball.new()
	extra.name = "ExtraBall%d" % _extra_count
	extra.tuning = ball.tuning
	add_child(extra)
	_in_play.append(extra)
	_place_in_lane(extra)
	_auto_plunging = extra
	_auto_plunge_left = auto_plunge_delay


func set_flippers_enabled(value: bool) -> void:
	left_flipper.enabled = value
	right_flipper.enabled = value


func set_plunger_enabled(value: bool) -> void:
	plunger.enabled = value


## Flippers, slingshots and pop bumpers: everything a tilt switches off.
func set_solenoids_enabled(value: bool) -> void:
	set_flippers_enabled(value)
	for type: Variant in [Slingshot, PopBumper]:
		for part in parts_of(type):
			part.set("enabled", value)


func reset_tilt() -> void:
	cabinet.reset_tilt()
	set_solenoids_enabled(true)


## All parts of a given class, e.g. `parts_of(Rollover)`.
func parts_of(type: Variant) -> Array[Node]:
	var result: Array[Node] = []
	for node in find_children("*", "", true, false):
		if is_instance_of(node, type):
			result.append(node)
	return result


func _on_scored(points: int, part: Node) -> void:
	score += points
	score_changed.emit(score)
	part_scored.emit(points, part)


func _on_tilted() -> void:
	set_solenoids_enabled(false)
	tilted.emit()


func _on_ball_drained(drained: Ball) -> void:
	if not _in_play.has(drained):
		return
	if balls_in_play() > 1:
		if _in_play.size() > 1:
			_take_out_of_play(drained)
		elif drained != ball:
			_remove_extra(drained)
		else:
			# Only queued balls are left: the main ball becomes the next one.
			_in_play.erase(ball)
		ball_lost.emit(balls_in_play())
		return
	drained_count += 1
	ball_drained.emit()
	if respawn_delay >= 0.0:
		if cabinet.is_tilted:
			reset_tilt()
		get_tree().create_timer(respawn_delay, true, true).timeout.connect(serve_ball)
