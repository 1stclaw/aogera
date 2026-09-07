# Aogera v0.3.1 Collision Plan

## Purpose

This document describes the planned collision architecture for **Aogera v0.3.1**.

It is a design target for the next development milestone, not a description of the current v0.3.0 implementation.

Aogera v0.3.0 already has:

- true 3D rendering through raylib;
- a first-person camera and mouse look;
- continuous player movement on the X/Z ground plane;
- `GroundPosition` for continuous player coordinates;
- `GroundBody(radius)` for authored horizontal body size;
- `GroundSpace` for ground-plane spatial relationships;
- continuous player-to-actor collision;
- authored melee and interaction reach/arc;
- grid-based NPC movement and pathfinding.

The current system is sufficient as a bridge, but collision still fundamentally answers questions such as:

> Can this body occupy this candidate position?

The planned v0.3.1 system should instead answer:

> If this body moves from A to B, what is the first thing it hits, where does the impact happen, and what is the contact normal?

That trace/sweep model should become the shared spatial foundation for movement, melee obstruction, interaction obstruction, and later BSP collision.

---

## 1. Scope

The v0.3.1 collision work should remain deliberately limited to Aogera's current **ground-plane model**.

The system should support:

- continuous X/Z movement;
- static collision against the current authored terrain grid;
- dynamic collision against `GroundBody` entities;
- segment traces for obstruction tests;
- swept-circle traces for moving actors;
- structured collision results;
- movement sliding based on contact normals;
- melee obstruction;
- interaction obstruction.

The system should **not** introduce:

- BSP loading;
- vertical movement or collision;
- gravity;
- jumping;
- stairs or step-height rules;
- floor detection;
- generic 3D collision shapes;
- rigid-body physics;
- mass, friction or restitution;
- projectiles;
- hitscan weapons;
- collision masks modeled after Quake;
- generic `Transform`, `PhysicsBody`, or `Spatial` abstractions.

The purpose of v0.3.1 is to establish a durable collision query contract before the static-world backend changes from the temporary grid to BSP.

---

## 2. Design principle

Collision should provide **spatial facts**.

Gameplay systems should decide what those facts mean.

The intended separation is:

```text
movement / combat / interaction
            |
            | asks spatial questions
            v
        GroundSpace
            |
            | returns trace results
            v
movement / combat / interaction policy
```

`GroundSpace` should not know:

- what a sword is;
- what a goblin is;
- whether an interaction starts dialogue;
- how much damage an attack causes;
- whether a collision should cause knockback;
- whether a future projectile explodes.

It should only answer geometric questions.

This keeps collision reusable without turning it into a general physics framework.

---

## 3. Ground-space model

Aogera's current 3D coordinate convention remains:

```text
+X = east/right
+Y = up
+Z = south
```

The planned v0.3.1 collision system remains strictly two-dimensional in the horizontal plane:

```text
GroundSpace = X/Z space
```

Vertical Y information is outside this milestone.

### Continuous entities

An entity with:

```text
GroundPosition(x, z)
```

has a canonical continuous ground position.

### Grid-only entities

NPCs may still have only:

```text
Position(x, y)
```

For ground-space queries, their temporary continuous position is projected to the center of their grid cell:

```text
ground_x = x + 0.5
ground_z = y + 0.5
```

This fallback exists only to allow current grid NPCs to participate in continuous player collision and targeting.

It is not intended as the final NPC spatial model.

### GroundBody

Horizontal body extent is authored explicitly:

```text
GroundBody(radius)
```

A `GroundBody` means only:

> This entity occupies this radius on the X/Z ground plane.

It does not imply:

- mass;
- velocity;
- physics simulation;
- vertical extent;
- material properties.

---

## 4. Structured trace results

The central new concept should be an immutable trace result.

A likely shape is:

```ruby
GroundTrace = Data.define(
  :fraction,
  :end_x,
  :end_z,
  :normal_x,
  :normal_z,
  :entity_id,
  :world_hit,
  :start_blocked
)
```

