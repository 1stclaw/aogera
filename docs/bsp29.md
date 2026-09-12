# BSP29 Reader and Static Preview

Aogera's first Quake map integration begins with a **format Reader** and now includes a static-world preview plus operational BSP collision queries. The stable v0.3.2a release separated parsing, rendering, gameplay collision, and temporary grid navigation; the stable v0.3.3 release moved active chase onto continuous local navigation while preserving the same BSP collision boundary.

The current path is:

```text
.bsp file
   |
   v
BSP29::Reader
   |
   | normalized Aogera axes and world-unit magnitude
   v
BSP29::MapData
   |
   +--> Render::BSP29SurfaceBuilder -> Render::BSP29World (world model 0 preview)
   +--> BSP29::GroundClearance (compiled hull 1, actor movement/local probes)
   |       |
   |       +--> BSP29::GroundHull (radius-bound fixed-hull adapter)
   +--> BSP29::PointHull (headnode 0, obstruction traces)
   +--> future map-entity importer
```

`BSP29::Reader` understands Quake 1 BSP version 29 binary structure. It does not construct an Aogera `Level`, spawn gameplay actors, call raylib, or perform collision queries.

`Reader.read(path)` is the filesystem convenience entry point; `Reader.read_bytes(bytes)` is the source-neutral parsing boundary. File-access failures from `read(path)` remain source errors rather than being relabeled as BSP format errors. Future package/content sources can supply BSP bytes through `read_bytes` without making the BSP Reader aware of PAK, ZIP, or mounting rules.

## Normalization boundary

Aogera uses Quake 1-compatible world-unit magnitude:

```text
1 Quake map unit = 1 Aogera world unit
```

Quake is Z-up. Aogera is Y-up. Values leaving the BSP29 Reader are converted through:

```text
Quake  (x, y, z)
   ->
Aogera (x, z, -y)
```

The transform is applied to:

- vertices;
- plane normals;
- texture projection axes;
- node/leaf/model bounds;
- model origins;
- parsed entity `origin` values.

Plane distance and scalar map measurements are unchanged.

The Reader therefore exposes **Aogera-space BSP data**, not a second Quake-space coordinate model inside the runtime.

## Parsed data

`BSP29::MapData` currently preserves all 15 BSP29 lump categories:

```text
entities
planes
textures
vertices
visibility
nodes
texinfo
faces
lighting
clipnodes
leaves
marksurfaces
edges
surfedges
models
```

Fixed-size records are decoded into immutable data records. Visibility and baked-lighting lumps remain immutable binary blobs until their consumers exist.

Embedded Quake miptextures are decoded into:

```text
MipTexture
├── name
├── width
├── height
└── four indexed-color mip levels
```

The BSP Reader still performs no palette or raylib texture conversion. A separate source-neutral `Quake::PaletteReader` decodes Quake's 768-byte `gfx/palette.lmp` into 256 RGB entries while retaining the original packed RGB lookup table. `Quake::MipTextureDecoder` can now combine one already-parsed BSP mip level with that palette into one packed RGBA buffer on demand. The original indexed mipmaps remain the authoritative BSP data; the decoder does not eagerly expand the whole mip chain or create per-pixel Ruby records. Palette-specific rendering semantics such as fullbright treatment are deliberately not collapsed into the decoded map representation: the indexed source bytes remain available so a later shader/upload step can derive those effects without reconstructing or reparsing texture data.

Brush model `0` remains the static world model. Additional BSP submodels remain separate in `MapData#models`; the Reader does not flatten doors/platforms/moving brush candidates into world geometry.

Clipnodes and model headnodes are preserved as first-class collision data. The current preview uses `BSP29::GroundClearance` over compiled hull 1 for player/NPC static movement and for the positive-radius probes issued by continuous local navigation through `GroundSpace`. The obsolete grid Pathfinder has been removed after the local-navigation cutover.

## Entity lump

The Quake entity-text lump is parsed into immutable key/value dictionaries.

Each record exposes:

```text
Entity#properties
Entity#classname
Entity#origin
```

`origin`, when present, is converted to Aogera coordinates. Other entity properties remain source declarations until a later Aogera map-entity importer assigns gameplay meaning.

