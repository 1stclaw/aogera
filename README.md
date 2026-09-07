# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.2.3**

Aogera uses **raylib** for its graphical frontend. The 0.2 series established a native windowed 2D baseline while keeping simulation and authored content independent from rendering. Version 0.2.3 is the final cleanup/polish release planned before true 3D work begins.

Current features include fixed-step simulation, prototypes and runtime entities, movement/collision, pathfinding and NPC behavior, combat, dialogue/modes, and persistent session state.

The current 2D renderer is intentionally transitional.

## Running

```bash
bundle install
bundle exec ruby bin/aogera
```

The raylib window is the active input target. If your window manager leaves focus on the launching terminal, click the Aogera window once.

## Testing

Aogera uses Minitest directly. Run the complete suite with:

```bash
bundle exec ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

This is the preferred project test command.

## Runtime structure

Simulation timing is independent from rendering. The simulation runs at a fixed **30 Hz**, while the raylib frontend targets **60 FPS**.

```text
Host::Raylib -> Input -> Mode -> Simulation

Level + World::View -> Render::Projector2D -> Render::Scene2D -> Render::Raylib2D
```

`World::View` is a persistent read-only view of canonical runtime state. Render projection remains downstream of the simulation, and raylib types do not enter gameplay state.

Authored Ruby content lives under `content/` and is resolved through `Content::Paths`. Aogera does not yet have a general asset manager; that will be designed from concrete 3D requirements rather than from the temporary 2D frontend.

## Direction

The next major technical direction is **true 3D with raylib**. TrenchBroom and Quake 1 BSP are being considered as the first practical 3D level-authoring and compiled-map path. BSP support is not implemented yet.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
