# Aogera

Aogera is an experimental Ruby game engine and runtime for a small fantasy action game.

It began as a branch of Sunbird and is now developed independently. The project is intentionally focused rather than general-purpose, with a design direction inspired by late-1990s and early-2000s PC games, especially the Heretic / Hexen lineage.

## Current status

**Version: 0.3.5 (development)**

Aogera 0.3.5 development starts from the 0.3.4 real-BSP milestone: BSP-native bootstrap, explicit diagnostic spectator launch, persistent world-model rendering, baked-lightmap preview, and inspection diagnostics remain the current runtime baseline. The ordinary Ruby-authored launch remains unchanged.

Aogera 0.3.5 now has seven incremental checkpoints: source/decoder boundary cleanup, the minimal binary-content VFS foundation, BSP CLI integration through Quake PAK files, source-neutral Quake palette decoding, a BSP surface-preparation boundary, indexed miptexture expansion, and the first dual-texture BSP renderer. `Content::VFS` mounts `Content::Directory` and `Content::Pak` sources behind normalized virtual paths, with later mounts taking precedence. `bin/aogera-bsp29 --pak FILE VIRTUAL_PATH` reads BSP bytes through that namespace and passes them to `BSP29::Reader.read_bytes`; direct host-filesystem BSP paths remain supported. During PAK-backed spectator launch the same VFS also supplies `gfx/palette.lmp`, which `Quake::PaletteReader` decodes before `App` construction. `Quake::MipTextureDecoder` expands only the mip levels actually uploaded, while `Render::BSP29TextureMapping` preserves Quake tiling through normalized but deliberately unwrapped base UVs. `Render::BSP29World` now keeps the original low-resolution baked-lightmap atlas as a separate GPU texture and multiplies it with the real embedded base miptextures in a minimal two-texture shader. Direct loose-BSP launch remains a grayscale lightmap fallback because it has no palette content source.

Every spatial runtime entity uses:

```text
Component::Position(x, y, z)
```

The coordinate convention is Y-up:

```text
world +X -> east/right
world +Y -> up
world +Z -> south / current grid +Y
```

Aogera world-unit magnitude is now compatible with Quake 1 map units. The temporary grid uses **32 world units per authored cell**. Existing movement speeds, body radii, melee/interaction reach, camera eye height, and primitive renderer dimensions were scaled proportionally, so the current test level keeps the same gameplay proportions while no longer using the old one-cell/one-unit scale.

### Authored-data path

Map/world authored data now has an explicit boundary:

```text
source file
    |
    v
Reader
    |
    | normalized Aogera coordinates / world units
    v
Level::AuthoredData
    |
    v
Level::Loader
    |
    v
Level / runtime
```

The current `Level::Readers::Ruby` understands the existing Ruby/grid source format and converts grid coordinates into Aogera world-space positions before `Level::Loader` sees them. `Level::Loader` accepts normalized authored data only; it does not parse source files.

The first external reader now exists as `BSP29::Reader`. It decodes Quake 1 BSP29 into normalized `BSP29::MapData`, preserving BSP-specific structure while converting vectors, bounds, plane normals, texture axes, model origins, and entity origins to Aogera axes at 1:1 world-unit magnitude.

The Reader has been validated end-to-end with controlled and real BSP29 maps. BSP mode renders world model `0` directly and bootstraps the player from the BSP entity lump; the matching Ruby `test_field` is no longer loaded by `bin/aogera-bsp29`. `Render::BSP29SurfaceBuilder` now reconstructs world-model faces once at map load into stable flat numeric buffers, preserving Quake texture-space S/T, local lightmap-space S/T, texture identity/flags, face identity, and compact baked-light metadata. `Render::BSP29World` consumes that prepared data, packs the first stored baked-light style into the same grayscale lightmap atlas as before, and uploads persistent raylib resources after the graphics context opens. The original low-resolution BSP lightmaps are neither rebaked nor upscaled; the lighting lump remains one shared binary blob referenced by face offset. When a decoded Quake palette is supplied, the renderer groups world surfaces by referenced BSP miptexture, expands only each used base texture for upload, keeps UV0 (base) and UV1 (lightmap) independent, and combines the base texture with the shared low-resolution baked-lightmap atlas in a GPU shader. Expanded RGBA buffers are transient upload data; the compact indexed BSP mipmaps remain authoritative. Without a palette, the established grayscale lightmap path remains available. The spectator also draws a compact diagnostic overlay with measured FPS, camera position/orientation, BSP triangle count, persistent mesh-draw count, lightmapped-face/atlas statistics, and runtime entity count. The Ruby level path remains the normal non-BSP fallback.