The Reader therefore does **not** automatically spawn Quake monsters, items, doors, or triggers.

## Validation

The Reader currently validates:

- minimum header size;
- exact BSP version `29`;
- non-negative lump offsets and lengths;
- lump ranges against the source file;
- fixed-record lump alignment;
- miptexture directory/header/mip ranges;
- basic entity-text structure and numeric origins.

Cross-reference validation between faces, surfedges, nodes, models, and other records can be strengthened once real external maps become integration fixtures.

## Existing-map inspection and launch CLI

`bin/aogera-bsp29` provides the small command-line surface used during real-map bring-up. Runtime launch modes are explicit. Collision-free inspection uses:

```bash
bundle exec ruby bin/aogera-bsp29 --spectator /path/to/map.bsp
```

The first player-bound collision-aware mode uses:

```bash
bundle exec ruby bin/aogera-bsp29 --walkthrough /path/to/map.bsp
```

Walkthrough is currently horizontal-only at the bootstrap height. It exercises the existing fixed-step hull-1 movement path but does not yet implement gravity, floor following, steps, jumping, or other vertical actor physics.

The BSP can alternatively be addressed as a virtual path inside a Quake PAK:

```bash
bundle exec ruby bin/aogera-bsp29 \
  --walkthrough \
  --pak /path/to/id1/pak0.pak \
  maps/e1m3.bsp
```

Use `--spectator` instead of `--walkthrough` for collision-free flight through the same PAK-backed map.

The two-sided diagnostic confirmed the earlier world-face winding bug. Normal preparation now reverses each complete Quake surfedge polygon once for raylib, rather than guessing orientation from the first three vertices. `--bsp-two-sided` is retained as a map-authoring/compatibility diagnostic and duplicates each prepared world-model triangle with reversed winding before GPU upload:

```bash
bundle exec ruby bin/aogera-bsp29 \
  --walkthrough \
  --bsp-two-sided \
  --pak /path/to/id1/pak0.pak \
  maps/e1m3.bsp
```

This is an A/B compatibility diagnostic, not the default two-sided rendering policy. It remains useful for custom-authored BSP29 maps and alternate QBSP toolchains such as ericw-tools. The normal path should render ordinary model-0 walls/floors with only the single corrected winding. If a surface still appears only in two-sided mode, investigate its winding/conversion; if it is absent in both, inspect face-preparation/drop counters and the separate skipped-brush-submodel diagnostics.

Without `--pak`, the BSP argument is a host-filesystem path and uses `Reader.read`. With `--pak FILE`, the CLI mounts that archive in a fresh `Content::VFS`, reads the virtual BSP path, and sends the resulting bytes to `Reader.read_bytes`. The BSP Reader therefore remains unaware of PAK structure and mounting rules. A bare BSP argument remains intentionally invalid: runtime mode selection is explicit, and `--spectator` conflicts with `--walkthrough`.

The same executable can inspect a map without opening raylib:

```bash
bundle exec ruby bin/aogera-bsp29 /path/to/map.bsp --bsp-info
bundle exec ruby bin/aogera-bsp29 --pak /path/to/id1/pak0.pak maps/e1m3.bsp --bsp-info
bundle exec ruby bin/aogera-bsp29 --pak /path/to/id1/pak0.pak maps/e1m3.bsp --dump-entities
bundle exec ruby bin/aogera-bsp29 --pak /path/to/id1/pak0.pak maps/e1m3.bsp --dump-textures
```

`--bsp-info` prints structural counts, world-model bounds, visibility/light byte counts, and normalized `info_player_start` origins. `--dump-entities` prints the parsed source key/value declarations for every entity and also shows the normalized Aogera-space origin when the Reader parsed one. `--dump-textures` follows world-model faces through `TexInfo` to the BSP miptexture table and reports texture names, dimensions, face counts, missing referenced slots, and embedded-but-currently-unused textures. Miptexture names use Quake's 16-byte NUL-terminated convention; bytes after the first NUL are padding and are not part of the logical name. This is intended to inventory replacement/debug materials without guessing from map themes. `--help` documents the available options. Exit-style inspection commands are mutually exclusive.

