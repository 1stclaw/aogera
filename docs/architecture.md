# Aogera Architecture

This document describes the current Aogera 0.3.0 development runtime and its present boundaries.

## Design goals

Aogera favors a small, explicit, data-oriented runtime over framework-heavy abstractions.

- keep persistent, authored, runtime, control/view, and presentation state separate;
- keep `Simulation` independent of wall-clock time and host input;
- schedule simulation with a fixed-step policy outside the core simulation;
- keep rendering downstream of canonical runtime/control state;
- maintain one canonical runtime spatial representation;
- add abstractions only when concrete gameplay or performance requirements need them.

## Lifetime model

```text
persistent              authored                 runtime
----------------        ----------------         ----------------
Session                 Level                    Simulation
└── Character           ├── Terrain              ├── World
                        ├── Spawns               ├── Bindings
                        ├── Entries              ├── Executor
                        └── Relations             └── step number

control/view
----------------
FirstPersonView
├── yaw / pitch
├── eye height
└── FOV / mouse sensitivity
```

`Session` owns persistent character state. `Level` is immutable authored structure. `World` is the canonical mutable runtime container and owns entity IDs, component tables, and runtime relations. Runtime entity IDs never serve as persistent identity.

`FirstPersonView` owns logical first-person orientation and updates at render cadence. It is not raylib camera state and it is not the player's physical position.

`World::View` is a cached read-only facade over `World`; callers receive the same view object rather than allocating wrappers repeatedly. `World#entity_ids` similarly caches its immutable existing-entity snapshot and invalidates it only on spawn/despawn.

Runtime lifetime distinguishes existence from gameplay activity. `Component::Retired` marks an entity that still exists in `World` but no longer participates as an active actor. Retired entities remain in `entity_ids` and may retain descriptive state such as `Position`, `GroundBody`, health, or prototype identity. The executor rejects movement/action commands from retired entities; despawn removes runtime identity entirely.

## Canonical runtime position

Every spatial runtime entity uses:

```text
Component::Position(x, y, z)
```

Aogera's coordinate convention is:

```text
+X = east/right
+Y = up
+Z = south
```

The current flat authored levels spawn actors at Y = 0.0. Authored cell coordinates are converted at instantiation time:

```text
cell (x, y) -> Position(x + 0.5, 0.0, y + 0.5)
```

The grid coordinate is not retained as a second runtime entity position. There is no position synchronization step and no player/NPC distinction in spatial representation.

`GroundSpace` is the current shared X/Z geometry boundary. It reads canonical `Position`, reads authored `GroundBody` radii, computes separation/overlap, performs parameterized arc queries, and provides structured segment/swept-circle traces. Static terrain cells and active dynamic bodies participate in one earliest-hit result containing reached fraction, end position, contact normal, dynamic entity/static-world identity, and start-blocked state. Automatic dynamic scans skip retired entities even when retained body data remains.

`GroundSpace` is intentionally still ground-specific. A canonical 3D `Position` is now justified by the real runtime, but Aogera does not yet claim to have generic 3D physics, vertical actor collision, or a universal spatial framework.

## Simulation and movement

`Simulation` owns one running level:

```text
Simulation
├── Level
├── World
├── Bindings
├── Executor
└── step_number
```

Its mutation boundary is `Simulation#step(commands:)`. Command producers build `Simulation::Commands::Buffer` values; `Simulation::Executor` validates and applies them. Persistent effects are emitted separately and applied by `Session`.

All current actor locomotion uses one command:

```text
GroundMove(entity_id, dx, dz)
```

The player produces view-relative continuous displacement every fixed simulation tick. NPC behavior currently produces ground displacement at the lower NPC decision cadence. Both are executed by the same `GroundMovement` and the same `GroundSpace#sweep_circle` collision path.