### Runtime movement and collision

Player and NPC locomotion both use `Simulation::Commands::GroundMove` and the same continuous swept-circle collision solver. `GroundSpace` provides shared distance, arc, segment-trace, and swept-circle queries, returning structured `GroundTrace` results. The active static-world backend and dynamic bodies participate in one earliest-hit contract. The normal Ruby launch uses grid terrain; the BSP preview uses compiled hull/node data.

Melee and interaction keep their own authored reach/arc profiles while using shared spatial and obstruction queries. Defeated actors enter an explicit retired lifecycle state: they may retain runtime identity and descriptive state, but they no longer act or participate in ordinary active collision queries.

The remaining grid has deliberately limited jobs:

- an inert one-cell `Level` terrain scaffold required by the current `Simulation` container in BSP mode;
- the normal non-BSP Ruby rendering/collision fallback.

The BSP scaffold is not consulted by BSP rendering or static collision and carries no test-field spawns, relations, or dialogue.

Active chase no longer uses grid cells. `RealtimeController` now stores only a high-level world-space `Component::SteeringTarget`; for entity pursuit that target carries `goal_entity_id`, allowing `Simulation::GroundSteering` to resolve the goal entity's live position on every fixed 30 Hz simulation tick. `Simulation::GroundNavigation` then probes the actor's actual continuous `Position`/`GroundBody` through `GroundSpace` and returns `direct`, `local_avoidance`, `route_needed`, or `arrived` together with a normalized `GroundHeading`. `GroundSteering` converts that heading into the ordinary `GroundMove` command used by the existing sweep-and-slide collision path.

The obsolete grid `Simulation::Pathfinder` implementation has been removed from the active source tree after the local-navigation cutover was manually validated. Historical details remain in the migration documents. If local navigation proves insufficient, `route_needed` is the seam for a future GoldSrc-like world-space route graph whose links are certified by the real collision system.

## Running

Aogera 0.3.5 requires **Ruby 3.4+**. The repository currently pins Ruby 3.4.10 for development through `.ruby-version`.

```bash
bundle install
bundle exec ruby bin/aogera
```

The raylib window captures the mouse for first-person look. `Q` or `Esc` exits and the host releases the cursor during shutdown.

For a useful direct-file rendering test, launch the diagnostic spectator against an external lightmapped Quake BSP rather than the unlit controlled fixture:

```bash
bundle exec ruby bin/aogera-bsp29 --spectator ../quake1-bsp/e1m3.bsp
```

The small controlled `bsp29-test-field` fixture remains useful for automated structure/collision tests, but it is not the preferred visual-lightmap target.

A BSP can also be read directly from a Quake PAK without extraction. With `--pak`, the final BSP argument is a virtual path inside the archive:

```bash
bundle exec ruby bin/aogera-bsp29 \
  --spectator \
  --pak ../quake1-shareware/id1/pak0.pak \
  maps/e1m3.bsp
```

`bin/aogera-bsp29` has a deliberately small development CLI. No runtime launch mode is implicit: a bare BSP argument is a usage error until a playable BSP mode exists. Without `--pak` the BSP argument is a host-filesystem path; with `--pak FILE` it is a normalized VFS path inside that PAK.

Structural and entity inspection can be performed without opening raylib in either source mode:

