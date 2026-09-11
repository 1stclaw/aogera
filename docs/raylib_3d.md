# Aogera 0.3.2a Raylib 3D Frontend

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

For the normal Ruby/grid static-world path, entity drawing still respects `Level` bounds. In BSP mode, the renderer does not convert entity positions back to grid cells and does not use `Level#inside?` as a drawing gate; positioned/renderable entities are drawn directly from canonical world-space `Position`.

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

Dynamic renderable entities are still drawn at canonical `Position` values. In the v0.3.4 BSP preview, the bound player position comes directly from the map's `info_player_start`; the Ruby `test_field` is no longer loaded by the BSP launcher. `Mode::Spectator` starts its camera at that player's eye position and then supplies an explicit camera position to `Render::Raylib3D`, leaving actor `Position` untouched while it flies through geometry. The current one-cell `Level` terrain is inert structural scaffolding only, while BSP29 supplies visible static geometry and configured collision queries.

This is intentionally a simple RC bridge. There is no `Scene3D`, `Projector3D`, model/material framework, or generic transform hierarchy.

## Navigation is separate

Active chase navigation is a simulation concern and does not depend on renderer state.

`Simulation::GroundNavigation` consumes continuous runtime positions and probes short candidate movements through `GroundSpace`. In BSP mode those positive-radius probes reach the same `BSP29::GroundClearance` backend used by actual `GroundMovement`. `GroundSteering` stores/uses a normalized local `GroundHeading` and emits ordinary fixed-step `GroundMove` commands.

The obsolete grid `Simulation::Pathfinder` has been removed. Active chase uses continuous local navigation and does not expose navigation cells to the renderer.

## Combat and interaction

BSP static rendering now has an explicit GPU-resource lifecycle. `Render::BSP29World` reconstructs world-model triangles on the Ruby side, derives BSP29 lightmap extents/UVs, packs baked grayscale samples into one padded atlas, and `Render::Raylib3D#prepare` uploads the persistent mesh plus atlas texture only after the raylib window/context opens. `#close` unloads both resources before the context closes. Drawing a BSP frame therefore issues a persistent model draw rather than one Ruby/FFI draw call per BSP triangle. Base Quake textures are still deferred; the atlas is currently used as the model's grayscale albedo solely to expose baked lighting.

In BSP spectator mode, `Render::Raylib3D` also draws a small diagnostic overlay after leaving 3D mode. It shows measured raylib FPS, the spectator camera position, yaw/pitch, BSP triangle count, mesh-draw count, lightmapped-face/atlas statistics, and runtime entity count. FPS is observational only: simulation still runs at the independent fixed 30 Hz cadence while the host targets 60 rendered frames per second.

The renderer does not define combat geometry.

`MeleeAttack(reach, arc_degrees)` and `Interactor(reach, arc_degrees)` remain authored gameplay data. Player and NPC melee validation use continuous body separation and segment obstruction traces; interaction uses the same spatial foundation with separate eligibility semantics.

## Raylib boundary

Raylib-specific FFI structures remain near `RaylibAPI` and the frontend. Core simulation and world components use Ruby data rather than raylib types.

This preserves the useful platform boundary established before the 3D renderer and keeps future BSP/static-world work independent from raylib's native structures.

## Still deferred

Aogera 0.3.4 still defers:

- BSP palette/base-texture sampling and animated/multi-style lightmap evaluation;
- PVS-driven BSP visibility;
- vertical actor physics;
- projectile or hitscan rendering/simulation;
- model or texture asset pipelines;
- a general material framework;
- generic scene/transform/physics abstractions.

The important frontend state is already normalized: rendering, camera placement, movement, collision, and NPC/player positions consume the same continuous runtime world coordinates.
