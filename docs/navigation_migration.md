# Navigation Migration

This document records Aogera's transition away from the temporary grid-BFS chase model toward world-space local navigation with an optional future global route graph.

It describes the intended migration surface. It does **not** make the staged local-navigation code authoritative for gameplay until the runtime cutover is explicitly made.

## 1. Why the grid navigator is being retired

Aogera's original chase logic was built around a grid-era identity:

```text
2 Hz NPC decision
    = one BFS decision
    = one 32-unit cell step
```

The 0.3.3 cleanup line has already separated those responsibilities:

```text
Pathfinder
    -> world-space waypoint

SteeringTarget
    -> persistent movement intent

GroundSteering
    -> 30 Hz locomotion

GroundMovement
    -> collision-constrained displacement
```

That separation exposed the remaining mismatch: the Pathfinder still reasons in cell centers while actors now occupy arbitrary continuous positions and move against BSP collision.

The resulting bugs are structural rather than isolated arithmetic mistakes:

- an actor can be in a target-adjacent cell but outside true melee reach;
- a center-to-center edge can be clear while the actor's actual off-center route to the waypoint is blocked;
- a continuous actor can be deflected by collision while the next BFS decision still assumes the old cell-center route;
- a 90-degree obstacle corner can repeatedly receive the same theoretically valid but locally unreachable waypoint.

The project should therefore stop extending the cell model and replace the active chase mechanism incrementally.

## 2. Historical direction

The replacement is inspired by the Quake/GoldSrc lineage without copying either engine literally.

Quake-style local pursuit provides the useful common-case structure:

```text
current position + current goal
          |
          v
try useful local movement direction
          |
          +-- clear -> move
          |
          +-- blocked -> try local alternatives
```

The important architectural lesson is that game/AI policy chooses a goal while the movement/collision layer answers whether a proposed local step is possible.

GoldSrc adds the useful larger-scale fallback idea: when local movement cannot solve the topology, consult a precomputed world-space node graph whose links were certified against real collision hulls rather than inferred from visual adjacency alone.

Aogera should combine those ideas with its own current runtime:

- continuous `Position`;
- `GroundBody`;
- BSP-backed `GroundSpace`;
- continuous sweep-and-slide `GroundMovement`;
- fixed-step `GroundSteering`;
- immutable runtime data.

## 3. Staged local-navigation surface

0.3.3 now stages two values without switching gameplay yet:

```text
GroundHeading(dx, dz)
```

and:

```text
Simulation::GroundNavigation
```

`GroundHeading` is a normalized world-space X/Z direction. It is not a grid direction, waypoint, velocity, or facing state.

`GroundNavigation#query` consumes:

```text
source entity
source continuous Position
source GroundBody
goal world-space X/Z
optional goal entity
optional previous heading
GroundSpace
```

It deliberately does **not** consume:

```text
Level::Terrain cells
Pathfinder::Waypoint
BSP nodes
BSP leaves
clipnodes directly
```

All geometry questions pass through `GroundSpace`.

## 4. Local-navigation outcomes

The staged query returns one of four explicit outcomes:

```text
:arrived
:direct
:local_avoidance
:route_needed
```

### `:arrived`

The source is already at the requested ground-space goal within movement epsilon.

### `:direct`

A short movement probe in the normalized direction toward the goal is currently usable.

### `:local_avoidance`

The direct probe is blocked, but a local alternative is usable. The staged implementation may reuse a previous non-reversing heading, use a tangent derived from the blocking plane, or probe rotated alternatives around the desired direction.

### `:route_needed`

No tested local heading is currently usable.

This does **not** mean the destination is globally unreachable. It is intentionally the seam where a future larger-scale route graph can be consulted.

## 5. Probe semantics

The local query uses the actor's actual continuous position and actual authored `GroundBody` radius.

Conceptually:

```text
actual Position
      |
      | short candidate movement
      v
GroundSpace#sweep_circle
      |
      +-- static BSP world
      +-- current dynamic blockers
      |
      v
usable / blocked
```

This is a live runtime query. It is intentionally not cached as a cell edge because its answer depends on the actor's current continuous position and current dynamic occupancy.

A goal entity may be accepted as the terminal dynamic hit for direct pursuit; other movement-blocking entities remain obstacles.

## 6. Local heading policy

The staged implementation is deliberately small and deterministic.

Current candidate ordering is conceptually:

