# Aogera Architecture

This document describes the current Aogera runtime as an independent project. It documents present responsibilities and invariants rather than migration history.

## Design goals

Aogera favors a small, explicit, data-oriented runtime over framework-heavy abstractions.

The main goals are:

- keep persistent state, authored data, and runtime state separate;
- make runtime mutation pass through explicit command boundaries;
- keep `Simulation` independent of wall-clock time and host input;
- make fixed-step scheduling a policy outside the core simulation;
- keep rendering downstream of canonical runtime state;
- preserve straightforward tests and a plausible path to lower-level reimplementations later.

## Lifetime model

The primary lifetime split is:

```text
persistent                    authored                     runtime
------------------            ------------------           ------------------
Session                       Level                        Simulation
└── Characters                ├── Terrain                  ├── World
    └── Character             ├── Spawns                   ├── Bindings
                              ├── Entries                  ├── Executor
                              └── Relations                └── step number
```

### Session

`Session` is the persistent game-lifetime root. It owns `Character` values by stable keys.

A character is currently intentionally small and flat: HP, maximum HP, MP, maximum MP, and attack. More structure should be introduced only when real gameplay systems require it.

Persistent identity never depends on runtime `EntityId` values.

### Level

`Level` is immutable authored structure. It contains terrain, spawns, entries, and authored relations.

A spawn identifies a prototype and its placement:

```text
Spawn
├── key
├── prototype
├── x
└── y
```

An entry is an authored reference point used when a persistent character enters a level:

```text
Entry
├── key
├── x
├── y
└── facing
```

Persistent player characters are not ordinary authored spawns. `Simulation` instantiates them at entries and binds their persistent character keys to runtime entities.

### World

`World` is the canonical mutable runtime container.

It owns:

- integer `EntityId` values;
- component tables;
- runtime relations;
- a read-only `World::View`.

It does not own persistent `Character` state.

## Components and prototypes

Component value types are independent of world storage and live under `Component`.

Current examples include:

```text
Component::PrototypeRef
Component::Position
Component::Health
Component::Renderable
Component::Behavior
Component::Collision
Component::Facing
Component::Interactable
Component::Combatant
```

`Prototype` is an authored reusable component recipe. Instantiating a prototype creates a runtime entity in `World`; the runtime entity is identified only by its integer `EntityId`.

```text
Prototype
   |
   | instantiate
   v
World EntityId
```

`Prototype::Catalog` and `Prototype::Loader` own authored prototype lookup/loading responsibilities.

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

Its primary mutation API is:

```text
Simulation#step(commands:) -> StepResult
```

`StepResult` contains the completed step number and persistent effects emitted while applying the commands.

Simulation does **not** own the real-time controller, fixed-step clock, host input, or renderer.

## Bindings

`Simulation::Bindings` is the single mapping between stable persistent character keys and runtime entity IDs.

```text
:player <-> EntityId 7
```

Bindings live in `Simulation` because runtime entity IDs only have meaning inside a running simulation.

## Commands::Buffer

`Simulation::Commands::Buffer` is the explicit batch boundary between command production and command execution.

Current command types include movement, attack, and defeat-related mutations.

Keeping a real buffer object rather than passing an arbitrary array gives the runtime a stable boundary for later scheduling, inspection, recording, validation, batching, and alternate implementations.

## Executor and persistent effects

`Simulation::Executor` receives a command buffer, validates execution-time legality, mutates `World`, and emits persistent effects when runtime actions affect bound persistent characters.

Conceptually:

```text
Attack local entity
  -> mutate runtime Health in World

Attack bound persistent player entity
  -> emit Effect::DamageCharacter(:player, amount)
```

When local runtime `Health` reaches zero during an `Attack`, the executor immediately retires that entity's gameplay components. Command producers therefore do not need to predict lethal damage or append a separate `Defeat` command. Explicit `Defeat` remains available as a command for already-zero-health entities.\n\nPersistent effects are applied by `Session`, keeping persistent mutation outside `World`.

## Fixed-step scheduling

Aogera currently uses a 30 Hz fixed engine clock.

`App` owns the monotonic fixed-step loop. The simulation itself receives one explicit command buffer per step and has no wall-clock dependency.

`RealtimeController` owns gameplay scheduling policy such as:

- held player movement;
- player movement-repeat cadence;
- NPC idle, wander, and chase decisions;
- NPC action cadence;
- pathfinding decisions;
- adjacent NPC attack intent.

Current provisional rates are centralized under `Aogera::Realtime`:

- engine: 30 ticks/second;
- player held movement: 5 moves/second;
- NPC behavior: 2 actions/second.

These values are prototype tuning constants, not permanent physics assumptions.

## Input

Kitty input is polled non-blockingly between fixed ticks.

`Input::Tracker` converts press/repeat/release events into:

- held state;
- per-tick pressed edges;
- per-tick released edges.

Movement reads held state. Attack, interact, cancel, and quit read edge-triggered state, so key-repeat events do not retrigger actions that should fire once.

```text
Kitty key events
      |
      v
Input::Tracker
      |
      v
Mode::Play
      |
      +--> RealtimeController
      |         |
      |         v
      |   Commands::Buffer
      |
      `--> direct edge-triggered commands
                |
                v
          Simulation#step
```

`Mode::Play` advances the simulation on every fixed tick, including empty-command ticks. Autonomous actors therefore continue to act while the player is idle.

Dialogue remains modal and currently pauses world advancement.

## Rendering

Projection consumes canonical runtime state:

```text
Level + World::View
        |
        v
Render::Projector
        |
        v
Render::Scene
        ├── Tile
        └── Entity(entity_id, ...)
        |
        v
renderer backend
```

Kitty is the active runtime backend. ASCII remains reference/test infrastructure. Renderer replacement should not require changing world, simulation, or persistence ownership.

## Authored content

Authored Ruby content is kept outside runtime implementation code:

```text
content/prototypes/
content/levels/
content/dialogue/
content/sprites/
```

Loaders convert authored data into the runtime's explicit level, prototype, and catalogue values.

## Current architectural boundary

Aogera intentionally leaves several systems open while the real-time runtime is still being proven:

- continuous spatial representation and collision;
- richer action phases and cooldowns;
- projectiles, spells, weapons, and equipment;
- persistent map/world changes;
- save serialization;
- a generalized gameplay-rules/intent layer;
- a generic ECS system-manager abstraction;
- a permanent graphical backend.

New abstractions should be added because a concrete gameplay or performance requirement needs them, not to anticipate a hypothetical general engine.
