# Aogera 0.3.0: first raylib 3D path

Aogera 0.3.0 replaces the transitional 2D presentation path with the first true 3D renderer while deliberately leaving gameplay simulation unchanged.

## Scope

The active path is:

```text
Level + World::View
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

`Raylib3D` consumes the authored level and read-only runtime world directly. This milestone does not introduce a `Scene3D` or `Projector3D`; a BSP-backed static world may eventually want a substantially different render path.

## Temporary grid extrusion

The existing level is rendered in world units with one grid cell equal to one unit on X/Z.

```text
grid x -> world +X
grid y -> world +Z
world +Y -> up
```

Non-wall terrain becomes a thin floor cube below Y=0. Wall tiles become one-unit-high cubes. Runtime entities that possess both `position` and `renderable` components become smaller vertical cubes centered in their grid cells.

Requiring `renderable` preserves the existing defeat behavior: defeated entities may retain a position but stop being presented after their renderable component is removed.

## Camera

The first camera is a fixed perspective overview chosen from level dimensions. Its purpose is to prove the coordinate convention and real 3D drawing path, not to become the permanent player camera.

`RaylibAPI#begin_mode_3d` receives plain Ruby arrays and constructs the actual raylib `Camera3D`. This keeps FFI values out of the rest of Aogera.

## Preserved gameplay

The following remain unchanged in 0.3.0:

- 30 Hz fixed-step simulation;
- 60 FPS target frontend cadence;
- keyboard event mapping and held-state tracking;
- grid `Position(x, y)`;
- cardinal movement/facing;
- terrain passability and occupancy;
- BFS pathfinding/chase behavior;
- melee adjacency;
- dialogue/mode transitions;
- session persistence.

Existing keyboard movement is therefore visible as entities moving from 3D cell to 3D cell.

## Deliberately deferred

This patch does not add:

- first-person camera control;
- mouse input;
- continuous 3D position;
- 3D collision or physics;
- projectiles;
- BSP;
- models or textures;
- lights/shaders;
- an asset manager;
- generic renderer/scene/transform abstractions.

The next milestone should introduce first-person control and let that implementation determine the first real continuous spatial state.
