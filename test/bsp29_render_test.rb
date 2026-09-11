# frozen_string_literal: true

require_relative "test_helper"

class BSP29RenderTest < Minitest::Test
  class FakeAPI
    attr_reader :created, :drawn, :unloaded

    def initialize
      @created = []
      @drawn = []
      @unloaded = []
    end

    def create_static_model(vertices:)
      handle = [:model, @created.length]
      @created << {handle: handle, vertices: vertices}
      handle
    end

    def draw_model(model:, rgba:)
      @drawn << {model: model, rgba: rgba}
    end

    def unload_model(model)
      @unloaded << model
    end
  end

  def test_world_model_faces_are_reconstructed_batched_and_uploaded_once
    renderer = Aogera::Render::BSP29World.new(map: square_map)
    api = FakeAPI.new

    assert_equal 2, renderer.triangle_count
    assert_equal 1, renderer.batches.length
    assert_equal 1, renderer.batch_count
    assert_equal 18, renderer.batches.first.vertices.length
    assert_equal [82, 76, 62, 255], renderer.batches.first.rgba

    renderer.prepare(api)
    renderer.draw(api)
    renderer.draw(api)

    assert_equal 1, api.created.length
    assert_equal 2, api.drawn.length
    assert_equal api.created.first.fetch(:handle), api.drawn.first.fetch(:model)
    assert_equal [82, 76, 62, 255], api.drawn.first.fetch(:rgba)

    triangles = api.created.first.fetch(:vertices).each_slice(9).to_a
    triangles.each do |triangle|
      assert_operator cross_y_from_flat(triangle), :>, 0.0
    end
  end

  def test_prepare_groups_faces_by_diagnostic_color_not_texture_name
    map = square_map(extra_face: true, extra_texture_name: "OTHER_TEXTURE")
    map = map.with(models: [map.world_model.with(face_count: 2)].freeze)
    renderer = Aogera::Render::BSP29World.new(map: map)
    api = FakeAPI.new

    renderer.prepare(api)

    assert_equal 4, renderer.triangle_count
    assert_equal 2, renderer.batches.length
    assert_equal 2, api.created.length
  end

  def test_prepare_is_idempotent_and_close_unloads_once
    renderer = Aogera::Render::BSP29World.new(map: square_map)
    api = FakeAPI.new

    renderer.prepare(api)
    renderer.prepare(api)
    renderer.close(api)
    renderer.close(api)

    assert_equal 1, api.created.length
    assert_equal 1, api.unloaded.length
    refute renderer.prepared?
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

  def test_missing_texture_directory_entry_uses_default_batch_color
    map = square_map
    bad_texinfo = map.texinfo.first.with(texture_index: 1)
    map_with_missing_texture = map.with(
      texinfo: [bad_texinfo].freeze,
      textures: [map.textures.first, nil].freeze
    )

    renderer = Aogera::Render::BSP29World.new(map: map_with_missing_texture)

    assert_equal Aogera::Render::BSP29World::DEFAULT_COLOR,
      renderer.batches.first.rgba
  end

  private

  def square_map(extra_face: false, extra_texture_name: nil)
    vec = Aogera::BSP29::Vec3
    face = Aogera::BSP29::Face.new(
      plane_index: 0,
      side: 0,
      first_edge: 0,
      edge_count: 4,
      texinfo_index: 0,
      styles: [0, 255, 255, 255].freeze,
      light_offset: -1
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
        vec.new(x: 1.0, y: 0.0, z: 0.0),
        vec.new(x: 1.0, y: 0.0, z: 1.0),
        vec.new(x: 0.0, y: 0.0, z: 1.0)
      ].freeze,
      visibility: "".b.freeze,
      nodes: [].freeze,
      texinfo: texinfo.freeze,
      faces: faces.freeze,
      lighting: "".b.freeze,
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
            maxs: vec.new(x: 1.0, y: 0.0, z: 1.0)
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