The older helper remains valid:

```bash
bundle exec ruby bin/aogera-bsp29-info /path/to/map.bsp
```

It is now only a compatibility wrapper around the primary CLI's `--bsp-info` action. This command line is intentionally limited to process launch and inspection; it is not a Quake-style in-game console, cvar system, or gameplay command registry.

This is intended as the first structural compatibility surface for real Quake/TrenchBroom maps.


## Controlled fixture validation

The v0.3.2a release is validated against a generated BSP29 fixture derived from Aogera's original 44×14 `test_field` and compiled with ericw-tools `qbsp`. The compiler and `BSP29::Reader` agree on the structural counts:

```text
models          1
planes        136
vertices      392
nodes         335
texinfo        10
faces         339
clipnodes    5262
leaves        100
marksurfaces  370
edges          730
surfedges     1458
textures         5
entities         6
```

The normalized world-model bounds are approximately:

```text
(1.0, -1.56, 1.0) -> (1407.0, 31.0, 447.0)
```

and `info_player_start` resolves to the expected Aogera position:

```text
(112.0, 0.0, 112.0)
```

`visdata` and `lightdata` are intentionally empty because the fixture currently stops after `qbsp`; `vis` and `light` are not required for the current preview.

## Static-world preview

The current BSP preview can render world model `0` from a parsed BSP29 map:

```bash
bundle exec ruby bin/aogera-bsp29 --spectator /path/to/map.bsp
```

The preview reconstructs each BSP face through `Face -> SurfEdges -> Edges -> Vertices` and then converts Quake's source polygon winding to raylib by reversing the complete polygon once. Surface preparation records the world-model face count, prepared/dropped face count, number of Quake-source polygons flipped for raylib, source triangle count, and zero-area fan-triangle count. The winding conversion deliberately does not infer orientation from the first three vertices: valid QBSP faces may begin with collinear T-junction vertices. In the current v0.3.5 checkpoint, `Render::BSP29SurfaceBuilder` performs that work once at map load and stores face-level flat position buffers plus two independent coordinate domains: unwrapped Quake texture-space S/T for repeating miptextures and local lightmap-space S/T on Quake's original 16-unit luxel grid. Texture index/name, texinfo flags, original face index, active light-style IDs, and light offset are retained without assigning atlas coordinates. Baked samples remain in one compact lighting blob rather than being copied into one Ruby String per face.

`Render::BSP29World` consumes those stable surfaces, triangulates faces into persistent GPU batches, packs only the first stored baked-light style into the same padded lightmap atlas used since v0.3.4, and derives normalized atlas UVs at that rendering boundary. The original low-resolution lightmaps are not rebaked, upscaled, or rewritten. Faces with no baked samples use the atlas fullbright fallback texel. When a Quake palette is supplied, `Render::BSP29TextureMapping` converts preserved base S/T into normalized coordinates while deliberately leaving negative and greater-than-one values unwrapped; surfaces are grouped by their referenced embedded miptexture, each used base texture is palette-expanded only for upload and repeat-wrapped, and UV0 base coordinates plus UV1 lightmap-atlas coordinates are supplied to a minimal two-texture shader. The shared lightmap atlas is clamp-wrapped and multiplied with the base sample per fragment. Without a palette, `BSP29World` retains the established grayscale lightmap-only fallback.

Beginning with the v0.3.4 bring-up line, `bin/aogera-bsp29` no longer imports the Ruby `test_field` as gameplay state. `BSP29::Bootstrap` selects the first `info_player_start`, uses its already-normalized origin as the Aogera player entry, and converts the Quake `angle` property to `FirstPersonView` yaw. BSP mode currently creates only the bound player; it does not import Quake monsters, items, triggers, or other map entities yet.

When launched with `--spectator`, the BSP launcher enters `Mode::Spectator` rather than ordinary `Mode::Play`. The spectator camera begins at that bound player's eye position and then keeps independent camera coordinates. Its fixed-step movement bypasses `GroundMovement`, `GroundSpace`, and actor `Position`, allowing arbitrary vertical inspection before floor following, steps, gravity, and jumping exist. The underlying player entity remains at the BSP start and the configured BSP collision services remain available to the runtime for later gameplay tests.

