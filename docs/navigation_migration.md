# Navigation Migration

This document records Aogera's migration away from the temporary grid-BFS chase model toward continuous world-space local navigation with an optional future global route graph.

As of the current v0.3.3 development line, the **runtime chase cutover is active**. `Simulation::Pathfinder` still exists as dormant/reference code and retains its tests, but normal chase behavior no longer calls it.

The active navigation stack is intentionally small:

```text
high-level behavior
      |
      | chooses/refreshes a goal
      v
SteeringTarget
      |
      | live goal position
      v
GroundNavigation
      |
      | GroundHeading
      v
GroundSteering @ 30 Hz
      |
      | GroundMove
      v
GroundMovement
      |
      v
GroundSpace
```

No navmesh, BSP-leaf graph, route table, gravity, stairs, doors, or moving-brush navigation has been introduced.

## 1. Why the grid navigator was retired from active chase

Aogera's original chase logic was built around a grid-era identity:

```text
2 Hz NPC decision
    = one BFS decision
    = one grid step
```

The 0.3.3 cleanup line separated those responsibilities incrementally:

```text
world-space waypoint boundary
        |
        v
persistent SteeringTarget
        |
        v
30 Hz GroundSteering
        |
        v
world-space local navigation
```

Once actors moved continuously, the remaining cell-center assumptions produced structural failures rather than isolated arithmetic bugs:

- a target-adjacent cell could still be outside true melee reach;
- a center-to-center grid edge could be clear while the actor's actual off-center route was blocked;
- continuous collision could deflect an actor away from the theoretical cell-center route;
- a 90-degree obstacle corner could receive the same locally unreachable waypoint repeatedly;
- retiring a dynamic blocker could legitimately change the BFS route and expose another off-center route mismatch;
- straight obstacle borders could also trap an actor when the graph edge was valid only from a theoretical cell center.

Those failures were evidence that the grid graph was no longer the right active pursuit representation.

The project therefore stops extending the cell-BFS chase model here.

## 2. Historical direction

The replacement is inspired by the Quake/GoldSrc lineage without copying either engine literally.

The useful Quake-style common-case model is:

```text
current position + current goal
          |
          v
try direct local movement
          |
          +-- clear -> move
          |
          +-- blocked -> try useful local alternatives
```

The important architectural lesson is that gameplay policy chooses a goal while the movement/collision layer answers whether a proposed local step is possible.

The useful GoldSrc-style extension is a later larger-scale fallback: when local movement cannot solve map topology, consult a world-space graph whose links were certified using the real collision system rather than inferred from visual or BSP-partition adjacency.

Aogera combines those ideas with its own current runtime:

- continuous `Position`;
- authored `GroundBody`;
- BSP-backed `GroundSpace`;
- continuous sweep-and-slide `GroundMovement`;
- fixed-step `GroundSteering`;
- immutable runtime data;
- explicit high-level behavior state.

## 3. `SteeringTarget`: high-level movement goal

NPC behavior persists movement intent as:

```text
Component::SteeringTarget(x, z, goal_entity_id)
```

The coordinates are a world-space fallback/static goal.

`goal_entity_id` is optional. When present, `GroundSteering` resolves that entity's **current** `Position` every simulation tick instead of chasing the stale coordinates stored when the behavior decision was made.

This creates a useful distinction:

```text
behavior decision @ low frequency
    "chase entity N"

local navigation @ fixed simulation cadence
    "where is entity N now, and which way can I move this tick?"
```

Wander/static goals can continue to use `x/z` without a goal entity.

If a goal entity disappears or becomes retired, steering intent is cleared.

## 4. `GroundHeading`: local navigation state

Local movement direction is represented by:

```text
GroundHeading(dx, dz)
```

`GroundHeading` is normalized on construction.

It is not:

- a grid direction;
- a waypoint;
- velocity;
- actor facing;
- canonical position.

The active heading is stored in the runtime world under the `:ground_heading` component key. Keeping the previous successful heading gives local navigation a small amount of movement memory without introducing a remembered global path.

Clearing `SteeringTarget`, retiring an entity, or completing a valid attack also clears `ground_heading`.

