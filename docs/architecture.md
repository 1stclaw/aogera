# Aogera Architecture

This document describes the current Aogera 0.3.4 runtime and its present boundaries. The core BSP collision-authority split descends from the stable 0.3.2a checkpoint, 0.3.3 completed the continuous-navigation cutover, and 0.3.4 changes BSP bootstrap and rendering without replacing that collision boundary.

## Design goals

Aogera favors a small, explicit, data-oriented runtime over framework-heavy abstractions.

- keep persistent, authored, runtime, control/view, and presentation state separate;
- keep `Simulation` independent of wall-clock time and host input;
- schedule simulation with a fixed-step policy outside the core simulation;
- keep rendering downstream of canonical runtime/control state;
- maintain one canonical runtime spatial representation;
- let gameplay systems consume shared spatial facts instead of duplicating collision geometry;
- add abstractions only when concrete gameplay or performance requirements need them.

## Lifetime model

```text
persistent              authored pipeline                 runtime
----------------        -------------------------         ----------------
Session                 source file                       Simulation
└── Character               |                             ├── World
                            v                             ├── Bindings
                         Reader                           ├── Executor
                            |                             └── step number
                            v
                     Level::AuthoredData
                            |
                            v
                         Loader
                            |
                            v
                          Level
                        ├── Terrain
                        ├── Spawns
                        ├── Entries
                        └── Relations

control/view
----------------
FirstPersonView
├── yaw / pitch
├── eye height
└── FOV / mouse sensitivity
```

`Session` owns persistent character state. `Character` is an immutable validated `Data` value and persistent updates replace it with `Data#with`. Public persistent mutation enters through `Session#apply_effects`; effect-specific replacement helpers remain internal, and unsupported healing/MP verbs are not exposed ahead of real gameplay systems. `Level` is immutable authored structure. `World` is the canonical mutable runtime container and owns entity IDs, component tables, and runtime relations. Runtime entity IDs never serve as persistent identity.

`FirstPersonView` owns logical first-person orientation and updates at render cadence. It is not raylib camera state and it is not the player's physical position.

`World::View` is a cached read-only facade over `World`; callers receive the same view object rather than allocating wrappers repeatedly. `World#entity_ids` similarly caches its immutable existing-entity snapshot and invalidates it only on spawn/despawn.

### Active, retired, despawned

Runtime lifetime distinguishes existence from gameplay activity.

```text
active
  |
  | defeat / retirement
  v
retired
  |
  | explicit despawn
  v
despawned
```

`Component::Retired` marks an entity that still exists in `World` but no longer participates as an active actor. Retired entities remain in `entity_ids` and may retain descriptive state such as `Position`, `GroundBody`, health, or prototype identity. The executor rejects movement/action commands from retired entities, and ordinary `GroundSpace` dynamic scans omit them. Despawn removes runtime identity entirely.

Retirement is therefore not inferred from health or from a particular list of deleted components.

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

The current flat authored levels spawn actors at Y = 0.0. Source-format readers normalize authored coordinates before runtime loading. The current Ruby/grid reader uses 32 world units per cell:

```text
cell (x, y) -> Position((x + 0.5) * 32, 0.0, (y + 0.5) * 32)
```

The grid coordinate is not retained as a second runtime entity position. There is no position synchronization step and no player/NPC distinction in spatial representation.

`GroundSpace` is the current shared X/Z geometry boundary. It reads canonical `Position`, reads authored `GroundBody` radii, computes separation/overlap, performs parameterized arc queries, and provides structured segment/swept-circle traces.

`GroundSpace` is intentionally ground-specific. Canonical 3D `Position` is justified by the real runtime, but Aogera does not yet claim generic 3D physics, vertical actor collision, or a universal spatial framework.

## Simulation boundary

`Simulation` owns one running level:

```text
Simulation
├── Level
├── World
├── Bindings
├── Executor
├── GroundSteering
└── step_number
```

Its mutation boundary is `Simulation#step(commands:)`. Command producers build `Simulation::Commands::Buffer` values; `Simulation::Executor` validates and applies them. After those decision/input commands are applied, `Simulation::GroundSteering` reads current `SteeringTarget` components and builds the per-tick locomotion commands, which are also executed through the same `Executor`. Persistent effects are emitted separately and applied by `Session`.

Current command types include:

```text
GroundMove
SetSteeringTarget
ClearSteeringTarget
SetGroundHeading
ClearGroundHeading
Attack
Defeat
Despawn
```

Gameplay producers request changes; `Executor` remains the authoritative mutation path.

## Movement and collision

All current actor locomotion ultimately uses:

```text
GroundMove(entity_id, dx, dz)
```

The player produces view-relative displacement directly every fixed simulation tick. NPC behavior instead updates persistent `SteeringTarget` intent on the existing low-frequency decision cadence. `Simulation::GroundSteering` resolves that goal every fixed simulation tick, asks `Simulation::GroundNavigation` for a local world-space heading, and emits capped `GroundMove` displacement at `NPC_SPEED / TICK_HZ`. Player and NPC movement are therefore both resolved by the same `GroundMovement` and the same `GroundSpace#sweep_circle` collision path, while NPC behavior timing no longer controls either physical movement cadence or local obstacle response.

