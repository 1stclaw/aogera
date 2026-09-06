# Aogera

Aogera is an experimental Ruby game runtime for a single-character, real-time action-RPG direction inspired by games such as *Heretic* and *Hexen*.

The current prototype deliberately keeps the world simple: integer-grid geometry, direct map combat, and a Kitty-terminal presentation backend. The architecture is not intended to depend on terminal rendering. Its purpose is to make simulation, scheduling, input, persistent state, and authored content explicit enough to evolve or be reimplemented independently.

Aogera begins its own version line at **0.1.0**.

## Core model

Aogera separates four lifetimes:

```text
Session
  persistent game state
  └── Characters

Level
  immutable authored area
  ├── Terrain
  ├── Spawns
  ├── Entries
  └── authored Relations

Simulation
  one running Level
  ├── World
  ├── persistent-character bindings
  ├── Executor
  └── step number

World
  mutable runtime entities, components, and relations
```

Important terms:

- **Prototype** — authored reusable component recipe.
- **EntityId** — integer runtime identity.
- **Component** — runtime component value types stored by `World`.
- **Character** — persistent RPG state such as HP, MP, and attack.
- **Simulation::Commands::Buffer** — explicit batch boundary between command production and execution.
- **Simulation::Executor** — validates/applies commands to the runtime world and emits persistent effects.
- **Simulation::StepResult** — the completed simulation step number and emitted effects.
- **RealtimeController** — produces movement and NPC commands according to fixed-tick gameplay cadence.
- **Input::Tracker** — converts key press/repeat/release events into held and edge-triggered input state.

## Real-time loop

The engine currently advances at **30 fixed ticks per second**. Simulation itself does not read wall-clock time or keyboard state.

```text
Kitty key events
      |
      v
Input::Tracker
      |
      v
Mode::Play
      |
      +--> RealtimeController --> Commands::Buffer
      |
      +--> edge-triggered direct actions
      |
      v
Simulation#step
```

Movement is held-state driven. Attack, interact, cancel, and quit are edge-triggered. Empty-command ticks still advance the simulation, so autonomous actors continue to act while the player is idle.

Current provisional grid-action rates are:

- engine clock: 30 ticks/second;
- held player movement: 5 moves/second;
- NPC behavior: 2 actions/second.

These are tuning values for the current prototype rather than permanent physics constants.

## Persistent and runtime identity

A persistent character and its runtime entity are intentionally different identities:

```text
Session Character :player
        |
        | Simulation binding
        v
World EntityId 7
```

`Session` never stores an `EntityId` as persistent character identity. A `Level` provides an entry point; `Simulation` instantiates the player prototype and owns the binding between the stable character key and the local runtime entity.

## Commands and effects

Runtime mutation remains explicit:

```text
RealtimeController / Mode
        |
        v
Simulation::Commands::Buffer
        |
        v
Simulation::Executor
        |
        +--> World mutation
        |
        `--> persistent Effect values
                 |
                 v
              Session
```

For example, damage to a local world entity mutates its runtime health component, while damage to a bound persistent player character can be emitted as a persistent effect for `Session` to apply.

## Authored content

Ruby-authored content currently lives under:

```text
content/prototypes/
content/levels/
content/dialogue/
content/sprites/
```

A level spawn references a prototype. Persistent characters enter through a `Level::Entry` rather than being authored as ordinary player spawns.

## Rendering

Rendering is downstream of simulation state:

```text
Level + World::View
        |
        v
Render::Projector
        |
        v
Render::Scene
        |
        v
Render::Kitty
```

Kitty is the active backend. The ASCII renderer remains reference/test infrastructure for now; future graphical backends are expected to consume the same projected scene rather than redefine the runtime model.

## Controls

```text
WASD / arrows  move
Space          attack the adjacent entity you are facing
Enter          interact / advance dialogue
Esc / Q        quit or cancel the active dialogue
```

## Requirements

- Ruby 3.2+
- Kitty graphics protocol support for the active runtime path

Install dependencies:

```bash
bundle install
```

Run:

```bash
bundle exec ruby bin/aogera
```

Run the tests:

```bash
bundle exec ruby -Itest -e \
  'Dir["test/*_test.rb"].sort.each { |file| require_relative file }'
```

## Current scope

The current prototype intentionally does not yet define a final solution for:

- continuous movement or continuous collision geometry;
- attack windup/active/recovery phases;
- projectiles and richer spell systems;
- inventory and equipment;
- persistent per-level world changes;
- save serialization;
- a general Intent -> Rules -> Effects architecture;
- a generic ECS `System` layer;
- a permanent graphics backend.

The near-term direction is richer real-time combat timing while keeping the current runtime boundaries explicit and testable.

## Origins

Aogera was extracted from the experimental `v0.4-solo` branch of the Sunbird Ruby RPG-engine project after that branch diverged into a fixed-step, single-character action-RPG runtime. Aogera starts with fresh repository history and evolves independently from Sunbird.
