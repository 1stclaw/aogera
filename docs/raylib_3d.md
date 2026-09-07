# Aogera 0.3.0: continuous first-person ground movement

Aogera 0.3.0 replaces the temporary player grid-stepping bridge with continuous X/Z movement while keeping the existing grid systems alive for NPC gameplay.

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
    +-- GroundPosition + FirstPersonView
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

Mouse look remains frontend/render-frame state. Player translation remains canonical simulation state and changes only through the fixed-step command/executor boundary.

## GroundPosition

The controlled persistent character receives:

```text
Component::GroundPosition(x, z)
```

This is deliberately a ground-plane coordinate rather than a padded `Position3D` or generic transform. Aogera does not yet have vertical player motion, velocity, acceleration or a general 3D body model.

The coordinate convention is:

```text
+X = east/right
+Y = up
+Z = south / old grid +Y
```

Authored grid entries initialize continuous position at the cell center:

```text
grid (x, y) -> ground (x + 0.5, z = y + 0.5)
```

`Render::Raylib3D` now places the first-person camera directly at the controlled entity's `GroundPosition`, plus `FirstPersonView#eye_height` on Y.

## GroundMove

Player movement now enters simulation as:

```text
Simulation::Commands::GroundMove(entity_id, dx, dz)
```

`RealtimeController` emits one ground-motion command for every simulation tick while movement input is held. The default speed is expressed in world units per second and converted to a 30 Hz per-tick displacement.

Movement uses exact view yaw rather than reducing yaw to a cardinal direction. Forward and strafe vectors are combined and normalized, so diagonal input does not move faster.

The old integer `Simulation::Commands::Move(dx, dy)` remains active for NPC wandering/pathfinding.

## Ground collision

`Simulation::GroundMovement` is intentionally small and specific to ground-plane locomotion.

Actors can carry `Component::GroundBody(radius)`. `GroundSpace#sweep_circle` continuously sweeps that circle across the complete requested X/Z displacement against impassable authored terrain cells and blocking ground bodies, returning the earliest `GroundTrace`. Large commands therefore cannot tunnel through a one-cell wall without relying on movement substeps.

`GroundMovement` moves to the exact trace contact position and accumulates distinct contact normals during the movement command. Remaining displacement must satisfy the full active contact set before another sweep, so compound contacts such as an actor beside a wall stop or slide without pushing the player through either surface. Resolution remains bounded to a small fixed number of contacts. Wall sliding is therefore geometric rather than X-first/Z-second.

This is not a generic physics system. There are no velocities, forces, rigid bodies, collision layers, arbitrary 3D shapes or vertical collision rules.

## Coarse grid synchronization

Several established systems still consume `Component::Position(x, y)`:

- NPC pathfinding;
- NPC chase/adjacency decisions;
- authored grid occupancy.

For the controlled character, `GroundPosition` is now authoritative for physical location. After ground movement, the executor synchronizes `Position` to the cell containing the continuous player center:

```text
grid x = floor(ground x)
grid y = floor(ground z)
```

Dynamic blockers no longer occupy their whole authored cell for continuous collision. `GroundBody` supplies their horizontal radius, while their grid `Position` supplies a temporary center until they gain continuous positions of their own.

Player `Facing` is no longer updated by continuous translation. `FirstPersonView` owns actual look direction. `GroundSpace` combines that continuous heading with action-specific authored profiles: `MeleeAttack(reach, arc_degrees)` for melee and `Interactor(reach, arc_degrees)` for interaction. These queries are no longer cardinal or grid-adjacent. After reach/arc filtering, a zero-radius ground segment trace rejects targets hidden behind static terrain or another blocking ground body.

## Still deferred

0.3.0 does **not** introduce:

- vertical player motion or jumping;
- velocity/acceleration;
- generic physics or transforms;
- continuous NPC navigation;
- full 3D ray/capsule/volume tracing;
- projectile simulation;
- BSP loading/collision;
- models/textures/materials;
- a general asset manager.

The current ground trace/sweep contract gives BSP work a stable collision-query boundary: a later BSP backend can replace static terrain-cell intersection while movement and action code keep consuming structured trace results.
