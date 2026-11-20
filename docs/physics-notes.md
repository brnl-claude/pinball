# Physics notes

Measurements and decisions from the physics test suite (`tests/physics_test.gd`, run in CI on every push). Numbers below are from Godot 4.7.2 with Jolt at 1000 Hz.

## Phase 1 results

### Tunneling

1000 balls fired at 8–20 m/s, at angles up to ±60°, into a 5 mm wall.

| Scale | CCD | Tunneled |
|---|---|---|
| ×1 (real) | on | 0 / 1000 |
| ×1 (real) | off | 0 / 1000 |
| ×10 | on | 0 / 1000 |
| ×10 | off | 3 / 1000 |

At 1000 Hz and real scale the ball travels at most 20 mm per tick, less than the ball diameter plus the wall thickness (32 mm), so even without CCD nothing tunnels. CCD stays on as a safety net for faster shots and thinner parts.

### Rolling

A ball released on the 6.5° playfield should accelerate at 5/7 · g · sin(6.5°) = 0.793 m/s² (solid sphere rolling without slipping).

| Scale | Measured | Error | Spin/speed | Resting penetration |
|---|---|---|---|---|
| ×1 (real) | 0.771 m/s² | −2.8% | 1.06 | 0.27 mm |
| ×10 | 7.929 m/s² | −0.0% | 1.00 | 0.02 mm |

## Decision: real scale

We keep real-world meters (`world_scale = 1.0`). Real scale passes every test, scaling up gives no tunneling benefit at 1000 Hz, and real units keep tuning values (ball mass, speeds, slopes) directly comparable to real machines. The slightly lower acceleration (−2.8%) and 0.27 mm resting penetration at real scale are within tolerance; we revisit them when the custom contact model arrives in Phase 5.

## Jolt settings that matter for pinball

| Setting | Default | Ours | Why |
|---|---|---|---|
| `limits/max_angular_velocity` | 47.1 rad/s | 3000 rad/s | The default caps a rolling 27 mm ball at ~0.64 m/s. The first test run caught this: acceleration was −59% and the ball topped out at 0.60 m/s. A ball at 20 m/s spins at ~1500 rad/s. |
| `simulation/penetration_slop` | 0.02 m | 0.002 m | 2 cm of allowed penetration is more than the ball's radius. |
| `simulation/bounce_velocity_threshold` | 1.0 m/s | 0.2 m/s | Below this speed contacts don't bounce at all; 1 m/s would make slow hits against rubbers feel dead. |

Other notes:

- Box shapes use a 1 mm collision margin (Godot's default is 4 cm), so thin walls and guides are not rounded off.
- The ball has `can_sleep = false` and no damping; gravity is applied as a constant force so the table slope lives in `PhysicsTuning`.
