# BSP29 to raylib Mesh Conversion

This document describes the current Aogera 0.3.5 path from normalized Quake BSP29 world data to persistent raylib meshes. It documents the renderer that exists now; it is not a proposal for a generic mesh, material, scene, or asset system.

The conversion has one guiding rule:

> prepare static BSP data once at map load, upload persistent GPU resources once, and keep the rendered frame path allocation-light.

That preserves the useful Quake model of precomputed world geometry, compact indexed textures, and low-resolution baked lightmaps while adapting it to raylib's mesh/material interface.

## Scope

The current renderer handles BSP world model `0` only. Brush submodels `*1...` remain preserved in `BSP29::MapData` but are not converted into render meshes yet.

The path is:

```text
BSP29::MapData
      |
      v
Render::BSP29SurfaceBuilder
      |
      | stable CPU-side face data
      v
Render::BSP29World
      |
      | triangulated/batched float buffers
      v
RaylibAPI#create_static_model
      |
      v
raylib Mesh -> uploaded GPU data -> Model
```

Textured PAK-backed rendering adds two independent texture inputs:

```text
embedded BSP miptexture --palette--> base RGBA texture -- UV0 --\
                                                           shader -> final surface
BSP lighting lump -----------> lightmap atlas ----------- UV1 --/
```

The original low-resolution BSP lightmaps are not rebaked or upscaled.

## 1. Select world-model faces

`BSP29SurfaceBuilder` begins with `map.world_model` (`models[0]`) and slices the global BSP face array using the model's `first_face` and `face_count`.

This distinction matters because the BSP file also contains faces used by brush submodels such as doors, lifts, platforms, switches, and other brush entities. Those faces are valid BSP geometry but are outside the current world-model renderer.

The builder records:

- number of model-0 faces presented;
- number of prepared surfaces;
- dropped faces;
- source triangle count;
- zero-area fan triangles;
- the number of source polygons converted to raylib winding.

These are preparation-time diagnostics, not per-frame queries.

## 2. Reconstruct a BSP face polygon

A BSP `Face` does not directly contain vertex indices. It references a run of signed surfedges:

```text
Face
  first_edge
  edge_count
      |
      v
SurfEdges[]
      |
      | sign selects edge direction
      v
Edges[]
      |
      v
Vertices[]
```

For each surfedge:

```text
surfedge >= 0 -> edge.vertex_indices[0]
surfedge <  0 -> edge.vertex_indices[1]
```

Walking the surfedges in order reconstructs the complete convex face polygon.

The Reader has already normalized Quake coordinates into Aogera's Y-up coordinate convention before the renderer sees these vertices. Surface preparation therefore does not reopen the BSP or perform source-coordinate conversion.

## 3. Convert Quake winding to raylib winding

Quake surfedge order is treated as source truth.

The current conversion reverses the **complete reconstructed polygon exactly once** before triangulation:

```text
Quake surfedge polygon
        |
        | reverse once
        v
raylib-facing polygon
```

This rule replaced an earlier geometric heuristic that inspected the first three vertices and compared their cross product with the BSP plane. That heuristic was incorrect for valid QBSP output because T-junction fixing can insert collinear boundary vertices at the beginning of a polygon. A zero-area first triple could therefore leave an otherwise valid face in the wrong GPU-facing orientation.

The winding correction was manually validated against E1M3 in both spectator and walkthrough modes.

### `--bsp-two-sided`

`--bsp-two-sided` is intentionally retained as a map-authoring and compatibility diagnostic. It is useful when testing custom BSP29 content, including maps compiled with toolchains such as ericw-tools.

It does **not** change global raylib/rlgl culling state. Instead, for every triangle submitted by the normal path, Aogera appends a second triangle with the opposite vertex order:

```text
normal:      0, i, i+1
extra copy:  0, i+1, i
```

This doubles submitted triangles and is therefore not the normal rendering policy. Its purpose is diagnostic:

- if a surface appears only in two-sided mode, investigate winding/conversion;
- if it is absent in both modes, investigate face reconstruction, dropped surfaces, batching, or unsupported brush submodels;
- if a custom map intentionally contains unusual one-sided authoring, the option provides a compatibility view without weakening the default renderer.

## 4. Preserve face-level CPU data

The builder stores one prepared `Surface` per valid model-0 BSP face rather than materializing per-triangle Ruby objects.

Each surface contains flat, frozen numeric buffers and metadata:

```text
Surface
  face_index
  positions[]       # x,y,z per polygon vertex
  texture_st[]      # Quake base-texture S/T
  lightmap_st[]     # local luxel-space S/T, when lightmapped
  texture_index
  texture_name
  texinfo_flags
  lightmap metadata
```

The position buffer preserves the polygon before GPU triangulation. Face identity therefore survives even though raylib ultimately receives independent triangles.

The prepared world also retains one shared frozen BSP lighting blob. Individual faces store offsets and dimensions into that blob instead of allocating copied light-sample strings.

This is deliberate for Ruby: static map preparation creates long-lived data once and avoids per-frame object churn.

## 5. Base-texture coordinates

Quake texture coordinates come from the face's `TexInfo` vectors:

```text
s = dot(position, s_axis) + s_offset
t = dot(position, t_axis) + t_offset
```

`BSP29SurfaceBuilder` stores those S/T values **unwrapped**. Negative values and values larger than the miptexture dimensions are valid because Quake world textures tile.

When textured rendering is active, `BSP29TextureMapping` converts them to normalized coordinates:

```text
u = s / texture.width
v = t / texture.height
```

