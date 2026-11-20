class_name PhysicsTuning
extends Resource
## Physics tunables for a table. All lengths are real-world meters and are
## multiplied by `world_scale`, so the same tuning can be tested at real
## scale and scaled up.

@export_group("World")
## Multiplier for every length (and therefore for gravity). 1.0 = real scale.
@export var world_scale := 1.0
## Playfield slope in degrees. Real machines are typically 6–7°.
@export_range(3.0, 10.0, 0.1) var slope_degrees := 6.5
## Gravitational acceleration in m/s² (before scaling).
@export var gravity := 9.81

@export_group("Ball")
## Ball radius in meters (standard ball: 27 mm diameter).
@export var ball_radius := 0.0135
## Ball mass in kg (standard ball: ~80 g).
@export var ball_mass := 0.08
@export_range(0.0, 1.0) var ball_friction := 0.3
@export_range(0.0, 1.0) var ball_bounce := 0.3

@export_group("Playfield")
@export_range(0.0, 1.0) var playfield_friction := 0.3


func scaled_ball_radius() -> float:
	return ball_radius * world_scale


## Gravity in table space: the playfield is the XZ plane with +Y up and the
## drain at +Z. Instead of tilting the geometry we tilt gravity, so the ball
## accelerates toward the drain with g·sin(slope).
func gravity_vector() -> Vector3:
	var slope := deg_to_rad(slope_degrees)
	var g := gravity * world_scale
	return Vector3(0.0, -g * cos(slope), g * sin(slope))
