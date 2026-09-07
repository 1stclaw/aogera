# Aogera 3D Migration: v0.2.3 to current 0.3 development

This document summarizes the architectural state that now exists relative to the final 2D/raylib baseline, Aogera v0.2.3. It describes the **current surviving design**, not superseded intermediate solutions.

## Current runtime

Aogera now has a true first-person 3D frontend and a single continuous runtime entity position:

```text
Component::Position(x, y, z)
```

All spatial runtime entities use the same world-space coordinate convention:

```text
+X = east/right
+Y = up
+Z = south
```

Current grid-authored cells map to world-space centers only when entities are instantiated:

```text
cell (x, y) -> Position(x + 0.5, 0.0, y + 0.5)
```

The authored grid is not retained as a second entity-position model.

## First-person control and rendering

`FirstPersonView` owns yaw, pitch, eye height, FOV and mouse sensitivity. Mouse deltas update view orientation at render cadence, while translational movement remains fixed-step simulation state.

`Render::Raylib3D` derives raylib `Camera3D` values from canonical `Position` plus `FirstPersonView`. It directly extrudes the current authored terrain into primitive floor/wall geometry and draws renderable entities at their runtime positions.

There is still no generic scene/projector/transform hierarchy.

## Unified actor movement

Player and NPC locomotion both use:

```text
Simulation::Commands::GroundMove(entity_id, dx, dz)
```

`GroundBody(radius)` supplies authored horizontal extent. `Simulation::GroundMovement` resolves every current actor move through `GroundSpace#sweep_circle`.

The solver:

- finds earliest collision across the full displacement;
- tests static terrain cells and active dynamic ground bodies;
- returns exact contact positions;
- accumulates distinct contact normals;
- constrains remaining motion against the active contact set;
- validates that the final returned position is not already blocked.

This replaced separate grid actor movement and removed the need for a player/NPC coordinate synchronization bridge.

## Shared spatial queries

`GroundSpace` now operates directly on canonical `Position` values. It provides:

- body radius lookup;
- center distance and surface separation;
- circle overlap tests;
- parameterized forward-arc queries;
- zero-radius segment traces;
- swept-circle traces;
- structured `GroundTrace` results.

Static terrain and dynamic bodies share one earliest-hit result contract. Retired entities are omitted from ordinary active dynamic scans.

## Combat and interaction

Player melee uses authored `MeleeAttack(reach, arc_degrees)`, current view heading and ground-space traces. Interaction uses independent `Interactor(reach, arc_degrees)` data with the same spatial facts.

NPC combat now uses the same continuous separation and obstruction model. Manhattan/grid adjacency is no longer an attack rule in the runtime.

Damage/lifecycle remain separate from targeting. Defeated local actors become explicitly `Retired`: runtime identity and retained descriptive/spatial state may remain, while active movement/combat/collision participation stops.

## Navigation

The current Pathfinder deliberately remains a temporary grid BFS because the current authored level is still a grid.

It projects canonical runtime positions to cells only while planning:

```text
navigation cell = (floor(position.x), floor(position.z))
```

Pathfinding returns a next-cell direction; `RealtimeController` converts that waypoint back to continuous displacement and emits `GroundMove`. Navigation cells are not stored on entities.

This isolates the remaining grid dependency to authored terrain/navigation instead of runtime actor state.

## Runtime boundaries retained from v0.2.3

The following useful boundaries survived the 3D migration:

- 30 Hz fixed-step simulation independent from 60 FPS rendering;
- `Host::Raylib` as window/input owner;
- `RaylibAPI` containing raylib/FFI-specific structures;
- `Input::Mapper`, handoff and tracker for gameplay actions;
- `Simulation#step(commands:)` as the mutation boundary;
- cached `World::View` and `World#entity_ids`;
- `Session` for persistent character state;
- authored Ruby prototype/level/dialogue data.

## Removed 2D/runtime-grid structures

The current architecture no longer contains the active v0.2.3 presentation pipeline:

```text
Render::Projector2D
Render::Scene2D
Render::Raylib2D
```

It also no longer contains separate runtime player/NPC position models or a grid-only actor movement command. Runtime actors have one `Position` and one ground-movement/collision execution path.

## BSP direction

This normalization leaves a cleaner BSP boundary:

```text
runtime entities
    Position(x,y,z)
    GroundBody / action data
          |
          v
      GroundSpace
          |
          +-- dynamic bodies
          |
          +-- current static grid backend
                       |
                       v later
                 BSP collision backend
```

The existing grid BFS can likewise be replaced later by a navigation representation appropriate to BSP without changing canonical runtime entity coordinates.

## Still absent by design

The current architecture does not yet contain:

- BSP loading;
- vertical actor collision/gravity/jumping;
- general physics;
- projectile/hitscan weapon systems;
- general collision masks;
- models/material framework;
- generic asset management;
- generic `Transform`/`Spatial` abstractions.

The current milestone is deliberately narrower: **one continuous world-space model for runtime entities, one shared actor movement/collision path, and one continuous spatial basis for combat and interaction.**