The exact Ruby representation may change during implementation, but the semantics should remain stable.

### `fraction`

`fraction` describes how much of the requested motion or segment was completed before the first collision.

```text
0.0   = blocked immediately
1.0   = full path completed
0..1  = collision occurred along the path
```

### End position

```text
end_x
end_z
```

represent the furthest valid position reached by the query.

For an unobstructed query they equal the requested destination.

For a collision they represent the position at first contact, adjusted as necessary to prevent penetration.

### Contact normal

```text
normal_x
normal_z
```

describe the horizontal surface normal at the first collision.

Examples:

```text
wall on west side   -> (-1, 0)
wall on east side   -> (+1, 0)
wall on north side  -> (0, -1)
wall on south side  -> (0, +1)
```

Corner collisions may return a normalized diagonal.

The normal is important because movement can use it to calculate sliding without giving X or Z a special priority.

### Dynamic entity hit

```text
entity_id
```

identifies the blocking dynamic entity when the first obstruction is an entity.

It is `nil` for purely static-world collision.

### Static-world hit

```text
world_hit
```

indicates that the obstruction belongs to the static world.

In v0.3.1 this means the current authored terrain grid.

Later it may mean BSP collision geometry without changing movement/combat callers.

### Start blocked

```text
start_blocked
```

indicates that the query began already intersecting solid space.

This is useful for:

- debugging invalid spawns;
- detecting inconsistent state;
- preventing ambiguous collision resolution;
- future BSP integration.

---

## 5. Two distinct query types

The v0.3.1 API should expose two conceptually different operations.

### 5.1 Segment trace

A segment trace has zero radius.

Conceptually:

```text
trace_segment(start_x, start_z, end_x, end_z, ...)
```

It asks:

> What is the first relevant obstruction between these two ground points?

Planned uses include:

- melee obstruction;
- interaction obstruction;
- line-of-sight-like checks;
- future hitscan groundwork.

A segment trace is not itself an attack.

It only reports geometry.

### 5.2 Swept-circle trace

A swept-circle trace moves a circular body along a segment.

Conceptually:

```text
sweep_circle(
  start_x,
  start_z,
  end_x,
  end_z,
  radius,
  ...
)
```

It asks:

> How far can this circle travel before first contact?

Planned uses include:

- first-person player movement;
- future continuous NPC movement;
- future moving ground entities.

This should replace movement's current reliance on repeated overlap/substep checks.

---

## 6. Static terrain collision

The first trace backend should continue using the existing authored terrain grid.

A passability-blocking grid cell is treated as a solid square in ground space.

Conceptually:

```text
grid cell (x, y)

covers:

X = x .. x + 1
Z = y .. y + 1
```

### Segment trace against terrain

A segment trace should find the earliest intersection with any relevant solid grid cell.

The result should include:

- fraction;
- contact position;
- contact normal;
- `world_hit = true`.

### Swept circle against terrain

A moving circular body should be tested against solid cells as a continuous sweep.

Implementation can use a Minkowski-style expansion:

```text
moving circle against square

becomes conceptually

moving point against square expanded by circle radius
```

The important contract is continuous collision detection across the complete requested movement.

The system should not need to divide every movement request into many artificial mini-steps in order to avoid tunneling.

---

## 7. Dynamic actor collision

Dynamic actors should continue using circles on the X/Z plane.

For two bodies:

```text
moving radius     = r1
stationary radius = r2
```

collision can be treated conceptually as:

```text
moving point

against

stationary circle with radius r1 + r2
```

The sweep should find the earliest segment-circle contact.

The result should report:

```text
fraction
contact position
contact normal
entity_id
world_hit = false
```

Only entities intended to block the relevant movement query should participate.

The source/moving entity itself must be ignored.

---

## 8. Earliest-hit rule

A trace may encounter several potential obstacles.

For example:

```text
player
   |
   | movement
   v

goblin
   |
   v

wall
```

