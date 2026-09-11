# BSP29 Collision and Navigation Migration

This document records the v0.3.2 migration from Aogera's original grid-backed static gameplay space toward BSP29 collision, while preserving the continuous runtime introduced in v0.3.1.

It is both a checkpoint description and a constraint for later work. The v0.3.2 implementation was intentionally hybrid: the grid still supplied authored-level/BFS scaffolding while BSP29 became authoritative for the static collision questions used by actor movement and ground-style obstruction queries. The current v0.3.3 cleanup line has since retired that BFS from active chase while preserving the collision boundary described here.

## 1. Why the migration is incremental

The v0.3.1 runtime already had useful continuous gameplay architecture:

```text
Position(x, y, z)
GroundBody(radius)
GroundMove(dx, dz)
GroundSpace / GroundTrace
GroundMovement sweep-and-slide
continuous melee/interaction reach
Retired lifecycle
```

The goal of BSP integration is not to replace those systems. BSP29 changes the source of static-world spatial facts.

The controlled BSP preview originally had two matching representations of the same `test_field`:

```text
visible static world   -> BSP29 model 0
static gameplay world  -> Ruby Level::Terrain
navigation             -> Ruby grid BFS
dynamic actors         -> continuous Aogera runtime
```

This bridge was valuable because the BSP fixture was generated from the same logical 44x14 field as the Ruby source. It let rendering, coordinates, collision, and navigation be migrated one responsibility at a time.

A large replacement would have been risky. The early collision patches exposed why: when BFS planned with grid clearance while all NPC movement executed against a stricter BSP hull, some goblins could repeatedly request a valid grid route that the executor rejected. The actor appeared frozen even though AI was still producing movement. The fix was not a new AI system; it was restoring a consistent authority boundary and then migrating planning clearance before NPC execution.

## 2. Source data used by BSP collision

Aogera consumes BSP collision data preserved by `BSP29::Reader` rather than reconstructing collision from rendered triangles.

The relevant normalized BSP29 records are:

```text
planes
nodes
leaves
clipnodes
models / headnodes
```

The Reader already converts Quake coordinates to Aogera coordinates:

```text
Quake  (x, y, z)
   ->
Aogera (x, z, -y)
```

The scalar magnitude remains 1:1:

```text
1 Quake map unit = 1 Aogera world unit
```

This means the collision layer operates directly on normalized Aogera-space BSP data.

## 3. Hull 0 and compiled clip hulls are different paths

BSP29 model headnodes have different meanings.

### Hull 0: node/leaf point space

World-model `headnodes[0]` refers to the BSP node tree used by point-space classification. Aogera exposes this through:

```text
BSP29::PointHull
```

`PointHull` traverses nodes and leaves and currently treats only `CONTENTS_SOLID` as blocking.

It is used for zero-radius ground-style obstruction queries such as melee and interaction line checks.

### Hulls 1..3: compiled clipnode space

The other standard BSP29 model headnodes refer to compiled clipnode hulls. Aogera exposes clipnode traversal through:

```text
BSP29::ClipHull
```

The current actor movement path uses compiled hull 1 via:

```text
BSP29::GroundClearance
    -> BSP29::GroundHull
        -> BSP29::ClipHull(hull 1)
```

The distinction is explicit so model `headnodes[0]` can never be accidentally interpreted as a clipnode index.

## 4. Clipnode trace primitive

`BSP29::ClipHull` is the low-level compiled-hull query.

It provides point-contents and segment tracing and returns BSP-local trace information including:

```text
fraction
end_position
plane_normal
start_solid
all_solid
```

Traversal follows BSP planes recursively until a negative contents value is reached. The implementation validates plane and clipnode references explicitly so Ruby negative array indexing cannot silently reinterpret malformed BSP references.

This trace primitive is deliberately independent of `GroundSpace`. It understands BSP29 hull structure, not gameplay entities or Aogera movement policy.

## 5. GroundHull and the fixed-shape policy

`BSP29::GroundHull` adapts compiled hull 1 to Aogera's current feet-based ground actor convention.

Aogera's current `Position.y` is the actor's feet height. Standard BSP29 hull 1 is compiled around a Quake-style hull origin with:

```text
horizontal half-extent  16
vertical minimum       -24
vertical maximum        32
```

Therefore `GroundHull` traces at:

```text
hull origin Y = actor feet Y + 24
```

This is an import/collision-source convention. Aogera does not change its canonical actor origin to match Quake.

### GroundBody radius does not resize hull 1

Aogera still authors dynamic ground bodies using `GroundBody(radius)`.

For the controlled content the important values are approximately:

```text
player radius   7.04
goblin radius   8.96
BSP hull 1      16.0 horizontal half-extent
```

These values describe different collision sources:

```text
static BSP world clearance -> fixed compiled hull 1
dynamic actor clearance    -> GroundBody circles
```

`GroundHull` is bound to the authored radius of the actor it serves. That radius is a contract check only. It does not modify the BSP hull. A mismatched radius raises rather than silently reusing an adapter created for another actor shape.

