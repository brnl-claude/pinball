# Pinball – Project Plan

Goal: a 3D pinball game in the style of Pinball FX / Zaccaria Pinball, with believable physics (flippers, slingshots, bumpers, nudge/tilt), built on an open source engine. This document picks the engine, explains where pinball physics gets hard, describes the controls, and lays out a phased roadmap to a first playable prototype.

> Status: approved. Phases 0 and 1 are done; Phase 2 (flippers and plunger) is in progress.

**Priorities:** (1) realistic physics, (2) realistic graphics, (3) runs smoothly on Linux.

**Target system:** Fedora 44, KDE Plasma 6 on Wayland, AMD Ryzen 7 5800X, NVIDIA RTX 3090, 57" 32:9 display at 7680×2160 @ 120 Hz. Must also work well on a vertical 9:16 display. Goal: a stable 120 fps at native or near-native resolution.

---

## 1. Recommendation in short

**Godot 4 (currently 4.7.2) with the built-in Jolt Physics backend.**

- Fully open source (MIT), no royalties, no account required.
- Jolt has been built in since Godot 4.4: fast, stable rigid-body physics with continuous collision detection (CCD), exactly what a small, fast ball needs.
- A real editor: tables can be assembled visually (walls, ramps, bumpers as reusable scenes) instead of everything in code.
- The physics tick rate is freely configurable (e.g. 480–1000 Hz), independent of the frame rate.
- Scripting in GDScript (fast iteration) or C#; performance-critical code later in C++/Rust via GDExtension.
- Exports to Windows, macOS, Linux, Android, iOS and (with limitations) web.
- **Linux is first-class**: the editor and games run natively on Linux (Vulkan), with native Wayland support. Godot is also on Flathub.

The most important architectural decision is independent of the engine: **we treat ball physics as "our" component**. We start with Jolt, but keep the code structured so the ball-vs-table simulation can later be replaced by a custom solver (as Visual Pinball does) if Jolt falls short on details. See §3.

---

## 2. Engine comparison

| Engine | License | Language | Physics | Editor | Strengths | Weaknesses for this project |
|---|---|---|---|---|---|---|
| **Godot 4 + Jolt** | MIT | GDScript, C#, C++ (GDExtension) | Jolt (built in), CCD, free tick rate | Yes, mature | Fast prototyping, editor for table building, large community, lightweight install | Renderer less "AAA" than Unreal; Pinball FX-level visuals need shader/lighting work |
| **Bevy** | MIT/Apache-2.0 | Rust (ECS) | Avian or Rapier (plugins) | No (no official editor yet) | Modern architecture, Rust performance, can be made deterministic | Breaking changes every release, building tables without an editor is slow, smaller ecosystem |
| **O3DE** | Apache-2.0 | C++, Lua, Script Canvas | PhysX 5 | Yes | Strong renderer, PhysX | Heavy (large install, long builds), steep learning curve, small community: lots of overhead for a solo project |
| **Stride** | MIT | C# | Bepu Physics v2 | Yes (mainly Windows) | Pleasant C# engine, good physics | Small community, Windows-centric editor, fewer tutorials and assets |
| **three.js** | MIT | JavaScript/TypeScript | None; integrate yourself (Rapier WASM, cannon-es, Ammo) | No | Runs directly in the browser, easy to share | Only a renderer: game loop, input, audio, physics integration and tooling are all on you |

For reference (not open source, or not meant as an engine):

- **Unity / Unreal**: very capable and widely used for commercial pinball games, but not open source and subject to license terms.
- **Visual Pinball X (VPX)**: an open source pinball simulator with its own physics engine, tuned over many years. Not an engine to build on, but the best **reference** for solving ball/flipper physics. Note: the VPX license does not allow free reuse for commercial purposes, so we read it as a source of ideas and do not copy code.

### Graphics and Linux per engine