The query must return the **earliest relevant collision**, not every overlap along the path.

The same rule applies across static and dynamic geometry.

Conceptually:

```text
static terrain candidate hits
+
dynamic body candidate hits
        |
        v
choose smallest valid fraction
```

The caller receives one coherent first-contact result.

This is the key behavior that lets movement, melee obstruction and later BSP collision share the same contract.

---

## 9. Movement resolution

`GroundMovement` should become a consumer of `GroundSpace#sweep_circle`.

It should no longer own the geometric rules for:

- terrain overlap;
- actor overlap;
- X-first/Z-second movement;
- anti-tunneling substeps.

Instead:

```text
desired displacement
        |
        v
GroundSpace sweep
        |
        v
GroundTrace
        |
        v
GroundMovement policy
```

### Unobstructed movement

If:

```text
trace.fraction == 1.0
```

the full requested displacement is accepted.

### Collision

If collision occurs:

1. move to the trace end position;
2. calculate the remaining displacement;
3. remove the component pointing into the collision normal;
4. sweep the resulting slide displacement;
5. repeat for a small bounded number of contacts.

For movement vector:

```text
v = (dx, dz)
```

and contact normal:

```text
n = (nx, nz)
```

the slide vector is conceptually:

```text
slide = v - n * dot(v, n)
```

This preserves motion parallel to the obstacle while removing motion into it.

### Bounded collision iterations

Movement resolution should use a small fixed maximum number of collision iterations.

For example, enough to handle:

- one wall;
- sliding into a second wall;
- an inside corner.

It should not become an unbounded solver.

---

## 10. Why this replaces axis-separated resolution

The current temporary collision bridge resolves X and Z independently.

That is simple but introduces an artificial axis preference.

Conceptually:

```text
try X
then try Z
```

can behave differently from:

```text
try Z
then try X
```

A trace result with a contact normal removes that special treatment.

Movement becomes based on actual impact geometry:

```text
requested direction
+
contact normal
=
slide direction
```

This is closer to the collision model Aogera will eventually need for arbitrary BSP planes.

---

## 11. Melee targeting

The existing v0.3.0 combat foundation should remain:

```text
MeleeAttack
    reach
    arc_degrees
```

These are authored gameplay parameters.

`GroundSpace` should not contain melee-specific constants.

### Candidate selection

Combat should first determine candidate targets using:

- target eligibility;
- ground-space distance/reach;
- view-relative attack arc.

Conceptually:

```text
authored melee reach + arc
           |
           v
geometrically eligible candidates
```

### Occlusion

For each candidate, combat should then ask whether the target is unobstructed.

Conceptually:

```text
player
   |
   | segment trace
   v
candidate
```

If static world geometry blocks the segment before reaching the target, the target is not attackable.

This prevents attacks through walls while preserving Aogera's forgiving authored melee arc.

### Important distinction

The planned system should **not** replace arc-based melee with a single narrow ray.

Aogera's melee policy remains:

```text
reach + arc
```

The trace adds obstruction testing.

It does not define which targets the weapon is allowed to attack.

---

## 12. Interaction

Interaction should use the same collision-query foundation but retain independent gameplay rules.

The existing authored concept remains:

```text
Interactor
    reach
    arc_degrees
```

The interaction sequence becomes:

```text
interaction eligibility
        |
        v
reach + arc filtering
        |
        v
segment obstruction trace
        |
        v
interaction-specific target selection
```

A wall should therefore prevent talking to or activating something on the other side.

Interaction should not be implemented as a special form of melee.

The systems merely share ground-space geometry.

---

## 13. Combat validation

Attack selection and damage validation should remain distinct.

The player's combat logic decides:

> Which entity is the intended melee target?

The simulation/executor still decides:

> Is this attack spatially valid when it is executed?

For a continuous attacker, validation should continue to use the attack's authored reach and ground-space relationship.

The new trace foundation may also allow obstruction validation to occur at the authoritative simulation boundary.

