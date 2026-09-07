# Aogera Architecture

This document describes the current Aogera 0.2.3 runtime and its present boundaries.

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

## Rendering

The current presentation path is explicitly 2D and transitional:

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

`Scene2D` is immutable presentation data. Pixel conversion and current grid layout live in `Raylib2D`; logical simulation coordinates are not screen coordinates. The 2D types are deliberately not generalized in advance for 3D.

## Authored content and assets

Authored Ruby data currently lives in:

```text
content/prototypes/
content/levels/
content/dialogue/
```

`Content::Paths` centralizes the content root and paths used by the current Ruby loaders. There is intentionally no general asset manager yet. Models, textures, shaders, BSP data, and their lifetime rules will be introduced from concrete 3D requirements.

## Near-term boundary

Aogera 0.2.3 intentionally does not define continuous 3D positions, physics, projectile motion, BSP loading, a generic renderer hierarchy, or a permanent asset format. Those belong to the upcoming 3D work rather than to the transitional 2D runtime.
