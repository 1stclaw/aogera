# Aogera 0.3.2 Collision and Spatial Queries

This document describes the current Aogera 0.3.2 ground-space collision model.

The system is deliberately narrower than a general physics engine. It provides continuous X/Z spatial facts for current actors and gameplay while keeping the API suitable for a later replacement of static grid collision with BSP collision data.

## 1. Spatial authority

Every current spatial runtime entity uses:

```text
Position(x, y, z)
```

Ground-space collision consumes X/Z from that canonical position. Y remains real world-space state even though vertical actor collision is not implemented yet.

There is no second runtime grid-position component.

## 2. GroundBody

Current horizontal actor extent is authored as:

```text
GroundBody(radius)
```

A `GroundBody` means only that an entity occupies a circle of this radius on the X/Z ground plane.

It does not imply:

- mass;
- velocity;
- material;
- vertical extent;
- gravity;
- rigid-body simulation.

## 3. GroundSpace responsibilities

`GroundSpace` supplies shared spatial facts and collision queries.

Current responsibilities include:

- canonical position lookup;
- body-radius lookup;
- center distance;
- body-surface separation;
- circle overlap checks;
- parameterized forward-arc queries;
- segment traces;
- swept-circle traces.

It does not own weapon damage, AI policy, dialogue, lifecycle effects, or movement intent.

```text
movement / combat / interaction
            |
            | query spatial facts
            v
        GroundSpace
            |
            v
        GroundTrace
```

## 4. GroundTrace

A trace returns one structured earliest-hit result:

```text
GroundTrace
├── fraction
├── end_x
├── end_z
├── normal_x
├── normal_z
├── entity_id
├── world_hit
└── start_blocked
```

### fraction

`fraction` is the completed portion of the requested segment:

```text
0.0   blocked immediately
1.0   complete path reached
0..1  first collision occurred along the path
```

### end position

`end_x` / `end_z` are the exact reached endpoint of the query.

Trace results do not nudge authoritative positions along contact normals.

### contact normal

`normal_x` / `normal_z` describe the ground-plane contact normal used by movement to constrain remaining displacement.

### hit identity

`entity_id` identifies a dynamic body hit. `world_hit` identifies static terrain collision.

### start_blocked

`start_blocked` means the query started inside relevant collision geometry. Normal movement is expected to begin from valid state.

## 5. Segment traces

A segment trace has zero moving radius:

```text
trace_segment(start -> end)
```

It asks:

> What is the first relevant obstruction between these two ground points?

`GroundSpace#unobstructed_between?` is the shared entity-to-entity form of this query. It resolves source and target positions, ignores the source body, treats the target as an acceptable terminal hit, and treats other entities as obstructing only when their `Collision` component has `blocks_movement` enabled. Player targeting, NPC melee planning, and executor-side attack validation use this same query instead of rebuilding the trace/filter policy independently.

Current consumers include:

- melee obstruction;
- interaction obstruction;
- line-of-sight-like spatial checks.

In the BSP preview, zero-radius static obstruction is now provided by `BSP29::PointHull`, which traverses world-model headnode 0 through BSP nodes and leaves. Dynamic `GroundBody` circles still participate in the same earliest-hit query. The current ground-style combat model samples the BSP point trace 16 world units above the source `Position.y`; this keeps the trace off the floor/brush boundary without introducing vertical aiming, gravity, or a new actor-height model.

A segment trace is not an attack and does not define damage or target policy.

## 6. Swept-circle traces

A swept-circle query moves a ground circle continuously along the requested segment:

```text
sweep_circle(start -> end, radius)
```

It asks:

> How far can this ground body move before first contact?

Current player and NPC locomotion both use this query through one `Simulation::GroundMovement`. In BSP mode, the same `GroundSpace` sends all positive-radius static traces through `BSP29::GroundClearance`, while continuous `GroundBody` collision remains authoritative for dynamic actors:

```text
all actor static movement -> BSP29 hull 1 via GroundClearance
all actor dynamic contact -> GroundBody circles
```

`GroundClearance` caches a radius-bound `GroundHull` per authored actor radius. The player and NPCs therefore share one static collision source without pretending their authored radii resize the compiled hull.

The query covers the complete requested displacement, so anti-tunneling behavior does not depend on dividing movement into many artificial substeps.

## 7. Static terrain backends

The current authored level is still a grid. Impassable terrain cells remain the static collision source for the normal Ruby launch. In BSP mode, positive-radius player and NPC movement uses compiled BSP hull 1 instead.

