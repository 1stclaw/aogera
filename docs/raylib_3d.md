# Aogera 0.3.2 Raylib 3D Frontend

Aogera's active 3D frontend consumes the same canonical runtime position used by simulation and collision.

## Active frame path

```text
raylib frame
    |
    +-- Host::Raylib polls keys + mouse delta
    |
    +-- Input::Mapper
    |       |
    |       +-- Action ------> Handoff / Tracker --> fixed simulation ticks
    |       |                                      |
    |       |                                      v
    |       |                              RealtimeController
    |       |                                      |
    |       |                                      v
    |       |                                  GroundMove
    |       |                                      |
    |       |                                      v
    |       |                              GroundMovement
    |       |
    |       +-- LookDelta ---> FirstPersonView
    |
    +-- Position + FirstPersonView
            |
            v
        Render::Raylib3D
            |
            v
        RaylibAPI
            |
            v
          raylib
```

Mouse look is render-frame control state. Translation is canonical simulation state and changes only through the fixed-step command/executor boundary.

## Canonical position

Every current spatial runtime entity uses:

```text
Component::Position(x, y, z)
```

The coordinate convention is:

```text
+X = east/right
+Y = up
+Z = south / authored grid +Y
```

Current grid-authored actors begin at cell centers:

```text
cell (x, y) -> Position((x + 0.5) * 32, 0.0, (y + 0.5) * 32)
```

The renderer draws entities directly from these coordinates. There is no renderer-owned entity position and no player-only spatial component.

## FirstPersonView and Camera3D

`FirstPersonView` owns logical:

- yaw;
- pitch;
- eye height;
- field of view;
- mouse sensitivity.

It is plain Aogera state, not a raylib FFI object.

`Render::Raylib3D` combines the controlled entity's `Position` with `FirstPersonView` to derive the camera eye and target. `RaylibAPI` performs conversion into raylib `Camera3D`/`Vector3` structures near the native boundary.

The controlled player is omitted from the ordinary entity drawing pass because the current presentation is first person.

## Input cadence

Keyboard actions follow the gameplay/fixed-step path. Mouse deltas are applied to `FirstPersonView` once per rendered frame, including frames in which zero simulation ticks are due.

This keeps looking smooth at frontend cadence without making rendering FPS define gameplay speed.

`Host::Raylib` captures the cursor once after opening/focusing the window and releases it during shutdown.

## Ground movement

All current actor locomotion enters simulation as:

```text
Simulation::Commands::GroundMove(entity_id, dx, dz)
```

Player movement is generated from exact view yaw every 30 Hz simulation tick while movement input is held. NPC behavior also emits `GroundMove`; its path/behavior decisions currently occur at a lower cadence.

Both are resolved by the same `Simulation::GroundMovement` and continuous X/Z collision path.

## Ground collision visible through the frontend

Actors can carry `GroundBody(radius)`. `GroundSpace#sweep_circle` sweeps that body across requested X/Z displacement against impassable authored terrain cells and active blocking ground bodies.

`GroundMovement` moves to exact contact, accumulates distinct contact normals, and constrains remaining displacement against the full active contact set. This supports wall sliding and stable compound wall/actor contacts without axis-separated movement or anti-tunneling substeps.

Vertical actor collision, gravity, jumping, and arbitrary 3D collision shapes are not part of the current frontend/runtime contract.

## Current world drawing

The normal launch still uses the authored grid directly for temporary static-world presentation. Tile width/length come from the level's normalized `cell_size` (32 world units for current authored content):

```text
passable tile -> floor primitive
blocked tile  -> wall primitive
```

The BSP29 preview adds a second static-world drawing path:

```text
BSP29::MapData
    -> world model 0 faces
    -> surfedges / edges / vertices
    -> convex face triangulation
    -> RaylibAPI
```

Dynamic renderable entities are still drawn at canonical `Position` values. For the controlled preview, the matching Ruby `test_field` remains authoritative for gameplay/collision/navigation while BSP29 supplies visible static geometry.

This is intentionally a simple RC bridge. There is no `Scene3D`, `Projector3D`, model/material framework, or generic transform hierarchy.

## Navigation is separate

`Simulation::Pathfinder` still uses the authored grid as temporary BFS navigation data. It derives cells with:

```text
cell_x = floor(position.x / level.cell_size)
cell_z = floor(position.z / level.cell_size)
```

Those cells are not renderer state and are not stored as entity positions. NPC movement returns to continuous world-space displacement before entering `GroundMove`.

## Combat and interaction

The renderer does not define combat geometry.

`MeleeAttack(reach, arc_degrees)` and `Interactor(reach, arc_degrees)` remain authored gameplay data. Player and NPC melee validation use continuous body separation and segment obstruction traces; interaction uses the same spatial foundation with separate eligibility semantics.

## Raylib boundary

Raylib-specific FFI structures remain near `RaylibAPI` and the frontend. Core simulation and world components use Ruby data rather than raylib types.

This preserves the useful platform boundary established before the 3D renderer and keeps future BSP/static-world work independent from raylib's native structures.

## Still deferred

Aogera 0.3.2 does not introduce:

- BSP hull/clipnode collision;
- BSP palette/texture sampling and lightmaps;
- PVS-driven BSP visibility;
- vertical actor physics;
- projectile or hitscan rendering/simulation;
- model or texture asset pipelines;
- a general material framework;
- generic scene/transform/physics abstractions.

The important frontend state is already normalized: rendering, camera placement, movement, collision, and NPC/player positions consume the same continuous runtime world coordinates.
