# BSP29 Collision and Navigation Migration

This document records the v0.3.2 migration from Aogera's original grid-backed static gameplay space toward BSP29 collision, while preserving the continuous runtime introduced in v0.3.1.

It is both a checkpoint description and a constraint for later work. The current implementation is intentionally hybrid. The remaining grid data is still useful for authored-level scaffolding and BFS topology, but BSP29 is now authoritative for the static collision questions used by actor movement and ground-style obstruction queries in the BSP preview.

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

This became the v0.3.2a release checkpoint.

## 9. Current v0.3.2a authority map

The current BSP preview is still hybrid, but static collision authority is no longer split between player and NPC movement.

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

BFS TOPOLOGY
    Ruby Level::Terrain cells

BFS STATIC STEP CLEARANCE
    same BSP29::GroundClearance used by movement

BFS DYNAMIC OCCUPANCY
    active blocking actors projected into cells

SPAWNS / ENTRIES / CURRENT LEVEL CONSTRUCTION
    Ruby authored test_field through Level::Readers::Ruby / Level::Loader
```

This is the key release invariant:

> BSP29 now answers the static collision questions used by BSP-mode actor movement and obstruction, while the Ruby grid remains a temporary navigation/authored-level scaffold.

## 10. What the grid still does

The grid is not runtime actor position authority, and it is no longer BSP-mode static actor collision authority.

It still provides several concrete services in v0.3.2:

- the authored `test_field` terrain representation loaded by the current `Level::Loader` path;
- authored spawn/entry declarations and their current level validation;
- BFS cell topology;
- BFS dynamic occupancy projection;
- cell-center waypoints used by the current NPC steering model;
- the complete static collision/rendering fallback for the normal non-BSP Ruby launch.

The controlled BSP launch intentionally continues loading the matching Ruby level because gameplay entity import from the BSP entity lump has not yet replaced it.

## 11. What "BSP-aware pathfinding" means today

Aogera does not yet have BSP-native navigation.

The current Pathfinder still performs ordinary grid BFS:

```text
continuous Position
    -> temporary grid cell
    -> BFS over grid neighbors
    -> next cell center
    -> continuous GroundMove
```

The important v0.3.2 change is that static eligibility of each candidate transition is no longer based on the grid alone.

In BSP mode:

```text
neighbor exists in grid topology?
        |
        v
grid terrain passable?
        |
        v
not dynamically occupied?
        |
        v
BSP hull-1 center-to-center clearance?
        |
        v
accept BFS transition
```

Planning and movement execution therefore consult the same compiled static collision source even though route topology is still cell-based.

This is intentionally a compatibility bridge rather than a new navigation architecture.

## 12. Recommended post-v0.3.2 navigation migration

Further navigation work should remain incremental.

### Phase A: preserve the release baseline

Do not replace BFS while preserving the v0.3.2a baseline. Treat regressions in the controlled BSP field as maintenance bugs rather than opportunities for broad redesign.

### Phase B: isolate grid topology from `Level::Terrain`

When a real BSP-authored gameplay level requires it, define a small navigation-topology source instead of having `Pathfinder` directly assume that gameplay terrain and navigation topology are the same object.

The first replacement can still be a grid or coarse cell graph. The goal is dependency separation, not algorithm novelty.

### Phase C: derive or author navigation for BSP worlds

Only then choose how BSP levels provide navigation nodes/edges. Possibilities include an offline generated graph, authored navigation hints, or another compact representation appropriate to Aogera's maps.

The collision service should remain the final static-clearance validator even if the topology source changes.

### Phase D: remove Ruby-level dependency from BSP launch

After BSP map entities/spawns and BSP navigation data exist, the BSP launch no longer needs to load the matching Ruby `test_field` as gameplay scaffolding.

At that point `Level::Terrain` can remain as the normal Ruby-level implementation without being a required BSP runtime dependency.

## 13. Deferred systems

The v0.3.2a release intentionally does not combine the collision migration with:

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

## 14. Release test and manual fixture commands

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

Manual release checks should include:

- player movement and wall sliding;
- goblin movement and rerouting;
- killing one goblin while others continue chasing;
- dynamic actor blocking and recovery after retirement;
- melee/interaction obstruction by BSP walls;
- the known blocked 32-unit water pinch, which remains an expected fixed-hull limitation.

## 15. Release-baseline rule

For v0.3.2, the migration is now at a coherent stopping point.

After v0.3.2a, avoid folding new collision/navigation features into this release baseline. The important achievement is not removal of every grid data structure; it is that BSP-mode static collision now has one consistent authority while the remaining grid roles are narrow, visible, and testable.