```bash
bundle exec ruby bin/aogera-bsp29 ../quake1-bsp/e1m3.bsp --bsp-info
bundle exec ruby bin/aogera-bsp29 --pak ../quake1-shareware/id1/pak0.pak maps/e1m3.bsp --bsp-info
bundle exec ruby bin/aogera-bsp29 --pak ../quake1-shareware/id1/pak0.pak maps/e1m3.bsp --dump-entities
bundle exec ruby bin/aogera-bsp29 --pak ../quake1-shareware/id1/pak0.pak maps/e1m3.bsp --dump-textures
bundle exec ruby bin/aogera-bsp29 --help
```

`--bsp-info` prints BSP counts, world bounds, visibility/light byte counts, and normalized player starts. `--dump-entities` prints the original entity key/value declarations and, where available, the Reader's normalized Aogera-space origin. `--dump-textures` reports world-model texture names, dimensions, face-reference counts, missing texture slots, and embedded textures not currently used by world model `0`. Only one exit-style inspection command may be selected per invocation. `--spectator` is currently the only runtime launch mode and must be explicit. `--pak` changes only source resolution: PAK/VFS code returns bytes, while `BSP29::Reader.read_bytes` remains the format decoder. The older `bin/aogera-bsp29-info` executable remains as a compatibility wrapper around `--bsp-info`. This is a launch/inspection CLI, not an interactive developer console or a game-command system.

BSP mode reads the first `info_player_start` from the map entity lump, uses its normalized origin as the initial Aogera player position, and converts its Quake `angle` to the initial first-person yaw. It no longer imports the Ruby `test_field`, its NPCs, relations, or dialogue. The preview now starts in `Mode::Spectator`: the camera begins at the spawned player's eye position but then flies independently without changing the player entity or consulting collision. A top-left diagnostic panel reports actual raylib FPS, camera XYZ, yaw/pitch, BSP triangle and mesh-draw counts, lightmapped-face/atlas statistics, and runtime entity count; the bottom bar remains the spectator controls/tick readout. BSP world-model faces provide static rendering; the compiled collision backends remain configured in the dormant runtime for later actor testing. The current one-cell `Level` terrain in BSP mode is only structural scaffolding for `Simulation`.

## Controls

Normal Ruby-authored launch:

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

BSP diagnostic spectator:

```text
Mouse        look
W / Up       fly forward
S / Down     fly backward
A / Left     strafe left
D / Right    strafe right
Space        fly up
Shift / C    fly down
Q / Esc      quit
```

## Testing

Aogera uses Minitest directly. Run the complete suite with:

```bash
bundle exec ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

This is the preferred project test command. The stable v0.3.4 release baseline is **306 runs / 1106 assertions / 0 failures / 0 errors / 0 skips**. The v0.3.5 source-boundary preparation checkpoint was **308 runs / 1116 assertions / 0 failures / 0 errors / 0 skips**; the VFS-foundation checkpoint was **320 runs / 1165 assertions / 0 failures / 0 errors / 0 skips**; and the PAK/BSP CLI integration checkpoint was **327 runs / 1198 assertions / 0 failures / 0 errors / 0 skips**. The palette-decoder checkpoint was **332 runs / 1218 assertions / 0 failures / 0 errors / 0 skips**; the BSP surface-preparation checkpoint was **336 runs / 1246 assertions / 0 failures / 0 errors / 0 skips**. The miptexture-decoding checkpoint was **343 runs / 1274 assertions / 0 failures / 0 errors / 0 skips**. The current dual-texture renderer checkpoint is **350 runs / 1382 assertions / 0 failures / 0 errors / 0 skips**.

## Runtime structure

Simulation timing is independent from rendering. The simulation runs at a fixed **30 Hz**, while the raylib frontend targets **60 FPS**.

```text
keyboard -> Host::Raylib -> Input::Action -> fixed-step gameplay
mouse    -> Host::Raylib -> Input::LookDelta -> FirstPersonView

Position + FirstPersonView
        -> Render::Raylib3D -> RaylibAPI -> raylib