`BSP29::GroundClearance` caches one radius-bound `GroundHull` adapter per encountered authored radius so the same compiled BSP source can safely serve player and NPC movement.

## 6. The controlled 32-unit pinch

The controlled `test_field` deliberately preserves an important mismatch.

At cell `(30, 4)` there is a one-cell-wide passable corridor between blocked water-looking cells above and below. With 32 world units per grid cell, the corridor is 32 units wide.

The authored player circle has positive clearance:

```text
32 - (2 * 7.04) = 17.92 world units of total slack
```

Standard hull 1 has zero nominal horizontal slack:

```text
32 - (2 * 16) = 0
```

Therefore the BSP player cannot reliably pass through that pinch even though the old grid/circle model could.

This is retained intentionally as a diagnostic fixture. v0.3.2 does not widen the map, pretend that `GroundBody(radius)` resizes BSP hulls, or reconstruct arbitrary-radius collision from render triangles.

Arbitrary authored actor sizes for static BSP collision remain future work and require a collision representation that can actually encode them.

## 7. GroundSpace remains the gameplay-facing service

The BSP migration did not replace `GroundSpace` or `GroundMovement`.

The BSP preview configures one `GroundSpace` with two static query providers:

```text
positive-radius actor sweep
    -> BSP29::GroundClearance
    -> compiled hull 1

zero-radius obstruction trace
    -> BSP29::PointHull
    -> world-model node/leaf tree
```

Dynamic actors still participate through continuous `GroundBody` circle collision.

All candidates continue to produce the existing `GroundTrace` gameplay contract:

```text
fraction
end_x / end_z
normal_x / normal_z
entity_id
world_hit
start_blocked
```

The movement solver therefore remains unaware of BSP planes, clipnodes, nodes, or leaves.

## 8. Migration sequence completed in v0.3.2

The collision work was intentionally staged.

### Step 1: compiled clip-hull primitive

Added `BSP29::ClipHull` and tested clear traces, impacts, contents classification, solid starts, plane normals, nested trees, and malformed references.

### Step 2: first player BSP movement integration

The first integration attached compiled hull 1 to movement. This exposed an important problem: applying the new BSP backend to all actors while NPC route planning remained grid-only could make NPCs repeatedly choose movement the executor would reject.

### Step 3: restore explicit player/NPC authority split

BSP static movement was temporarily restricted to the bound player while NPCs remained grid-backed. This restored behavioral consistency and separated the collision migration from NPC navigation migration.

### Step 4: harden authority and fixed-hull assumptions

Regression tests documented the 32-unit pinch and verified that retirement removes dynamic blockers without altering immutable BSP static collision.

The hull-1 dimensions and the difference between fixed BSP clearance and authored `GroundBody` radius were made explicit.

### Step 5: migrate ground-style obstruction

Added `BSP29::PointHull` for hull-0 node/leaf tracing. BSP-mode melee, interaction, NPC melee planning, and executor validation now share BSP static obstruction.

Current obstruction queries run at a fixed 16-unit height above actor feet. This avoids tracing exactly along the fixture's floor/brush boundary and is only a temporary flat-ground combat convention, not a vertical combat system.

### Step 6: remove the rendering grid gate

Dynamic entity rendering in BSP mode stopped converting actor positions back to grid cells merely to decide whether an entity should be drawn.

### Step 7: make BFS candidate transitions BSP-aware

The BFS topology remained unchanged, but every candidate center-to-center static transition gained a `BSP29::GroundClearance` check before entering the route.

This made navigation conservative with respect to the same static BSP source that movement would later use.

### Step 8: migrate NPC static movement

Spawned NPC movement execution moved from grid static collision to the same BSP `GroundClearance` source already used by BFS candidate validation.

The existing `GroundMovement` sweep-and-slide solver continued unchanged. Dynamic actor collision and retirement behavior also remained unchanged.

### Step 9: unify actor movement authority

Once both player and NPC movement used BSP static collision, the temporary bound-player movement service was removed.

The BSP preview now has one actor movement path:

```text
GroundMove
    -> GroundMovement
    -> GroundSpace
    -> GroundClearance
    -> radius-bound GroundHull
    -> BSP29 ClipHull 1
```

This is the v0.3.2 RC checkpoint.

## 9. v0.3.2 RC authority map (historical)

The v0.3.2 BSP preview reached the following stable collision boundary:

```text
STATIC RENDERING
    BSP29 world model 0

ACTOR STATIC MOVEMENT
    GroundSpace
      -> BSP29::GroundClearance
      -> compiled hull 1

DYNAMIC ACTOR COLLISION
    GroundBody circles

MELEE / INTERACTION STATIC OBSTRUCTION
    GroundSpace
      -> BSP29::PointHull
      -> hull-0 node/leaf tree

NAVIGATION AT THAT CHECKPOINT
    Ruby grid BFS
      -> candidate static edges validated by GroundClearance

SPAWNS / ENTRIES / LEVEL CONSTRUCTION
    Ruby authored test_field through Level::Readers::Ruby / Level::Loader
```

