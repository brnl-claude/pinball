extends Node
## Placeholder sound effects, synthesized at startup so the project needs no
## audio assets yet. Call `Sfx.play("bumper")` from anywhere.

const MIX_RATE := 22050
const VOICES := 12

## name: [frequency Hz, duration s, noise 0–1, decay 1/s, volume 0–1]
const SOUNDS := {
	"flipper": [90.0, 0.08, 0.6, 45.0, 0.8],
	"slingshot": [160.0, 0.09, 0.5, 40.0, 0.8],
	"bumper": [220.0, 0.14, 0.35, 28.0, 0.9],
	"target": [520.0, 0.07, 0.3, 55.0, 0.6],
	"drop": [140.0, 0.12, 0.7, 30.0, 0.7],
	"bank_reset": [110.0, 0.2, 0.8, 18.0, 0.7],
	"rollover": [880.0, 0.06, 0.1, 60.0, 0.4],
	"plunger": [70.0, 0.15, 0.7, 25.0, 0.8],
	"drain": [55.0, 0.4, 0.5, 8.0, 0.6],
}

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for sound_name: String in SOUNDS:
		var spec: Array = SOUNDS[sound_name]
		_streams[sound_name] = _synthesize(spec[0], spec[1], spec[2], spec[3], spec[4])
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


func play(sound_name: String) -> void:
	if not _streams.has(sound_name) or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[sound_name]
	player.play()


func _synthesize(frequency: float, duration: float, noise: float, decay: float,
		volume: float) -> AudioStreamWAV:
	var samples := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(frequency * 1000.0)
	for i in samples:
		var t := float(i) / MIX_RATE
		var tone := sin(TAU * frequency * t) * (1.0 - noise) + rng.randf_range(-1.0, 1.0) * noise
		var value := clampf(tone * exp(-t * decay) * volume, -1.0, 1.0)
		data.encode_s16(i * 2, int(value * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