The spectator also renders a compact top-left diagnostic panel. It reports raylib's measured FPS, camera XYZ, yaw/pitch in degrees, submitted and source triangle counts, persistent mesh draws per frame, prepared/world face counts and dropped faces, raylib-winding-flip and degenerate-triangle counts, preserved-but-unrendered BSP submodel count, base-texture or grayscale-fallback state, missing texture-face references, baked-lightmapped face count, lightmap-atlas dimensions, and current runtime entity count. These values are presentation diagnostics only; they do not feed back into simulation timing or collision.

Spectator controls are mouse look, WASD/arrows for view-relative flight, Space for world-up, Shift or C for world-down, and Q/Esc to quit. Forward flight follows pitch; combined directions are normalized to one configured speed.

The current `Level` API still requires a terrain object, so BSP bootstrap supplies an inert one-cell terrain with no spawns, relations, or gameplay authority. The runtime still configures actor static movement through BSP29 compiled hull 1 / `BSP29::GroundClearance`, zero-radius obstruction through `BSP29::PointHull`, and local navigation through the same BSP-backed `GroundSpace`; spectator flight intentionally bypasses all of them. The one-cell terrain is not consulted by BSP rendering, collision, or spectator movement.

`PointHull` follows BSP node children into leaves (`-(leaf_index + 1)`) and currently treats only `CONTENTS_SOLID` as blocking. Ground-style obstruction queries sample that point trace 16 world units above the source feet position so the flat combat/interaction model does not run exactly along floor/brush boundaries. This is a temporary 0.3.2 bridge, not vertical combat or a general contents/mask system.

BSP29 hull 1 has fixed Quake clearance: horizontal half-extent 16 and vertical bounds -24..32 around its hull origin. It does not represent Aogera's authored player `GroundBody(radius: 7.04)`. The controlled field intentionally retains a 32-unit pinch between blocked water cells, which exposes the resulting zero-clearance hull-1 case instead of hiding it by changing the fixture.

The current policy keeps these two body descriptions separate. `BSP29::GroundHull` is bound to the authored `GroundBody` radius of the character using it, but that radius is a contract check rather than a request to resize hull 1. `GroundSpace` forwards the radius on every BSP sweep; a mismatched radius raises instead of silently applying the same fixed hull to another actor shape. For the current player the diagnostic horizontal clearance delta is `16.0 - 7.04 = 8.96` world units.

Only model `0` is rendered. BSP submodels remain preserved for later doors/platforms.

The complete model-0 conversion path from surfedges through prepared face data, dual UV domains, triangle batching, and `RaylibAPI#create_static_model` is documented in `docs/bsp_to_raylib_meshes.md`.

### BSP runtime bootstrap

`BSP29::Bootstrap` is intentionally smaller than a Quake entity importer. Its only semantic entity today is `info_player_start`. A missing start, missing origin, or non-numeric `angle` is reported as `BSP29::FormatError` rather than silently falling back to the Ruby test level. The ordinary `bin/aogera` launch still uses `Level::Readers::Ruby` and `Level::Loader`.

The controlled fixture historically authored `info_player_start` as an Aogera feet-origin position, so v0.3.4 currently consumes the normalized entity origin directly. Real Quake-map validation must confirm whether a Quake player-origin-to-Aogera-feet offset is required before Aogera claims faithful spawn-height compatibility. This is deliberately left visible rather than guessed in the bootstrap patch.

## Not implemented yet

The BSP path does not yet provide:

- Quake fullbright-palette treatment or animated miptexture sequencing;
- special sky/turbulent-surface rendering;
- animated/multi-style lightmap evaluation beyond the first stored style;
- PVS traversal;
- arbitrary authored actor radii for BSP static collision;
- brush-submodel motion;
- general map-entity spawning/import beyond the bootstrap `info_player_start`;
- a global collision-certified route graph.

Those systems should consume `BSP29::MapData` rather than reopen or reinterpret the source file themselves.

The detailed history of the collision migration, the fixed hull-1 policy, and the retirement of active grid chase are documented in `docs/bsp_collision_migration.md` and `docs/navigation_migration.md`.
