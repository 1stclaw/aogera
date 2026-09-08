# Aogera 3D Migration: v0.2.3 to v0.3.2

This document summarizes the architectural state of Aogera v0.3.2 relative to the final cleaned 2D/raylib baseline, v0.2.3.

It is a state comparison rather than a chronological changelog. Superseded intermediate solutions are omitted; only systems and boundaries that exist in v0.3.2 are described here.

## v0.2.3 baseline

The v0.2.3 runtime already had several boundaries worth preserving:

- raylib as the sole frontend;
- fixed-step simulation independent from render cadence;
- `Host::Raylib` for window/input ownership;
- a small `RaylibAPI` boundary around `raylib-bindings`;
- `Input::Mapper`, handoff, and tracker;
- `Simulation#step(commands:)` as the mutation boundary;
- cached `World::View` and `World#entity_ids`;
- `Session` for persistent character state;
- authored Ruby prototypes, levels, and dialogue.

Its active presentation path was explicitly 2D:

```text
Level + World::View
        |
Render::Projector2D
        |
Render::Scene2D
        |
Render::Raylib2D
```

Runtime gameplay was also grid-oriented.

## v0.3.2 runtime position

Aogera now has one canonical continuous runtime position:

```text
Component::Position(x, y, z)
```

All current spatial runtime entities use the same world-space coordinate convention:

```text
+X = east/right
+Y = up
+Z = south
```

Current grid-authored cells map to world-space centers only when entities are instantiated:

```text
cell (x, y) -> Position((x + 0.5) * 32, 0.0, (y + 0.5) * 32)
```

The authored grid is not retained as a second entity-position model. Player, enemies, and NPCs do not synchronize against a stored runtime cell coordinate.

## First-person control

`FirstPersonView` owns yaw, pitch, eye height, FOV, and mouse sensitivity.

Mouse deltas update first-person orientation at render cadence. Keyboard/gameplay movement remains fixed-step simulation input.

The logical view is independent from the raylib `Camera3D` FFI object; the renderer derives camera values from canonical `Position` plus `FirstPersonView`.

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

`Render::Raylib3D` directly extrudes the current authored terrain into primitive floor/wall geometry and draws renderable entities at canonical positions.

The controlled player is omitted from the first-person entity pass. There is no active `Scene3D`, `Projector3D`, generic transform hierarchy, or generic physics layer.

The v0.2.3 2D presentation pipeline is no longer part of the active tree:

```text
Render::Projector2D
Render::Scene2D
Render::Raylib2D
```

## Unified actor movement

Player and NPC locomotion both use:

```text
Simulation::Commands::GroundMove(entity_id, dx, dz)
```

Current ground actors can carry:

```text
GroundBody(radius)
```

`Simulation::GroundMovement` resolves actor movement through `GroundSpace#sweep_circle`.

The solver:

- sweeps across the complete requested displacement;
- selects the earliest static/dynamic collision;
- returns exact contact positions;
- accumulates distinct contact normals within one movement command;
- constrains remaining movement against the active contact set;
- rejects a numerically invalid final position rather than storing penetration.

The former separation between player continuous movement and NPC grid movement no longer exists.

## Shared spatial queries

`GroundSpace` operates directly on canonical `Position` values and authored `GroundBody` radii.

It provides:

- center distance and surface separation;
- circle overlap checks;
- parameterized forward-arc queries;
- segment traces;
- swept-circle traces;
- structured `GroundTrace` results.

`GroundTrace` reports:

```text
fraction
end_x / end_z
normal_x / normal_z
entity_id
world_hit
start_blocked
```

Static terrain cells and active dynamic ground bodies participate in one earliest-hit contract. Retired entities are omitted from ordinary active dynamic scans.

## Combat and interaction

Melee geometry is authored rather than embedded in collision code:

```text
MeleeAttack(reach, arc_degrees)
```

Player target selection combines current view heading, authored reach/arc, continuous separation, and segment obstruction traces.

NPC melee now uses the same continuous separation and obstruction model. Manhattan/grid adjacency is no longer a runtime attack rule.

