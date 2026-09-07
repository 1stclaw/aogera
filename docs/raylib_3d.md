# Aogera 0.3.1: first-person raylib 3D path

Aogera 0.3.1 turns the 0.3.0 fixed overview into the first playable first-person 3D frontend while deliberately retaining the existing grid simulation underneath it.

## Active path

```text
raylib frame
    |
    +-- Host::Raylib polls keys + mouse delta
    |
    +-- Input::Mapper
    |       |
    |       +-- Action ------> Handoff / Tracker --> fixed simulation ticks
    |       |
    |       +-- LookDelta ---> FirstPersonView ----> current rendered frame
    |
    +-- Level + World::View + FirstPersonView
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

Mouse look is intentionally updated at frontend/render cadence rather than at the 30 Hz simulation cadence. The logical view is still an Aogera object; raylib `Camera3D` and `Vector3` values remain confined to `RaylibAPI`.

## FirstPersonView

`FirstPersonView` owns only the concrete state now required by first-person control:

- yaw;
- pitch;
- eye height;
- vertical field of view;
- mouse sensitivity.

It also provides a forward vector and a temporary cardinal heading for the existing grid gameplay bridge. It is not a generic transform, physics body, scene camera, or world-space entity component.

Pitch is clamped so the camera cannot flip over. The initial yaw is derived from the player's authored cardinal `Facing` at the level entry.

## Temporary grid movement bridge

The canonical axes remain:

```text
+X = east/right
+Y = up
+Z = south / old grid +Y
```

Player position is still `Component::Position(x, y)`. The camera eye is placed at the center of that grid cell:

```text
world X = grid x + 0.5
world Y = eye height
world Z = grid y + 0.5
```

W/S now mean forward/back and A/D mean strafe left/right. Arrow keys mirror those four actions. At each simulation tick, the current view yaw is reduced to the nearest cardinal direction and translated back into the existing integer `Move(dx, dy)` command.

This is intentionally transitional. It gives the current game correct first-person control semantics without pretending that grid position is a permanent 3D movement model.

## Combat and interaction

Adjacent melee attack and interaction targeting now use the current view heading. This matters because first-person looking can rotate independently of movement.

The old `Facing` component still exists and is still updated by successful or blocked grid movement through the existing simulation executor, but it no longer determines player attack/interaction direction.

## Renderer

`Render::Raylib3D` now derives its camera from:

```text
World::View player Position
        +
FirstPersonView orientation
```

The controlled player entity is hidden from the first-person render pass. Other renderable entities remain primitive cubes for now.

The renderer still consumes `Level + World::View` directly. There is still no `Scene3D`, `Projector3D`, generic renderer, or transform hierarchy.

## Cursor ownership

`Host::Raylib` captures/disables the cursor once after opening and focusing the raylib window, and releases it before closing. `RaylibAPI` owns the direct `DisableCursor`, `EnableCursor`, and `GetMouseDelta` calls.

## Still deferred

0.3.1 does **not** introduce:

- continuous player world position;
- velocity or acceleration;
- 3D collision/physics;
- jumping or vertical movement;
- projectile simulation;
- BSP loading;
- models/textures/materials;
- generic spatial/transform abstractions;
- a general asset manager.

The next movement/collision milestone should replace the temporary grid bridge only when a concrete continuous 3D requirement is ready to become authoritative.