`GroundMovement` uses the moving entity's authored `GroundBody(radius)`. Impassable terrain is currently cell-shaped; blocking actors with `GroundBody` are circles. Sweeps find the earliest collision across the complete requested displacement. Distinct contact normals are accumulated during one movement command and remaining motion is constrained against the active contact set, handling wall/actor compound contacts without axis-order bias.

Trace endpoints are exact contact positions. After contact resolution, `GroundMovement` verifies that the returned body does not begin inside active solid geometry; an invalid numerical result falls back to the command's known-valid start. This is collision/locomotion policy, not a general physics engine.

## Navigation

The current BFS Pathfinder remains grid-based because the authored test levels are grids. It is now explicitly a **navigation representation**, not an entity-position model.

For planning only:

```text
Position(x, y, z)
      |
      v
navigation cell = (floor(x), floor(z))
```

The Pathfinder checks terrain passability and projects active blocking entities into navigation cells. It returns a next-cell direction; `RealtimeController` converts that cell waypoint back into continuous world displacement and emits `GroundMove`.

This keeps the useful existing BFS while allowing a future BSP/navigation system to replace it without changing canonical entity coordinates or collision execution.

## Combat and interaction

Ground actors use authored `MeleeAttack(reach, arc_degrees)` profiles. Player target selection uses current first-person heading, authored reach/arc and segment obstruction traces. NPC chase logic uses the same continuous body separation and obstruction checks before emitting an `Attack` command.

`Simulation::Executor` validates melee attacks through continuous `GroundSpace` separation and trace queries regardless of whether the attacker is the player or an NPC. Manhattan/grid adjacency is no longer a combat rule.

Interaction remains semantically separate from combat. `Interactor(reach, arc_degrees)` uses the same spatial facts and obstruction traces but selects only interactable targets.

This common spatial model is also the intended foundation for future interactive entities such as doors: they should occupy canonical world space and expose their own interaction/collision state rather than requiring a separate coordinate system.

## Fixed-step scheduling

`App` owns the host loop and a monotonic `FixedStep`. The engine advances simulation at 30 Hz while raylib targets 60 rendered frames per second. A rendered frame may therefore contain zero or more simulation steps.

Keyboard/gameplay actions remain fixed-step input. Mouse yaw/pitch remains render-frame control state.

## Input

Keyboard/gameplay actions:

```text
Host::Raylib
    |
Host::KeyEvent
    |
Input::Mapper -> Input::Action
    |
Input::Handoff -> Input::Tracker
    |
Mode::Play -> RealtimeController -> Commands::Buffer -> Simulation#step
```

Mouse look:

```text
Host::Raylib
    |
Host::MouseMotion(dx, dy)
    |
Input::Mapper -> Input::LookDelta(dx, dy)
    |
FirstPersonView#rotate
    |
Render::Raylib3D
```

`Host::Raylib` captures the cursor once after opening/focusing the window and releases it before close.

Dialogue remains modal and currently pauses world advancement.

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

`Render::Raylib3D` directly extrudes the current grid level into primitive floors/walls and draws renderable entities from canonical `Position`. The controlled player is omitted from the first-person entity pass.

The camera eye uses the controlled entity's `Position` plus logical eye height. Its target comes from the `FirstPersonView` forward vector.

There is no `Scene3D`, `Projector3D`, generic transform hierarchy, or generic physics system. `RaylibAPI` owns conversion from plain Ruby camera/geometry values into `raylib-bindings` FFI types.

## Authored content and assets

Authored Ruby data currently lives in:

```text
content/prototypes/
content/levels/
content/dialogue/
```

`Content::Paths` centralizes paths used by the current Ruby loaders. There is intentionally no general asset manager yet.

## Near-term boundary

Aogera now has one continuous runtime position model for player, enemies and NPCs; one ground movement/collision execution path; one continuous melee validation model; and a separate temporary grid navigation representation.

The next BSP work can therefore focus on replacing static world geometry/collision and later navigation without first reconciling multiple runtime entity coordinate systems.
