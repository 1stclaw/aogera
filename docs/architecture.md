# Aogera Architecture

This document describes the current Aogera 0.3.0 runtime and its present boundaries.

## Design goals

Aogera favors a small, explicit, data-oriented runtime over framework-heavy abstractions.

- keep persistent, authored, runtime, and presentation state separate;
- keep `Simulation` independent of wall-clock time and host input;
- schedule simulation with a fixed-step policy outside the core simulation;
- keep rendering downstream of canonical runtime state;
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
```

`Session` owns persistent character state. `Level` is immutable authored structure. `World` is the canonical mutable runtime container and owns entity IDs, component tables, and runtime relations. Runtime entity IDs never serve as persistent identity.

`World::View` is a cached read-only facade over `World`; callers receive the same view object rather than allocating wrappers repeatedly. `World#entity_ids` similarly caches its immutable active-ID snapshot and invalidates it only on spawn/despawn.

## Components and prototypes

Component values live under `Component`. `Prototype` is an authored reusable component recipe. Instantiating a prototype creates a runtime entity identified by an integer `EntityId`.

```text
Prototype -> World EntityId
```

`Prototype::Catalog` and `Prototype::Loader` own authored prototype lookup/loading.

The existing `Component::Position(x, y)`, cardinal `Facing`, grid movement commands and pathfinding remain explicitly 2D gameplay concepts in this first 3D milestone. They have not been renamed or padded with a dummy Z coordinate.

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

## Fixed-step scheduling

`App` owns the host loop and a monotonic `FixedStep`. The engine currently advances simulation at 30 Hz while raylib targets 60 rendered frames per second. A rendered frame may therefore contain zero or more simulation steps.

`RealtimeController` owns gameplay scheduling policy such as held movement and NPC decision cadence. These rates are prototype tuning values rather than permanent physics assumptions.

## Input

`Host::Raylib` polls raylib and emits `Host::KeyEvent` values. `Input::Mapper` converts those physical events into gameplay `Input::Action` values. `Input::Handoff` and `Input::Tracker` carry press/release state safely across render frames and fixed simulation ticks.

```text
Host::Raylib
    |
Host::KeyEvent
    |
Input::Mapper -> Input::Handoff -> Input::Tracker
    |
Mode::Play -> RealtimeController -> Commands::Buffer -> Simulation#step
```

Dialogue remains modal and currently pauses world advancement.

Mouse motion is not part of this contract yet. It will be introduced when first-person view rotation creates a concrete non-boolean input requirement.

## 3D rendering

The active presentation path is now:

```text
Level + World::View
        |
Render::Raylib3D
        |
RaylibAPI
        |
raylib
```

`Render::Raylib3D` is intentionally specific. It directly extrudes the existing grid level into raylib primitives:

```text
passable/non-wall tile -> thin floor cube
wall tile              -> vertical wall cube
renderable entity      -> smaller vertical cube
```

There is no `Scene3D`, `Projector3D`, generic `Scene`, generic `Renderer`, or generic transform hierarchy. The direct path is sufficient for the temporary bridge and leaves BSP free to use a different representation later.

`RaylibAPI` owns conversion from plain Ruby camera/geometry values into `raylib-bindings` FFI types. `Camera3D` and `Vector3` do not enter simulation or authored gameplay state.

### Coordinate convention

The initial Aogera/raylib 3D convention is:

```text
+X = east/right
+Y = up
+Z = south (the old grid +Y direction)
```

The old grid therefore maps as:

```text
grid (x, y) -> world (x, 0, y)
```

Tiles/entities are drawn at cell centers, so rendered primitive centers add half a tile on X and Z. This convention is covered by renderer contract tests and can later form the boundary for Quake Z-up conversion.

## Authored content and assets

Authored Ruby data currently lives in:

```text
content/prototypes/
content/levels/
content/dialogue/
```

`Content::Paths` centralizes the content root and paths used by the current Ruby loaders. There is intentionally no general asset manager yet. The first 3D path uses only raylib primitives; models, textures, shaders, BSP data, and their lifetime rules will be introduced from concrete requirements.

## Near-term boundary

Aogera 0.3.0 establishes real 3D rendering but intentionally does not yet define continuous 3D gameplay positions, mouse look, 3D collision/physics, projectile motion, BSP loading, or a permanent asset format.

The next implementation milestone is first-person control. That work should determine the smallest logical position/orientation state needed by gameplay while keeping raylib camera structs presentation-local.
