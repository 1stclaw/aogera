# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.3.1**

Aogera 0.3.1 establishes one continuous runtime spatial model for the player, enemies, NPCs, and future interactive world entities.

```text
Component::Position(x, y, z)
```

All runtime actors use canonical world-space coordinates. Authored grid spawns are converted to world-space cell centers when a level is instantiated; the grid is no longer retained as a second runtime entity-position system.

Current ground actors can carry `GroundBody(radius)`. Player and NPC locomotion both use `Simulation::Commands::GroundMove` and the same continuous swept-circle collision solver. `GroundSpace` provides shared distance, arc, segment-trace, and swept-circle queries, returning structured `GroundTrace` results. Static terrain cells and active dynamic bodies participate in one earliest-hit contract.

Melee and interaction keep their own authored reach/arc profiles while using shared spatial and obstruction queries. NPC melee is validated through the same continuous separation/trace model as player melee. Defeated actors enter an explicit retired lifecycle state: they may retain runtime identity and descriptive state, but they no longer act or participate in ordinary active collision queries.

The remaining grid has two deliberately limited jobs:

- authored static terrain;
- temporary BFS navigation.

`Simulation::Pathfinder` derives navigation cells from continuous positions only while planning. Navigation cells are not entity state.

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

The 3D coordinate convention is Y-up:

```text
world +X -> east/right
world +Y -> up
world +Z -> south / authored grid +Y
```

One authored grid cell is currently one world unit. An authored cell `(x, y)` spawns an entity at `(x + 0.5, 0.0, y + 0.5)`.

Aogera still has no generic scene/projector/transform layer, no general physics system, and no general asset manager. The current renderer directly extrudes the authored grid. Ground collision is continuous in X/Z, while vertical actor collision, gravity, jumping, BSP, and projectile/hitscan systems remain future work.

## Documentation

- `docs/architecture.md` — current runtime architecture and subsystem boundaries;
- `docs/collision.md` — current ground-space trace, sweep, movement, and obstruction model;
- `docs/raylib_3d.md` — raylib 3D frontend and first-person presentation path;
- `docs/3d_migration.md` — cumulative architectural change from the v0.2.3 2D baseline to v0.3.1.

## Direction

The 0.3.1 runtime is normalized enough for the first BSP29 experiments: one canonical entity position model, one actor ground-movement path, one continuous collision-query contract, and one melee validation model.

BSP can therefore replace the current static grid geometry/collision backend without first migrating NPCs out of a second coordinate system. Navigation can evolve separately when a BSP-appropriate representation becomes necessary.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
