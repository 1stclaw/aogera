# Aogera Future Directions

This document records possible future directions for Aogera that are intentionally **not**
part of the current architecture contract.

It exists to preserve promising ideas without forcing the current Ruby implementation to
anticipate them prematurely.

Anything in this document should be treated as:

- exploratory;
- benchmark-driven;
- revisable;
- subordinate to the actual needs of the game;
- non-binding for the current release line.

The uploaded/source repository and current architecture documents remain authoritative for
the implementation that exists today.

---

# 1. Current invariants

Aogera is currently a Ruby + raylib project.

The stable v0.3.2a line retained Ruby 3.2 compatibility. The v0.3.3 development line deliberately raises the minimum to:

```text
Ruby 3.4+
```

This is now an explicit project baseline rather than an experiment. It permits the codebase to use modern immutable-data conveniences such as `Data#with` without compatibility shims.

Current development environments may be newer than the supported baseline. At the time this
document was written:

```text
Linux development:   Ruby 3.4.10
Windows development: Ruby 4.0.3
```

This difference is useful for experimentation, but it should not silently redefine the
project's compatibility contract.

Aogera should continue to prefer:

- explicit data-oriented runtime state;
- immutable value records where practical;
- integer entity IDs and component tables;
- fixed-step simulation;
- small, purpose-specific systems;
- mature external tooling;
- profiling before optimization;
- incremental architectural changes;
- direct solutions over speculative engine frameworks.

A future optimization opportunity is not a reason to distort today's code.

---

# 2. Ruby 3.4 baseline

Aogera 0.3.3 adopts Ruby 3.4+ as its development and support baseline. The immediate purpose is simpler, more consistent modern Ruby rather than syntax churn or speculative optimization.

The project should still measure the runtime benefits rather than assume them. Relevant Ruby 3.4 advantages to evaluate include:

- newer `Data` conveniences such as `Data#with`;
- YJIT improvements;
- improved profiling and runtime diagnostics;
- lower allocation or GC overhead in relevant workloads;
- improvements in byte-oriented and binary-processing code;
- simpler implementation of immutable value updates;
- opportunities to reduce hand-written compatibility code.

The evaluation should use Aogera itself rather than generic language microbenchmarks.

---

# 3. Ruby 3.4 experiment targets

The first runtime experiment should compare the supported Ruby 3.4 configuration with and without YJIT, and may keep older results only as historical reference.

At minimum, benchmark:

```text
Ruby 3.4 interpreter
Ruby 3.4 + YJIT
```

where practical.

Useful Aogera workloads include:

## BSP29 traversal

Measure:

- clipnode traversal;
- hull traces;
- node/leaf point traces;
- repeated static collision queries;
- malformed-reference validation overhead.

Relevant current systems include:

```text
BSP29::ClipHull
BSP29::GroundHull
BSP29::GroundClearance
BSP29::PointHull
```

## Ground collision

Measure:

- dynamic circle sweeps;
- static BSP traces;
- earliest-hit selection;
- repeated near-contact traces;
- multi-contact wall sliding.

Relevant systems include:

```text
GroundSpace
GroundMovement
```

## Navigation

Measure:

- BFS expansion;
- BSP-aware transition validation;
- dynamic occupancy checks;
- repeated chase replanning.

The current grid BFS is deliberately simple and should remain a useful baseline even if
navigation changes later.

## ECS iteration

Measure:

- entity scans;
- component-table access;
- cached `entity_ids`;
- active/retired filtering;
- command execution over representative entity counts.

Relevant systems include:

```text
World
ComponentTable
View
Relations
Simulation::Executor
```

## Content loading

Measure:

- BSP29 binary parsing;
- entity-text parsing;
- authored Ruby content loading;
- coordinate normalization;
- allocation behavior during map loading.

Loading is less latency-sensitive than simulation, but it is a useful binary-processing
benchmark for newer Ruby runtimes.

---

# 4. Benchmark policy

Do not optimize from intuition alone.

For every performance-oriented change:

1. identify a real workload;
2. record a baseline;
3. profile before changing code;
4. make one coherent change;
5. benchmark again;
6. keep the change only if it improves the real target without unacceptable complexity.

Prefer representative scenarios over isolated microbenchmarks.

A useful benchmark scene should eventually include:

```text
one BSP world
multiple moving actors
dynamic collisions
NPC pathfinding
melee/interaction traces
retirement/despawn activity
normal 30 Hz simulation
normal rendering cadence
```

The purpose is to measure Aogera as a game runtime, not Ruby as an abstract language.

---

# 5. Data representation before native code

If profiling reveals a hotspot, optimize the representation and algorithm before reaching
for a native extension.

