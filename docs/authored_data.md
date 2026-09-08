# Aogera 0.3.2 Authored Data Boundary

Aogera 0.3.2 introduces an explicit boundary between **reading an authored source format** and **loading normalized authored data into the runtime**.

## Reader

A Reader understands a source format.

Current implementation:

```text
Level::Readers::Ruby
```

Its responsibilities include:

- locating/reading the source representation;
- understanding source-specific structure;
- converting source coordinates into Aogera coordinates;
- converting source measurement conventions into Aogera world units;
- producing normalized authored records.

The current Ruby reader converts grid cells into world-space cell centers using the current 32-unit grid scale.

A future BSP29 reader will additionally understand binary BSP29 lumps and Quake's Z-up coordinate convention. BSP-specific structure such as planes, faces, nodes, leaves, clipnodes, models, visibility, lighting, and entity declarations should be preserved where useful rather than flattened into a fake generic scene structure.

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

It does **not** read files, decode binary formats, choose coordinate transforms, or understand BSP lump layouts.

The intended flow is:

```text
source
  |
  v
Reader
  |
  | Aogera-normalized authored data
  v
Loader
  |
  v
Level / runtime consumers
```

Readers may multiply over time. The loader remains an Aogera boundary rather than becoming a universal file parser.

## World units

Aogera 0.3.2 standardizes world-unit magnitude around Quake 1 map units:

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

These are Aogera gameplay values expressed in the new unit scale; they are not claims that Aogera should use Quake's original player dimensions or movement speeds.

## BSP29 implication

A BSP29 reader should not need a scalar resize for Quake map coordinates. It should perform the coordinate-system normalization only.

The currently planned axis mapping is:

```text
Quake  (x, y, z)
   ->
Aogera (x, z, -y)
```

That exact mapping still needs to be established with real BSP29 fixtures and executable tests, especially for plane normals, face winding, bounds, entity origins, and brush submodels.

No BSP reader is included in 0.3.2. The purpose of this release is to make its boundary explicit before the first BSP implementation.
