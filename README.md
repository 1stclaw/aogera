# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.3.0**

Aogera now has continuous first-person movement on the ground plane. The controlled character owns a runtime `GroundPosition(x, z)` in Aogera world space, while mouse yaw/pitch remains in `FirstPersonView`. raylib `Camera3D` is derived from those Aogera-owned values rather than acting as canonical gameplay state.

The player moves continuously at the 30 Hz simulation cadence. W/S move forward/back relative to the exact current yaw and A/D strafe; diagonal input is normalized. `GroundBody(radius)` gives ground actors authored horizontal extent. `Simulation::GroundMovement` now consumes continuous swept-circle traces, accumulates contact normals for each movement command, and resolves sliding against the full active contact set instead of resolving X/Z independently or relying on anti-tunneling substeps.

`GroundSpace` provides shared X/Z spatial facts plus structured segment/sweep collision queries. Static terrain cells and dynamic ground bodies participate in one earliest-hit contract. Player melee and interaction retain authored reach/arc profiles, then use segment traces to reject targets obstructed by terrain or blocking actors. NPC movement, pathfinding and autonomous attack decisions remain on the established integer grid. The player's old `Position(x, y)` remains a synchronized coarse cell while `GroundPosition` is authoritative for player location and camera placement.

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

The next 0.3 work can now evaluate BSP29 against an established trace/sweep contract. The present static terrain-cell backend can later be replaced by BSP collision hulls while movement, melee and interaction continue consuming the same ground-space collision results.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
