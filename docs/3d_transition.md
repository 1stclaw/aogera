# Aogera 3D Transition: v0.2.3 to v0.3.2

This document summarizes the **current architectural changes** between the final 2D baseline, Aogera v0.2.3, and the present v0.3.2 runtime.

It is intentionally a state comparison rather than a chronological changelog. Superseded intermediate solutions are omitted. Only systems and boundaries that still exist in v0.3.2 are described here.

## Overview

Aogera v0.2.3 ended the raylib 2D line with an explicitly 2D presentation path:

```text
Level + World::View
        |
Render::Projector2D
        |
Render::Scene2D
        |
Render::Raylib2D
        |
raylib
```

Aogera v0.3.2 is now a true 3D first-person runtime with a continuous controlled-player coordinate on the ground plane:

```text
keyboard -> Host::Raylib -> Input::Action -> fixed-step gameplay
mouse    -> Host::Raylib -> Input::LookDelta -> FirstPersonView

GroundPosition + FirstPersonView
        |
Render::Raylib3D
        |
RaylibAPI
        |
raylib Camera3D / 3D primitives
```

The transition did **not** generalize the old 2D renderer into a universal scene system. The obsolete 2D presentation path was removed, while the existing simulation, world, session, mode, fixed-step, and authored-content systems were kept where they remained useful.

## 1. Active presentation is now 3D

The active presentation implementation is `Render::Raylib3D`.

It consumes the current `Level`, cached `World::View`, logical `FirstPersonView`, and the controlled entity ID directly. There is no `Scene3D`, `Projector3D`, generic `Scene`, generic `Renderer`, or transform hierarchy.

The current authored grid is rendered as simple 3D primitives:

- wall cells become vertical cubes;
- other terrain cells become thin floor cubes;
- renderable entities become upright cubes;
- the controlled player entity is omitted from the entity draw pass because the camera is first-person.

Renderable entities with `GroundPosition` use their continuous X/Z coordinate. Other entities continue to render at the center of their integer grid cell.

This primitive extrusion remains a direct bridge from the current authored level format to 3D. It is not intended to prescribe the eventual BSP rendering representation.

### Removed 2D presentation files

The active v0.2.3 presentation path is no longer present:

```text
lib/aogera/render/projector_2d.rb
lib/aogera/render/scene_2d.rb
lib/aogera/render/raylib_2d.rb
docs/raylib_2d.md
test/render_2d_contract_test.rb
```

The historical implementation remains available through Git history rather than through compatibility aliases or dead runtime code.

## 2. Canonical 3D coordinate convention

Aogera now has an explicit Y-up world convention:

```text
+X = east / right
+Y = up
+Z = south / old grid +Y
```

The current grid-to-world bridge uses one world unit per authored cell.

A grid cell center maps as:

```text
(x, y) -> (x + 0.5, 0, y + 0.5)
```

The controlled character's camera eye adds `FirstPersonView#eye_height` on the world Y axis.

This gives later Quake/BSP loading a clear conversion boundary rather than allowing map-space axes to leak implicitly into the rest of the engine.

## 3. First-person view state is Aogera-owned

`FirstPersonView` is the canonical logical view state for the controlled player.

It owns:

- yaw;
- pitch;
- eye height;
- vertical field of view;
- mouse sensitivity.

It can derive:

- a normalized 3D forward vector;
- a nearest cardinal heading for gameplay systems that are still grid-adjacent;
- a yaw-relative ground movement vector for forward/back/strafe input.

Pitch is clamped and yaw wraps continuously.

`FirstPersonView` is deliberately **not** a raylib `Camera3D`, a physical player transform, or a world component. raylib camera structs are derived presentation values.

## 4. Raylib camera and FFI state remain at the frontend boundary

`RaylibAPI` now wraps the raylib operations required by the 3D frontend, including:

- `BeginMode3D` / `EndMode3D`;
- perspective `Camera3D` construction;
- `Vector3` construction through the binding;
- cube drawing;
- mouse delta polling;
- cursor capture/release.

Core gameplay and simulation code continue to pass ordinary Ruby numeric values instead of raylib FFI structs.

`Render::Raylib3D` derives the camera from:

```text
controlled entity GroundPosition
        +
FirstPersonView eye height / forward vector / FOV
```

The camera therefore follows Aogera-owned state rather than becoming authoritative gameplay state itself.

## 5. Mouse look has its own value-bearing input path

The v0.2.3 boolean key-event contract remains appropriate for keyboard gameplay input, but continuous mouse displacement is represented separately.

The host can now emit:

```text
Host::MouseMotion(dx, dy)
```

`Input::Mapper` maps it to:

```text
Input::LookDelta(dx, dy)
```

The current input paths are:

```text
keyboard
Host::KeyEvent
    |
Input::Mapper -> Input::Action
    |
Input::Handoff -> Input::Tracker
    |
fixed-step Mode / Simulation
```

and:

```text
mouse
Host::MouseMotion
    |
Input::Mapper -> Input::LookDelta
    |
FirstPersonView#rotate
    |
3D camera derivation
```

Mouse look is applied once per rendered frontend frame and is therefore not quantized to the 30 Hz simulation cadence.

The raylib host captures the cursor once after opening/focusing the window and releases it during shutdown.

## 6. Controlled-player position is now continuous

The controlled persistent character receives:

```text
Component::GroundPosition(x, z)
```

This is the canonical physical position for player translation on the current ground plane.

It is intentionally specific. Aogera still has no generic `Transform`, `Position3D`, velocity component, rigid body, or general-purpose physics abstraction.

A persistent character spawned from an authored entry begins at the center of that entry cell:

```text
authored entry (x, y)
    ->
GroundPosition(x + 0.5, y + 0.5)
```

The camera uses this continuous position directly.

## 7. Player translation is fixed-step and view-relative

The controlled player no longer uses the integer `Move(dx, dy)` command for normal locomotion.

Player movement enters the simulation as:

```text
Simulation::Commands::GroundMove(entity_id, dx, dz)
```

`RealtimeController` creates a `GroundMove` every simulation tick while movement input is held.

The current simulation cadence remains:

```text
30 Hz fixed simulation
60 FPS raylib target
```

The default player speed is:

```text
2.4 world units / second
```

Movement is calculated from the exact current view yaw:

- W / Up: forward;
- S / Down: backward;
- A / Left: strafe left;
- D / Right: strafe right.

Combined forward/strafe input is normalized, so diagonal movement does not increase total speed.

Translation remains simulation-owned and therefore changes only through the fixed-step command/executor boundary, while yaw/pitch can update at render cadence.

## 8. Minimal continuous ground collision

`Simulation::GroundMovement` resolves `GroundMove` commands against the current authored grid.

The controlled player is represented as a small circle on the X/Z plane. Current constants are:

```text
radius       = 0.22 world units
max substep  = 0.22 world units
```

Collision treats these as solid:

- impassable authored terrain cells;
- cells occupied by entities whose `Collision#blocks_movement` is true.

Resolution is axis-separated:

```text
resolve X
then resolve Z
```

This permits wall sliding when one axis is blocked and the other remains clear.

Large displacement commands are internally subdivided before collision resolution so they cannot simply tunnel through a one-cell obstacle.

This is deliberately a narrow ground-movement collision resolver, **not** a general physics system. It should not accumulate speculative rigid-body or arbitrary geometry responsibilities before BSP establishes the next collision requirements.

## 9. Integer grid position remains as an explicit compatibility bridge

Aogera currently has two position representations with distinct responsibilities:

```text
GroundPosition(x, z)
    continuous
    authoritative for controlled-player translation
    authoritative for first-person camera location

Position(x, y)
    integer grid cell
    authoritative for current NPC/grid systems
```

After a successful `GroundMove`, the executor synchronizes the controlled player's coarse grid position as:

```text
grid x = floor(ground x)
grid y = floor(ground z)
```

This retained `Position` is not the player's precise physical location. It exists because several current systems are still intentionally grid-based:

- NPC movement;
- NPC pathfinding;
- NPC chase behavior;
- melee adjacency validation;
- interaction adjacency;
- authored level spawns and entries;
- current terrain passability representation.

The controlled player can therefore move continuously while existing NPC/gameplay systems continue to function without a speculative all-at-once 3D rewrite.

## 10. NPC movement and pathfinding remain grid-based

NPC behavior continues to use the existing command:

```text
Simulation::Commands::Move(entity_id, dx, dy)
```

The existing integer movement resolver and BFS pathfinder remain active for NPCs.

NPC behavior cadence is still lower than the main simulation cadence. Current realtime constants are:

```text
simulation       30 Hz
player movement  every simulation tick while held
NPC decisions     2 Hz
```

The introduction of continuous player motion therefore did not force NPC navigation into a premature continuous or navmesh-based design.

## 11. Combat and interaction use the current view direction

Melee attack and interaction still operate on adjacent grid cells, but their direction is derived from `FirstPersonView` rather than from the controlled player's legacy movement-facing state.