Interaction remains separate from combat:

```text
Interactor(reach, arc_degrees)
```

It uses the same spatial facts and obstruction traces with interaction-specific target eligibility.

## Entity retirement

Defeated local actors enter an explicit retired lifecycle state.

```text
active -> retired -> optional despawn
```

A retired entity can remain in `World` and retain descriptive/spatial state, but it cannot keep issuing movement/attack commands and is excluded from ordinary active collision/target scans.

This makes lifecycle independent from health and prevents already-buffered actor commands from continuing after retirement.

## Navigation

The current Pathfinder remains a temporary BFS over the authored grid because the current levels are still grid-authored.

It derives temporary cells from canonical positions only while planning:

```text
Position(x, y, z)
      |
      v
level.cell_for_world(x, z)
      |
      v
BFS next cell
      |
      v
continuous waypoint displacement
      |
      v
GroundMove
```

Navigation cells are not stored as entity state. This isolates the remaining grid dependency to terrain and route planning.

## Boundaries retained from v0.2.3

Several v0.2.3 design decisions survived the migration and now support the 3D runtime:

- 30 Hz fixed-step simulation independent from 60 FPS rendering;
- `Host::Raylib` as window/input owner;
- `RaylibAPI` containing raylib/FFI details;
- the gameplay input mapper/handoff/tracker path;
- `Simulation#step(commands:)` and `Simulation::Executor` as mutation boundaries;
- cached read-only `World::View`;
- cached `World#entity_ids` snapshot;
- `Session` persistent state;
- authored Ruby content.

## Remaining grid role

The grid now has only roles that are genuinely grid-derived:

```text
authored static terrain
BFS navigation cells
```

It no longer defines runtime actor positions, actor locomotion, melee adjacency, or player/NPC collision as separate systems.

## Authored-data and unit normalization

Aogera 0.3.2 adds a real source-format boundary before BSP work:

```text
source -> Reader -> normalized Level::AuthoredData -> Level::Loader -> runtime
```

The current Ruby/grid reader converts source grid coordinates to Aogera world coordinates. `Level::Loader` no longer parses source files and rejects unnormalized source definitions.

World-unit magnitude is now Quake 1 compatible. The temporary grid uses 32 world units per cell, and existing linear gameplay/render values are scaled proportionally. This removes the old one-cell/one-unit prototype scale before external BSP geometry enters the runtime.

## BSP boundary in the v0.3.2 RC

The normalized runtime now has a concrete BSP29 source path in addition to the Ruby/grid path. `BSP29::Reader` preserves BSP structure in normalized Aogera coordinates, and `Render::BSP29World` reconstructs and triangulates world-model faces for a controlled preview.

The collision replacement point remains clear:

```text
runtime entities
    Position(x,y,z)
    GroundBody / action data
          |
          v
      GroundSpace
          |
          +-- active dynamic bodies
          |
          +-- current static grid collision
                       |
                       v later
                BSP29 collision data
```

Movement, melee, and interaction already consume trace results rather than implementing grid collision directly. BSP can therefore replace the static backend without changing the canonical entity-position model.

Navigation can evolve independently when the first BSP levels make a replacement for grid BFS necessary.

## Still absent by design

Aogera v0.3.2 does not yet contain:

- vertical actor collision, gravity, jumping, or step/floor handling;
- projectile or hitscan weapon systems;
- generalized collision masks;
- models/material framework;
- generic asset management;
- generic `Transform`, `PhysicsBody`, or `Spatial` frameworks.

The v0.3.2 RC therefore establishes **one continuous world-space runtime, one shared actor movement/collision path, explicit lifecycle state, one continuous spatial basis for combat/interaction, a Reader/Loader authored-data boundary, Quake-compatible world-unit magnitude, a validated BSP29 Reader, and a minimal BSP world-model rendering path.**

The controlled BSP29 fixture is intentionally still paired with the matching Ruby/grid gameplay backend. BSP collision is the next replacement step, not part of the RC.