```

Aogera still has no generic scene/projector/transform layer, no general physics system, and no general asset manager. The normal path directly extrudes the authored grid; the BSP29 preview reconstructs and triangulates world-model faces without routing them through a generic scene representation. Collision remains deliberately hybrid during the migration: actor static movement uses BSP29 compiled hull 1 through one shared `GroundClearance` backend, melee/interaction obstruction uses the BSP node/leaf point hull, active local navigation probes that same `GroundSpace`, and dynamic actor collision remains continuous `GroundBody` collision. Vertical actor collision, gravity, jumping, and projectile/hitscan systems remain future work.

## Documentation

- `docs/architecture.md` — current runtime architecture and subsystem boundaries;
- `docs/authored_data.md` — Reader/normalized-data/Loader boundary and world-unit convention;
- `docs/content_vfs.md` — binary-content VFS path rules, source contract, mount precedence, PAK behavior, and errors;
- `docs/bsp29.md` — current BSP29 binary Reader, normalization, records, and inspection tool;
- `docs/bsp_collision_migration.md` — BSP collision migration history, authority decisions, fixed-hull limitation, and later cutover notes;
- `docs/navigation_migration.md` — migration record for the completed grid-BFS to continuous local-navigation cutover and its future route-graph seam;
- `docs/collision.md` — current ground-space trace, sweep, movement, and obstruction model;
- `docs/raylib_3d.md` — raylib 3D frontend and first-person presentation path;
- `docs/3d_migration.md` — frozen historical record of the v0.2.3 -> v0.3.2 migration and early v0.3.3 follow-on;
- `docs/future.md` — explicitly speculative future runtime, Ruby-version, performance, rendering, and navigation directions.

## Direction

Aogera 0.3.4 established the first self-contained BSP launch path: BSP29 supplies the player start, world model `0` supplies visible static geometry, compiled hull/node data supplies the configured collision services, and `Mode::Spectator` provides safe free-flight inspection while vertical actor physics remains deferred. The Ruby `test_field` is no longer part of BSP launch.

The rendering checkpoint now preserves Quake's two static appearance signals separately: BSP faces are persistent GPU geometry with repeating base-texture UVs plus independent baked-lightmap UVs; PAK-backed spectator launch renders embedded BSP miptextures through the Quake palette and multiplies them with the original low-resolution lightmap atlas on the GPU. Direct loose-BSP launch remains the grayscale lightmap fallback. Collision remains hybrid and explicit: compiled hull 1 is authoritative for current actor static movement, the point hull handles obstruction traces, continuous `GroundBody` handles dynamic actors, and local NPC navigation probes the same `GroundSpace`.

Aogera 0.3.5 develops the content/rendering milestone incrementally. The preparation checkpoint separated repository-local Ruby source paths from binary content, the VFS checkpoint added directory and Quake PAK sources, the PAK/BSP checkpoint routed BSP launch/inspection through `Content::VFS`, and the palette checkpoint added `Quake::PaletteReader` for the canonical 256-color `gfx/palette.lmp` bytes without coupling that decoder to storage or rendering. The surface checkpoint moved BSP face interpretation out of GPU-resource ownership: `BSP29SurfaceBuilder` prepares stable face-level buffers once, keeps base-texture and lightmap coordinate domains separate, and references one compact lighting blob by offset instead of materializing per-face light sample strings. The miptexture checkpoint added on-demand palette expansion of one requested BSP mip level into a packed RGBA buffer plus a base-UV mapping helper that preserves Quake tiling by leaving normalized coordinates unwrapped. The current dual-texture checkpoint uses that boundary: PAK spectator launch reads the palette from the same VFS, base textures are uploaded per used BSP texture, the one compact lightmap atlas is uploaded once, and a minimal shader samples UV0/UV1 separately and multiplies the two textures. The compact indexed mip chain and original BSP lighting lump remain authoritative; expanded base pixels are transient upload inputs. Direct BSP file loading remains available as the grayscale fallback. Animated textures, sky/turbulent rendering, Quake fullbright semantics, multi-style lightmap animation, WAD2, Quake UI, ZIP support, generic asset management, and broader package features remain out of scope. WAD2, Quake UI, ZIP support, generic asset management, and broader package features remain out of scope.

Aogera favors small explicit systems, authored game worlds, mature external tools where useful, and incremental evolution instead of designing future subsystems too early.
