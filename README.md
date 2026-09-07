# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.2.2**

Aogera currently uses **raylib** for its graphical frontend.

The 0.2 series moved the project from Kitty/ASCII terminal rendering to a native window while keeping the existing gameplay model and authored content. Version 0.2.2 is a small structural preparation release before the move to true 3D: the current grid presentation is now explicitly named `Scene2D` / `Projector2D`, while simulation and level data remain unchanged.

Current features include:

- raylib window, rendering, and keyboard input
- grid-based 2D terrain and entities
- fixed-step simulation independent of rendering cadence
- prototypes and runtime entities
- movement and collision
- pathfinding and NPC behavior
- combat
- dialogue and mode transitions
- persistent session state

The current 2D renderer is intentionally transitional.

## Running

Install dependencies:

```bash
bundle install
```

Run Aogera:

```bash
bundle exec ruby bin/aogera
```

The raylib window is the active input target. If your window manager leaves focus on the launching terminal, click the Aogera window once.

## Testing

Aogera uses Minitest directly. Run the full test suite with:

```bash
bundle exec ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

This is the preferred project test command.

## Runtime structure

Aogera keeps simulation timing separate from rendering. The simulation runs at a fixed **30 Hz**, while the raylib frontend targets **60 FPS**.

```text
Host::Raylib -> Input -> Mode -> Simulation

Level + World::View -> Render::Projector2D -> Render::Scene2D -> Render::Raylib2D
```

The 2D presentation types are deliberately specific. They are not being generalized in advance for future 3D requirements, and raylib types do not enter gameplay or simulation state.

## Content

Authored Ruby content lives under `content/` and currently covers actor prototypes, levels, and dialogue. The 0.2 series did not introduce a new level or asset format.

## Direction

The next major technical direction is **true 3D with raylib**.

Aogera is intended to remain a compact, understandable engine rather than a general-purpose competitor. TrenchBroom and Quake 1 BSP are being considered as the first practical 3D level-authoring and compiled-map path. BSP support is not implemented yet.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
