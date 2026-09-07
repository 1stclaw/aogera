# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.3.0**

Aogera is now a true first-person 3D runtime with one canonical continuous entity position model:

```text
Component::Position(x, y, z)
```

All runtime actors—including the player, enemies and NPCs—use this world-space position. Authored grid spawns are converted to world-space cell centers when a level is instantiated; there is no separate runtime grid-position component and no player/NPC position synchronization bridge.

`GroundBody(radius)` gives current ground actors authored horizontal extent. `Simulation::GroundMovement` consumes continuous swept-circle traces, accumulates contact normals for each movement command, and resolves sliding against the full active contact set. Player and NPC locomotion both use `Simulation::Commands::GroundMove` and the same collision solver.

`GroundSpace` provides shared X/Z spatial facts plus structured segment/sweep collision queries. Static terrain cells and dynamic ground bodies participate in one earliest-hit contract. Melee and interaction keep authored reach/arc profiles and use segment traces to reject obstructed targets. NPC melee is also validated through the same continuous separation/trace rules as player melee.

The existing grid now has two deliberately limited jobs: authored static terrain and temporary BFS navigation. `Simulation::Pathfinder` projects continuous positions to navigation cells with `floor(x), floor(z)` when planning a route, but those cells are not stored as entity state.

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

Aogera still has no generic scene/projector/transform layer, no general physics system and no general asset manager. The current renderer directly extrudes the authored grid, and the current Pathfinder still uses that grid as a temporary navigation graph.

## Direction

The next BSP work can now start from a normalized runtime: one continuous entity position model, one actor ground-movement path and one continuous melee/collision model. BSP can replace the static terrain collision backend without also having to migrate NPCs out of a second runtime coordinate system.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
