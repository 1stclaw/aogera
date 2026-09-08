# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.3.2 RC**

Aogera 0.3.2 is at release-candidate status. It keeps the unified continuous runtime introduced in 0.3.1, standardizes Quake-compatible world-unit magnitude, introduces the Reader/Loader authored-data boundary, and adds the first validated BSP29 path.

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

The Reader has been validated end-to-end with an Aogera-controlled BSP29 fixture compiled by ericw-tools from the original `test_field` layout. The current RC can render BSP world model `0` directly as a static-world preview while gameplay still uses the matching Ruby/grid level.

### Runtime movement and collision

Player and NPC locomotion both use `Simulation::Commands::GroundMove` and the same continuous swept-circle collision solver. `GroundSpace` provides shared distance, arc, segment-trace, and swept-circle queries, returning structured `GroundTrace` results. Static terrain cells and active dynamic bodies participate in one earliest-hit contract.

Melee and interaction keep their own authored reach/arc profiles while using shared spatial and obstruction queries. Defeated actors enter an explicit retired lifecycle state: they may retain runtime identity and descriptive state, but they no longer act or participate in ordinary active collision queries.

The remaining grid has two deliberately limited jobs:

- current authored static terrain;
- temporary BFS navigation.

Navigation cells are derived from world-space positions and are not runtime entity state.

## Running

```bash
bundle install
bundle exec ruby bin/aogera
```

The raylib window captures the mouse for first-person look. `Q` or `Esc` exits and the host releases the cursor during shutdown.

For the controlled BSP29 test-field preview:

```bash
bundle exec ruby bin/aogera-bsp29 /path/to/test_field.bsp
```

That preview uses BSP29 world-model faces for static rendering and the matching Ruby `test_field` for current gameplay, collision, interaction, and navigation. This is an intentional RC bridge so BSP presentation can be validated before BSP collision replaces the grid backend.

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

This is the preferred project test command. The v0.3.2 RC documentation snapshot corresponds to the playable BSP preview baseline of **173 runs / 523 assertions / 0 failures / 0 errors / 0 skips**.

## Runtime structure

Simulation timing is independent from rendering. The simulation runs at a fixed **30 Hz**, while the raylib frontend targets **60 FPS**.

```text
keyboard -> Host::Raylib -> Input::Action -> fixed-step gameplay
mouse    -> Host::Raylib -> Input::LookDelta -> FirstPersonView

Position + FirstPersonView
        -> Render::Raylib3D -> RaylibAPI -> raylib
```

Aogera still has no generic scene/projector/transform layer, no general physics system, and no general asset manager. The normal path directly extrudes the authored grid; the BSP29 preview reconstructs and triangulates world-model faces without routing them through a generic scene representation. Ground collision is continuous in X/Z and remains grid-backed in the BSP preview. BSP hull collision, vertical actor collision, gravity, jumping, and projectile/hitscan systems remain future work.

## Documentation

- `docs/architecture.md` — current runtime architecture and subsystem boundaries;
- `docs/authored_data.md` — Reader/normalized-data/Loader boundary and world-unit convention;
- `docs/bsp29.md` — current BSP29 binary Reader, normalization, records, and inspection tool;
- `docs/collision.md` — current ground-space trace, sweep, movement, and obstruction model;
- `docs/raylib_3d.md` — raylib 3D frontend and first-person presentation path;
- `docs/3d_migration.md` — cumulative architectural change from the v0.2.3 2D baseline to v0.3.2.

## Direction

The 0.3.2 runtime now includes the first BSP29 **Reader**. BSP29 binary structure is decoded outside `Level::Loader`, and geometry-related values are normalized to Aogera axes without scalar resizing.

The first downstream BSP integration now exists as a minimal world-model renderer. A controlled 44×14 test-field fixture compiled as BSP29 has matching structural counts between ericw-tools and `BSP29::Reader`, and its normalized player start resolves to `(112, 0, 112)` as expected.

The next BSP milestone is the collision-query boundary: consume model headnodes, planes, and clipnodes so the BSP static world, rather than the matching grid fixture, becomes authoritative for movement and obstruction.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