`FirstPersonView#cardinal_direction` converts the current yaw to the nearest cardinal direction. `Mode::Play` then checks the adjacent coarse cell in that direction for an attack or interaction target.

The executor still validates melee attacks through grid adjacency.

This preserves existing combat/dialogue behavior while the player's translation and camera are already continuous. Continuous raycast or volume-based targeting has not yet been introduced.

## 12. Existing runtime boundaries preserved from v0.2.3

The 3D transition retained the major runtime boundaries that were already useful:

- `Session` remains persistent character state;
- `Level` remains immutable authored structure;
- `World` remains the mutable component/relation container;
- `World::View` remains the cached read-only world facade;
- `Simulation#step(commands:)` remains the mutation boundary;
- `Simulation::Executor` still validates/applies commands;
- persistent effects still flow back into `Session` separately;
- `FixedStep` still schedules simulation independently from render cadence;
- `ModeStack`, play mode, and dialogue mode remain active;
- authored gameplay data remains Ruby content loaded through `Content::Paths`;
- `Host::Raylib` remains the raylib window/input host;
- raylib/FFI details remain concentrated in `RaylibAPI` and the presentation boundary.

The 0.3 work therefore extends the existing runtime rather than replacing it with a new engine architecture.

## 13. Dialogue and mode behavior in the 3D frontend

Dialogue remains modal and pauses normal world advancement while active.

The current mode still exposes the level/world/camera entity needed by the shared 3D renderer, so dialogue renders from the controlled character's current first-person location rather than switching to a separate presentation model.

Mouse look remains part of the shared `FirstPersonView`, independent from simulation stepping.

## 14. Current controls

```text
Mouse        look
W / Up       forward
S / Down     backward
A / Left     strafe left
D / Right    strafe right
Space        melee attack
Enter        interact / advance dialogue
Q / Esc      quit
```

## 15. New active files introduced by the 3D transition

The current 0.3.2 tree adds these principal runtime files relative to v0.2.3:

```text
lib/aogera/first_person_view.rb
lib/aogera/input/look_delta.rb
lib/aogera/render/raylib_3d.rb
lib/aogera/simulation/ground_movement.rb
```

Supporting changes are present in the existing host, input mapper, app/mode, component, realtime controller, simulation command/executor, simulation spawning, and raylib API files.

Current 3D-focused tests include:

```text
test/first_person_view_test.rb
test/ground_movement_test.rb
test/render_3d_contract_test.rb
```

Existing frontend, input, simulation, collision, combat, dialogue, and controller tests were also updated where their contracts changed.

## 16. Current test baseline

The reconstructed v0.3.2 tree used for this transition work passes:

```text
121 runs, 325 assertions, 0 failures, 0 errors, 0 skips
```

The project-standard full-suite command remains:

```bash
bundle exec ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

Graphical/frontend changes should additionally be checked with:

```bash
bundle exec ruby bin/aogera
```

## 17. Systems intentionally not present

The current 0.3.2 architecture does **not** contain:

- BSP loading or BSP collision;
- a custom native level format;
- vertical player movement or jumping;
- velocity or acceleration simulation;
- generic rigid-body physics;
- a generic `Transform` or `Spatial` abstraction;
- continuous NPC navigation;
- continuous melee/raycast targeting;
- projectile simulation;
- ranged-attack delivery systems;
- 3D models or skeletal animation;
- texture/material/shader architecture;
- dynamic lighting/shadow systems;
- a generic asset manager or VFS;
- `Scene3D` / `Projector3D`;
- a universal renderer abstraction.

These omissions are deliberate. The current runtime establishes only the 3D concepts already required by first-person movement and rendering, leaving BSP and later gameplay work to introduce further abstractions from concrete requirements.

## 18. Current transition boundary

The current v0.3.2 state can be summarized as:

```text
Aogera v0.2.3
    |
    |  explicit raylib 2D presentation removed
    |  canonical Y-up 3D coordinates established
    |  first-person yaw/pitch and mouse input established
    |  Camera3D derived from Aogera-owned state
    |  controlled player gains continuous X/Z position
    |  view-relative fixed-step movement established
    |  minimal continuous ground collision established
    |  old grid retained only where current gameplay still needs it
    v
Aogera v0.3.2
    |
    |  continuous first-person player + temporary grid world bridge
    |  grid NPC/pathfinding/combat/interaction still active
    |  no generic physics/render/asset framework
    v
next 3D requirements, especially BSP29
```

The important architectural result is that Aogera now has a real first-person spatial model **before** BSP is introduced, while the old grid remains contained as a known compatibility layer rather than being disguised as a universal 3D representation.