```text
grid cell (x, z), cell size S

X = x * S .. (x + 1) * S
Z = z * S .. (z + 1) * S

Current authored grid levels use S = 32 world units.
```

The BSP preview additionally supplies explicit static-space BSP adapters:

- `BSP29::GroundClearance` supplies compiled hull-1 traces for actor movement and BFS step clearance;
- `BSP29::GroundHull` is the radius-bound fixed-hull adapter cached behind `GroundClearance`;
- `BSP29::PointHull` traces world-model headnode 0 through nodes/leaves for zero-radius melee and interaction obstruction.

Hull 1 is a fixed collision-source shape with horizontal half-extent 16 and vertical bounds -24..32 around the Quake hull origin; it is not derived from `GroundBody(radius)`. PointHull is shape-free and blocks only `CONTENTS_SOLID` for now; generalized Quake-style contents/masks remain deferred.

The current 0.3.2 policy is explicit rather than pretending those shapes are equivalent:

```text
BSP static clearance        -> compiled hull 1
actor-vs-actor clearance    -> authored GroundBody radius
```

`GroundHull` is constructed with the authored radius of the character it serves. `GroundSpace` forwards the moving body's radius into each BSP trace and `GroundHull` verifies that it matches the configured radius. The value does **not** resize the compiled hull; the check exists so a fixed BSP hull cannot silently be reused for a differently sized actor. `horizontal_clearance_delta` exposes the difference between hull 1's 16-unit half-extent and the bound `GroundBody` radius for diagnostics.

Static terrain participates in the same earliest-hit result as dynamic entities. Gameplay callers consume `GroundTrace`, not grid-cell or clipnode details.

## 8. Dynamic collision backend

Current dynamic blocking actors use circular `GroundBody` collision.

A moving body and stationary body are treated through their combined radii for swept collision.

Only dynamic entities selected by the caller's filter participate. Ordinary active scans also exclude retired entities.

The moving/source entity itself is ignored when appropriate.

## 9. Earliest-hit rule

Static and dynamic collision candidates compete in one query.

```text
static candidate hits
+
dynamic candidate hits
        |
        v
smallest valid fraction
        |
        v
GroundTrace
```

The caller receives the first relevant contact rather than a collection of overlapping results.

## 10. GroundMovement

`Simulation::GroundMovement` owns locomotion policy. `GroundSpace` owns intersection queries.

```text
desired displacement
        |
        v
sweep_circle
        |
        v
GroundTrace
        |
        v
move to exact contact
        |
        v
accumulate contact normal
        |
        v
constrain remaining displacement
        |
        v
repeat within bounded contact count
```

### Multi-contact constraints

Distinct contact normals are accumulated during one movement command.

This matters when an actor is constrained by more than one surface at once, for example a wall plus another actor. Remaining displacement must satisfy all active contact normals rather than resolving one contact and forgetting it.

### Duplicate near-zero contacts

A repeated near-zero hit against an already-recorded normal is treated defensively. The solver stops that remaining motion rather than exhausting contact iterations on the same surface.

### Final validity invariant

A movement command must not commit a result that already begins blocked.

After resolving contacts, `GroundMovement` verifies the returned body position with a zero-displacement sweep. If the result is invalid, the command returns its known-valid starting position rather than storing penetration or guessing a depenetration direction.

## 11. Melee

Melee policy is authored independently from collision geometry:

```text
MeleeAttack(reach, arc_degrees)
```

Player target selection combines:

- action eligibility;
- continuous separation;
- current view heading;
- authored attack arc;
- segment obstruction trace.

NPC melee uses the same continuous reach/obstruction foundation. The executor validates those facts regardless of whether the attacker is player-controlled or AI-controlled.

Grid/Manhattan adjacency is not a runtime melee rule.

Damage remains separate from target geometry.

## 12. Interaction

Interaction uses independent authored policy:

```text
Interactor(reach, arc_degrees)
```

It consumes the same position, separation, arc, and obstruction queries but applies interaction-specific target eligibility and behavior.

This keeps combat and interaction semantically separate while sharing spatial facts.

## 13. Retirement and collision

`Component::Retired` marks an entity that still exists in `World` but is no longer an active actor.

Retired entities may retain `Position` and `GroundBody`, but ordinary `GroundSpace` dynamic scans skip them. The executor also rejects active movement/attack commands from retired entities.

Retirement therefore does not require deleting descriptive spatial state simply to make an entity nonblocking.

## 14. Navigation relationship

The current BFS navigation grid is derived planning data, not collision authority for actor positions.

