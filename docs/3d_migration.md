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

Player and NPC locomotion both resolve through:

```text
Simulation::Commands::GroundMove(entity_id, dx, dz)
```

Player input produces this displacement directly each fixed tick. NPC behavior persists `SteeringTarget(x, z, goal_entity_id)`. `Simulation::GroundSteering` resolves that goal every fixed 30 Hz tick, asks `Simulation::GroundNavigation` for a continuous local `GroundHeading`, and produces the NPC `GroundMove` until the target is cleared or local navigation cannot currently provide a usable heading.

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

The active static-world backend and active dynamic ground bodies participate in one earliest-hit contract. Retired entities are omitted from ordinary active dynamic scans.

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

The original v0.3 navigation bridge used BFS over the authored grid, converting continuous runtime positions to cells only while planning. During the v0.3.2 collision migration that Pathfinder was progressively hardened so its static candidate edges consulted BSP hull clearance, and during early v0.3.3 cleanup it was separated from locomotion through world-space waypoints and persistent steering targets.

That grid Pathfinder is no longer the active chase mechanism.

Current v0.3.3 chase uses:

```text
Behavior(:chase)
      |
      v
SteeringTarget(goal entity)
      |
      v
GroundNavigation @ fixed simulation cadence
      |
      v
GroundHeading
      |
      v
GroundSteering
      |
      v
GroundMove
```

`GroundNavigation` reasons from the actor's actual continuous `Position`, `GroundBody`, current world-space goal, previous local heading, and `GroundSpace`. It does not consume navigation cells or BSP-format records directly. Direct pursuit is preferred; when blocked, local alternatives are probed through the same collision service that actual movement uses.

The obsolete `Simulation::Pathfinder` was removed after the local-navigation cutover was validated. Its grid cells and cell-edge clearance cache are no longer part of the source tree. A future global route graph, if real maps require one, should be a fallback from the local navigator rather than a replacement for fixed-step locomotion.

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

The grid is now a compatibility/authored-navigation scaffold rather than BSP-mode static collision authority.

In the current BSP preview it still provides:

```text
Ruby-authored level/spawn/entry scaffolding
```

The normal non-BSP Ruby launch also continues to use grid terrain for its own static rendering and collision fallback.

It no longer defines runtime actor positions, BSP-mode actor static movement, melee adjacency, or BSP-mode static obstruction.

## Authored-data and unit normalization

Aogera 0.3.2 adds a real source-format boundary before BSP work:

```text
source -> Reader -> normalized Level::AuthoredData -> Level::Loader -> runtime
```

The current Ruby/grid reader converts source grid coordinates to Aogera world coordinates. `Level::Loader` no longer parses source files and rejects unnormalized source definitions.

World-unit magnitude is now Quake 1 compatible. The temporary grid uses 32 world units per cell, and existing linear gameplay/render values are scaled proportionally. This removes the old one-cell/one-unit prototype scale before external BSP geometry enters the runtime.

## BSP collision and navigation boundary in the v0.3.2 RC

The normalized runtime now has a concrete BSP29 source path in addition to the Ruby/grid path. `BSP29::Reader` preserves BSP structure in normalized Aogera coordinates, and `Render::BSP29World` reconstructs and triangulates world-model faces for the controlled preview.

The static collision replacement has progressed through the existing Aogera query boundary rather than replacing the continuous runtime:

```text
runtime entities
    Position(x,y,z)
    GroundBody / action data
          |
          v
      GroundSpace
          |
          +-- active dynamic GroundBody circles
          |
          +-- positive-radius BSP GroundClearance -> compiled hull 1
          |
          +-- zero-radius BSP PointHull -> node/leaf tree
```

All current actor `GroundMove` execution in BSP mode now uses the same `GroundMovement`/`GroundSpace` path and the same `BSP29::GroundClearance` source. Melee and interaction obstruction use `BSP29::PointHull`. The movement solver and `GroundTrace` contract remain Aogera-owned.

At the v0.3.2 checkpoint, navigation was intentionally only partially migrated: `Simulation::Pathfinder` still performed BFS over the Ruby grid and projected dynamic blocking actors into cells, while each BSP-mode candidate center-to-center transition was checked through the same `GroundClearance` source used by movement execution. That historical bridge has since been retired from active chase in the v0.3.3 cleanup line.

The controlled fixture also exposes the fixed compiled-hull limitation: standard hull 1 has a 16-unit horizontal half-extent, while Aogera authors smaller `GroundBody` radii. The 32-unit water pinch therefore has zero nominal hull-1 slack even though the old player circle fit. v0.3.2 records this mismatch instead of hiding it by resizing the map or pretending `GroundBody` can resize a compiled BSP hull.

This is the release-candidate stopping point. BSP-native navigation topology, BSP gameplay entity import, and removal of the Ruby-level bridge are later migrations. See `docs/bsp_collision_migration.md` for the detailed sequence and roadmap.

## Still absent by design

Aogera v0.3.2 does not yet contain:

- vertical actor collision, gravity, jumping, or step/floor handling;
- projectile or hitscan weapon systems;
- generalized collision masks;
- models/material framework;
- generic asset management;
- generic `Transform`, `PhysicsBody`, or `Spatial` frameworks.

The v0.3.2 RC therefore established **one continuous world-space runtime, one shared actor movement/collision path, explicit lifecycle state, one continuous spatial basis for combat/interaction, a Reader/Loader authored-data boundary, Quake-compatible world-unit magnitude, a validated BSP29 Reader, BSP world-model rendering, compiled-hull actor static collision, point-hull obstruction, and BSP-aware clearance validation inside the then-active grid BFS.**

The controlled BSP29 fixture remains paired with the matching Ruby-authored level for current spawn/entry scaffolding. In v0.3.3, active chase no longer consumes that grid topology: local navigation now operates on continuous positions through `GroundSpace`, and the obsolete grid Pathfinder has been removed.
