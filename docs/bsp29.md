# BSP29 Reader and Static Preview

Aogera's first Quake map integration begins with a **format Reader** and now includes a static-world preview plus operational BSP collision queries. The stable v0.3.2a release separated parsing, rendering, gameplay collision, and temporary grid navigation; the current v0.3.3 line has since moved active chase onto continuous local navigation while preserving the same BSP collision boundary.

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
   +--> Render::BSP29World (world model 0 preview)
   +--> BSP29::GroundClearance (compiled hull 1, actor movement/local probes)
   |       |
   |       +--> BSP29::GroundHull (radius-bound fixed-hull adapter)
   +--> BSP29::PointHull (headnode 0, obstruction traces)
   +--> future map-entity importer
```

`BSP29::Reader` understands Quake 1 BSP version 29 binary structure. It does not construct an Aogera `Level`, spawn gameplay actors, call raylib, or perform collision queries.

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

No Quake palette or raylib texture conversion is performed yet.

Brush model `0` remains the static world model. Additional BSP submodels remain separate in `MapData#models`; the Reader does not flatten doors/platforms/moving brush candidates into world geometry.

Clipnodes and model headnodes are preserved as first-class collision data. The current preview uses `BSP29::GroundClearance` over compiled hull 1 for player/NPC static movement and for the positive-radius probes issued by continuous local navigation through `GroundSpace`. The old grid Pathfinder remains only as dormant/reference code.

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

## Existing-map inspection

An existing BSP29 file can be inspected without loading it into gameplay:

```bash
bundle exec ruby bin/aogera-bsp29-info /path/to/map.bsp
```

The tool prints structural counts, world-model bounds, visibility/light byte counts, and normalized `info_player_start` origins.

This is intended as the first structural compatibility check for real Quake/TrenchBroom maps.


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

The current 0.3.2a release can render world model `0` from a parsed BSP29 map:

```bash
bundle exec ruby bin/aogera-bsp29 /path/to/map.bsp
```

The preview reconstructs each BSP face through `Face -> SurfEdges -> Edges -> Vertices`, verifies/corrects polygon winding against the normalized BSP face plane, triangulates the convex polygon, and sends the triangles through `RaylibAPI`. The fixture texture names are mapped to diagnostic colors; embedded miptexture pixels are not sampled yet.

For the controlled `test_field.bsp` fixture, gameplay state still comes from the existing Ruby `test_field`, but static collision authority is BSP-backed. The bound persistent character and spawned NPCs use BSP29 compiled hull 1 for static movement through `BSP29::GroundClearance`; zero-radius melee/interaction obstruction uses world-model headnode 0 through `BSP29::PointHull`; and active NPC chase now chooses local headings by probing the same `GroundSpace` from actual continuous positions. Dynamic actor-vs-actor collision remains continuous `GroundBody` collision. The Ruby level is therefore still an authored/spawn/entry bridge, but it is no longer active chase topology.

`PointHull` follows BSP node children into leaves (`-(leaf_index + 1)`) and currently treats only `CONTENTS_SOLID` as blocking. Ground-style obstruction queries sample that point trace 16 world units above the source feet position so the flat combat/interaction model does not run exactly along floor/brush boundaries. This is a temporary 0.3.2 bridge, not vertical combat or a general contents/mask system.

BSP29 hull 1 has fixed Quake clearance: horizontal half-extent 16 and vertical bounds -24..32 around its hull origin. It does not represent Aogera's authored player `GroundBody(radius: 7.04)`. The controlled field intentionally retains a 32-unit pinch between blocked water cells, which exposes the resulting zero-clearance hull-1 case instead of hiding it by changing the fixture.

The current policy keeps these two body descriptions separate. `BSP29::GroundHull` is bound to the authored `GroundBody` radius of the character using it, but that radius is a contract check rather than a request to resize hull 1. `GroundSpace` forwards the radius on every BSP sweep; a mismatched radius raises instead of silently applying the same fixed hull to another actor shape. For the current player the diagnostic horizontal clearance delta is `16.0 - 7.04 = 8.96` world units.

Only model `0` is rendered. BSP submodels remain preserved for later doors/platforms.

## Not implemented yet

The BSP path does not yet provide:

- palette conversion or raylib textures;
- lightmap rendering;
- PVS traversal;
- arbitrary authored actor radii for BSP static collision;
- brush-submodel motion;
- map-entity spawning through `Level::Loader`;
- a global collision-certified route graph.

Those systems should consume `BSP29::MapData` rather than reopen or reinterpret the source file themselves.

The detailed history of the collision migration, the fixed hull-1 policy, and the retirement of active grid chase are documented in `docs/bsp_collision_migration.md` and `docs/navigation_migration.md`.
