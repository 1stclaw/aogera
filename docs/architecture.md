# Aogera Architecture

This document describes the current Aogera 0.3.1 runtime and its present boundaries.

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

`FirstPersonView` is current player control/view state, deliberately separate from `World`. It exists because first-person orientation must update at render cadence while the current gameplay world still advances at a fixed 30 Hz. It is not raylib camera state and does not introduce a generic transform model.

`World::View` is a cached read-only facade over `World`; callers receive the same view object rather than allocating wrappers repeatedly. `World#entity_ids` similarly caches its immutable active-ID snapshot and invalidates it only on spawn/despawn.

## Components and prototypes

Component values live under `Component`. `Prototype` is an authored reusable component recipe. Instantiating a prototype creates a runtime entity identified by an integer `EntityId`.

```text
Prototype -> World EntityId
```

`Prototype::Catalog` and `Prototype::Loader` own authored prototype lookup/loading.

The current `Component::Position(x, y)`, cardinal `Facing`, grid movement commands and pathfinding remain explicitly grid gameplay concepts. They have not been renamed or padded with a dummy Z coordinate.

Player first-person yaw/pitch does not currently replace `Facing`. `Facing` remains useful to the legacy grid executor and authored entries, while player attack/interaction direction now comes from `FirstPersonView`.

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

The 0.3.1 first-person bridge still emits the existing integer `Move(dx, dy)` command. Continuous 3D movement has not entered simulation yet.

## Fixed-step scheduling

`App` owns the host loop and a monotonic `FixedStep`. The engine currently advances simulation at 30 Hz while raylib targets 60 rendered frames per second. A rendered frame may therefore contain zero or more simulation steps.

`RealtimeController` owns gameplay scheduling policy such as held movement and NPC decision cadence. W/S and A/D now represent local first-person forward/back and strafe input. At command-building time the controller asks `FirstPersonView` for the corresponding temporary grid delta.

## Input

There are now two deliberately different input paths because boolean gameplay actions and continuous mouse look have different timing requirements.

Keyboard/gameplay actions remain fixed-step input:

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

Mouse look is a value-bearing render-frame input:

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

This split is intentional. Mouse rotation should not become visibly quantized to the 30 Hz simulation tick, and it does not mutate canonical world state.

`Host::Raylib` captures the cursor once after opening/focusing the window and releases it before close.

Dialogue remains modal and currently pauses world advancement, while the shared first-person view can still be rendered from the controlled character position.

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

`Render::Raylib3D` directly extrudes the existing grid level into raylib primitives:

```text
passable/non-wall tile -> thin floor cube
wall tile              -> vertical wall cube
renderable entity      -> smaller vertical cube
```

The camera eye is derived from the controlled player's grid-cell center plus `FirstPersonView#eye_height`; its target comes from the logical forward vector. The controlled player entity is omitted from the first-person entity draw pass.

There is no `Scene3D`, `Projector3D`, generic `Scene`, generic `Renderer`, or generic transform hierarchy. The direct path remains sufficient for this bridge and leaves BSP free to use a different representation later.

`RaylibAPI` owns conversion from plain Ruby camera/geometry values into `raylib-bindings` FFI types. `Camera3D`, `Vector2`, and `Vector3` do not enter simulation or authored gameplay state.

### Coordinate convention

Aogera's current 3D convention remains:

```text
+X = east/right
+Y = up
+Z = south (the old grid +Y direction)
```

The old grid maps as:

```text
grid (x, y) -> world (x, 0, y)
```

Tiles/entities use cell centers, so rendered primitive/camera X/Z coordinates add half a tile. This convention can later form the boundary for Quake Z-up conversion.

## Authored content and assets

Authored Ruby data currently lives in:

```text
content/prototypes/
content/levels/
content/dialogue/
```

`Content::Paths` centralizes the content root and paths used by the current Ruby loaders. There is intentionally no general asset manager yet. Models, textures, shaders, BSP data, and their lifetime rules will be introduced from concrete requirements.

## Near-term boundary

Aogera 0.3.1 establishes a real first-person camera/control loop but intentionally leaves player location and collision grid-based. Continuous 3D position, 3D collision/physics, projectile motion, BSP loading, and a permanent asset format remain undesigned.

The next implementation should make one of those concepts real only when it can replace part of the temporary grid bridge rather than coexist as speculative infrastructure.