Preferred order:

```text
1. remove unnecessary work
2. improve algorithm
3. reduce allocation
4. improve data layout
5. simplify dispatch
6. use newer Ruby/JIT capabilities
7. consider a native implementation only for a demonstrated hotspot
```

Aogera already benefits from data-oriented choices such as integer entity IDs, flat component
storage, immutable records, and explicit systems.

Preserve those advantages.

Do not introduce native code merely because collision, BSP parsing, or navigation are commonly
written in C/C++ in other engines.

---

# 6. Ruby 4.x policy

Ruby 4.0 is useful as an experimental environment but should not become Aogera's required
baseline merely because it is available.

The intended policy is:

```text
Ruby 4.0
    -> experiment only

Ruby 4.1+
    -> reevaluate after the release line has stabilized
```

The important threshold is not the number `4.1` itself.

The project should reconsider Ruby 4.x when:

- the runtime is mature enough for ordinary Aogera development;
- its JIT behavior is stable;
- gem/tooling compatibility is comfortable;
- raylib integration is reliable;
- profiling shows a meaningful benefit;
- adoption does not force unnecessary architectural churn.

---

# 7. ZJIT / future JIT evaluation

Ruby 4.x introduces a new JIT direction with a potentially higher optimization ceiling.

Aogera should revisit this only when the implementation is mature enough to be evaluated
against real workloads.

The eventual comparison should be empirical:

```text
Ruby 3.4 + YJIT
Ruby 4.1+ + YJIT, if available/relevant
Ruby 4.1+ + ZJIT
```

Useful targets are the same Aogera workloads listed earlier:

- BSP traversal;
- `GroundSpace` queries;
- `GroundMovement`;
- ECS iteration;
- command execution;
- pathfinding;
- rendering-data preparation.

Aogera may be a useful JIT workload because it contains:

- long-running loops;
- repeated small-method calls;
- predictable system passes;
- immutable value records;
- integer-indexed runtime state;
- fixed simulation cadence.

These characteristics make JIT experimentation worthwhile, but performance gains should not
be assumed in advance.

---

# 8. Parallelism and Ractors

Do not introduce parallelism simply because future Ruby versions improve Ractors or runtime
locking.

Aogera currently benefits from a simple execution model.

Parallel work should only be considered for workloads that are naturally separable, such as:

- offline preprocessing;
- asset decoding;
- map conversion;
- expensive background content preparation;
- potentially isolated navigation work;
- tooling that is independent of the authoritative simulation tick.

The main simulation should remain deterministic and easy to reason about unless a real
performance limit forces reconsideration.

Do not revive older planner/execution multi-thread designs merely because newer Ruby makes
parallel execution more capable.

---

# 9. Native extensions

A native extension is a possible optimization tool, not a planned architectural layer.

Potential candidates might eventually include:

- very hot BSP collision traversal;
- heavy geometry processing;
- specialized navigation queries;
- binary decoding.

But native code should only be introduced when all of the following are true:

1. profiling identifies a dominant hotspot;
2. algorithmic and Ruby-level optimizations are insufficient;
3. the interface can remain small and data-oriented;
4. portability costs are acceptable;
5. Windows and Linux development remain practical;
6. the extension does not turn Aogera into a wrapper around another engine.

The default implementation language remains Ruby.

---

# 10. Odin + Lua

A possible future Odin + Lua implementation remains a separate long-term direction.

It should not be treated as the destination that current Ruby Aogera must prepare for.

If such a project happens, it may reuse:

- game rules;
- lessons from BSP integration;
- content concepts;
- collision semantics;
- architectural ideas.

It does not require Ruby Aogera to mirror Odin data structures or Lua scripting conventions
today.

Aogera should remain a good Ruby program first.

---

# 11. Persistent-state cleanup opportunities

A future Ruby minimum-version bump may justify small consistency cleanups.

One example is immutable persistent character state.

The 0.3.3 cleanup line has now converted persistent `Character` state to a validated `Data` value and uses `Data#with` for replacement updates. It also narrows `Session` mutation to `apply_effects`, keeping effect-specific replacement logic private instead of exposing speculative healing or MP-management verbs before those systems exist. This is the preferred idiom for flat immutable persistent values when validation remains straightforward.

Do not force service objects, catalogs, or state owners into `Data.define`; the goal is to distinguish data from systems, not to eliminate classes.

Other cleanup opportunities should follow the same rule:

> behavior and clarity first; stylistic uniformity second.

---

# 12. GroundSpace growth

`GroundSpace` is currently a central geometric-query service.

That is appropriate, but future features could cause it to grow too broadly.