1. direct normalized heading toward the goal;
2. previous heading when it is useful and not an immediate turnaround;
3. wall-tangent alternatives derived from the blocking trace normal;
4. rotated local alternatives around the desired direction;
5. reverse direction only as a late fallback;
6. otherwise return `:route_needed`.

This is Quake-like in spirit, but Aogera keeps continuous vectors rather than permanently quantizing movement to eight compass headings.

`GroundMovement` remains authoritative for actual sweep-and-slide resolution. `GroundNavigation` only chooses a direction worth trying.

## 7. Current gameplay remains unchanged in this preparation patch

The active chase path is still:

```text
RealtimeController
      |
      v
Simulation::Pathfinder
      |
      v
world-space Waypoint
      |
      v
SteeringTarget
      |
      v
GroundSteering @ 30 Hz
```

`Simulation::GroundNavigation` is staged and tested alongside that path but is not yet called by `RealtimeController`.

This is intentional. The patch establishes one clean rollback/checkpoint surface before the behavioral cutover.

## 8. Immediate next cutover

Unless a concrete blocker appears, the next navigation patch should switch chase behavior from the old Pathfinder to the staged local-navigation surface.

The intended first cutover is:

```text
Behavior(:chase)
      |
      | target entity / position
      v
GroundNavigation
      |
      +-- direct
      +-- local avoidance
      +-- route needed
      |
      v
GroundHeading
      |
      v
fixed-step steering / GroundMove
```

The first runtime version does not need a global node graph immediately. `:route_needed` can initially mean that local navigation has no solution and the actor should keep/reconsider its local state on subsequent navigation updates.

The important change is that the active BSP chase path should stop asking `Simulation::Pathfinder` for grid-cell waypoints.

## 9. Future GoldSrc-like route graph

A later global route system should be a fallback for topology that local movement cannot solve, not the common-case locomotion mechanism.

A minimal future graph could contain immutable records such as:

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

Nodes may be authored or generated by a dedicated offline tool. The exact authoring policy is deliberately undecided.

The important invariant is link certification:

```text
candidate node A
      |
      | static movement probe
      v
GroundSpace / BSP hull collision
      |
      +-- traversable -> keep link
      +-- blocked     -> reject link
```

The global graph must not invent a second, approximate walkability model that disagrees with runtime collision.

Dynamic entities should not be baked into static links. They remain runtime obstacles.

## 10. Sidecar direction

If a graph becomes necessary, a per-map sidecar is preferable to rebuilding large route data every gameplay launch.

Conceptually:

```text
map.bsp
map.<future-nav-extension>
```

The extension, binary/text representation, graph compiler, and node authoring format are intentionally deferred until local navigation has been proven insufficient on real Aogera levels.

Do not derive a graph from BSP leaf adjacency merely because the map is BSP. BSP partitions space for visibility/collision structure; navigation connectivity must still be validated against actor movement rules.

## 11. AI timing after the cutover

The current `NPC_ACTION_HZ = 2` remains a temporary behavior-decision cadence.

It should no longer own physical locomotion; 0.3.3 already moved locomotion to 30 Hz.

After local navigation replaces BFS, timing can be separated further if necessary:

```text
behavior decisions        low frequency
local navigation probes   higher frequency / when blocked
GroundSteering            30 Hz
GroundMovement            30 Hz command resolution
```

Do not raise AI frequency merely to hide a navigation-state bug. Timing changes should be measured independently.

## 12. What survives the migration

The navigation replacement should preserve:

```text
Position(x, y, z)
GroundBody(radius)
SteeringTarget / world-space goal intent during transition
GroundSpace
GroundTrace
GroundMovement
30 Hz fixed-step simulation
component/prototype model
retirement lifecycle
BSP static collision
continuous dynamic actor collision
```

The old grid Pathfinder is a temporary implementation, not the foundation of the replacement.

## 13. Explicit non-goals

This migration does not require:

- navmesh generation;
- BSP-leaf pathfinding;
- gravity;
- jumping;
- stairs;
- ledge logic;
- flying/swimming navigation;
- doors or moving brush route negotiation;
- GoldSrc capability masks;
- a generic navigation-backend hierarchy;
- a general physics engine.

Those features should only appear when a concrete Aogera requirement justifies them.

## 14. Guiding rule

The intended long-term split is:

```text
behavior chooses a goal
        |
        v
local navigation chooses a useful heading
        |
        +-- if local navigation fails,
        |   optional global routing chooses a coarse route
        |
        v
fixed-step locomotion requests movement
        |
        v
GroundMovement + GroundSpace decide what actually happens
```

Navigation should consume collision facts, not duplicate collision geometry.
