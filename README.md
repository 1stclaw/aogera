# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.3.3 (development)**

Aogera 0.3.3 is an internal cleanup line built on the stable 0.3.2a BSP29 collision checkpoint. The cleanup line raises the project baseline to Ruby 3.4+, normalizes persistent `Character` state as immutable `Data`, narrows `Session` mutation to validated persistent-effect batches, and separates legacy grid navigation decisions from fixed-step locomotion in small controlled steps. BSP rendering and collision semantics remain inherited from 0.3.2a.

Every spatial runtime entity uses:

```text
Component::Position(x, y, z)
```

The coordinate convention is Y-up:

```text
world +X -> east/right
world +Y -> up
world +Z -> south / current grid +Y
```

Aogera world-unit magnitude is now compatible with Quake 1 map units. The temporary grid uses **32 world units per authored cell**. Existing movement speeds, body radii, melee/interaction reach, camera eye height, and primitive renderer dimensions were scaled proportionally, so the current test level keeps the same gameplay proportions while no longer using the old one-cell/one-unit scale.

### Authored-data path

Map/world authored data now has an explicit boundary:

```text
source file
    |
    v
Reader
    |
    | normalized Aogera coordinates / world units
    v
Level::AuthoredData
    |
    v
Level::Loader
    |
    v
Level / runtime
```

The current `Level::Readers::Ruby` understands the existing Ruby/grid source format and converts grid coordinates into Aogera world-space positions before `Level::Loader` sees them. `Level::Loader` accepts normalized authored data only; it does not parse source files.

The first external reader now exists as `BSP29::Reader`. It decodes Quake 1 BSP29 into normalized `BSP29::MapData`, preserving BSP-specific structure while converting vectors, bounds, plane normals, texture axes, model origins, and entity origins to Aogera axes at 1:1 world-unit magnitude.

The Reader has been validated end-to-end with an Aogera-controlled BSP29 fixture compiled by ericw-tools from the original `test_field` layout. The current release can render BSP world model `0` directly as a static-world preview while gameplay still uses the matching Ruby/grid level.

### Runtime movement and collision

Player and NPC locomotion both use `Simulation::Commands::GroundMove` and the same continuous swept-circle collision solver. `GroundSpace` provides shared distance, arc, segment-trace, and swept-circle queries, returning structured `GroundTrace` results. The active static-world backend and dynamic bodies participate in one earliest-hit contract. The normal Ruby launch uses grid terrain; the BSP preview uses compiled hull/node data.

Melee and interaction keep their own authored reach/arc profiles while using shared spatial and obstruction queries. Defeated actors enter an explicit retired lifecycle state: they may retain runtime identity and descriptive state, but they no longer act or participate in ordinary active collision queries.

The remaining grid has deliberately limited jobs in the BSP preview:

- current Ruby-authored level/spawn/entry scaffolding;
- temporary BFS navigation topology and dynamic cell occupancy;
- the normal non-BSP Ruby rendering/collision fallback.

Navigation cells are derived from world-space positions and are not runtime entity state. In BSP mode, BFS still searches those cells, but candidate center-to-center transitions are additionally validated against the same BSP29 compiled hull-1 clearance used by actor movement execution. Because BSP static geometry is immutable for the loaded level, the Pathfinder memoizes those directed static transition results per level, actor radius, and feet height; dynamic entity occupancy is still recomputed on every search. The grid is now internal to `Simulation::Pathfinder`: its public chase result is a world-space `Pathfinder::Waypoint(x, z)`, so `RealtimeController` no longer converts grid directions or cells into movement targets. NPC decisions persist their chosen world-space destination as `Component::SteeringTarget(x, z)`. When BFS has already reached a target-adjacent goal cell but continuous melee reach has not yet been achieved, `Simulation::Pathfinder` returns the target's current world-space X/Z as a final-approach waypoint instead of the current cell center; BSP mode only accepts that shortcut when static ground-hull clearance is clear. `Simulation::GroundSteering` consumes steering intent every fixed 30 Hz simulation tick and emits ordinary `GroundMove` commands capped to `NPC_SPEED / TICK_HZ`; the controller therefore decides only on its existing low-frequency cadence while locomotion continues between decision ticks.

The grid Pathfinder is now explicitly frozen as a temporary compatibility implementation. A staged `Simulation::GroundNavigation` surface operates only on continuous positions, `GroundBody`, `GroundSpace`, and normalized `GroundHeading` values, returning `direct`, `local_avoidance`, `route_needed`, or `arrived`. It is not yet wired into gameplay in this preparation patch; the next navigation milestone can replace active BFS chase without changing the movement/collision layers again.

## Running

Aogera 0.3.3 requires **Ruby 3.4+**. The repository currently pins Ruby 3.4.10 for development through `.ruby-version`.

