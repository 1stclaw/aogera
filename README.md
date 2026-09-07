# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.3.1**

Aogera now has its first playable first-person 3D control loop. raylib supplies the native window, mouse capture and drawing, while Aogera owns logical yaw/pitch in `FirstPersonView` and derives the raylib `Camera3D` from the controlled player's runtime position.

The underlying gameplay world is still deliberately grid-based. W/S move forward/back relative to the current view; A/D strafe; those controls are reduced to the existing integer grid movement commands at simulation ticks. Mouse look updates at frontend/render cadence rather than being quantized to the 30 Hz simulation rate.

Combat, interaction, NPC pathfinding and collision otherwise continue to use the established gameplay systems. Continuous 3D player position, 3D collision and BSP are later 0.3 work.

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

Level + World::View + FirstPersonView
        -> Render::Raylib3D -> RaylibAPI -> raylib
```

The 3D coordinate convention is Y-up:

```text
grid x -> world +X
grid y -> world +Z
world +Y -> up
```

Aogera still has no generic scene/projector/transform layer and no general asset manager. The current renderer directly extrudes the authored grid because that remains the smallest useful bridge to the coming BSP work.

## Direction

The next 0.3 work should replace the temporary grid bridge incrementally: continuous first-person position/collision is the next obvious pressure point, followed by the planned Quake 1 BSP29 experiment once the basic movement model is trustworthy.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
