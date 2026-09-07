# Aogera v0.3.1 Collision Plan

## Purpose

This document describes the collision/spatial architecture intended for the first 0.3.x development release after v0.3.0.

The current `next` runtime already establishes the core foundation:

- one canonical `Component::Position(x, y, z)` for all runtime entities;
- `GroundBody(radius)` for current actor horizontal extent;
- one `GroundMove(entity_id, dx, dz)` command for player and NPC locomotion;
- `GroundSpace` as the current X/Z collision/query boundary;
- structured `GroundTrace` results;
- segment traces and swept-circle traces;
- normal-based multi-contact sliding;
- continuous melee and interaction obstruction tests;
- explicit retired-entity lifecycle handling.

The remaining authored grid is static terrain plus a temporary BFS navigation representation. It is not a second runtime entity-position system.

## 1. Collision query contract

Collision provides spatial facts. Movement, combat and interaction decide what those facts mean.

```text
movement / combat / interaction
            |
            v
        GroundSpace
            |
            v
        GroundTrace
```

`GroundSpace` should not know weapon damage, dialogue behavior, AI policy, knockback rules or projectile effects.

## 2. Canonical position

All spatial entities use:

```text
Position(x, y, z)
```

with:

```text
+X = east/right
+Y = up
+Z = south
```

Current ground collision consumes X/Z. Y is retained as real world-space state for the 3D runtime even though vertical actor collision is still deferred.

Grid-authored spawn coordinates are converted once at instantiation:

```text
cell (x, y) -> Position(x + 0.5, 0.0, y + 0.5)
```

## 3. Ground bodies

Current horizontal actor extent is authored as:

```text
GroundBody(radius)
```

This means only that the entity occupies a circle in current ground-plane collision. It does not imply mass, velocity, material, vertical extent or generic rigid-body physics.

## 4. GroundTrace

A trace result provides the facts required by callers:

```text
fraction
end_x / end_z
normal_x / normal_z
entity_id
world_hit
start_blocked
```

`fraction` describes how much of the requested segment was completed before the earliest collision. The end position is the exact reached contact position. The normal supplies the current ground-plane contact direction. Dynamic and static hits are distinguished explicitly.

## 5. Segment traces

A zero-radius segment trace asks:

> What is the first relevant obstruction between these two ground points?

Current uses include:

- melee obstruction;
- interaction obstruction;
- line-of-sight-like checks.

Later hitscan may consume the same kind of query without making the collision service weapon-specific.

## 6. Swept-circle traces

A swept-circle query asks:

> How far can this ground body move before first contact?

Current player and NPC locomotion both use this query through `GroundMovement`.

Static terrain cells and active dynamic `GroundBody` entities participate in the same earliest-hit result.

## 7. Movement resolution

`GroundMovement` owns movement policy, not shape-intersection mathematics.

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
move to contact
        |
        v
constrain remaining displacement by contact normals
        |
        v
repeat within a small bounded contact count
```

Distinct normals are accumulated during one movement command. This lets wall/actor compound contacts constrain motion together instead of resolving one surface, forgetting it and penetrating another.

The solver should never commit a result that begins already blocked. If numerical error violates that invariant, the known-valid command start is preferred over speculative depenetration.

## 8. Combat

Melee policy remains authored:

```text
MeleeAttack(reach, arc_degrees)
```

Target selection and authoritative attack validation consume continuous body separation and trace obstruction results. Grid adjacency is not a combat rule.

The current player uses view heading for arc selection. NPC AI may choose its known target according to behavior policy, but the executor validates the same continuous reach and obstruction facts regardless of attacker type.

Damage remains separate from attack delivery/targeting.

## 9. Interaction

Interaction retains independent authored policy:

```text
Interactor(reach, arc_degrees)
```

It uses the same spatial query foundation but separate target eligibility and interaction semantics.

This model is intended to extend naturally to future interactive world entities such as doors without giving them a special coordinate model.

## 10. Navigation

The present BFS grid is planning data only.

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

NPCs therefore share runtime position and collision with the player even while route planning still uses the current authored grid.

A future BSP-appropriate navigation model can replace BFS without rewriting entity coordinates or actor movement execution.

## 11. Filtering

Aogera does not yet need Quake-style contents/mask families. Current queries should support only concrete filtering needs such as:

- ignoring the source/moving entity;
- choosing which dynamic entities participate;
- distinguishing static world from dynamic body hits;
- excluding retired entities from ordinary active queries.

More elaborate collision filtering should be introduced from real gameplay requirements.

## 12. BSP relationship

The current static backend is temporary:

```text
GroundSpace
    |
    +-- static grid collision
    +-- dynamic GroundBody collision
```

The intended later shape is:

```text
GroundSpace / successor trace boundary
    |
    +-- BSP29 collision hull backend
    +-- dynamic entity collision
```

Movement, melee and interaction should consume the same trace-result contract regardless of which static-world representation answers the query.

Quake collision hulls/clipnodes should be treated as imported collision data rather than reconstructing collision from rendered BSP polygons.

## 13. Deferred work

This plan does not yet introduce:

- gravity or jumping;
- floor/ceiling/step handling;
- arbitrary vertical actor shapes;
- generic rigid-body physics;
- projectiles or hitscan weapons;
- generalized collision masks;
- BSP loading itself;
- generic `Transform`, `PhysicsBody` or `Spatial` frameworks.

## 14. Success criteria

The v0.3.1 spatial/collision milestone is successful when:

1. all runtime spatial entities use canonical `Position(x,y,z)`;
2. player and NPC movement use one `GroundMove` + sweep solver path;
3. runtime grid-position synchronization is gone;
4. grid data remains only where it is actually authored/navigation data;
5. movement uses earliest-hit sweeps and multi-contact normals;
6. melee and interaction cannot pass through blocking geometry;
7. NPC melee uses continuous reach/obstruction rather than Manhattan adjacency;
8. retired entities cannot keep acting or blocking ordinary active queries;
9. BSP can replace static collision later without changing gameplay callers;
10. no generic physics framework has been invented prematurely.

The central principle is:

> **Aogera has one runtime world-space model; specialized systems may derive temporary representations from it, but they do not become competing spatial truths.**
