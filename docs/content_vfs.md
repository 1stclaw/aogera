# Aogera binary-content VFS

Aogera 0.3.5 introduces a deliberately small virtual filesystem for **binary game content**. It is not used for the repository's executable Ruby-authored definitions and it is not an asset manager.

## Boundary

```text
virtual path
    |
    v
Content::VFS
    |
    +--> Content::Directory
    |
    `--> Content::Pak
             |
             v
            bytes
             |
             v
       format Reader
```

The VFS resolves storage. Format readers interpret bytes. Runtime systems receive decoded data rather than VFS handles.

## Virtual paths

`Content::VirtualPath` provides one canonical namespace for mounted sources. Paths use `/` separators and must be relative file paths. Repeated separators are collapsed and `\\` is accepted as an input separator, but absolute paths, drive-letter paths, `.` / `..` segments, trailing directory separators, empty paths, and NUL bytes are rejected.

Examples:

```text
maps/e1m3.bsp       valid
gfx/palette.lmp     valid
maps//e1m3.bsp      -> maps/e1m3.bsp
maps\\e1m3.bsp      -> maps/e1m3.bsp

/maps/e1m3.bsp      invalid
../gfx/palette.lmp  invalid
./maps/e1m3.bsp     invalid
maps/               invalid
```

Virtual paths are case-sensitive. No Quake-specific case folding is performed.

## Source contract

Mounted sources provide only:

```text
read(path)   -> binary bytes
exist?(path) -> boolean
```

`Content::VFS#read` checks sources in reverse mount order, so the **last mounted source wins**. If a higher-priority source does not contain the requested path, lookup falls through to earlier sources.

There are intentionally no mount points, write operations, globbing, automatic package discovery, caching, or common enumeration API in this checkpoint.

## Directory source

`Content::Directory` maps virtual paths beneath one host directory and reads files in binary mode. Lexical traversal through `.` / `..` or absolute virtual paths is rejected by `Content::VirtualPath` before host-path construction. Ordinary host-filesystem symlink behavior is intentionally left unchanged; this source is a content resolver, not a filesystem sandbox.

## Quake PAK source

`Content::Pak` implements the Quake `PACK` container directly without extraction. Construction reads and validates the header and directory table once. Individual file data is read on demand from the archive.

Validated structure includes:

- `PACK` magic;
- 12-byte header;
- directory range within the physical file;
- directory length divisible by the 64-byte entry size;
- normalized 56-byte entry names;
- entry byte ranges within the physical file.

`Pak#entries` exposes immutable directory-entry records for diagnostics, but enumeration is not part of the generic VFS source contract.

If a PAK contains duplicate names, lookup uses the **first directory entry**. This deterministic archive-local rule is independent from VFS mount precedence: between separate mounted sources, the later source still wins.

## Errors

```text
Content::InvalidPath       invalid virtual namespace path
Content::NotFound          valid virtual path absent from a source/VFS
Content::Pak::FormatError  malformed PAK structure
```

Failure to open the physical directory or PAK itself remains a host-filesystem error. The content layer does not relabel missing/corrupt physical containers as missing virtual members.

## Current integration state

`bin/aogera-bsp29` is the first VFS consumer. Direct BSP paths continue to use the Reader's filesystem convenience entry point. When `--pak FILE` is supplied, the CLI mounts `Content::Pak` into a fresh `Content::VFS`, resolves the BSP argument as a virtual path, and passes the returned bytes to `BSP29::Reader.read_bytes`.

```text
--pak FILE + maps/e1m3.bsp
          |
          v
     Content::Pak
          |
          v
      Content::VFS
          | bytes
          v
BSP29::Reader.read_bytes
```

This source choice does not propagate into `App`, simulation, collision, or rendering. They continue to receive decoded BSP data. `Content::Directory` is implemented and tested as a VFS source but does not yet have a dedicated BSP CLI option.

The same byte boundary is proven for Quake's palette data. `Quake::PaletteReader` accepts bytes only; tests mount a synthetic PAK, read `gfx/palette.lmp` through `Content::VFS`, and pass those bytes to the palette decoder. `Quake::MipTextureDecoder` then operates only on an already-parsed `BSP29::MipTexture` plus the decoded palette; neither decoder knows about PAKs or VFS mounts. The world renderer still does not request or upload the palette-expanded miptexture pixels at this checkpoint.
