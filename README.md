# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.2.1**

Aogera currently uses **raylib** for its graphical frontend.

The 0.2 series moved the project from Kitty/ASCII terminal rendering to a native window while keeping the existing gameplay model and authored content. Version 0.2.1 is a cleanup release built on 0.2.0: the old terminal frontend and related compatibility code have been removed, and the raylib path is now the only active frontend.

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

The current 2D renderer is intentionally simple and serves as a stepping stone toward true 3D.

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

Aogera uses Minitest directly.

Run the full test suite with:

```bash
bundle exec ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

This is the preferred project test command.

## Runtime structure

Aogera keeps simulation timing separate from rendering.

```text
raylib frame
    |
    +-- poll input
    +-- FixedStep -> zero or more simulation ticks
    +-- project world state
    +-- draw Render::Scene
```

The simulation runs at a fixed **30 Hz**, while the raylib frontend targets **60 FPS**.

Input and rendering stay behind narrow boundaries:

```text
Host::Raylib -> Input -> Mode -> Simulation

Level + World::View -> Render::Projector -> Render::Scene -> Render::Raylib2D
```

The 2D scene model is kept deliberately specific to the current renderer rather than generalized in advance for future 3D requirements.

## Content

Authored Ruby content lives under `content/` and currently covers actor prototypes, levels, and dialogue.

The 0.2 series did not introduce a new level or asset format.

## Project layout

Core runtime code lives under `lib/aogera/`.

```text
lib/aogera/
├── app.rb
├── fixed_step.rb
├── realtime.rb
├── session.rb
├── simulation.rb
├── world.rb
├── host/
├── input/
├── level/
├── mode/
├── prototype/
├── render/
└── simulation/
```

`RaylibAPI` provides a small boundary around `raylib-bindings` so raylib/FFI details do not spread through the engine.

## Direction

The next major technical direction is **true 3D with raylib**.

Aogera is not intended to compete with large general-purpose engines. The goal is a compact, understandable engine that can combine classic level-design ideas with modern rendering where useful.

TrenchBroom and Quake 1 BSP are being considered as the first practical 3D level-authoring and compiled-map path. BSP support is not implemented yet.

Future work may include 3D rendering, BSP loading, richer assets and materials, and eventually a native Aogera level format if the project outgrows the imported formats.