The exact division between selection-time and execution-time trace checks should be determined during implementation, but combat must not regress to Manhattan grid adjacency.

NPC grid attacks may retain current adjacency semantics until NPC movement itself is migrated.

---

## 14. NPC behavior during v0.3.1

v0.3.1 should not force continuous locomotion onto NPCs.

The current split remains valid:

```text
PLAYER
    GroundPosition
    continuous movement
    GroundBody
    ground-space melee/interaction

NPC
    Position(x, y)
    grid movement
    grid BFS/pathfinding
    grid chase logic
```

Grid-only NPCs still participate in `GroundSpace` through cell-center projection and authored `GroundBody` radius.

This allows:

- player collision with NPCs;
- player melee against NPCs;
- player interaction with NPCs;

without prematurely replacing NPC navigation.

---

## 15. Filtering

A trace system eventually needs to distinguish different collision purposes.

Examples from a more mature engine might include:

- player movement blockers;
- monster movement blockers;
- projectile blockers;
- shot blockers;
- visibility blockers.

Aogera v0.3.1 should **not** implement a large contents/mask system yet.

However, the trace API must avoid permanently assuming:

> Every `GroundBody` blocks every possible query.

At minimum, the design should support:

- ignoring the source entity;
- choosing which dynamic entities participate in a query;
- distinguishing static-world collision from dynamic-body collision.

More elaborate filtering should be introduced only when real gameplay requirements demand it.

---

## 16. Numerical behavior

Collision code will require small numerical tolerances.

These should be treated as implementation details of tracing rather than gameplay parameters.

Potential uses include:

- preventing a body from ending microscopically inside a wall;
- avoiding repeated collision with the exact same plane;
- treating near-zero remaining motion as complete;
- handling tangent circle contacts consistently.

The implementation should prefer a small number of clearly named tolerances rather than scattered magic values.

Authored values such as body radius, melee reach, and interaction arc remain gameplay data and should not be mixed with numerical collision tolerances.

---

## 17. Expected GroundSpace responsibilities

After v0.3.1, `GroundSpace` should answer questions such as:

```text
Where is this entity on the ground plane?

How large is this entity's ground body?

What is the distance/separation between these entities?

Is a target inside this range and arc?

What is the first obstruction along this segment?

How far can this circle move before collision?

What was hit?

What was the contact normal?
```

It should not answer:

```text
How much damage does this attack cause?

Which weapon animation should play?

Should the goblin chase the player?

Should the player bounce?

What dialogue should begin?

Should this projectile explode?
```

Those remain gameplay/system responsibilities.

---

## 18. Expected GroundMovement responsibilities

After v0.3.1, `GroundMovement` should be much smaller conceptually.

It should own:

- interpreting requested ground displacement;
- asking `GroundSpace` for swept collision results;
- sliding along collision normals;
- updating `GroundPosition`;
- synchronizing the player's coarse grid `Position` bridge if still required.

It should no longer own detailed shape-intersection rules.

---

## 19. Tests required for the collision contract

The trace/sweep contract should receive focused tests because later BSP collision will depend on the same behavior.

At minimum, tests should cover:

### Segment traces

- unobstructed segment returns full fraction;
- wall blocks a segment;
- first wall is returned when several lie on the path;
- expected wall normal is returned;
- dynamic `GroundBody` can be hit;
- source entity can be ignored;
- static and dynamic hits choose the earliest fraction.

### Swept circles

- unobstructed circle reaches its destination;
- circle stops before penetrating a wall;
- circle collides with another `GroundBody`;
- large displacement cannot tunnel through a one-cell wall;
- diagonal wall contact returns a usable normal;
- tangent movement along a wall remains possible;
- an inside corner stops movement cleanly;
- starting inside solid geometry produces a defined blocked result.

### Movement

- player slides along a wall;
- diagonal speed remains normalized by the movement producer;
- collision no longer depends on X-before-Z ordering;
- continuous actor collision remains stable.

