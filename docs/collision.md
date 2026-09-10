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

Current player and NPC locomotion both use this query through `Simulation::GroundMovement`, but the BSP preview deliberately supplies different static backends while navigation remains grid-based:

```text
bound persistent character -> BSP29 hull 1 static collision
spawned NPCs              -> Ruby-grid static collision
all actors                -> dynamic GroundBody collision
```

This split is temporary and explicit. It prevents grid-planned NPC movement from being rejected by a different BSP clearance model before BSP-aware navigation exists.

The query covers the complete requested displacement, so anti-tunneling behavior does not depend on dividing movement into many artificial substeps.

## 7. Static terrain backends

The current authored level is still a grid. Impassable terrain cells act as solid static collision cells for the normal Ruby launch and for spawned NPC movement in the BSP preview.

```text
grid cell (x, z), cell size S

X = x * S .. (x + 1) * S
Z = z * S .. (z + 1) * S

Current authored grid levels use S = 32 world units.
```

The BSP preview additionally supplies two static-space BSP adapters:

- `BSP29::GroundHull` traces Quake BSP29 compiled hull 1 through clipnodes for bound-player movement;
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
continuous waypoint displacement
   |
   v
GroundMove
```

NPCs still share the same continuous `Position`, `GroundMove`, `GroundBody`, and `GroundMovement` machinery with the player, but in the current BSP preview their **movement execution** backend remains the authored grid. BFS topology is also still the grid, while candidate center-to-center transitions are now additionally validated against BSP29 compiled hull-1 static clearance. This deliberately removes the dangerous direction of mismatch where BFS plans a route that the future BSP movement backend cannot traverse, without switching NPC movement execution in the same patch.

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
visible static world          -> BSP29 model 0
bound-player static movement -> BSP29 compiled hull 1
NPC static movement          -> Ruby grid
zero-radius obstruction      -> BSP29 hull-0 node/leaf tree
BFS topology                 -> Ruby grid
BFS static step clearance    -> BSP29 compiled hull 1
dynamic actor collision      -> GroundBody circles
```

`Simulation::Executor` selects the BSP-backed movement service only for an entity bound through `Simulation::Bindings`. Ordinary spawned NPCs continue to use the default grid-backed movement service.

This split is a temporary safety boundary, not the target architecture. It exists because standard BSP29 compiled hulls have fixed clearance while Aogera currently authors smaller `GroundBody` radii. The controlled 32-unit water pinch in `test_field` exposes that mismatch: the player circle with radius 7.04 has positive clearance, while hull 1's 16-unit horizontal half-extent has zero clearance in a 32-unit gap.

For the current BSP preview that mismatch is accepted as a source-format limitation rather than hidden. The bound-player `GroundHull` records radius 7.04 and reports a horizontal clearance delta of 8.96 units, while still tracing the unmodified compiled hull. Supporting arbitrary authored radii for static BSP collision remains deferred until there is a collision source that can actually represent them.

Zero-radius melee/interaction obstruction now uses `BSP29::PointHull` through model headnode 0. `App` supplies the same BSP point-backed `GroundSpace` to player target selection, NPC melee planning, and executor-side attack validation, so those domains no longer disagree about static obstruction.

For navigation, `App` also supplies `Simulation::Pathfinder` with `BSP29::GroundClearance`. The Pathfinder keeps the current grid cells, ordering, target-adjacent goals, and dynamic-cell occupancy behavior. During BFS expansion it converts the current and candidate cells to their world-space centers and accepts the transition only when compiled hull 1 is clear for the source actor. `GroundClearance` caches a radius-bound `GroundHull` adapter per authored `GroundBody` radius; the radius remains a contract check and does not resize the fixed BSP hull.

Positive-radius NPC movement execution itself remains grid-backed. This is intentionally one-way conservative during the migration: navigation may reject a grid-clear transition that BSP hull 1 cannot traverse, but the executor does not yet apply a stricter BSP backend after BFS has chosen a route.

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

> **Aogera keeps one continuous runtime position/body model while static grid and BSP authorities are migrated behind explicit, tested boundaries.**
