# Aogera Architecture

This document describes the current Aogera 0.3.2 runtime and its present boundaries.

## Design goals

Aogera favors a small, explicit, data-oriented runtime over framework-heavy abstractions.

- keep persistent, authored, runtime, control/view, and presentation state separate;
- keep `Simulation` independent of wall-clock time and host input;
- schedule simulation with a fixed-step policy outside the core simulation;
- keep rendering downstream of canonical runtime/control state;
- add abstractions only when concrete gameplay or performance requirements need them.

## Lifetime model

```text
persistent              authored                 runtime
----------------        ----------------         ----------------
Session                 Level                    Simulation
└── Character           ├── Terrain              ├── World
                        ├── Spawns               ├── Bindings
                        ├── Entries              ├── Executor
                        └── Relations             └── step number

control/view
----------------
FirstPersonView
├── yaw / pitch
├── eye height
└── FOV / mouse sensitivity
```

`Session` owns persistent character state. `Level` is immutable authored structure. `World` is the canonical mutable runtime container and owns entity IDs, component tables, and runtime relations. Runtime entity IDs never serve as persistent identity.

`FirstPersonView` owns logical first-person orientation and updates at render cadence. It is not raylib camera state and it is not the player's physical position.

The controlled character's continuous physical location now lives in `World` as `Component::GroundPosition(x, z)`, because player translation affects collision and gameplay and therefore belongs on the fixed-step simulation side of the boundary.

`World::View` is a cached read-only facade over `World`; callers receive the same view object rather than allocating wrappers repeatedly. `World#entity_ids` similarly caches its immutable active-ID snapshot and invalidates it only on spawn/despawn.

## Position models during the transition

Aogera currently has two explicit position representations with different jobs.

```text
GroundPosition(x, z)
    continuous player ground-plane position
    authoritative for player translation and camera location

Position(x, y)
    integer authored/runtime grid cell
    authoritative for current NPC/grid systems
```

A persistent controlled character is spawned at the center of its authored entry cell. Whenever its `GroundPosition` crosses into another passable cell, the executor synchronizes its coarse `Position` with `floor(x), floor(z)`.

This coexistence is temporary but intentional. It lets the player acquire a real continuous coordinate without forcing NPC pathfinding, melee adjacency, authored spawns, or terrain representation through a speculative 3D rewrite.

There is still no generic `Transform`, `Spatial`, `Position3D`, or physics-body abstraction.

## Simulation

`Simulation` owns one running level:

```text
Simulation
├── Level
├── World
├── Bindings
├── Executor
└── step_number
```

Its mutation boundary is `Simulation#step(commands:)`. Command producers build `Simulation::Commands::Buffer` values; `Simulation::Executor` validates and applies them. Persistent effects are emitted separately and applied by `Session`.

Two movement commands now coexist deliberately:

```text
Move(entity_id, dx, dy)
    integer grid movement used by NPCs

GroundMove(entity_id, dx, dz)
    continuous ground-plane movement used by the controlled player
```

`GroundMovement` resolves the latter against the current authored grid. It treats the player as a small circle and impassable/blocking cells as solid unit squares. Axis-separated resolution permits wall sliding, and large commands are subdivided to avoid tunneling through a cell.

This is collision logic, not a general physics engine.

## Fixed-step scheduling

`App` owns the host loop and a monotonic `FixedStep`. The engine advances simulation at 30 Hz while raylib targets 60 rendered frames per second. A rendered frame may therefore contain zero or more simulation steps.

`RealtimeController` emits controlled-player ground motion every fixed simulation tick while movement is held. Player speed is expressed in world units per second. NPC behavior continues to run at its separate lower decision cadence.

Mouse yaw/pitch remains render-frame control state; translational movement remains fixed-step world state.

## Input

Boolean gameplay actions and continuous mouse look still use different timing paths.

Keyboard/gameplay actions:

```text
Host::Raylib
    |
Host::KeyEvent
    |
Input::Mapper -> Input::Action
    |
Input::Handoff -> Input::Tracker
    |
Mode::Play -> RealtimeController -> Commands::Buffer -> Simulation#step
```

Mouse look:

```text
Host::Raylib
    |
Host::MouseMotion(dx, dy)
    |
Input::Mapper -> Input::LookDelta(dx, dy)
    |
FirstPersonView#rotate
    |
Render::Raylib3D
```

`Host::Raylib` captures the cursor once after opening/focusing the window and releases it before close.

Dialogue remains modal and currently pauses world advancement, while the shared first-person view renders from the controlled character's current `GroundPosition`.

## 3D rendering

The active presentation path is:

```text
Level + World::View + FirstPersonView
        |
Render::Raylib3D
        |
RaylibAPI
        |
raylib
```

`Render::Raylib3D` still directly extrudes the current grid level into primitive floors/walls and draws renderable entities as primitive cubes. The controlled player is omitted from the first-person entity pass.

The camera eye uses the controlled entity's continuous `GroundPosition` plus logical eye height. Its target comes from the `FirstPersonView` forward vector.

There is no `Scene3D`, `Projector3D`, generic `Scene`, generic `Renderer`, or generic transform hierarchy. The direct path remains sufficient for this bridge and leaves BSP free to use a different representation later.

`RaylibAPI` owns conversion from plain Ruby camera/geometry values into `raylib-bindings` FFI types. raylib `Camera3D`/vector structs do not enter simulation or authored gameplay data.

### Coordinate convention

Aogera's current 3D convention is:

```text
+X = east/right
+Y = up
+Z = south (the old grid +Y direction)
```

One authored grid cell is currently one world unit. Grid cell centers map as:

```text
(x, y) -> (x + 0.5, 0, y + 0.5)
```

This convention can later form the explicit boundary for Quake Z-up conversion.

## Authored content and assets

Authored Ruby data currently lives in:

```text
content/prototypes/
content/levels/
content/dialogue/
```

`Content::Paths` centralizes paths used by the current Ruby loaders. There is intentionally no general asset manager yet. Models, textures, shaders, BSP data, and their lifetime rules will be introduced from concrete requirements.

## Near-term boundary

Aogera 0.3.2 now has a real continuous player coordinate, view-relative ground movement and a minimal collision boundary. NPC navigation and combat targeting remain intentionally grid-based.

The temporary cell collision resolver should not grow into a general physics framework before BSP. The next BSP29 experiment can use the continuous player coordinate to determine what world geometry, collision representation and map-space conversion Aogera actually needs.
