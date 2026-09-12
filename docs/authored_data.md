# Aogera Authored Data and Source Boundary

Aogera keeps **source access**, **source-format decoding**, and **runtime loading** as separate responsibilities where the source format permits it. This boundary began with the v0.3.2 authored-data work and is now explicit in v0.3.5 through a minimal binary-content VFS.

## Source access versus format decoding

Binary game content should reach a format reader as bytes rather than making the reader responsible for package or filesystem policy:

```text
physical/package source
        |
        v
source access
        |
        | bytes
        v
format Reader
        |
        | normalized format data
        v
runtime consumer / Loader
```

`BSP29::Reader.read_bytes` is the current concrete binary boundary. `BSP29::Reader.read(path)` remains a convenience filesystem adapter that performs `File.binread` and delegates to `read_bytes`; filesystem access failures remain source errors rather than being converted into BSP format errors.

The v0.3.5 content-source layer now sits upstream of `read_bytes`: `Content::VFS` resolves a normalized virtual path against mounted `Content::Directory` and `Content::Pak` sources and returns bytes, while the BSP Reader remains unaware of mounts, package formats, and source precedence. Later-mounted sources take precedence over earlier sources.

Ruby-authored definitions are intentionally a separate special case. `Content::RubyPaths` identifies the current repository-local Ruby files and `Content::RubySource` supports their `require`/constant conventions. Those executable Ruby sources are not forced through the binary-content VFS.

## Reader

A Reader understands a source format.

Current level implementation:

```text
Level::Readers::Ruby
```

Its responsibilities include:

- understanding source-specific structure;
- converting source coordinates into Aogera coordinates;
- converting source measurement conventions into Aogera world units;
- producing normalized authored records.

The current Ruby level Reader is path-based because Ruby `require` itself is path-based. It converts grid cells into world-space cell centers using the current 32-unit grid scale.

`BSP29::Reader` is the first external binary map Reader. It understands BSP29 lumps and Quake's Z-up coordinate convention, and it preserves planes, faces, nodes, leaves, clipnodes, models, visibility, lighting, texture data, and entity declarations in normalized `BSP29::MapData` rather than flattening them into a fake generic scene structure.

## Normalized authored data

The current level boundary is:

```text
Level::AuthoredData
├── name
├── terrain
├── spawns
├── entries
├── relations
└── default_entry
```

Current normalized spawn/entry records use Aogera world coordinates:

```text
AuthoredSpawn(key, prototype, x, y, z)
AuthoredEntry(key, x, y, z, facing)
```

The current grid source records remain source-format data:

```text
Spawn(key, prototype, x, y)
Entry(key, x, y, facing)
```

Readers, not runtime simulation, convert between those representations.

## Loader

`Level::Loader` consumes normalized `Level::AuthoredData`.

It owns Aogera-facing validation and runtime level construction, including:

- prototype reference validation;
- spawn/entry placement validation;
- reference-key validation;
- static relation validation;
- `Level` construction.

It does **not** decode binary formats, choose coordinate transforms, or understand BSP lump layouts.

For the current Ruby-authored level path, the flow is:

```text
Ruby source path
  |
  v
Level::Readers::Ruby
  |
  | Aogera-normalized authored data
  v
Level::Loader
  |
  v
Level / runtime consumers
```

For binary formats, VFS source access stays before the Reader:

```text
Directory / PAK
  |
  v
Content::VFS
  |
  | bytes
  v
format Reader
  |
  v
normalized format data / runtime consumers
```

The common VFS-source contract is deliberately only `read(path)` and `exist?(path)`. Archive enumeration is not required: `Content::Pak#entries` is available because PAK already contains a directory table, but `Content::Directory` is not forced to recursively enumerate the host filesystem.

Readers may multiply over time. Loaders and runtime consumers remain Aogera boundaries rather than becoming universal file or package parsers.

## World units

Aogera standardizes world-unit magnitude around Quake 1 map units:

```text
1 Quake map unit = 1 Aogera world unit
```

This is a **measurement-scale convention**, not an adoption of Quake's entity-origin, collision-hull, gameplay-speed, or coordinate-axis conventions.

The current grid uses:

```text
1 authored grid cell = 32 Aogera world units
```

Therefore source grid cell `(3, 3)` has world-space center:

```text
(112, 0, 112)
```

Existing 0.3.1 linear gameplay values were scaled by 32 in 0.3.2 so their proportions remain stable.

Examples:

```text
player speed       2.4  -> 76.8 world units/sec
NPC speed          2.0  -> 64.0 world units/sec
player body radius 0.22 -> 7.04 world units
eye height         0.68 -> 21.76 world units
melee reach        0.65 -> 20.8 world units
```

These are Aogera gameplay values expressed in the current unit scale; they are not claims that Aogera should use Quake's original player dimensions or movement speeds.

## BSP29 implication

A BSP29 reader does not need a scalar resize for Quake map coordinates. It performs coordinate-system normalization only.

The established axis mapping is:

```text
Quake  (x, y, z)
   ->
Aogera (x, z, -y)
```

That mapping is established in executable code and has been validated with a controlled BSP29 fixture compiled from Aogera's original `test_field`. Structural lump counts match ericw-tools, world bounds are consistent with the 1408×448 authored footprint, and the normalized `info_player_start` resolves to `(112, 0, 112)` as expected.

The BSP29 Reader is intentionally not connected to `Level::Loader`, because the current loader constructs grid-backed `Level` objects and BSP static-world structure should not be forced through that representation. `Render::BSP29SurfaceBuilder` consumes world model `0` from `BSP29::MapData` once and produces stable renderer-facing surface data; `Render::BSP29World` then owns atlas/mesh/GPU preparation. BSP bootstrap/collision consume other normalized BSP structures according to their own needs.
