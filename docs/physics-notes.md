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

- Godot (and its Jolt module) **adds** the bounce of both bodies, clamped to 1. The first flipper rubber test measured 0.93 where the model asked 0.71, because the ball's own bounce (0.3) was added. The flipper therefore subtracts the ball's bounce when it sets its own.
- Box shapes use a 1 mm collision margin (Godot's default is 4 cm), so thin walls and guides are not rounded off.
- The ball has `can_sleep = false` and no damping; gravity is applied as a constant force so the table slope lives in `PhysicsTuning`.

## Phase 2 results

From `tests/table_test.gd` on the prototype table:

| Test | Result |
|---|---|
| Flipper stroke | up in 33 ms, back to rest in 37 ms (real flippers: ~30–50 ms) |
| Flipper shot (ball rolling down a resting flipper, hit at mid-length) | peak 3.55 m/s straight up the table |
| Cradle (ball dropped near the tip of a raised flipper) | settles after 3 s at 0.007 m/s, 29 mm from the pivot, no drain |
| Plunger at 100% | ball leaves the shooter lane and reaches the top arc |
| Plunger at 10% | ball rolls back without leaving the lane |
| Ball in the left outlane | drains once |

Tuning notes:

- Flipper shots are on the soft side; real machines reach roughly 4–6 m/s off the sweet spot. Raise `up_max_speed` or the rubber `bounce` when the first ramp needs it, or move to the custom contact impulse planned for Phase 5.
- The drain reports each ball once until it is served again, because a drained ball can bounce in and out of the drain area.

## Nudge and tilt (Phase 5)

The playfield is the physics frame, so a nudge is modelled as the cabinet accelerating underneath the ball (`table_parts/cabinet.gd`). The ball feels the inertial force `-m·a` on top of gravity:

- **Shove:** 15 m/s² for 20 ms, so the cabinet reaches 0.3 m/s. It then settles back on its legs as a damped spring (4 Hz, damping ratio 0.7) and moves about 6 mm in total. The camera stays put, so the table jolts on screen.
- **Effect on the ball:** a free ball lags behind the shove and catches up again. A ball resting on a flipper or post is carried by it and leaves it as the cabinet settles. That is the useful part of a real nudge.
- **Tilt bob:** a 15 cm pendulum (period 0.78 s) with 4.5 cm clearance to the ring and a damping of 1/s. It is driven by the shove only, not by the gentle settle back. One shove swings it about 3.7 cm. Shoves in step with its swing build it up: 3 shoves 0.78 s apart touch the ring three times, which is 2 warnings and a tilt. In a simulation of 10 shoves at random 0.2–0.6 s intervals, 60% gave a warning and 16% tilted.

All values are exports on `Cabinet` and will be tuned by feel.

## Flipper refinement (Phase 5b)

- **EOS switch and hold winding:** above 92% of the stroke only the hold winding pulls (500 rad/s² instead of 1600). A ball that hits a raised flipper pushes it back with its impulse, `Δω = (r × F)·Δt / I`, with an effective inertia of 0.004 kg·m² for bat, crank and coil plunger. The hit is found from the ball's change in velocity near the bat, not from the contact event, because Jolt's speculative contacts can resolve a hit a few ticks before the ball touches.
- **Speed-dependent rubber:** `e = 0.75 / (1 + 0.12 · v)`, which gives 0.71 at 0.5 m/s, 0.61 at 2 m/s and 0.51 at 4 m/s. Each tick the flipper sets its bounce from the nearest ball's approach speed, relative to the bat's own surface speed, so Jolt's solver applies it, including to a ball already resting on the bat.
