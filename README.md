# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.3.0**

Aogera now has a true 3D raylib presentation path. The first 0.3 milestone deliberately keeps the existing grid gameplay model unchanged while rendering the authored level as simple 3D floor/wall geometry and runtime entities as 3D primitives.

The simulation remains fixed-step and independent from rendering. Current gameplay still uses the established grid movement, pathfinding, combat and interaction rules; continuous first-person movement, mouse look, 3D collision and BSP are later 0.3 work.

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

Level + World::View -> Render::Raylib3D -> RaylibAPI -> raylib
```

`World::View` is a persistent read-only view of canonical runtime state. `Render::Raylib3D` currently performs the temporary grid-to-3D bridge directly; no generic scene/projector abstraction has been introduced.

The initial 3D coordinate convention is raylib-style **Y-up**:

```text
grid x -> world +X
grid y -> world +Z
world +Y -> up
```

Authored Ruby content lives under `content/` and is resolved through `Content::Paths`. Aogera still has no general asset manager because this first 3D milestone uses only raylib primitives.

## Direction

The next 0.3 work is first-person control: continuous player/view position, orientation and mouse input should be introduced from actual gameplay requirements rather than by generalizing the old grid components.

Quake 1 BSP remains the planned first serious compiled 3D map experiment after the basic 3D camera/control loop is established. BSP support is not implemented yet.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
