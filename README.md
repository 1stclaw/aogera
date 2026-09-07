# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.3.0**

Aogera now has continuous first-person movement on the ground plane. The controlled character owns a runtime `GroundPosition(x, z)` in Aogera world space, while mouse yaw/pitch remains in `FirstPersonView`. raylib `Camera3D` is derived from those Aogera-owned values rather than acting as canonical gameplay state.

The player moves continuously at the 30 Hz simulation cadence. W/S move forward/back relative to the exact current yaw and A/D strafe; diagonal input is normalized. A small temporary ground-collision resolver keeps the player out of impassable terrain and cells occupied by blocking entities, with axis-separated resolution so movement can slide along walls.

NPC movement, pathfinding, melee adjacency and interaction still use the established integer grid. The player's old `Position(x, y)` is therefore retained as a synchronized coarse cell while `GroundPosition` is authoritative for player location and camera placement. This is an explicit migration bridge, not a generic transform or physics system.

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

GroundPosition + FirstPersonView
        -> Render::Raylib3D -> RaylibAPI -> raylib
```

The 3D coordinate convention is Y-up:

```text
world +X -> east/right
world +Y -> up
world +Z -> south / old grid +Y
```

The temporary grid bridge uses one world unit per authored cell. A grid cell `(x, y)` has center `(x + 0.5, z = y + 0.5)`.

Aogera still has no generic scene/projector/transform layer, no general physics system and no general asset manager. The current renderer directly extrudes the authored grid because it remains the smallest useful bridge to the coming BSP work.

## Direction

The next 0.3 work can now evaluate BSP29 against a real continuous player coordinate model. The current ground collision is deliberately small and disposable: BSP geometry/collision should replace it where appropriate rather than being forced through a generic physics interface designed in advance.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