NPC behavior can persist:

```text
SteeringTarget(x, z, goal_entity_id)
```

`SteeringTarget` is runtime goal data, not a second position and not velocity. For static/wander goals, `x/z` are used directly. For chase goals, `goal_entity_id` lets `GroundSteering` resolve the target entity's live `Position` every fixed tick. Local navigation can additionally persist the previous normalized `GroundHeading(dx, dz)` under the `:ground_heading` component key.

A behavior decision chooses or clears the high-level goal; `GroundNavigation` chooses the current local heading; `GroundSteering` converts that heading into one-tick displacement. Retirement and explicit target clearing remove both steering target and heading. A successful attack also clears navigation intent, while a rejected attack leaves pursuit intact for the steering phase later in the same simulation step.

### Current body model

Ground actors can carry:

```text
GroundBody(radius)
```

This describes current horizontal collision extent only. It does not imply mass, velocity, vertical extent, or rigid-body physics.

Static collision has two current backends. The normal Ruby/grid launch uses cell-shaped terrain collision. In the BSP preview, all current actor static movement uses BSP29 compiled hull 1 through `BSP29::GroundClearance`. Active blocking dynamic actors with `GroundBody` remain circles.

### Trace contract

The active static-world backend and dynamic bodies participate in one earliest-hit result:

```text
GroundTrace
├── fraction
├── end_x / end_z
├── normal_x / normal_z
├── entity_id
├── world_hit
└── start_blocked
```

Segment traces are used for obstruction queries. Swept-circle traces are used for moving ground bodies.

Trace endpoints are exact contact positions; the trace service does not nudge authoritative positions by collision epsilon.

### Multi-contact movement

`GroundMovement` accumulates distinct contact normals during one movement command. Remaining displacement is constrained against the active contact set rather than resolving one surface and forgetting it.

This handles compound contacts such as a player being constrained simultaneously by a wall and another actor. Repeated zero-fraction contact against the same surface is treated defensively rather than consuming the full contact budget.

After collision resolution, `GroundMovement` validates that the returned body does not begin inside active solid geometry. If numerical error violates that invariant, it returns the command's known-valid start rather than storing a penetrated position or attempting speculative depenetration.

This is collision/locomotion policy, not a general physics engine.

## Navigation

Active NPC chase no longer uses grid BFS.

The current BSP/world-space chase path is:

```text
Behavior(:chase)
      |
      | low-frequency goal refresh
      v
SteeringTarget(goal entity)
      |
      | every fixed simulation tick
      v
GroundNavigation
      |
      v
GroundHeading
      |
      v
GroundSteering
      |
      v
GroundMove
      |
      v
GroundMovement / GroundSpace
```

`RealtimeController` no longer owns or calls `Simulation::Pathfinder`. Chase behavior only resolves its relation target, stores a world-space `SteeringTarget`, and attempts melee according to the existing behavior cadence. When a steering target contains `goal_entity_id`, `GroundSteering` resolves that entity's current `Position` every simulation tick, so local pursuit follows a moving target between behavior updates.

`Simulation::GroundNavigation` operates on the actor's actual continuous `Position`, authored `GroundBody`, optional previous `GroundHeading`, and `GroundSpace`. It has no cell, BFS, BSP-format, or `Level::Terrain` topology knowledge. Short candidate movements are validated through the same `GroundSpace#sweep_circle` collision query used by actual locomotion.

It returns one of four outcomes:

```text
arrived
direct
local_avoidance
route_needed
```

Direct pursuit is preferred. When direct movement is blocked, the query may reuse a useful previous heading, derive tangents from the blocking contact normal, and probe deterministic rotated alternatives. `route_needed` means only that local navigation cannot currently provide a usable heading. In the current implementation the goal is kept, the unusable heading is cleared, and local navigation retries on the next simulation tick. A future collision-certified route graph can use this outcome as its fallback seam.

The active `GroundHeading` is stored in runtime component data so local movement has limited directional memory without keeping a global path. `GroundMovement` remains authoritative for actual sweep-and-slide resolution; navigation only proposes a heading worth trying.

The obsolete grid `Simulation::Pathfinder` implementation and its cell-edge cache have been removed from the source tree. Their historical role is documented in `docs/navigation_migration.md`; active navigation code should not reintroduce cell-center routing as a compatibility layer.

The Ruby grid still exists for authored level/spawn/entry scaffolding and the normal non-BSP fallback. It is no longer required to choose active BSP goblin chase directions. See `docs/navigation_migration.md` for the migration history and future GoldSrc-like collision-certified route-graph direction.

## Combat

Ground actors can carry an authored melee profile:

```text
MeleeAttack(reach, arc_degrees)
```

