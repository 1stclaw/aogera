# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.3.2**

Aogera 0.3.2 keeps the unified continuous runtime introduced in 0.3.1 and standardizes the authored-data boundary before BSP29 integration.

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

This boundary is intended for future readers such as BSP29 without turning the loader into a format parser. A BSP29 reader can preserve BSP-specific structural data while guaranteeing that values crossing the reader boundary already use Aogera axes and world-unit magnitude.

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

This is the preferred project test command.

## Runtime structure

Simulation timing is independent from rendering. The simulation runs at a fixed **30 Hz**, while the raylib frontend targets **60 FPS**.

```text
keyboard -> Host::Raylib -> Input::Action -> fixed-step gameplay
mouse    -> Host::Raylib -> Input::LookDelta -> FirstPersonView

Position + FirstPersonView
        -> Render::Raylib3D -> RaylibAPI -> raylib
```

Aogera still has no generic scene/projector/transform layer, no general physics system, and no general asset manager. The current renderer directly extrudes the authored grid. Ground collision is continuous in X/Z, while vertical actor collision, gravity, jumping, BSP, and projectile/hitscan systems remain future work.

## Documentation

- `docs/architecture.md` — current runtime architecture and subsystem boundaries;
- `docs/authored_data.md` — Reader/normalized-data/Loader boundary and world-unit convention;
- `docs/collision.md` — current ground-space trace, sweep, movement, and obstruction model;
- `docs/raylib_3d.md` — raylib 3D frontend and first-person presentation path;
- `docs/3d_migration.md` — cumulative architectural change from the v0.2.3 2D baseline to v0.3.2.

## Direction

The 0.3.2 runtime is prepared for the first BSP29 reader: one canonical entity position model, one actor ground-movement path, one continuous collision-query contract, one normalized authored-data boundary, and Quake-compatible world-unit magnitude.

BSP29 can therefore be introduced as a new **Reader**, with format/axis normalization kept outside `Level::Loader`. Static BSP rendering and collision can then replace the current grid backends incrementally without another entity-space or unit migration.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
