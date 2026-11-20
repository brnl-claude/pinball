# Pinball

A 3D pinball game with realistic physics and graphics, built with [Godot 4](https://godotengine.org) and its built-in Jolt physics. The plan and roadmap are in [PLAN.md](PLAN.md).

## Getting started

1. Install **Godot 4.7.2** (standard build, not .NET). On Fedora you can use Flathub (`org.godotengine.Godot`) or unpack the binary from godotengine.org.
2. Open `project.godot` in the editor and press F5.

From the command line:

```sh
godot --path . main.tscn                                       # play
godot --path . --headless --script res://tests/smoke_test.gd   # smoke test
godot --path . --headless --fixed-fps 1000 --script res://tests/physics_test.gd   # physics test
godot --path . --headless --fixed-fps 1000 --script res://tests/table_test.gd     # table parts test
godot --path . --headless --fixed-fps 1000 --script res://tests/rules_test.gd     # game rules test
```

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Left / right flipper | Left / right Shift | LB / RB |
| Plunger (hold to pull, release to launch) | Enter | A |
| Nudge left / right / up | Z / `/` / Space | – |
| Start game | 1 | Start |
| Pause | Esc | Back |
| Switch camera | C | – |
| Re-serve ball | Backspace | – |
| Debug overlay | F3 | – |

## Game rules

Press **1** to start a game: 3 balls, an 8-second ball save after each launch, and an end-of-ball bonus. Rollovers, standups and drop targets add to the bonus; lighting all three top lanes advances the bonus multiplier (up to 5×), and lighting all three standups scores 5,000.

**Nudging and tilt:** Z, `/` and Space shove the cabinet from the left, from the right and from the front. The ball reacts to the cabinet's motion, and a cradled ball can be bumped off a flipper. A tilt bob swings with every shove: the first two times it touches its ring you get a DANGER warning, the third time the ball tilts. A tilted ball loses its flippers, coils, scoring, ball save and bonus; the next ball starts normally. Press F3 to see the bob's swing.

The top 5 scores are saved in `user://high_scores.cfg`.

## Settings (Phase 0)

- Physics: Jolt, 1000 Hz, max. 32 steps per frame, physics interpolation on.
- Rendering: Vulkan, Forward+.
- Linux: native Wayland display server.
- The window scales to any aspect ratio (stretch `canvas_items`, aspect `expand`).

## Folders

| Folder | Contents |
|---|---|
| `core/` | tick loop, settings, input |
| `physics/` | physics tuning |
| `table_parts/` | reusable table parts, including the cabinet (nudge and tilt) |
| `tables/` | tables |
| `rules/` | game rules |
| `cameras/` | camera rigs and layout profiles |
| `ui/` | HUD, menus, debug overlay |
| `tests/` | CI smoke tests |

## CI

On every push and PR, GitHub Actions imports the project, runs the smoke, physics, table and rules tests (results in the run summary) and builds a Linux export, which can be downloaded as an artifact from the run.
