# Aogera 0.2.0: raylib 2D frontend

Aogera 0.2.0 moves the primary application frontend from Kitty terminal rendering to raylib while deliberately leaving the game model and authored content unchanged.

## Scope

The 0.2.0 path remains:

```text
Level + World::View
        |
        v
Render::Projector
        |
        v
Render::Scene
        |
        v
Render::Raylib2D
```

The simulation remains fixed-step at the existing Aogera tick rate. The raylib window is frame-driven: each rendered frame polls physical input, runs zero or more due simulation ticks, then draws the current scene. Rendering frequency therefore no longer defines simulation frequency.

The existing input mapper, handoff, tracker, modes, simulation, world, level loader, pathfinding, combat, dialogue and authored Ruby content remain the gameplay path.

## Rendering

`Render::Raylib2D` intentionally uses simple raylib primitives for this first transition. Logical map cells are rendered as a fixed-size grid and existing render keys/glyph information identify tiles and entities. No new sprite or level authoring format is introduced in 0.2.0.

The terminal/Kitty renderer remains in the source tree for reference during the transition, but `App` now launches the raylib frontend.

## Input

`Host::Raylib` converts raylib key press/release state into Aogera physical key events. Aogera's existing tracker continues to own held-state semantics and gameplay action repetition.

Raylib's default Escape-to-close behavior is disabled so Escape remains an Aogera input rather than bypassing the mode/input system. Closing the OS window still exits immediately.

## Deliberately deferred

0.2.0 does not introduce BSP, Quake/Valve map formats, 3D cameras, Lua, shaders, lighting, audio, a VFS, custom level serialization, or a generalized 2D/3D renderer abstraction. Those should be designed after the raylib platform boundary has proved itself.
