# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.3.4 (development)**

Aogera 0.3.4 begins the real-BSP bring-up line on top of the stable 0.3.3 continuous-navigation release. BSP mode now bootstraps its runtime player entry directly from the map's normalized `info_player_start` instead of importing the Ruby `test_field` as gameplay scaffolding. It launches into a collision-free diagnostic spectator camera so arbitrary BSP geometry can be inspected before vertical Quake-style actor physics exists. The ordinary Ruby-authored launch remains unchanged.

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

The Reader has been validated end-to-end with an Aogera-controlled BSP29 fixture compiled by ericw-tools from the original `test_field` layout. BSP mode now renders world model `0` directly and bootstraps the player from the BSP entity lump; the matching Ruby `test_field` is no longer loaded by `bin/aogera-bsp29`. BSP world geometry is reconstructed once into diagnostic-color batches and uploaded to persistent raylib mesh/model resources after the graphics context opens, replacing the former per-triangle Ruby/FFI draw loop. The spectator also draws a compact diagnostic overlay with measured FPS, camera position/orientation, BSP triangle count, persistent mesh-draw count, and runtime entity count. The Ruby level path remains the normal non-BSP fallback.

### Runtime movement and collision

Player and NPC locomotion both use `Simulation::Commands::GroundMove` and the same continuous swept-circle collision solver. `GroundSpace` provides shared distance, arc, segment-trace, and swept-circle queries, returning structured `GroundTrace` results. The active static-world backend and dynamic bodies participate in one earliest-hit contract. The normal Ruby launch uses grid terrain; the BSP preview uses compiled hull/node data.

Melee and interaction keep their own authored reach/arc profiles while using shared spatial and obstruction queries. Defeated actors enter an explicit retired lifecycle state: they may retain runtime identity and descriptive state, but they no longer act or participate in ordinary active collision queries.

The remaining grid has deliberately limited jobs:

- an inert one-cell `Level` terrain scaffold required by the current `Simulation` container in BSP mode;
- the normal non-BSP Ruby rendering/collision fallback.

The BSP scaffold is not consulted by BSP rendering or static collision and carries no test-field spawns, relations, or dialogue.

Active chase no longer uses grid cells. `RealtimeController` now stores only a high-level world-space `Component::SteeringTarget`; for entity pursuit that target carries `goal_entity_id`, allowing `Simulation::GroundSteering` to resolve the goal entity's live position on every fixed 30 Hz simulation tick. `Simulation::GroundNavigation` then probes the actor's actual continuous `Position`/`GroundBody` through `GroundSpace` and returns `direct`, `local_avoidance`, `route_needed`, or `arrived` together with a normalized `GroundHeading`. `GroundSteering` converts that heading into the ordinary `GroundMove` command used by the existing sweep-and-slide collision path.

The obsolete grid `Simulation::Pathfinder` implementation has been removed from the active source tree after the local-navigation cutover was manually validated. Historical details remain in the migration documents. If local navigation proves insufficient, `route_needed` is the seam for a future GoldSrc-like world-space route graph whose links are certified by the real collision system.

## Running

Aogera 0.3.4 requires **Ruby 3.4+**. The repository currently pins Ruby 3.4.10 for development through `.ruby-version`.

```bash
bundle install
bundle exec ruby bin/aogera
```

The raylib window captures the mouse for first-person look. `Q` or `Esc` exits and the host releases the cursor during shutdown.

For the controlled BSP29 test-field preview, launch the diagnostic spectator explicitly:

```bash
bundle exec ruby bin/aogera-bsp29 --spectator ../bsp29-test-field/test_field.bsp
```

`bin/aogera-bsp29` has a deliberately small development CLI. No runtime launch mode is implicit: a bare BSP path is a usage error until a playable BSP mode exists.

Structural and entity inspection can be performed without opening raylib:

```bash
bundle exec ruby bin/aogera-bsp29 ../bsp29-test-field/test_field.bsp --bsp-info
bundle exec ruby bin/aogera-bsp29 ../bsp29-test-field/test_field.bsp --dump-entities
bundle exec ruby bin/aogera-bsp29 --help
```

`--bsp-info` prints BSP counts, world bounds, visibility/light byte counts, and normalized player starts. `--dump-entities` prints the original entity key/value declarations and, where available, the Reader's normalized Aogera-space origin. Only one exit-style inspection command may be selected per invocation. `--spectator` is currently the only runtime launch mode and must be explicit. The older `bin/aogera-bsp29-info` executable remains as a compatibility wrapper around `--bsp-info`. This is a launch/inspection CLI, not an interactive developer console or a game-command system.