Possible future collision features include:

- gravity;
- vertical movement;
- stairs;
- moving brush submodels;
- doors;
- triggers;
- water contents;
- hitscan;
- projectiles;
- area effects;
- arbitrary actor hulls.

Do not simply place every one of these directly into `GroundSpace`.

Continue the pattern already established by BSP support:

```text
GroundSpace
    |
    +-- BSP29::GroundHull
    +-- BSP29::GroundClearance
    +-- BSP29::PointHull
```

New lower-level geometry responsibilities should earn their own focused components when
actual implementation pressure appears.

Avoid speculative hierarchies such as:

```text
PhysicsWorld
UniversalCollider
GenericSpatialBackend
TransformEverything
```

until the game genuinely requires them.

---

# 13. Navigation future

Current BSP-mode navigation intentionally remains hybrid:

```text
topology
    -> Ruby grid BFS

candidate-step static clearance
    -> BSP29 compiled hull collision
```

This is a useful intermediate design.

Do not replace BFS simply because BSP collision now exists.

A future navigation migration should proceed incrementally.

Possible stages:

```text
1. retain grid BFS as reference behavior
2. isolate authored-grid topology from collision authority
3. introduce BSP-derived navigation data only when needed
4. compare behavior against controlled test maps
5. migrate one NPC/navigation consumer at a time
6. remove old topology only after replacement is proven
```

Navigation should remain a separate problem from collision.

---

# 14. BSP format future

BSP29 is the current active map/collision format.

Potential future work may include:

- brush submodels;
- doors/platforms;
- triggers;
- real contents;
- lightmaps;
- PVS;
- richer materials;
- additional map formats;
- possibly BSP38.

Do not generalize BSP29 code prematurely around hypothetical formats.

A future BSP38 reader may legitimately produce a different normalized structure.

Format-specific readers should continue to preserve meaningful source structure rather than
flatten everything into a universal geometry schema.

---

# 15. Rendering future

Aogera's use of BSP does not imply Quake-era visual limits.

Possible future rendering improvements include:

- higher-resolution textures;
- modern materials;
- shaders;
- dynamic lighting;
- particles;
- external models;
- animation;
- post-processing.

These should remain independent from collision architecture where practical.

BSP may remain the static world structure while rendering becomes substantially more modern.

Do not require the collision format and visual format to evolve in lockstep.

---

# 16. Release discipline

Future-runtime experiments should not destabilize release candidates.

A useful policy is:

```text
release candidate
    -> freeze architectural experiments

next development milestone
    -> benchmark/runtime experiments allowed

release branch/main
    -> stable supported baseline
```

Ruby 3.4 became the explicit minimum in the 0.3.3 cleanup milestone. Future minimum-version changes should follow the same discipline: document them, verify the intended runtime, and justify them through clarity, tooling, or measured performance rather than silently following development-machine versions.

---

# 17. Decision points

The following questions should be revisited after v0.3.2 rather than answered prematurely.

## Ruby 3.4 performance

Ask:

- Does YJIT materially improve Aogera?
- Does Ruby 3.4 reduce allocation/GC cost in hot paths?
- Which real Aogera workloads benefit enough to influence coding decisions?

## Ruby 4.1+

Ask:

- Is the runtime mature?
- Is ZJIT stable enough?
- Is it faster on Aogera's real workloads?
- Are dependencies/tooling ready?
- Does adoption simplify or complicate the project?

## Native optimization

Ask:

- Is a hotspot dominant?
- Can Ruby/JIT improvements solve it first?
- Can the interface remain small?
- Is the portability cost justified?

## Parallelism

Ask:

- Is the workload truly independent?
- Does concurrency improve throughput materially?
- Does it preserve deterministic simulation?
- Is the complexity justified?

---

# 18. Non-goals

This document does **not** commit Aogera to:

- Ruby 4.x adoption;
- ZJIT;
- Ractors;
- native extensions;
- a rewrite;
- Odin;
- Lua;
- BSP38;
- a generic physics engine;
- a new navigation system;
- any particular performance target.

It records areas worth evaluating.

Current implementation decisions should continue to be driven by actual code, tests,
profiling, and game requirements.

---

# 19. Guiding principle

The long-term performance strategy should remain:

> Keep Aogera simple enough that Ruby can do as much of the work as possible, then use
> measurement to identify the small number of places where something stronger is actually
> needed.

Aogera does not need to become a conventional C++-style engine in order to use BSP worlds,
3D collision, richer rendering, or more demanding gameplay.

The project should take advantage of improvements in Ruby when they genuinely help, while
keeping its architecture explicit, compact, and understandable.
