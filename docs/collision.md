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

A segment trace is not an attack and does not define damage or target policy.

## 6. Swept-circle traces

A swept-circle query moves a ground circle continuously along the requested segment:

```text
sweep_circle(start -> end, radius)
```

It asks:

> How far can this ground body move before first contact?

Current player and NPC locomotion both use this query through `Simulation::GroundMovement`.

The query covers the complete requested displacement, so anti-tunneling behavior does not depend on dividing movement into many artificial substeps.

## 7. Static terrain backend

The current authored level is a grid. Impassable terrain cells act as solid static collision cells.

```text
grid cell (x, z), cell size S

X = x * S .. (x + 1) * S
Z = z * S .. (z + 1) * S

Current authored grid levels use S = 32 world units.
```

Static terrain participates in the same earliest-hit result as dynamic entities.

This static backend is intentionally replaceable. Gameplay callers consume `GroundTrace`, not grid-cell collision details.

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
(floor(x), floor(z)) navigation cell
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

NPCs therefore share runtime collision and movement with the player even while route planning still uses the authored grid.

## 15. Filtering

Aogera 0.3.2 does not introduce Quake-style contents/mask families.

Current trace calls support concrete filtering needs such as:

- ignoring the source/moving entity;
- selecting which dynamic entities participate;
- distinguishing static world from dynamic body hits;
- excluding retired entities from ordinary active queries.

More elaborate collision categories can be introduced when real gameplay requires them.

## 16. BSP replacement boundary

The current static side of the collision service is:

```text
GroundSpace
    |
    +-- static grid collision
    +-- dynamic GroundBody collision
```

A later BSP-oriented shape can become:

```text
GroundSpace / successor trace boundary
    |
    +-- BSP29 collision data
    +-- dynamic entity collision
```

Movement, melee, and interaction already consume the trace-result contract rather than the static grid implementation.

BSP29 loading and world-model rendering now exist, but the controlled BSP preview intentionally continues to use the matching grid collision backend. Quake BSP collision hulls/clipnodes are already preserved by `BSP29::Reader` and are the next static-collision source; collision must not be reconstructed from rendered polygons merely because rendering also consumes BSP geometry.

## 17. Deferred collision work

Aogera 0.3.2 does not yet implement:

- vertical actor collision;
- gravity or jumping;
- floors/ceilings/step movement;
- arbitrary 3D actor shapes;
- projectiles or hitscan delivery;
- generalized contents/masks;
- rigid-body physics;
- BSP hull/clipnode integration into the trace service;
- generic `Transform`, `PhysicsBody`, or `Spatial` frameworks.

The current invariant is simpler:

> **Aogera has one runtime world-space model; movement and gameplay consume shared collision results instead of maintaining competing spatial truths.**