BSP mode reads the first `info_player_start` from the map entity lump, uses its normalized origin as the initial Aogera player position, and converts its Quake `angle` to the initial first-person yaw. It no longer imports the Ruby `test_field`, its NPCs, relations, or dialogue. The preview now starts in `Mode::Spectator`: the camera begins at the spawned player's eye position but then flies independently without changing the player entity or consulting collision. A top-left diagnostic panel reports actual raylib FPS, camera XYZ, yaw/pitch, BSP triangle and mesh-draw counts, and runtime entity count; the bottom bar remains the spectator controls/tick readout. BSP world-model faces provide static rendering; the compiled collision backends remain configured in the dormant runtime for later actor testing. The current one-cell `Level` terrain in BSP mode is only structural scaffolding for `Simulation`.

## Controls

Normal Ruby-authored launch:

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

BSP diagnostic spectator:

```text
Mouse        look
W / Up       fly forward
S / Down     fly backward
A / Left     strafe left
D / Right    strafe right
Space        fly up
Shift / C    fly down
Q / Esc      quit
```

## Testing

Aogera uses Minitest directly. Run the complete suite with:

```bash
bundle exec ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

This is the preferred project test command. The stable v0.3.3 release baseline is **268 runs / 848 assertions / 0 failures / 0 errors / 0 skips**. The current v0.3.4 real-BSP bring-up line, including BSP-native bootstrap, spectator/CLI work, persistent mesh rendering, and the diagnostic overlay, is **298 runs / 1002 assertions / 0 failures / 0 errors / 0 skips**.

## Runtime structure

Simulation timing is independent from rendering. The simulation runs at a fixed **30 Hz**, while the raylib frontend targets **60 FPS**.

```text
keyboard -> Host::Raylib -> Input::Action -> fixed-step gameplay
mouse    -> Host::Raylib -> Input::LookDelta -> FirstPersonView

Position + FirstPersonView
        -> Render::Raylib3D -> RaylibAPI -> raylib
```

Aogera still has no generic scene/projector/transform layer, no general physics system, and no general asset manager. The normal path directly extrudes the authored grid; the BSP29 preview reconstructs and triangulates world-model faces without routing them through a generic scene representation. Collision remains deliberately hybrid during the migration: actor static movement uses BSP29 compiled hull 1 through one shared `GroundClearance` backend, melee/interaction obstruction uses the BSP node/leaf point hull, active local navigation probes that same `GroundSpace`, and dynamic actor collision remains continuous `GroundBody` collision. Vertical actor collision, gravity, jumping, and projectile/hitscan systems remain future work.

## Documentation

- `docs/architecture.md` — current runtime architecture and subsystem boundaries;
- `docs/authored_data.md` — Reader/normalized-data/Loader boundary and world-unit convention;
- `docs/bsp29.md` — current BSP29 binary Reader, normalization, records, and inspection tool;
- `docs/bsp_collision_migration.md` — v0.3.2 BSP collision migration history, current authority map, fixed-hull limitation, and incremental pathfinding roadmap;
- `docs/navigation_migration.md` — active migration from grid BFS to Quake-like local navigation with a future collision-certified route-graph fallback;
- `docs/collision.md` — current ground-space trace, sweep, movement, and obstruction model;
- `docs/raylib_3d.md` — raylib 3D frontend and first-person presentation path;
- `docs/3d_migration.md` — cumulative architectural change from the v0.2.3 2D baseline to the v0.3.2 line;
- `docs/future.md` — explicitly speculative future runtime, Ruby-version, performance, rendering, and navigation directions.

## Direction

The 0.3.2 runtime now includes the first BSP29 **Reader**. BSP29 binary structure is decoded outside `Level::Loader`, and geometry-related values are normalized to Aogera axes without scalar resizing.

The first downstream BSP integration now exists as a minimal world-model renderer. A controlled 44×14 test-field fixture compiled as BSP29 has matching structural counts between ericw-tools and `BSP29::Reader`, and its normalized player start resolves to `(112, 0, 112)` as expected.

The current BSP collision-query boundary consumes compiled clip hull 1 for all current actor static movement and the world-model node/leaf tree for melee/interaction obstruction. BSP-mode dynamic entity rendering no longer consults the Ruby grid for bounds. Active NPC chase now operates directly on continuous world-space goals and probes movement through `GroundSpace`; grid BFS is no longer part of the production chase path.

The stable v0.3.2a release remains the collision checkpoint. The 0.3.3 line is cleanup-focused and now includes the explicit navigation cutover: world-space `SteeringTarget`, collision-driven `GroundNavigation`, persistent local `GroundHeading`, and 30 Hz `GroundSteering`. The obsolete grid Pathfinder has been removed after the cutover was validated. See `docs/bsp_collision_migration.md` for the detailed migration record and roadmap.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
