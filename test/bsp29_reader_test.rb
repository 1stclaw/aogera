# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"

class BSP29ReaderTest < Minitest::Test
  def test_reads_and_normalizes_structural_bsp29_data
    bsp = build_bsp(
      entities: "{\n\"classname\" \"worldspawn\"\n}\n{\n\"classname\" \"info_player_start\"\n\"origin\" \"10 20 30\"\n}\n\0".b,
      planes: [1.0, 2.0, 3.0, 64.0, 5].pack("eeee l<"),
      textures: texture_lump,
      vertices: [10.0, 20.0, 30.0].pack("eee"),
      visibility: "\x01\x02\x03".b,
      nodes: [
        7, -1, -2,
        -10, -20, -30,
        40, 50, 60,
        2, 3
      ].pack("l<s<s<s<s<s<s<s<s<S<S<"),
      texinfo: [
        1.0, 2.0, 3.0, 4.0,
        5.0, 6.0, 7.0, 8.0,
        9, 1
      ].pack("eeeeeeee l<l<"),
      faces: [2, 1, 12, 4, 3, 0, 1, 255, 255, 1234].pack("s<s<l<s<s<CCCC l<"),
      lighting: "\x10\x20\x30".b,
      clipnodes: [6, -1, -2].pack("l<s<s<"),
      leaves: [
        -1, 44,
        -10, -20, -30,
        40, 50, 60,
        5, 6,
        1, 2, 3, 4
      ].pack("l<l<s<s<s<s<s<s<S<S<CCCC"),
      marksurfaces: [7, 8].pack("S<S<"),
      edges: [11, 12].pack("S<S<"),
      surfedges: [-9, 10].pack("l<l<"),
      models: [
        -10.0, -20.0, -30.0,
        40.0, 50.0, 60.0,
        10.0, 20.0, 30.0,
        1, 2, 3, 4,
        12, 13, 14
      ].pack("eeeeee eee l<l<l<l< l<l<l<")
    )

    map = Aogera::BSP29::Reader.read_bytes(bsp)

    assert_equal 2, map.entities.length
    assert_equal "worldspawn", map.entities.first.classname
    assert_equal "info_player_start", map.entities.last.classname
    assert_equal [map.entities.last], map.entities_named("info_player_start")
    assert_equal Aogera::BSP29::Vec3.new(x: 10.0, y: 30.0, z: -20.0), map.entities.last.origin

    assert_equal Aogera::BSP29::Vec3.new(x: 1.0, y: 3.0, z: -2.0), map.planes.first.normal
    assert_in_delta 64.0, map.planes.first.distance
    assert_equal 5, map.planes.first.type

    assert_equal Aogera::BSP29::Vec3.new(x: 10.0, y: 30.0, z: -20.0), map.vertices.first
    assert_equal [7, 8], map.marksurfaces
    assert_equal [-9, 10], map.surfedges
    assert_equal [11, 12], map.edges.first.vertex_indices
    assert_equal "\x01\x02\x03".b, map.visibility
    assert_equal "\x10\x20\x30".b, map.lighting

    node = map.nodes.first
    assert_equal 7, node.plane_index
    assert_equal [-1, -2], node.children
    assert_equal Aogera::BSP29::Vec3.new(x: -10.0, y: -30.0, z: -50.0), node.bounds.mins
    assert_equal Aogera::BSP29::Vec3.new(x: 40.0, y: 60.0, z: 20.0), node.bounds.maxs

    texinfo = map.texinfo.first
    assert_equal Aogera::BSP29::Vec3.new(x: 1.0, y: 3.0, z: -2.0), texinfo.s_axis
    assert_equal Aogera::BSP29::Vec3.new(x: 5.0, y: 7.0, z: -6.0), texinfo.t_axis
    assert_in_delta 4.0, texinfo.s_offset
    assert_in_delta 8.0, texinfo.t_offset

    face = map.faces.first
    assert_equal 2, face.plane_index
    assert_equal [0, 1, 255, 255], face.styles
    assert_equal 1234, face.light_offset

    assert_equal [6, [-1, -2]], [map.clipnodes.first.plane_index, map.clipnodes.first.children]

    leaf = map.leaves.first
    assert_equal(-1, leaf.contents)
    assert_equal [1, 2, 3, 4], leaf.ambient_levels
    assert_equal Aogera::BSP29::Vec3.new(x: -10.0, y: -30.0, z: -50.0), leaf.bounds.mins
    assert_equal Aogera::BSP29::Vec3.new(x: 40.0, y: 60.0, z: 20.0), leaf.bounds.maxs

    model = map.world_model
    assert_equal Aogera::BSP29::Vec3.new(x: 10.0, y: 30.0, z: -20.0), model.origin
    assert_equal [1, 2, 3, 4], model.headnodes
    assert_equal 12, model.visible_leaf_count
    assert_equal 13, model.first_face
    assert_equal 14, model.face_count
  end

  def test_reads_embedded_miptextures_without_palette_interpretation
    map = Aogera::BSP29::Reader.read_bytes(build_bsp(textures: texture_lump))

    texture = map.textures.fetch(0)
    assert_equal "TEST", texture.name
    assert_equal 16, texture.width
    assert_equal 16, texture.height
    assert_equal [256, 64, 16, 4], texture.mipmaps.map(&:bytesize)
    assert_equal [0, 1, 2, 3], texture.mipmaps.map { |mip| mip.getbyte(0) }
  end

  def test_preserves_missing_texture_directory_entries
    texture_bytes = [2, -1, -1].pack("l<l<l<")
    map = Aogera::BSP29::Reader.read_bytes(build_bsp(textures: texture_bytes))

    assert_equal [nil, nil], map.textures
  end

  def test_reads_from_a_file_path
    Tempfile.create(["aogera-bsp29", ".bsp"]) do |file|
      file.binmode
      file.write(build_bsp(vertices: [1.0, 2.0, 3.0].pack("eee")))
      file.flush

      map = Aogera::BSP29::Reader.read(file.path)
      assert_equal Aogera::BSP29::Vec3.new(x: 1.0, y: 3.0, z: -2.0), map.vertices.first
    end
  end

  def test_rejects_non_bsp29_versions
    bytes = build_bsp
    bytes[0, 4] = [30].pack("l<")

    error = assert_raises(Aogera::BSP29::FormatError) do
      Aogera::BSP29::Reader.read_bytes(bytes)
    end
    assert_match(/unsupported BSP version 30/, error.message)
  end

  def test_rejects_truncated_or_misaligned_lumps
    truncated = build_bsp
    # planes lump header: version (4) + lump index 1 * 8
    truncated[12, 8] = [truncated.bytesize - 2, 20].pack("l<l<")
    assert_raises(Aogera::BSP29::FormatError) do
      Aogera::BSP29::Reader.read_bytes(truncated)
    end

    misaligned = build_bsp(planes: "x" * 19)
    error = assert_raises(Aogera::BSP29::FormatError) do
      Aogera::BSP29::Reader.read_bytes(misaligned)
    end
    assert_match(/planes lump length 19/, error.message)
  end

  def test_rejects_malformed_entity_origin
    entities = "{\"classname\" \"info_player_start\" \"origin\" \"1 2\"}\0".b
    error = assert_raises(Aogera::BSP29::FormatError) do
      Aogera::BSP29::Reader.read_bytes(build_bsp(entities: entities))
    end
    assert_match(/origin must contain exactly three numbers/, error.message)
  end

  private

  def build_bsp(**lumps)
    payload = +"".b
    directory = Aogera::BSP29::LUMP_NAMES.map do |name|
      bytes = lumps.fetch(name, "".b).b
      if bytes.empty?
        [Aogera::BSP29::HEADER_SIZE, 0]
      else
        offset = Aogera::BSP29::HEADER_SIZE + payload.bytesize
        payload << bytes
        [offset, bytes.bytesize]
      end
    end

    header = [Aogera::BSP29::VERSION].pack("l<") +
      directory.flatten.pack("l<#{Aogera::BSP29::HEADER_LUMP_COUNT * 2}")
    header + payload
  end

  def texture_lump
    width = 16
    height = 16
    mip_sizes = [256, 64, 16, 4]
    mip_offsets = [40]
    mip_sizes[0, 3].each { |size| mip_offsets << mip_offsets.last + size }

    header = "TEST\0".ljust(16, "\0") +
      [width, height, *mip_offsets].pack("V6")
    pixels = mip_sizes.each_with_index.map { |size, index| index.chr * size }.join.b
    texture = header + pixels

    [1, 8].pack("l<l<") + texture
  end
end