## 5. `Simulation::GroundNavigation`

`Simulation::GroundNavigation` is a stateless local-navigation query.

It consumes:

```text
source entity
source continuous Position
source GroundBody
goal world-space X/Z
optional goal entity
optional previous GroundHeading
GroundSpace
```

It deliberately does **not** consume:

```text
Level::Terrain cells
Pathfinder::Waypoint
BSP nodes/leaves directly
clipnodes directly
```

All geometry questions pass through `GroundSpace`.

This is the main replacement boundary for the old active grid Pathfinder.

## 6. Navigation outcomes

`GroundNavigation#query` returns one of four explicit outcomes:

```text
:arrived
:direct
:local_avoidance
:route_needed
```

### `:arrived`

The source is already at the requested static ground-space goal within movement epsilon.

For an entity goal, ordinary body collision normally prevents the two centers from becoming identical; combat behavior is responsible for deciding when true melee reach has been achieved.

### `:direct`

A short movement probe in the normalized direction toward the goal is currently usable.

### `:local_avoidance`

Direct pursuit is blocked, but another local heading is usable.

The current implementation can:

- reuse a previous non-reversing heading;
- derive tangent alternatives from the blocking trace normal;
- test deterministic rotated alternatives around the desired direction.

### `:route_needed`

No tested local heading is currently usable.

This does **not** mean the goal is globally unreachable.

In the current cutover, it means:

```text
keep the high-level goal
clear unusable local heading
retry local navigation on the next simulation tick
```

This status is the future hook for a larger-scale GoldSrc-like route graph.

## 7. Probe semantics

Every local candidate uses the actor's actual continuous runtime state:

```text
actual Position
      |
      | one short candidate movement
      v
GroundSpace#sweep_circle
      |
      +-- static BSP hull collision in BSP mode
      +-- current dynamic GroundBody blockers
      |
      v
usable / blocked
```

The query is live and deliberately uncached because its answer depends on:

- the actor's exact current position;
- dynamic actor occupancy;
- the current goal position;
- the previous heading.

A goal entity is accepted as a terminal dynamic hit for pursuit. Other movement-blocking actors remain obstacles.

The default probe distance matches one NPC locomotion step:

```text
NPC_SPEED / TICK_HZ
```

This keeps local obstacle response on the same spatial scale as actual movement.

## 8. Local heading policy

The active candidate order is deliberately small and deterministic.

Conceptually:

1. direct normalized heading toward the goal;
2. previous heading when useful and not an immediate turnaround;
3. wall tangents from the direct blocking plane normal;
4. rotated alternatives around the desired direction;
5. reverse direction only as a late fallback;
6. otherwise `:route_needed`.

The rotated fallback currently uses angles around the direct heading, but movement itself remains continuous. Aogera is not restoring a permanent eight-direction locomotion model.

`GroundNavigation` chooses a heading worth trying. `GroundMovement` remains authoritative for the actual sweep-and-slide displacement.

## 9. Fixed-step local navigation and locomotion

`Simulation::GroundSteering` now runs local navigation every simulation tick.

For each active entity with a `SteeringTarget` it:

1. resolves the live goal;
2. passes the previous `ground_heading` to `GroundNavigation`;
3. stores a new heading when one is chosen;
4. emits a normal one-tick `GroundMove`;
5. clears only the heading when local navigation reports `route_needed`;
6. clears the target when a static goal is reached or a dynamic goal disappears.

At the default rate:

```text
TICK_HZ   = 30
NPC_SPEED = 64 world units/sec

NPC locomotion step = 64 / 30
                    ~= 2.133 world units/tick
```

Local navigation and collision therefore react every fixed simulation tick instead of waiting for the old 2 Hz behavior cadence.

## 10. Behavior cadence after the cutover

`RealtimeController` still has the existing low-frequency NPC behavior cadence.

That cadence now decides and refreshes **intent**, not obstacle response or physical movement.

For chase:

```text
Behavior(:chase)
      |
      | resolve relation target
      v
SetSteeringTarget(goal_entity_id: target)
```

Because `GroundSteering` resolves `goal_entity_id` every fixed tick, pursuit follows the target's live position between behavior updates.