```bash
bundle install
bundle exec ruby bin/aogera
```

The raylib window captures the mouse for first-person look. `Q` or `Esc` exits and the host releases the cursor during shutdown.

For the controlled BSP29 test-field preview:

```bash
bundle exec ruby bin/aogera-bsp29 /path/to/test_field.bsp
```

That preview uses BSP29 world-model faces for static rendering and the matching Ruby `test_field` as the remaining authored/navigation bridge. Bound-player and spawned-NPC static movement use BSP29 compiled hull 1, melee/interaction obstruction uses the BSP world-model node/leaf tree, and BFS still uses the Ruby grid as its topology. In BSP mode each candidate center-to-center BFS step and spawned-NPC movement execution share the same `BSP29::GroundClearance` source. This is an intentional incremental migration boundary.

## Controls

```text
Mouse        look
W / Up       forward
S / Down     backward
A / Left     strafe left
D / Right    strafe right
Space        melee attack
Enter        interact / advance dialogue
Q / Esc      quit
```

## Testing

Aogera uses Minitest directly. Run the complete suite with:

```bash
bundle exec ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

This is the preferred project test command. The stable v0.3.2a BSP baseline was **239 runs / 727 assertions / 0 failures / 0 errors / 0 skips**. After the current 0.3.3 local-navigation staging work, the known cleanup baseline is **274 runs / 860 assertions / 0 failures / 0 errors / 0 skips**.

## Runtime structure

Simulation timing is independent from rendering. The simulation runs at a fixed **30 Hz**, while the raylib frontend targets **60 FPS**.

```text
keyboard -> Host::Raylib -> Input::Action -> fixed-step gameplay
mouse    -> Host::Raylib -> Input::LookDelta -> FirstPersonView

Position + FirstPersonView
        -> Render::Raylib3D -> RaylibAPI -> raylib
```

Aogera still has no generic scene/projector/transform layer, no general physics system, and no general asset manager. The normal path directly extrudes the authored grid; the BSP29 preview reconstructs and triangulates world-model faces without routing them through a generic scene representation. Collision remains deliberately hybrid during the migration: actor static movement uses BSP29 compiled hull 1 through one shared `GroundClearance` backend, melee/interaction obstruction uses the BSP node/leaf point hull, BFS keeps grid topology while validating candidate transitions against the same BSP hull-1 clearance source, and dynamic actor collision remains continuous `GroundBody` collision. Vertical actor collision, gravity, jumping, and projectile/hitscan systems remain future work.

## Documentation

- `docs/architecture.md` — current runtime architecture and subsystem boundaries;
- `docs/authored_data.md` — Reader/normalized-data/Loader boundary and world-unit convention;
- `docs/bsp29.md` — current BSP29 binary Reader, normalization, records, and inspection tool;
- `docs/bsp_collision_migration.md` — v0.3.2 BSP collision migration history, current authority map, fixed-hull limitation, and incremental pathfinding roadmap;
- `docs/navigation_migration.md` — staged migration from grid BFS toward Quake-like local navigation with a future collision-certified route-graph fallback;
- `docs/collision.md` — current ground-space trace, sweep, movement, and obstruction model;
- `docs/raylib_3d.md` — raylib 3D frontend and first-person presentation path;
- `docs/3d_migration.md` — cumulative architectural change from the v0.2.3 2D baseline to the v0.3.2 line;
- `docs/future.md` — explicitly speculative future runtime, Ruby-version, performance, rendering, and navigation directions.

## Direction

The 0.3.2 runtime now includes the first BSP29 **Reader**. BSP29 binary structure is decoded outside `Level::Loader`, and geometry-related values are normalized to Aogera axes without scalar resizing.

The first downstream BSP integration now exists as a minimal world-model renderer. A controlled 44×14 test-field fixture compiled as BSP29 has matching structural counts between ericw-tools and `BSP29::Reader`, and its normalized player start resolves to `(112, 0, 112)` as expected.

The current BSP collision-query boundary consumes compiled clip hull 1 for all current actor static movement and the world-model node/leaf tree for melee/interaction obstruction. BSP-mode dynamic entity rendering no longer consults the Ruby grid for bounds. Grid BFS keeps its existing cell topology and dynamic-cell occupancy rules while validating candidate center-to-center transitions against the same BSP hull-1 static-clearance source used by movement execution.

The stable v0.3.2a release remains the collision checkpoint. The 0.3.3 line is cleanup-focused but now also stages the final navigation boundary needed to retire active cell-BFS chase: world-space `GroundHeading` plus collision-driven `GroundNavigation`, with the old Pathfinder still active until the explicit cutover. See `docs/bsp_collision_migration.md` for the detailed migration record and roadmap.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