Player target selection combines:

- current first-person heading;
- authored reach and attack arc;
- continuous body separation;
- segment obstruction traces through the shared `GroundSpace#unobstructed_between?` entity query.

NPC chase/combat uses the same continuous separation and obstruction model before emitting `Attack`.

`Simulation::Executor` validates melee attacks through the same `GroundSpace` reach/trace facts regardless of attacker type. Manhattan/grid adjacency is not a runtime combat rule.

Damage remains separate from targeting and delivery. A successful spatial target does not itself define damage, retirement, or future weapon effects.

## Interaction

Interaction remains semantically separate from combat.

```text
Interactor(reach, arc_degrees)
```

Interaction target selection uses the same position, range/arc, and obstruction foundation but filters for `Interactable` entities and then invokes interaction-specific behavior.

This is also the spatial basis intended for future interactive world entities such as doors: they can occupy canonical world space and expose their own interaction/collision state without requiring another coordinate system.

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

`Render::Raylib3D` remains the first-person frontend and draws dynamic renderable entities from canonical `Position`. Static-world drawing currently has two explicit paths:

```text
Ruby/grid Level -> primitive floor/wall extrusion
BSP29::MapData -> Render::BSP29World -> reconstructed world-model batches -> persistent raylib meshes
```

The controlled player is omitted from the first-person entity pass. The BSP preview renders world model `0` only and intentionally bypasses any generic scene representation.

The camera eye uses the controlled entity's `Position` plus logical eye height. Its target comes from the `FirstPersonView` forward vector.

There is no `Scene3D`, `Projector3D`, generic transform hierarchy, or generic physics system. `RaylibAPI` owns conversion from plain Ruby camera/geometry values into `raylib-bindings` FFI types.

## Authored content and assets

Authored Ruby data currently lives in:

```text
content/prototypes/
content/levels/
content/dialogue/
```

Map/world authored data now has an explicit Reader/Loader boundary:

```text
source file -> Reader -> Level::AuthoredData -> Level::Loader -> Level
```

`Level::Readers::Ruby` understands the current Ruby/grid source format and converts source grid positions into Aogera world coordinates. `Level::Loader` accepts normalized `Level::AuthoredData` only and owns Aogera-facing validation/construction rather than file parsing.

Aogera world-unit magnitude is Quake 1 compatible: one current grid cell is 32 world units. This is a measurement convention only; Quake entity-origin and gameplay conventions are not imported into core runtime semantics.

`BSP29::Reader` is the first external Reader. It returns normalized `BSP29::MapData` rather than forcing BSP structure through the grid-shaped `Level::AuthoredData`. `Level::Loader` therefore remains honest about the representation it currently constructs.

`Content::Paths` still centralizes current authored Ruby paths. There is intentionally no general asset manager yet.

## Current v0.3.4 boundary

Aogera 0.3.4 currently has:

- one continuous runtime position model for player, enemies, NPCs, and spatial interactables;
- one ground movement/collision execution path for current actors;
- one trace-result contract for movement and obstruction;
- continuous player/NPC melee validation;
- explicit retired-entity lifecycle state;
- continuous local NPC navigation through `GroundNavigation`, with the obsolete grid Pathfinder removed after cutover validation;
- a Reader -> normalized authored data -> Loader map boundary;
- Quake 1-compatible world-unit magnitude with 32-unit current grid cells;
- a validated BSP29 Reader preserving geometry, BSP tree, clipnodes, textures, entities, visibility/light blobs, and submodels;
- a minimal BSP29 world-model renderer used by the controlled test-field preview;
- a BSP-only `Mode::Spectator` whose camera is detached from gameplay collision for arbitrary-map inspection;
- BSP29 compiled hull 1 through shared `GroundClearance` as the actor static movement backend;
- BSP29 world-model node/leaf tracing for melee and interaction obstruction.

It does not yet contain:

- vertical actor collision, gravity, jumping, floor/ceiling/step handling;
- projectiles or hitscan weapons;
- generalized collision masks;
- generic physics, transform, or spatial frameworks;
- a general asset manager.

In BSP mode, dynamic entity rendering consumes canonical `Position` directly and no longer uses Ruby-grid bounds as a presentation gate. The configured gameplay runtime still shares one BSP-backed `GroundSpace` / `BSP29::GroundClearance` source for actor movement and local-navigation probes, but the v0.3.4 diagnostic `Mode::Spectator` intentionally does not execute those systems: its camera keeps separate view-space coordinates and flies collision-free while the bound player stays at `info_player_start`. BSP launch no longer loads the Ruby `test_field`; `BSP29::Bootstrap` supplies only an inert one-cell terrain because the current `Level`/`Simulation` API still structurally requires one. That terrain has no BSP gameplay authority. Brush-submodel behavior can continue to evolve independently from the canonical entity-position model.

The detailed migration history, fixed-hull constraint, current authority map, and incremental pathfinding roadmap are recorded in `docs/bsp_collision_migration.md`.