The important v0.3.2 invariant was:

> BSP29 answered the static collision questions used by BSP-mode actor movement and obstruction, even though route topology was still temporarily grid-based.

That collision boundary survives unchanged into v0.3.3.

## 10. What the grid still does after the v0.3.3 chase cutover

The grid is not runtime actor-position authority, BSP-mode static collision authority, or active chase-navigation authority.

It still provides:

- the current authored `test_field` terrain representation loaded by `Level::Loader`;
- authored spawn/entry declarations and their current validation;
- the complete static collision/rendering fallback for the normal non-BSP Ruby launch;
- dormant/reference `Simulation::Pathfinder` behavior and tests.

The controlled BSP launch still loads the matching Ruby level because BSP entity declarations have not yet replaced the current gameplay spawn/entry path.

The old Pathfinder's cells, dynamic occupancy projection, cell-center waypoints, and static edge-clearance cache remain implementation history/reference rather than active BSP chase logic.

## 11. v0.3.3 local-navigation follow-on

The 0.3.3 cleanup line removed grid BFS from normal chase behavior without changing the collision solver.

The active chase path is now:

```text
Behavior(:chase)
      |
      v
SteeringTarget(goal entity)
      |
      v
GroundNavigation
      |
      | short sweep_circle probes
      v
GroundHeading
      |
      v
GroundSteering @ 30 Hz
      |
      v
GroundMove
      |
      v
GroundMovement / GroundSpace
```

`GroundNavigation` operates on actual continuous actor positions and asks `GroundSpace` whether candidate local headings are physically usable. In BSP mode those positive-radius queries reach the same `BSP29::GroundClearance` / compiled-hull path as actual actor movement. Dynamic blockers participate through the same `GroundSpace` query rather than through projected navigation cells.

For an entity goal, `SteeringTarget` stores `goal_entity_id`. `GroundSteering` resolves that entity's current `Position` every simulation tick, so local pursuit reacts between the existing low-frequency behavior updates. The previous chosen `GroundHeading` is kept as limited local movement memory.

The local query prefers direct pursuit, then can use a previous non-reversing heading, blocking-plane tangents, and deterministic rotated alternatives. If no candidate is usable it returns `route_needed`; the current runtime keeps the goal and retries on the next fixed tick.

This removes the cell-center/off-center mismatch that caused the late grid-era freeze and obstacle-border behaviors. It does not claim to solve global routing.

## 12. Future larger-scale routing

If real Aogera maps demonstrate that local pursuit cannot solve their topology, `GroundNavigation::ROUTE_NEEDED` is the intended fallback seam for a larger-scale route system.

The preferred direction is a compact world-space graph inspired by the GoldSrc lineage rather than a revival of the gameplay grid. Candidate links should be certified by the same static collision system used at runtime:

```text
node A
   |
   | candidate link
   v
GroundSpace / actor-hull static probe
   |
   +-- clear   -> keep link
   +-- blocked -> reject link
```

Dynamic actors must remain runtime obstacles rather than permanent graph properties.

The exact node authoring/generation scheme, sidecar format, and search algorithm are intentionally deferred until local navigation has been tested on real BSP levels. BSP-leaf adjacency is not assumed to be a navigation graph.

Removing the remaining Ruby-level spawn/entry bridge is a separate authored-data milestone from navigation.

## 13. Deferred systems

The v0.3.2 RC intentionally does not combine the collision migration with:

- gravity;
- jumping;
- stair/step movement;
- general floor/ceiling locomotion;
- brush submodel movement;
- doors or platforms;
- triggers;
- true liquid/water contents;
- generalized contents/masks;
- BSP gameplay entity import;
- BSP-native navigation generation;
- projectiles/hitscan;
- arbitrary BSP actor hull generation;
- rigid-body physics.

These should be introduced only when their own milestone requires them.

## 14. RC test and manual fixture commands

The documented automated baseline for this checkpoint is:

```text
239 runs, 727 assertions, 0 failures, 0 errors, 0 skips
```

Run the full suite from the project root with:

```bash
bundle exec ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

Run the controlled BSP test field with:

```bash
bundle exec ruby bin/aogera-bsp29 \
  ~/Downloads/aogera-test-field-bsp29-fixture/test_field.bsp
```

Manual RC checks should include:

- player movement and wall sliding;
- goblin movement and rerouting;
- killing one goblin while others continue chasing;
- dynamic actor blocking and recovery after retirement;
- melee/interaction obstruction by BSP walls;
- the known blocked 32-unit water pinch, which remains an expected fixed-hull limitation.

## 15. Release-candidate rule

For v0.3.2, the migration is now at a coherent stopping point.

Unless a concrete RC bug appears, avoid further collision/navigation feature work before release. The important achievement is not removal of every grid data structure; it is that BSP-mode static collision now has one consistent authority while the remaining grid roles are narrow, visible, and testable.