The values remain unwrapped; the base GPU texture uses repeat wrapping. A value such as `u = 4.5` therefore means repeated texture space, not an error that should be clamped into `0..1`.

## 6. Lightmap coordinates and atlas

Quake baked lighting uses a separate low-frequency coordinate domain. Aogera preserves the Quake 16-unit luxel scale:

```text
LIGHTMAP_SCALE = 16
```

For each lightmapped face the builder derives the lightmap extent from the minimum and maximum base S/T values, producing:

```text
Lightmap
  min_s
  min_t
  width
  height
  styles[]
  light_offset
```

Local lightmap S/T stays in luxel space. Atlas placement is deliberately **not** part of the prepared surface.

`BSP29World` later packs these rectangles into one padded power-of-two atlas. The current renderer reads the first stored light style only. Each face references the original shared lighting blob by byte offset; Aogera does not expand the lightmap to base-texture resolution.

A one-luxel padding border is filled by duplicating edge samples. This reduces filtering bleed between packed lightmap rectangles.

Faces without baked samples use the atlas white fallback texel.

## 7. Triangulate the convex face

Raylib's static mesh input is a triangle list. Each prepared convex polygon is converted to a triangle fan:

```text
polygon vertices: 0 1 2 3 4

triangles:
  0 1 2
  0 2 3
  0 3 4
```

The same vertex indices select:

- XYZ position;
- base UV0, when textured;
- lightmap UV1.

The builder reports zero-area fan triangles separately. A valid BSP face is not dropped merely because one T-junction-related fan triangle is degenerate; the diagnostic remains visible for map/compiler investigation.

In `--bsp-two-sided` mode only, the reverse copy of each triangle is appended after its normal copy.

## 8. Batch by base texture

There are two current material paths.

### Grayscale fallback

Loose BSP launch has no palette content source. All prepared surfaces can therefore use one lightmap-only batch:

```text
one mesh batch
one lightmap texture
UV0 = lightmap atlas coordinates
```

### Textured PAK path

When `gfx/palette.lmp` is available, surfaces are grouped by embedded BSP miptexture index:

```text
texture 0 -> batch of all model-0 surfaces using texture 0
texture 1 -> batch of all model-0 surfaces using texture 1
...
```

Only used miptextures are palette-expanded for GPU upload. The compact indexed BSP mip chain remains the authoritative content representation; expanded RGBA is transient upload data.

If a prepared face has no usable embedded texture, the textured renderer uses a 1x1 white base texture so its baked lightmap can remain visible. Missing texture references are counted in the diagnostic overlay.

## 9. Build raylib meshes

`BSP29World` passes flat Ruby arrays to `RaylibAPI#create_static_model`:

```text
vertices   -> 3 floats per submitted vertex
texcoords  -> UV0, 2 floats per vertex
texcoords2 -> UV1, 2 floats per vertex (textured path)
```

`RaylibAPI` allocates native float buffers, fills a raylib `Mesh`, and sets:

```text
vertexCount   = submitted vertices
triangleCount = vertexCount / 3
```

The mesh is uploaded as static (`UploadMesh(..., false)`) and converted into a raylib `Model` with `LoadModelFromMesh`.

This is the native-boundary step. Core BSP structures and prepared surfaces contain no raylib FFI objects.

Once prepared, a normal frame draws persistent models; it does not reconstruct BSP faces, recalculate texture axes, rebuild lightmaps, decode miptextures, or recreate meshes.

## 10. Textures and shader

The textured path uploads:

- one repeat-wrapped RGBA texture per used BSP miptexture;
- one clamp-wrapped low-resolution lightmap atlas;
- one small GLSL 330 shader shared by the BSP batches.

The shader receives two independent UV sets:

```glsl
base  = texture(texture0, UV0);
baked = texture(texture1, UV1);
final = base * baked;
```

This preserves the original Quake split between high-frequency surface detail and low-frequency static illumination. Ruby does not CPU-combine or rebake the two textures.

The current implementation uses raylib material texture slots as the binding bridge for the two sampler inputs. That is an implementation detail of the current raylib frontend rather than a general Aogera material abstraction.

## 11. Resource lifetime

GPU resources are created only after the raylib context is open.

`BSP29World#prepare` owns the prepared models, textures, and shader as one resource set. Partial initialization failures unwind already-created resources. `#close` unloads:

```text
models
base/lightmap textures
shader
```

before the graphics context closes.

The CPU-side normalized BSP and prepared surface data remain ordinary Ruby data and are independent of raylib resource lifetime.

## 12. Current diagnostics

The runtime overlay exposes the values most useful when validating BSP conversion:

```text
world/model-0 face count
prepared surface count
dropped face count
source triangle count
submitted triangle count
degenerate fan triangles
winding conversions
mesh draw count
skipped brush-submodel count
base-texture / grayscale-fallback state
missing texture-face count
lightmapped-face count
lightmap atlas dimensions
```

These diagnostics distinguish several visually similar failures. For example, an invisible but colliding wall can be separated from a missing brush submodel, a dropped face, or a winding/culling problem.

## 13. Intentionally deferred

This conversion path does not yet implement:

- rendering of BSP brush submodels `*1...`;
- Quake PVS-driven visibility;
- animated `+0/+1/...` miptexture families;
- sky or turbulent-water/lava rendering;
- palette fullbright semantics;
- animated/multiple light-style evaluation;
- a generic material, mesh, scene, or asset framework;
- dynamic shadowing or dynamic lighting.

Those systems should build on the prepared world data rather than move BSP interpretation back into the frame loop.