```text
Position
   |
   v
level.cell_for_world(x, z)
   |
   v
BFS next cell
   |
   v
Pathfinder::Waypoint(x, z)
   |
   v
continuous waypoint displacement
   |
   v
GroundMove
```

NPCs share the same continuous `Position`, `GroundMove`, `GroundBody`, and `GroundMovement` machinery with the player. In the current BSP preview their movement execution now uses BSP29 compiled hull-1 static clearance. BFS topology remains the grid, but candidate center-to-center transitions are checked through the same `BSP29::GroundClearance` instance used by spawned-NPC movement, so planning and execution no longer consult different static BSP sources.

The grid step is not exposed to steering. `Simulation::Pathfinder#next_waypoint` converts the chosen planning cell to a world-space `Pathfinder::Waypoint`, and `RealtimeController` consumes only that world-space target when constructing `GroundMove`.

## 15. Filtering

Aogera 0.3.2 does not introduce Quake-style contents/mask families.

Current trace calls support concrete filtering needs such as:

- ignoring the source/moving entity;
- selecting which dynamic entities participate;
- distinguishing static world from dynamic body hits;
- excluding retired entities from ordinary active queries.

More elaborate collision categories can be introduced when real gameplay requires them.

## 16. Current BSP authority boundary

The BSP preview is intentionally hybrid while collision is migrated incrementally:

```text
visible static world       -> BSP29 model 0
actor static movement     -> BSP29 compiled hull 1 via GroundClearance
zero-radius obstruction   -> BSP29 hull-0 node/leaf tree
BFS topology              -> Ruby grid
BFS static step clearance -> BSP29 compiled hull 1 via GroundClearance
dynamic actor collision   -> GroundBody circles
```

`App` now supplies one BSP-backed `GroundSpace` to `Mode::Play`, `RealtimeController`, and `Simulation::Executor`. Its positive-radius static traces use the same `BSP29::GroundClearance` object that the Pathfinder uses for candidate-step checks. `Simulation::Executor` no longer needs a separate bound-character movement service.

Standard BSP29 compiled hulls still have fixed clearance while Aogera authors smaller `GroundBody` radii. The controlled 32-unit water pinch in `test_field` exposes that mismatch: the player circle with radius 7.04 has positive clearance, while hull 1's 16-unit horizontal half-extent has zero clearance in a 32-unit gap.

For the current BSP preview that mismatch is accepted as a source-format limitation rather than hidden. `GroundClearance` caches a `GroundHull` bound to each encountered authored radius; for the player radius 7.04 that adapter reports a horizontal clearance delta of 8.96 units while still tracing the unmodified compiled hull. Supporting arbitrary authored radii for static BSP collision remains deferred until there is a collision source that can actually represent them.

Zero-radius melee/interaction obstruction now uses `BSP29::PointHull` through model headnode 0. `App` supplies the same BSP point-backed `GroundSpace` to player target selection, NPC melee planning, and executor-side attack validation, so those domains no longer disagree about static obstruction.

For navigation and actor movement, `App` supplies one shared `BSP29::GroundClearance` instance. The Pathfinder keeps the current grid cells, ordering, target-adjacent goals, and dynamic-cell occupancy behavior. During BFS expansion it converts the current and candidate cells to their world-space centers and accepts the transition only when compiled hull 1 is clear for the source actor. Those directed static transition answers are memoized by the Pathfinder per level, body radius, and feet height, while dynamic occupancy is always recomputed. The same `GroundClearance` object also supplies positive-radius BSP traces to the single `GroundMovement` execution path used by bound characters and spawned NPCs. `GroundClearance` caches a radius-bound `GroundHull` adapter per authored `GroundBody` radius; the radius remains a contract check and does not resize the fixed BSP hull.

Collision continues to use BSP collision/partition data rather than reconstructed render triangles.

## 17. Deferred collision work

Aogera 0.3.2 does not yet implement:

- vertical actor collision;
- gravity or jumping;
- floors/ceilings/step movement;
- arbitrary 3D actor shapes;
- projectiles or hitscan delivery;
- generalized contents/masks;
- rigid-body physics;
- arbitrary authored actor radii for BSP static collision;
- generic `Transform`, `PhysicsBody`, or `Spatial` frameworks.

The current invariant is narrower:

> **Aogera keeps one continuous runtime position/body model while BSP29 is the BSP-preview static collision authority and the remaining grid dependency is isolated to authored/navigation scaffolding and the normal Ruby fallback.**

For the detailed migration sequence, the controlled-fixture regressions that shaped it, and the post-v0.3.2 navigation roadmap, see `docs/bsp_collision_migration.md`.
