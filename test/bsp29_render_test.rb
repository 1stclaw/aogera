# frozen_string_literal: true

require_relative "test_helper"

class BSP29RenderTest < Minitest::Test
  class FakeAPI
    attr_reader :created, :textures, :textured, :drawn, :unloaded, :unloaded_textures

    def initialize(fail_on: nil)
      @fail_on = fail_on
      @created = []
      @textures = []
      @textured = []
      @drawn = []
      @unloaded = []
      @unloaded_textures = []
    end

    def create_static_model(vertices:, texcoords: nil)
      raise "create_static_model failed" if @fail_on == :create_static_model

      handle = [:model, @created.length]
      @created << {handle: handle, vertices: vertices, texcoords: texcoords}
      handle
    end

    def create_texture_rgba(width:, height:, pixels:)
      handle = [:texture, @textures.length]
      @textures << {handle: handle, width: width, height: height, pixels: pixels}
      handle
    end

    def set_model_texture(model:, texture:)
      raise "set_model_texture failed" if @fail_on == :set_model_texture

      @textured << {model: model, texture: texture}
    end

    def draw_model(model:, rgba:)
      @drawn << {model: model, rgba: rgba}
    end

    def unload_model(model)
      @unloaded << model
    end

    def unload_texture(texture)
      @unloaded_textures << texture
    end
  end

  def test_world_model_faces_are_reconstructed_into_one_textured_mesh
    renderer = Aogera::Render::BSP29World.new(map: square_map)
    api = FakeAPI.new

    assert_equal 2, renderer.triangle_count
    assert_equal 1, renderer.batch_count
    assert_equal 18, renderer.batches.first.vertices.length
    assert_equal 12, renderer.batches.first.texcoords.length
    assert_equal [255, 255, 255, 255], renderer.batches.first.rgba

    renderer.prepare(api)
    renderer.draw(api)
    renderer.draw(api)

    assert_equal 1, api.created.length
    assert_equal 1, api.textures.length
    assert_equal 1, api.textured.length
    assert_equal 2, api.drawn.length
    assert_equal api.created.first.fetch(:handle), api.drawn.first.fetch(:model)

    triangles = api.created.first.fetch(:vertices).each_slice(9).to_a
    triangles.each do |triangle|
      assert_operator cross_y_from_flat(triangle), :>, 0.0
    end
  end

  def test_baked_light_samples_build_grayscale_atlas_and_uvs
    lighting = [0, 16, 32, 48, 64, 80, 96, 112, 127].pack("C*")
    renderer = Aogera::Render::BSP29World.new(
      map: square_map(size: 32.0, light_offset: 0, lighting: lighting)
    )
    api = FakeAPI.new

    assert_equal 1, renderer.lightmapped_face_count
    assert_operator renderer.lightmap_atlas_width, :>=, 8
    assert_operator renderer.lightmap_atlas_height, :>=, 8

    renderer.prepare(api)

    texture = api.textures.fetch(0)
    pixels = texture.fetch(:pixels)
    grayscale_values = pixels.bytes.each_slice(4).map(&:first).uniq
    assert_includes grayscale_values, 0
    assert_includes grayscale_values, 32
    assert_includes grayscale_values, 128
    assert_includes grayscale_values, 224
    assert_includes grayscale_values, 254

    texcoords = api.created.fetch(0).fetch(:texcoords)
    assert_equal 12, texcoords.length
    texcoords.each do |coordinate|
      assert_operator coordinate, :>, 0.0
      assert_operator coordinate, :<, 1.0
    end
    assert_operator texcoords.each_slice(2).to_a.uniq.length, :>, 2
  end

  def test_faces_without_baked_light_use_fullbright_atlas_pixel
    renderer = Aogera::Render::BSP29World.new(map: square_map)
    api = FakeAPI.new

    assert_equal 0, renderer.lightmapped_face_count
    renderer.prepare(api)

    texcoords = api.created.fetch(0).fetch(:texcoords)
    assert_equal 1, texcoords.each_slice(2).to_a.uniq.length
    assert_equal 255, api.textures.fetch(0).fetch(:pixels).getbyte(0)
  end

  def test_faces_with_different_texture_names_share_lightmap_mesh
    map = square_map(extra_face: true, extra_texture_name: "OTHER_TEXTURE")
    map = map.with(models: [map.world_model.with(face_count: 2)].freeze)
    renderer = Aogera::Render::BSP29World.new(map: map)
    api = FakeAPI.new

    renderer.prepare(api)

    assert_equal 4, renderer.triangle_count
    assert_equal 1, renderer.batch_count
    assert_equal 1, api.created.length
    assert_equal 1, api.textures.length
  end

  def test_prepare_is_idempotent_and_close_unloads_model_and_texture_once
    renderer = Aogera::Render::BSP29World.new(map: square_map)
    api = FakeAPI.new

    renderer.prepare(api)
    renderer.prepare(api)
    renderer.close(api)
    renderer.close(api)

    assert_equal 1, api.created.length
    assert_equal 1, api.textures.length
    assert_equal 1, api.unloaded.length
    assert_equal 1, api.unloaded_textures.length
    refute renderer.prepared?
  end

  def test_prepare_failure_while_creating_model_releases_created_texture
    renderer = Aogera::Render::BSP29World.new(map: square_map)
    api = FakeAPI.new(fail_on: :create_static_model)

    error = assert_raises(RuntimeError) { renderer.prepare(api) }

    assert_match(/create_static_model failed/, error.message)
    assert_equal 1, api.textures.length
    assert_empty api.created
    assert_empty api.unloaded
    assert_equal [api.textures.first.fetch(:handle)], api.unloaded_textures
    refute renderer.prepared?
  end

  def test_prepare_failure_while_attaching_texture_releases_model_and_texture
    renderer = Aogera::Render::BSP29World.new(map: square_map)
    api = FakeAPI.new(fail_on: :set_model_texture)

    error = assert_raises(RuntimeError) { renderer.prepare(api) }

    assert_match(/set_model_texture failed/, error.message)
    model = api.created.first.fetch(:handle)
    texture = api.textures.first.fetch(:handle)
    assert_equal [model], api.unloaded
    assert_equal [texture], api.unloaded_textures
    refute renderer.prepared?

    retry_api = FakeAPI.new
    renderer.prepare(retry_api)
    assert renderer.prepared?
  end

  def test_draw_requires_prepared_gpu_resources
    renderer = Aogera::Render::BSP29World.new(map: square_map)

    error = assert_raises(RuntimeError) { renderer.draw(FakeAPI.new) }

    assert_match(/not prepared/, error.message)
  end

  def test_only_world_model_zero_faces_are_batched
    renderer = Aogera::Render::BSP29World.new(map: square_map(extra_face: true))

    assert_equal 2, renderer.triangle_count
  end

  def test_rejects_negative_cross_reference_indices
    map = square_map
    bad_face = map.faces.first.with(texinfo_index: -1)
    bad_map = map.with(faces: [bad_face].freeze)

    error = assert_raises(Aogera::BSP29::FormatError) do
      Aogera::Render::BSP29World.new(map: bad_map)
    end

    assert_match(/texinfo index is out of range: -1/, error.message)
  end

  def test_rejects_lightmap_data_outside_lighting_lump
    map = square_map(size: 32.0, light_offset: 2, lighting: "\x01\x02\x03".b)

    error = assert_raises(Aogera::BSP29::FormatError) do
      Aogera::Render::BSP29World.new(map: map)
    end

    assert_match(/face lightmap is outside lighting lump/, error.message)
  end

  private

  def square_map(
    extra_face: false,
    extra_texture_name: nil,
    size: 1.0,
    light_offset: -1,
    lighting: "".b
  )
    vec = Aogera::BSP29::Vec3
    face = Aogera::BSP29::Face.new(
      plane_index: 0,
      side: 0,
      first_edge: 0,
      edge_count: 4,
      texinfo_index: 0,
      styles: [0, 255, 255, 255].freeze,
      light_offset: light_offset
    )
    faces = [face]
    texinfo = [
      Aogera::BSP29::TexInfo.new(
        s_axis: vec.new(x: 1.0, y: 0.0, z: 0.0),
        s_offset: 0.0,
        t_axis: vec.new(x: 0.0, y: 0.0, z: 1.0),
        t_offset: 0.0,
        texture_index: 0,
        flags: 0
      )
    ]
    textures = [mip_texture("AOG_GROUND")]

    if extra_face
      extra_texinfo_index = 0
      if extra_texture_name
        textures << mip_texture(extra_texture_name)
        texinfo << texinfo.first.with(texture_index: 1)
        extra_texinfo_index = 1
      end
      faces << face.with(first_edge: 0, texinfo_index: extra_texinfo_index)
    end

    Aogera::BSP29::MapData.new(
      entities: [].freeze,
      planes: [
        Aogera::BSP29::Plane.new(
          normal: vec.new(x: 0.0, y: 1.0, z: 0.0),
          distance: 0.0,
          type: 1
        )
      ].freeze,
      textures: textures.freeze,
      vertices: [
        vec.new(x: 0.0, y: 0.0, z: 0.0),
        vec.new(x: size, y: 0.0, z: 0.0),
        vec.new(x: size, y: 0.0, z: size),
        vec.new(x: 0.0, y: 0.0, z: size)
      ].freeze,
      visibility: "".b.freeze,
      nodes: [].freeze,
      texinfo: texinfo.freeze,
      faces: faces.freeze,
      lighting: lighting.b.freeze,
      clipnodes: [].freeze,
      leaves: [].freeze,
      marksurfaces: [].freeze,
      edges: [
        Aogera::BSP29::Edge.new(vertex_indices: [0, 1].freeze),
        Aogera::BSP29::Edge.new(vertex_indices: [1, 2].freeze),
        Aogera::BSP29::Edge.new(vertex_indices: [2, 3].freeze),
        Aogera::BSP29::Edge.new(vertex_indices: [3, 0].freeze)
      ].freeze,
      surfedges: [0, 1, 2, 3].freeze,
      models: [
        Aogera::BSP29::Model.new(
          bounds: Aogera::BSP29::Bounds.new(
            mins: vec.new(x: 0.0, y: 0.0, z: 0.0),
            maxs: vec.new(x: size, y: 0.0, z: size)
          ),
          origin: vec.new(x: 0.0, y: 0.0, z: 0.0),
          headnodes: [0, 0, 0, 0].freeze,
          visible_leaf_count: 0,
          first_face: 0,
          face_count: 1
        )
      ].freeze
    )
  end

  def mip_texture(name)
    Aogera::BSP29::MipTexture.new(
      name: name,
      width: 16,
      height: 16,
      mipmaps: ["".b, "".b, "".b, "".b].freeze
    )
  end

  def cross_y_from_flat(values)
    ax, _ay, az, bx, _by, bz, cx, _cy, cz = values
    ab_x = bx - ax
    ab_z = bz - az
    ac_x = cx - ax
    ac_z = cz - az
    (ab_z * ac_x) - (ab_x * ac_z)
  end
end