### Melee

- visible target inside authored reach and arc can be hit;
- non-cardinal camera yaw remains valid;
- target behind a wall cannot be hit;
- target outside the authored arc cannot be hit;
- target beyond authored reach cannot be hit.

### Interaction

- visible interactable inside reach/arc can be selected;
- interactable behind a wall cannot be selected;
- non-interactable entities are ignored.

### Regression

Existing NPC grid/pathfinding behavior should continue to pass unchanged.

---

## 20. Relationship to BSP29

The v0.3.1 trace contract is specifically intended to prepare for Quake BSP without making the current code depend on BSP.

The planned evolution is:

```text
v0.3.1

GroundSpace
    |
    +-- static grid trace backend
    +-- dynamic GroundBody backend
```

Later:

```text
GroundSpace
    |
    +-- BSP29 collision-hull backend
    +-- dynamic GroundBody backend
```

Eventually the temporary grid static-collision backend may disappear.

The important architectural requirement is:

> `GroundMovement`, combat, and interaction should not care whether static obstruction came from a grid cell or a BSP collision hull.

BSP should replace the source of static collision facts, not force every gameplay system to be rewritten.

---

## 21. Why BSP collision hulls matter

When BSP29 work begins, Aogera should treat Quake collision hulls/clipnodes as first-class level data.

Static collision should not be reconstructed from rendered triangles if the BSP already contains collision structures designed for movement queries.

The intended future pipeline is:

```text
BSP29
    |
    +-- visible world geometry
    |
    +-- collision hulls / clipnodes
            |
            v
      GroundSpace / later spatial trace backend
```

Rendering geometry and collision representation are related but distinct concerns.

This is one of the primary reasons to stabilize the trace/sweep contract before BSP loading.

---

## 22. Deferred evolution

The v0.3.1 ground trace system should be allowed to evolve when real requirements arrive.

Possible later developments include:

```text
ground trace
    |
    +-- BSP static collision
    +-- continuous NPC movement
    +-- hitscan weapons
    +-- projectile sweeps
    +-- richer collision filtering
```

Eventually Aogera may require truly three-dimensional tracing:

```text
X/Y/Z position
vertical body extent
floors
ceilings
stairs
slopes
jumping/falling
```

At that point `GroundSpace` may evolve, delegate to another system, or be replaced.

The v0.3.1 design should not pretend that this future has already been solved.

---

## 23. Planned v0.3.1 architecture

The intended result can be summarized as:

```text
                           authored gameplay data
                        /                         \
             MeleeAttack / Interactor          GroundBody
                  |                                |
                  v                                v

Combat -----------+                            GroundMovement
Interaction ------+                                 |
                  |                                 |
                  +------------+--------------------+
                               |
                               v
                          GroundSpace
                               |
                    +----------+----------+
                    |                     |
                    v                     v
              segment trace         swept-circle trace
                    |                     |
                    +----------+----------+
                               |
                               v
                          GroundTrace
                               |
                    +----------+----------+
                    |                     |
                    v                     v
              static grid           dynamic bodies
              v0.3.1 backend         current actors
```

Later the lower-left backend can become:

```text
BSP29 collision hulls
```

without changing the systems above it.

---

## 24. v0.3.1 success criteria

The collision work should be considered successful when:

1. player movement no longer depends on repeated overlap substeps;
2. movement uses continuous swept collision;
3. wall sliding is derived from collision normals;
4. static terrain and dynamic bodies participate in one earliest-hit query;
5. melee cannot pass through static obstructions;
6. interaction cannot pass through static obstructions;
7. authored reach, arc, and body radii remain data rather than hardcoded collision behavior;
8. NPC grid/pathfinding behavior remains functional;
9. no generic physics framework has been introduced;
10. the static collision backend can later be replaced by BSP without rewriting movement, melee, or interaction.

The central v0.3.1 principle is:

> **Aogera gameplay should consume collision results, not implement collision geometry itself.**