| Engine | Renderer | Linux |
|---|---|---|
| Godot 4 | Vulkan (Forward+): PBR, SDFGI/VoxelGI, baked lightmaps, SSR, SSAO/SSIL, volumetric fog, FSR 2 | Editor and export native, Wayland native |
| Bevy | wgpu (Vulkan): PBR, experimental ray-traced GI | Good |
| O3DE | Atom (Vulkan): strongest renderer of the open source options, including ray tracing | Supported, but heavy to build and maintain |
| Stride | Vulkan/DirectX | Runtime yes, editor Windows only |
| three.js | WebGL/WebGPU in the browser | Via the browser; less compute and more latency than native |

Godot does not (yet) have hardware ray tracing. For a pinball table that is not a big loss: it is a small, mostly static scene, and **baked lightmaps, reflection probes and good PBR materials** are exactly the techniques that look realistic at low cost there. See §5.

### Why Godot and not the others

- **Bevy** is attractive if you want Rust and maximum control, but without an editor, building and tuning a table with dozens of parts is much slower. That is exactly the work that takes the most time in pinball.
- **O3DE** and **Stride** are capable, but their communities and documentation are much smaller, which is costly on a first project.
- **three.js** is a good choice if "playable in the browser" is the main goal. You do end up building an engine around it. Godot can also export to web later, so that option stays open.

---

## 3. Pinball physics: what matters

Pinball is unusual for a physics engine: one small, heavy, extremely fast object (the ball) against lots of static geometry and a few very fast moving parts (flippers). That calls for specific choices.

### 3.1 Scale and units

Real-world dimensions as the baseline:

| Quantity | Value |
|---|---|
| Ball | 27 mm diameter (1-1/16"), ~80 g, steel |
| Playfield | ~51 × 107 cm (width × length) |
| Table slope | ~6.5° (configurable, typically 6–7°) |
| Flipper | ~7.6 cm (3") long |
| Ball speed | up to ~5–10 m/s after a good flipper shot |

Two options, to be measured in Phase 1:

1. **Real scale (meters)**: everything is physically correct. Risk: a ball with a 13.5 mm radius is small for physics engines; collision margins and sleep thresholds need to go down.
2. **Scaled up (e.g. ×10)**: more stable contacts; gravity scales along (×10).

**Decided (Phase 1): real scale.** It passes all tunneling and rolling tests; scaling up gave no benefit. See [docs/physics-notes.md](docs/physics-notes.md).

### 3.2 High tick rate and substeps

At 60 Hz, a ball moving at 10 m/s travels ~17 cm per frame: more than six times its own diameter. The ball then passes through thin walls or flippers ("tunneling"), and flipper contact becomes unpredictable.

- Physics fixed at **480–1000 Hz** (`physics/common/physics_ticks_per_second`), independent of the render frame rate. At 1000 Hz that is ~1 cm per step.
- Raise `max_physics_steps_per_frame` so the simulation doesn't fall behind at lower frame rates.
- Interpolate rendering between physics steps (Godot physics interpolation) so the ball looks smooth.
- The cost is low: there is only one dynamic ball (a few during multiball).

### 3.3 CCD for the ball

- Continuous collision detection on for the ball (`continuous_cd = true`). Jolt then performs a sweep and never misses a contact between two steps.
- High tick rate and CCD combined: the tick rate for accurate contact behavior, CCD as a safety net.
- Don't model walls ultra-thin; keep collision shapes simple (boxes, convex hulls, and concave trimeshes only for ramps).

### 3.4 Flipper impulse model

The flipper is the heart of the game feel. A realistic flipper:

- Rotates from rest to the end position (~50–60° stroke) in ~30–50 ms, reaching a high angular velocity.
- Gives the ball an impulse that depends on **where** the ball hits: the surface velocity is `ω × r`, so the tip hits harder than the base.
- Has a rubber with **velocity-dependent restitution**: soft collisions are "dead" (the ball stops, enabling catches/cradles), hard collisions bounce more.
- Supports the well-known techniques: cradle, post pass, dead flip/drop catch, tap pass, live catch.

Two-step approach:

1. **Prototype**: the flipper as an `AnimatableBody3D` (kinematic) that we rotate ourselves every physics tick with a simple motor model (acceleration, max angular velocity, end stop with slight rebound). Jolt computes the contacts with the correct surface velocity.
2. **Refinement**: custom ball-flipper contact handling: we compute the impulse ourselves (relative velocity at the contact point, restitution as a function of impact speed, friction for spin) and drive the ball directly. This is also where VPX has most of its tuning.

In addition, EOS behavior (end-of-stroke: a weaker "hold" force while the flipper is held up) and a small chance of "flipper bounce" give the authentic feel.

### 3.5 Ball: rolling, spin and friction

- The ball is almost always rolling; a sliding-to-rolling transition and rolling friction make its motion believable.
- Spin is subtle but visible on ramps and flipper shots (rolling along the flipper).
- Ball-ball collisions (multiball) are nearly perfectly elastic (steel on steel).
- Disable sleeping for the ball, otherwise it gets stuck on flat spots.

### 3.6 Table slope

- Don't tilt the table; tilt **gravity** instead (`g · sin(6.5°)` along the playfield, `g · cos(6.5°)` into it). That keeps the geometry simple and makes the slope a tunable parameter.
- Visually, the camera can still show the slope.

### 3.7 Active elements

| Element | Model |
|---|---|
| Slingshots | On contact above a speed threshold, an extra impulse perpendicular to the rubber |
| Pop bumpers | On contact, a fixed radial impulse outward (plus light/sound) |
| Kickers/scoops | Capture the ball, hold briefly, eject along a fixed vector |
| Drop targets / standup targets | Area or contact detection; drop targets drop away (collision off) |
| Spinners, gates | Simple rotation model, gates are one-way |
| Ramps, wire ramps | Concave meshes; watch the transitions (no "bumps" between segments) |
| Magnets | Force toward a point within a radius |

### 3.8 Nudge and tilt

- **Nudge** = bumping the cabinet. Physically, the table moves and the ball does not follow immediately. We model it as a short, opposite acceleration on the ball (plus a visual camera/table shake). Directions: left, right, up (forward).
- **Tilt bob**: a simulated pendulum (spring + damping). Each nudge gives the pendulum an impulse; if it touches the ring, a warning follows, and too many warnings cause a tilt (flippers disabled, ball lost).
- Analog nudge (gamepad stick, or later an accelerometer) is a nice-to-have.

### 3.9 Determinism and debugging

- A fixed tick rate plus tick-level input makes it possible to record **replays** (input per tick). That is invaluable for physics bugs ("ball went through the flipper at tick 18,432").
- A debug overlay from day one: ball speed, tick rate, contact points, flipper angular velocity.

---

## 4. Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Left flipper | Left Shift | LB / L1 (or left trigger) |
| Right flipper | Right Shift | RB / R1 (or right trigger) |
| Plunger | Enter (hold = pull back) | Right stick down (analog) or A |
| Nudge left / right / up | Z / / (slash) / Space | Left stick |
| Start / extra ball | 1 | Start |
| Pause / menu | Esc | Menu |
| Switch camera | C | Select / View |

Notes:

- **Latency**: flipper input is read per physics tick, not per render frame. At 1000 Hz that saves up to ~16 ms compared to 60 Hz, and you can feel it.
- Everything goes through the Godot Input Map, so keys can be rebound.
- Plunger: analog (how far you pull determines the strength) and a digital variant for keyboard (strength grows while held).
- Possibly later: support for home-built pinball cabinets (cabinet mode, DOF/feedback). Out of scope for the prototype.

---

## 5. Graphics and performance

### 5.1 Realistic look

A pinball table is small, static and viewed up close. The look comes mostly from materials and light:

- **Lighting**: baked lightmaps (LightmapGI) for soft shadows and indirect light on the playfield; dynamic lamps (inserts, flashers, GI strings) as real-time lights on top.
- **Inserts**: the translucent lamps in the playfield, with emissive materials and subtle bloom.
- **The chrome ball**: the most-watched object. It has to reflect its surroundings; that means a reflection probe following the ball (or a cubemap updated every few frames), plus SSR on the playfield.
- **Materials**: PBR with lacquered wood (clearcoat), plastics, rubbers, metal rails and wear, and a glass sheet with subtle reflections and fingerprints.
- **Post-processing**: tonemapping (ACES/AgX), bloom, light depth of field in some camera modes, TAA or SMAA against flickering thin wire rails.

### 5.2 Performance at 7680×2160 @ 120 Hz

That is ~16.6 million pixels, twice 4K, and 120 frames per second leaves 8.3 ms per frame. An RTX 3090 can do that with a small scene, but only with deliberate choices:

- **Render scale + upscaling**: render at e.g. 67–77% and upscale with FSR 2 (built into Godot). DLSS is not part of Godot by default. Configurable in the menu.
- **Baked instead of real-time GI**: SDFGI/VoxelGI only where it adds something lightmaps can't.
- **Physics decoupled from rendering**: 1000 Hz physics with interpolation, so 120 Hz rendering is smooth without physics depending on the frame rate.
- **Profiling from Phase 1** with a fixed benchmark scenario (ball in motion, all lamps on) and a frame-time budget per phase.

### 5.3 Aspect ratios: from 32:9 to vertical 9:16

The game must work well on extremely wide displays (32:9) as well as a vertical display (9:16, portrait or cabinet). A pinball table is itself portrait-shaped, so each aspect ratio needs its own camera and layout. We design this as **layout profiles** selected automatically based on the aspect ratio (and overridable manually):

| Profile | Aspect ratio | Camera | Score/DMD and UI |
|---|---|---|---|
| **Portrait / cabinet** | 9:16 (and 9:21, 3:4) | The whole table in view from above-front, little perspective, like a real cabinet or a "full table" mode. This is where the table fits best and is sharpest. | DMD/score in a bar at the top (as if the backbox hangs above it), or hidden for a second display |
| **Landscape** | 16:9, 16:10, 21:9 | Tilted 3D camera (like Pinball FX), optionally with a camera following the ball | Score/DMD top right or in a panel next to the table |
| **Super ultrawide** | 32:9 | Tilted camera with the table centered | Backbox/DMD and score panels on the sides |

Resulting conventions:

- **Camera presets per profile**, with parameters (FOV, angle, distance) in resources, so they can be tuned per table.
- **UI built with Godot anchors and containers**, never fixed pixel positions. The UI scales with screen height, so text stays readable both at 2160 px tall and at 1920 px wide.
- **In-game screen rotation**: a setting for 0°/90°/270° rotation, for a landscape display turned upright without the OS knowing (common in pinball cabinets).
- **Later**: a second window/display for the backbox/DMD (cabinet setup with a playfield display + backglass display).
- **Test matrix**: every graphics or UI change is checked at 9:16, 16:9, 21:9 and 32:9 (via window sizes, also in CI screenshots).
- **Performance**: 9:16 at 2160×3840 is ~8.3 million pixels, half of the 32:9 display, so that profile is easier to hit.

### 5.4 Linux specifics

- Develop and test on Fedora/KDE Wayland with the NVIDIA driver; Vulkan as the renderer.
- Use Godot's native Wayland support (and test X11/XWayland as a fallback).
- Test VSync/variable refresh, since vsync behavior and input latency differ per compositor.
- CI builds a Linux export on every change.

---

## 6. Architecture (first sketch)

```
pinball/
├── project.godot
├── core/              # tick loop, settings, replay recording, input layer
├── physics/           # ball, flipper model, nudge/tilt, impulse helpers
├── table_parts/       # reusable scenes: Flipper, Slingshot, PopBumper, Target, Ramp, Plunger…
├── tables/
│   └── proto_table/   # first test table
├── rules/             # game rules: score, balls, modes (separate from physics)
├── cameras/           # camera rigs and layout profiles per aspect ratio
├── ui/                # HUD, menus, debug overlay
├── tests/             # smoke tests for CI
└── docs/
```

Principles:

- **Table = scene.** Every part is a reusable Godot scene with `@export` parameters (force, restitution, points), so a table is built and tuned in the editor.
- **Physics and rules are separate.** Parts emit signals (`hit`, `drained`), the rules layer listens. That way a second table can reuse the same physics with different rules.
- **Tunables in resources** (`.tres`), not hard-coded, so tuning doesn't require code changes.
- **Camera decoupled from game logic.** Cameras and layout profiles live in their own layer, so a VR rig (OpenXR) can be added later without touching the table or the rules.
- Start in **GDScript**; move hotspots (a custom ball solver) to C# or a GDExtension later if measurements call for it.

---

## 7. Roadmap to a first playable prototype

Every phase ends with something you can play or measure.

### Phase 0 – Setup
- Create the Godot project, folder structure, `.gitignore`, Jolt as the physics engine.
- Physics at 1000 Hz, physics interpolation on.
- Linux settings: Vulkan Forward+, native Wayland.
- CI: automatic export build (Linux first, Windows later) via GitHub Actions.
- **Done when:** an empty project builds in CI.

### Phase 1 – Physics sandbox
- Flat playfield on a slope (gravity at an angle), walls, one ball with CCD.
- Debug overlay (speed, tick rate), a test scene that fires the ball at 10+ m/s into thin walls.
- Scale test: real meters vs. ×10. Record the decision.
- First performance measurement at 7680×2160 with a frame-time overlay.
- Simple cameras for portrait (9:16) and landscape, so both work from the start.
- **Done when:** no tunneling in 1000 shots, the ball rolls believably, 120 fps on the target system.

### Phase 2 – Flippers and plunger
- Flipper scene with a motor model (kinematic), left and right flipper, input per tick.
- Plunger (analog and digital), shooter lane.
- Inlanes, outlanes, drain.
- **Done when:** you can launch the ball, hit it back, and do a cradle and a post pass.

### Phase 3 – Basic elements
- Slingshots, 3 pop bumpers, a row of standup targets, a drop target bank, rollovers.
- Simple sounds and lamps on hits.
- **Done when:** a full ball can be played on a simple but recognizable table.

### Phase 4 – Game rules (= first playable prototype)
- Score, 3 balls per game, ball save, end-of-ball bonus.
- HUD with score and ball number; start, game over and high score screens.
- **Milestone: first playable prototype.**

### Phase 5 – Feel and presentation
- Nudge and tilt bob.
- Flipper refinement (custom contact impulse, velocity-dependent restitution, EOS).
- Layout profiles with camera presets for 9:16 (portrait/cabinet), 16:9/21:9 and 32:9; screen rotation setting.
- Graphics pass: baked lightmaps, PBR materials, chrome ball with reflection probe, inserts with bloom, FSR 2 render scale in the menu.
- Per-tick replay recording for debugging.

### Phase 6 – Expansion (after the prototype)
- Ramps and wire ramps, kickers/scoops, spinners, magnet.
- Multiball, modes, DMD or LCD display in the backbox.
- Possibly a custom ball solver in C#/GDExtension if Jolt hits its limits.
- Second table, settings menu (slope, difficulty, keybindings), web or mobile export.

---

## 8. Legal

Tables in Pinball FX and Zaccaria are often based on licensed real machines or brands. We design **our own** tables, themes and artwork. Mechanics such as flippers, bumpers and ramps are free to use.

---

## 9. Open decisions

1. **GDScript or C#?** Proposal: GDScript for the prototype; C# only if we build a custom solver.
2. ~~**Real scale or scaled up?**~~ Decided: real scale (see [docs/physics-notes.md](docs/physics-notes.md)).
3. **Target platform:** Linux PC first (decided), Windows second. Web/mobile later or not at all.
4. **Theme of the first original table.**
