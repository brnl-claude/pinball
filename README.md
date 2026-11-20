# Pinball

A 3D pinball game with realistic physics and graphics, built with [Godot 4](https://godotengine.org) and its built-in Jolt physics. The plan and roadmap are in [PLAN.md](PLAN.md).

## Getting started

1. Install **Godot 4.7.2** (standard build, not .NET). On Fedora you can use Flathub (`org.godotengine.Godot`) or unpack the binary from godotengine.org.
2. Open `project.godot` in the editor and press F5, or start the game without the editor (below).

### Running from the command line

Run these from the repository folder. Without the editor, the editor's debugger keys (F7–F12) do not apply.

```sh
# Godot from Flathub
flatpak run org.godotengine.Godot --path .

# Godot binary from godotengine.org (adjust the file name)
~/Applications/Godot_v4.7.2-stable_linux.x86_64 --path .

# Useful flags: full screen, or a fixed window size to try an aspect ratio
flatpak run org.godotengine.Godot --path . --fullscreen
flatpak run org.godotengine.Godot --path . --resolution 1080x1920
```

Each CI run also uploads a ready-made Linux build (`pinball-linux`, under the run's Artifacts on GitHub). Unzip it and start `./pinball.x86_64`; no Godot install needed.

Tests (`godot` stands for either command above):

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
| Magna-save (left outlane magnet) | Left Ctrl | X |
| Pause and settings (slope, difficulty, balls, screen) | Esc | Back |
| Switch camera profile (auto, portrait, landscape, ultrawide, top-down) | C | – |
| Rotate screen 0/90/180/270° (monitor turned upright in a cabinet) | R | – |
| Render scale: native, or FSR 2 at 77/67/59/50% | V | – |
| Save the last 30 s as a replay / play the newest replay back | K / L | – |
| Re-serve ball | Backspace | – |
| Debug overlay | F3 | – |

## Game rules

Press **1** to start a game: 3 balls, an 8-second ball save after each launch, and an end-of-ball bonus. Rollovers, standups and drop targets add to the bonus; lighting all three top lanes advances the bonus multiplier (up to 5×), and lighting all three standups scores 5,000.

**Nudging and tilt:** Z, `/` and Space shove the cabinet from the left, from the right and from the front. The ball reacts to the cabinet's motion, and a cradled ball can be bumped off a flipper. A tilt bob swings with every shove: the first two times it touches its ring you get a DANGER warning, the third time the ball tilts. A tilted ball loses its flippers, coils, scoring, ball save and bonus; the next ball starts normally. Press F3 to see the bob's swing.

The top 5 scores are saved in `user://high_scores.cfg`.

Function keys F7–F12 are left alone on purpose: when the game runs from the Godot editor, the editor's debugger uses them (F8 stops the running game).

## Screen layouts

The camera picks a layout profile from the aspect ratio:

| Profile | Aspect ratio | Camera | Score |
|---|---|---|---|
| Portrait / cabinet | below 1:1 (9:16, 3:4) | steep, 62° | bar at the top |
| Landscape | 1:1 to 2.6:1 (16:9, 21:9) | tilted, 38° | column right of the table |
| Ultrawide | 2.6:1 and wider (32:9) | tilted, 40° | score left, info right |
| Top-down | manual (C) | straight down | bar at the top |

R rotates the whole picture for a landscape monitor turned upright, without telling the OS: use 90° when the monitor's top edge points left and 270° when it points right. The setting is saved in `user://settings.cfg`, and the profile is then picked from the rotated aspect ratio. Presets are `CameraPreset` resources, so a table can bring its own.

## Replays (debugging)

The table records every physics tick into a 30-second ring buffer: ball position, rotation and velocities, both flippers, the plunger, the coil inputs and the cabinet's nudge offset. K saves it to `user://replays/` (on Linux `~/.local/share/godot/app_userdata/Pinball/replays/`), and L plays the newest file back so a physics bug can be watched again with F3 open. Playback drives the ball and parts straight from the recording.

## Graphics

- PBR finishes from `TableMaterials`: clear-coated playfield, wood-grain cabinet walls, polished steel guides, matte rubbers and glossy plastic inserts and caps. Textures are procedural for now, so there are no asset files yet.
- A chrome ball that mirrors a box-projected reflection probe over the table.
- Lit inserts and flashing caps glow above the HDR threshold, so they bloom.
- Warm and cool fill lights, SSAO, SSIL and SSR.
- V lowers the render scale with AMD FSR 2 upscaling when 7680×2160 at 120 fps needs headroom. The setting is saved in `user://settings.cfg`.
- Baked lightmaps (LightmapGI) wait until the table geometry is final, because baking needs the editor and a GPU.

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
