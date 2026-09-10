# frozen_string_literal: true

require_relative "test_helper"

class BSP29RenderTest < Minitest::Test
  class FakeAPI
    attr_reader :calls

    def initialize
      @calls = []
    end

    def draw_triangle_3d(**options)
      @calls << options
    end
  end

  def test_world_model_faces_are_reconstructed_and_triangulated
    map = square_map
    renderer = Aogera::Render::BSP29World.new(map: map)
    api = FakeAPI.new

    renderer.draw(api)

    assert_equal 2, renderer.triangles.length
    assert_equal 2, api.calls.length
    assert_equal [82, 76, 62, 255], api.calls.first.fetch(:rgba)

    api.calls.each do |triangle|
      a = triangle.fetch(:a)
      b = triangle.fetch(:b)
      c = triangle.fetch(:c)
      normal_y = cross_y(a, b, c)
      assert_operator normal_y, :>, 0.0
    end
  end

  def test_only_world_model_zero_faces_are_drawn
    map = square_map(extra_face: true)
    renderer = Aogera::Render::BSP29World.new(map: map)

    assert_equal 2, renderer.triangles.length
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

  def test_preserves_missing_texture_directory_entries
    map = square_map
    bad_texinfo = map.texinfo.first.with(texture_index: 1)
    map_with_missing_texture = map.with(
      texinfo: [bad_texinfo].freeze,
      textures: [map.textures.first, nil].freeze
    )

    renderer = Aogera::Render::BSP29World.new(map: map_with_missing_texture)

    assert_nil renderer.triangles.first.texture_name
  end

  private

  def square_map(extra_face: false)
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
    if extra_face
      faces << face.with(first_edge: 0)
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
      textures: [
        Aogera::BSP29::MipTexture.new(
          name: "AOG_GROUND",
          width: 16,
          height: 16,
          mipmaps: ["".b, "".b, "".b, "".b].freeze
        )
      ].freeze,
      vertices: [
        vec.new(x: 0.0, y: 0.0, z: 0.0),
        vec.new(x: 1.0, y: 0.0, z: 0.0),
        vec.new(x: 1.0, y: 0.0, z: 1.0),
        vec.new(x: 0.0, y: 0.0, z: 1.0)
      ].freeze,
      visibility: "".b.freeze,
      nodes: [].freeze,
      texinfo: [
        Aogera::BSP29::TexInfo.new(
          s_axis: vec.new(x: 1.0, y: 0.0, z: 0.0),
          s_offset: 0.0,
          t_axis: vec.new(x: 0.0, y: 0.0, z: 1.0),
          t_offset: 0.0,
          texture_index: 0,
          flags: 0
        )
      ].freeze,
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

  def cross_y(a, b, c)
    ab_x = b[0] - a[0]
    ab_z = b[2] - a[2]
    ac_x = c[0] - a[0]
    ac_z = c[2] - a[2]
    (ab_z * ac_x) - (ab_x * ac_z)
  end
end
