# Pinball

A 3D pinball game with realistic physics and graphics, built with [Godot 4](https://godotengine.org) and its built-in Jolt physics. The plan and roadmap are in [PLAN.md](PLAN.md).

## Getting started

1. Install **Godot 4.7.2** (standard build, not .NET). On Fedora you can use Flathub (`org.godotengine.Godot`) or unpack the binary from godotengine.org.
2. Open `project.godot` in the editor and press F5.

From the command line:

```sh
godot --path . main.tscn                                       # play
godot --path . --headless --script res://tests/smoke_test.gd   # smoke test
```

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Left / right flipper | Left / right Shift | LB / RB |
| Plunger | Enter | A |
| Nudge left / right / up | Z / `/` / Space | – |
| Start | 1 | Start |
| Pause | Esc | Back |
| Switch camera | C | – |
| Debug overlay | F3 | – |

## Settings (Phase 0)

- Physics: Jolt, 1000 Hz, max. 32 steps per frame, physics interpolation on.
- Rendering: Vulkan, Forward+.
- Linux: native Wayland display server.
- The window scales to any aspect ratio (stretch `canvas_items`, aspect `expand`).

## Folders

| Folder | Contents |
|---|---|
| `core/` | tick loop, settings, input |
| `physics/` | ball, flippers, nudge/tilt |
| `table_parts/` | reusable table parts |
| `tables/` | tables |
| `rules/` | game rules |
| `cameras/` | camera rigs and layout profiles |
| `ui/` | HUD, menus, debug overlay |
| `tests/` | CI smoke tests |

## CI

On every push and PR, GitHub Actions imports the project, runs the smoke test and builds a Linux export, which can be downloaded as an artifact from the run.
