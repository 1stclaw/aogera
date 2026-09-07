# Aogera 0.3.0: unified continuous 3D runtime positions

Aogera's active 3D frontend now consumes the same canonical runtime position used by simulation and collision.

## Active path

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

Mouse look remains frontend/render-frame state. Translation remains canonical simulation state and changes only through the fixed-step command/executor boundary.

## Position

Every runtime spatial entity uses:

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
cell (x, y) -> Position(x + 0.5, 0.0, y + 0.5)
```

The renderer draws entities directly from these coordinates. The first-person camera uses the controlled entity's `Position`, adding `FirstPersonView#eye_height` to Y.

There is no separate renderer position and no player-only ground-position component.

## GroundMove

All current actor locomotion enters simulation as:

```text
Simulation::Commands::GroundMove(entity_id, dx, dz)
```

Player movement is generated from exact view yaw every 30 Hz simulation tick while input is held. NPC behavior also emits `GroundMove`; its route selection currently runs at a lower decision cadence.

Both are resolved by `Simulation::GroundMovement` and the same continuous collision path.

## Ground collision

Actors can carry `Component::GroundBody(radius)`. `GroundSpace#sweep_circle` sweeps that body across the requested X/Z displacement against impassable authored terrain cells and active blocking ground bodies, returning the earliest `GroundTrace`.

`GroundMovement` moves to exact contact, accumulates distinct contact normals, and constrains remaining displacement against the active contact set. This supports wall sliding and stable wall/actor compound contacts without X-first/Z-second resolution or anti-tunneling substeps.

This is not a generic physics system. Vertical actor collision, gravity, velocities, forces and arbitrary 3D shapes remain deferred.

## Navigation is separate from position

The current `Simulation::Pathfinder` still uses the authored terrain grid for BFS. It derives temporary navigation cells from canonical positions:

```text
cell_x = floor(position.x)
cell_z = floor(position.z)
```

Those cells are planning data only. NPC entities themselves remain continuously positioned and execute movement through the same sweep solver as the player.

## Combat and interaction

`GroundSpace` combines canonical continuous positions, `GroundBody` radii and action-specific authored profiles. `MeleeAttack(reach, arc_degrees)` and `Interactor(reach, arc_degrees)` remain gameplay data rather than collision constants.

Player and NPC melee validation use continuous body separation and segment obstruction traces. Interaction uses the same spatial foundation with separate eligibility semantics.

## Still deferred

The current runtime does **not** introduce:

- vertical actor movement, gravity or jumping;
- generic physics or transforms;
- BSP loading/collision;
- BSP/navigation integration;
- projectile simulation;
- models/textures/materials;
- a general asset manager.

The important normalization is already complete: BSP will not need to reconcile a player-only continuous coordinate with grid-positioned NPCs before replacing static world collision.