The low-frequency cadence still controls decisions such as melee attack attempts. It can be revisited later without changing locomotion or local-navigation architecture.

## 11. Attack sequencing

A melee decision no longer clears steering before the attack has actually been validated.

The controller now preserves pursuit intent and emits:

```text
SetSteeringTarget(goal entity)
Attack
```

The executor evaluates commands in order against the current world.

If an earlier player movement makes the attack invalid:

```text
Attack rejected
      |
      v
SteeringTarget survives
      |
      v
GroundSteering runs later in the same Simulation#step
      |
      v
pursuit continues
```

If the attack succeeds, `Executor` clears both `steering_target` and `ground_heading` before the steering phase.

This prevents the old execution-order stall where attack intent could erase locomotion even though no attack actually happened.

## 12. Status of the old `Simulation::Pathfinder`

`Simulation::Pathfinder` remains in the repository for now.

It is **not used by active production chase behavior**.

Its remaining value is:

- historical/reference behavior;
- regression comparison during the migration;
- a clean rollback point while local navigation is proven in the controlled BSP field.

Its grid-cell topology, cell-center waypoints, BSP edge-clearance cache, and dynamic-cell occupancy logic should not receive further gameplay fixes unless the project explicitly restores it as an active backend.

Removal can happen in a later cleanup patch after the local-navigation cutover has been manually validated.

## 13. Remaining grid roles

Removing active BFS chase does not yet remove the Ruby-authored level.

The grid still participates in:

- current Ruby level authoring;
- spawn and entry declarations/validation;
- normal non-BSP rendering and static-collision fallback;
- dormant `Pathfinder` reference/tests.

It is no longer required to choose active BSP goblin chase directions.

This is an important boundary:

```text
BSP-mode chase/navigation
    -> continuous world-space queries

Ruby level scaffolding
    -> still present for current authored content
```

## 14. Future GoldSrc-like route graph

A later global route mechanism should be a fallback for topology that local movement cannot solve, not the common-case locomotion mechanism.

A minimal graph could eventually contain immutable records such as:

```text
NavNode
    id
    x
    y
    z

NavLink
    from
    to
    distance
```

The important invariant is not how nodes are generated. It is how links are accepted.

Candidate links should be certified by the same static collision system used at runtime:

```text
candidate node A
      |
      | actor-hull movement probe
      v
GroundSpace / BSP ground collision
      |
      +-- clear -> keep link
      +-- blocked -> reject link
```

Dynamic actors must not become permanent graph-link properties.

This prevents a future graph from repeating the old grid/BSP disagreement in a different representation.

## 15. Possible sidecar direction

If a global graph becomes necessary, a per-map sidecar is preferable to rebuilding large route data on every normal gameplay launch.

Conceptually:

```text
map.bsp
map.<future-nav-extension>
```

The extension, encoding, graph compiler, node authoring policy, and search algorithm remain deliberately undecided.

Do not derive a graph from BSP leaf adjacency merely because the map is BSP. BSP partitions world space; traversable actor connectivity must still be validated against movement rules.

## 16. What is deliberately absent

This migration does not add:

- navmesh generation;
- active BSP-leaf routing;
- A* or Dijkstra route search;
- a GoldSrc-style `.nod` implementation yet;
- gravity;
- jumping;
- stairs/step movement;
- ledge/floor reasoning;
- doors or moving brush navigation;
- true water navigation;
- flying/swimming movement classes;
- generalized hull capability masks.

Those should only appear when actual Aogera gameplay requires them.

## 17. Current checkpoint

The active chase stack is now:

```text
Behavior(:chase)
      |
      v
SteeringTarget(goal entity)
      |
      v
GroundNavigation @ simulation cadence
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
GroundMovement
      |
      v
GroundSpace
      |
      +-- BSP static collision
      +-- dynamic GroundBody collision
```

This is the first Aogera chase path in the 3D line whose active movement decisions no longer require grid cells.

The next navigation work should be driven by manual behavior in real BSP geometry. If local navigation proves insufficient for larger map topology, `:route_needed` is the explicit place to add a collision-certified world-space route graph.
