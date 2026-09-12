# frozen_string_literal: true

require_relative "test_helper"

class BSP29RenderTest < Minitest::Test
  class FakeAPI
    attr_reader :created, :textures, :textured, :drawn, :unloaded,
      :unloaded_textures, :shaders, :shader_assignments, :wraps, :unloaded_shaders

    def initialize(fail_on: nil)
      @fail_on = fail_on
      @created = []
      @textures = []
      @textured = []
      @drawn = []
      @unloaded = []
      @unloaded_textures = []
      @shaders = []
      @shader_assignments = []
      @wraps = []
      @unloaded_shaders = []
    end

    def create_static_model(vertices:, texcoords: nil, texcoords2: nil)
      raise "create_static_model failed" if @fail_on == :create_static_model

      handle = [:model, @created.length]
      @created << {
        handle: handle,
        vertices: vertices,
        texcoords: texcoords,
        texcoords2: texcoords2
      }
      handle
    end

    def create_texture_rgba(width:, height:, pixels:)
      handle = [:texture, @textures.length]
      @textures << {handle: handle, width: width, height: height, pixels: pixels}
      handle
    end

    def create_shader(vertex_source:, fragment_source:)
      raise "create_shader failed" if @fail_on == :create_shader

      handle = [:shader, @shaders.length]
      @shaders << {
        handle: handle,
        vertex_source: vertex_source,
        fragment_source: fragment_source
      }
      handle
    end

    def set_model_shader(model:, shader:)
      raise "set_model_shader failed" if @fail_on == :set_model_shader

      @shader_assignments << {model: model, shader: shader}
    end

    def set_model_texture(model:, texture:, slot: :albedo)
      raise "set_model_texture failed" if @fail_on == :set_model_texture

      @textured << {model: model, texture: texture, slot: slot}
    end

    def set_texture_wrap(texture:, mode:)
      raise "set_texture_wrap failed" if @fail_on == :set_texture_wrap

      @wraps << {texture: texture, mode: mode}
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

    def unload_shader(shader)
      @unloaded_shaders << shader
    end
  end

  def test_world_model_faces_are_reconstructed_into_one_textured_mesh
    renderer = Aogera::Render::BSP29World.new(map: square_map)
    api = FakeAPI.new

    assert_equal 1, renderer.world_face_count
    assert_equal 1, renderer.world_surface_count
    assert_equal 0, renderer.dropped_surface_count
    assert_equal 1, renderer.reversed_surface_count
    assert_equal 2, renderer.source_triangle_count
    assert_equal 0, renderer.degenerate_triangle_count
    refute renderer.two_sided?
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

  def test_two_sided_diagnostic_submits_reversed_copy_of_each_triangle
    renderer = Aogera::Render::BSP29World.new(map: square_map, two_sided: true)
    api = FakeAPI.new

    assert renderer.two_sided?
    assert_equal 2, renderer.source_triangle_count
    assert_equal 4, renderer.triangle_count

    renderer.prepare(api)
    triangles = api.created.first.fetch(:vertices).each_slice(9).to_a

    assert_equal 4, triangles.length
    assert_operator cross_y_from_flat(triangles.fetch(0)), :>, 0.0
    assert_operator cross_y_from_flat(triangles.fetch(1)), :<, 0.0
    assert_equal triangles.fetch(0).each_slice(3).to_a.sort,
      triangles.fetch(1).each_slice(3).to_a.sort
  end


  def test_surface_builder_reverses_full_quake_winding_when_leading_vertices_are_collinear
    prepared = Aogera::Render::BSP29SurfaceBuilder.build(tjunction_winding_map(side: 0))
    surface = prepared.surfaces.fetch(0)
    diagnostics = prepared.diagnostics

    assert_equal 1, diagnostics.reversed_face_count
    assert_equal 3, diagnostics.source_triangle_count
    assert_equal 0, diagnostics.degenerate_triangle_count
    first_triangle = surface.positions.each_slice(3).take(3).flatten
    assert_operator cross_y_from_flat(first_triangle), :>, 0.0
  end

  def test_surface_builder_converts_planeback_quake_winding_for_raylib
    prepared = Aogera::Render::BSP29SurfaceBuilder.build(tjunction_winding_map(side: 1))
    surface = prepared.surfaces.fetch(0)
    diagnostics = prepared.diagnostics

    assert_equal 1, diagnostics.reversed_face_count
    assert_equal 3, diagnostics.source_triangle_count
    assert_equal 0, diagnostics.degenerate_triangle_count
    first_triangle = surface.positions.each_slice(3).take(3).flatten
    assert_operator cross_y_from_flat(first_triangle), :<, 0.0
  end

  def test_surface_builder_counts_world_faces_dropped_before_mesh_preparation
    map = square_map
    short_face = map.faces.first.with(edge_count: 2)
    map = map.with(faces: [short_face].freeze)

    prepared = Aogera::Render::BSP29SurfaceBuilder.build(map)
    diagnostics = prepared.diagnostics

    assert_equal 1, diagnostics.world_face_count
    assert_equal 0, diagnostics.prepared_surface_count
    assert_equal 1, diagnostics.dropped_face_count
    assert_equal 0, diagnostics.source_triangle_count
    assert_equal 0, diagnostics.degenerate_triangle_count
    assert_empty prepared.surfaces
  end

  def test_baked_light_samples_build_grayscale_atlas_and_uvs
    lighting = [0, 16, 32, 48, 64, 80, 96, 112, 127].pack("C*")
    renderer = Aogera::Render::BSP29World.new(
      map: square_map(size: 32.0, light_offset: 0, lighting: lighting)
    )
    api = FakeAPI.new

    assert_equal 1, renderer.lightmapped_face_count
    assert_equal 8, renderer.lightmap_atlas_width
    assert_equal 8, renderer.lightmap_atlas_height

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
    assert_equal [
      0.3125, 0.5625,
      0.5625, 0.5625,
      0.5625, 0.3125,
      0.3125, 0.5625,
      0.5625, 0.3125,
      0.3125, 0.3125
    ], texcoords
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

  def test_palette_enables_separate_base_textures_and_shared_low_resolution_lightmap
    map = square_map(
      extra_face: true,
      extra_texture_name: "OTHER_TEXTURE",
      size: 64.0,
      light_offset: 0,
      lighting: ([64] * 36).pack("C*")
    )
    map = map.with(models: [map.world_model.with(face_count: 2)].freeze)
    renderer = Aogera::Render::BSP29World.new(map: map, palette: test_palette)
    api = FakeAPI.new

    renderer.prepare(api)

    assert renderer.textured?
    assert_equal 2, renderer.world_surface_count
    assert_equal 0, renderer.brush_submodel_count
    assert_equal 2, renderer.used_texture_count
    assert_equal 0, renderer.missing_texture_face_count
    assert_equal 4, renderer.triangle_count
    assert_equal 2, renderer.batch_count
    assert_equal 2, api.created.length
    assert_equal 3, api.textures.length
    assert_equal 1, api.shaders.length
    assert_equal 2, api.shader_assignments.length

    lightmap = api.textures.fetch(0)
    assert_equal renderer.lightmap_atlas_width, lightmap.fetch(:width)
    assert_equal renderer.lightmap_atlas_height, lightmap.fetch(:height)
    assert_equal({texture: lightmap.fetch(:handle), mode: :clamp}, api.wraps.fetch(0))
    assert_equal [:repeat, :repeat], api.wraps.drop(1).map { |entry| entry.fetch(:mode) }

    api.created.each do |created|
      assert_equal 12, created.fetch(:texcoords).length
      assert_equal 12, created.fetch(:texcoords2).length
      assert_operator created.fetch(:texcoords).max, :>, 1.0
      created.fetch(:texcoords2).each do |coordinate|
        assert_operator coordinate, :>, 0.0
        assert_operator coordinate, :<, 1.0
      end
    end

    assert_equal 2, api.textured.count { |entry| entry.fetch(:slot) == :albedo }
    lightmap_bindings = api.textured.select { |entry| entry.fetch(:slot) == :lightmap }
    assert_equal 2, lightmap_bindings.length
    assert_equal [lightmap.fetch(:handle)], lightmap_bindings.map { |entry| entry.fetch(:texture) }.uniq

    renderer.close(api)
    assert_equal 2, api.unloaded.length
    assert_equal 3, api.unloaded_textures.length
    assert_equal 1, api.unloaded_shaders.length
  end

  def test_textured_missing_texture_slot_uses_one_white_fallback_base_texture
    map = square_map
    map = map.with(texinfo: [map.texinfo.first.with(texture_index: 99)].freeze)
    renderer = Aogera::Render::BSP29World.new(map: map, palette: test_palette)
    api = FakeAPI.new

    renderer.prepare(api)

    assert_equal 1, renderer.batch_count
    assert_equal 0, renderer.used_texture_count
    assert_equal 1, renderer.missing_texture_face_count
    assert_equal 2, api.textures.length
    fallback = api.textures.fetch(1)
    assert_equal 1, fallback.fetch(:width)
    assert_equal 1, fallback.fetch(:height)
    assert_equal [255, 255, 255, 255], fallback.fetch(:pixels).bytes
    assert_equal Array.new(12, 0.0), api.created.first.fetch(:texcoords)
  end

  def test_prepare_failure_while_configuring_lightmap_wrap_releases_texture
    renderer = Aogera::Render::BSP29World.new(
      map: square_map,
      palette: test_palette
    )
    api = FakeAPI.new(fail_on: :set_texture_wrap)

    error = assert_raises(RuntimeError) { renderer.prepare(api) }

    assert_match(/set_texture_wrap failed/, error.message)
    assert_equal 1, api.textures.length
    assert_equal [api.textures.first.fetch(:handle)], api.unloaded_textures
    assert_empty api.created
    assert_empty api.shaders
    refute renderer.prepared?
  end

  def test_textured_prepare_failure_after_shader_assignment_cleans_every_gpu_resource
    renderer = Aogera::Render::BSP29World.new(
      map: square_map,
      palette: test_palette
    )
    api = FakeAPI.new(fail_on: :set_model_shader)

    error = assert_raises(RuntimeError) { renderer.prepare(api) }

    assert_match(/set_model_shader failed/, error.message)
    assert_equal 1, api.created.length
    assert_equal 2, api.textures.length
    assert_equal 1, api.shaders.length
    assert_equal [api.created.first.fetch(:handle)], api.unloaded
    assert_equal api.textures.map { |texture| texture.fetch(:handle) }.reverse, api.unloaded_textures
    assert_equal [api.shaders.first.fetch(:handle)], api.unloaded_shaders
    refute renderer.prepared?
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

  def test_renderer_reports_preserved_but_unrendered_brush_submodels
    map = square_map
    submodel = map.world_model.with(first_face: 0, face_count: 0)
    map = map.with(models: [map.world_model, submodel].freeze)

    renderer = Aogera::Render::BSP29World.new(map: map)

    assert_equal 1, renderer.world_surface_count
    assert_equal 1, renderer.brush_submodel_count
  end

  def test_only_world_model_zero_faces_are_batched
    renderer = Aogera::Render::BSP29World.new(map: square_map(extra_face: true))

    assert_equal 2, renderer.triangle_count
  end

  def test_rejects_negative_face_plane_index_after_winding_conversion_refactor
    map = square_map
    bad_face = map.faces.first.with(plane_index: -1)
    bad_map = map.with(faces: [bad_face].freeze)

    error = assert_raises(Aogera::BSP29::FormatError) do
      Aogera::Render::BSP29World.new(map: bad_map)
    end

    assert_match(/plane index is out of range: -1/, error.message)
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

  def test_surface_builder_prepares_stable_face_level_buffers
    map = square_map(texinfo_flags: 7)
    prepared = Aogera::Render::BSP29SurfaceBuilder.build(map)
    surface = prepared.surfaces.fetch(0)

    assert_predicate prepared.surfaces, :frozen?
    assert_same map.lighting, prepared.lighting
    assert_equal 0, surface.face_index
    assert_equal 12, surface.positions.length
    assert_equal 8, surface.texture_st.length
    assert_predicate surface.positions, :frozen?
    assert_predicate surface.texture_st, :frozen?
    assert_equal 0, surface.texture_index
    assert_equal "AOG_GROUND", surface.texture_name
    assert_equal 7, surface.texinfo_flags
    assert_nil surface.lightmap
    assert_nil surface.lightmap_st
  end

  def test_surface_builder_preserves_unwrapped_texture_and_local_lightmap_coordinates
    lighting = ([32] * 36).pack("C*").freeze
    prepared = Aogera::Render::BSP29SurfaceBuilder.build(
      square_map(
        size: 64.0,
        light_offset: 0,
        lighting: lighting,
        s_offset: -24.0,
        t_offset: 8.0
      )
    )
    surface = prepared.surfaces.fetch(0)
    lightmap = surface.lightmap

    assert_equal [
      -24.0, 72.0,
      40.0, 72.0,
      40.0, 8.0,
      -24.0, 8.0
    ], surface.texture_st
    assert_equal(-2, lightmap.min_s)
    assert_equal 0, lightmap.min_t
    assert_equal 6, lightmap.width
    assert_equal 6, lightmap.height
    assert_equal [
      0.5, 4.5,
      4.5, 4.5,
      4.5, 0.5,
      0.5, 0.5
    ], surface.lightmap_st
    assert_predicate surface.lightmap_st, :frozen?
  end

  def test_texture_mapping_normalizes_but_does_not_wrap_quake_texture_coordinates
    map = square_map(
      size: 64.0,
      s_offset: -24.0,
      t_offset: 8.0
    )
    prepared = Aogera::Render::BSP29SurfaceBuilder.build(map)
    surface = prepared.surfaces.fetch(0)
    texture = map.textures.fetch(surface.texture_index)

    uvs = Aogera::Render::BSP29TextureMapping.normalized_uv(surface, texture)

    assert_equal [
      -1.5, 4.5,
      2.5, 4.5,
      2.5, 0.5,
      -1.5, 0.5
    ], uvs
    assert_predicate uvs, :frozen?
    assert_operator uvs.min, :<, 0.0
    assert_operator uvs.max, :>, 1.0
  end

  def test_surface_builder_preserves_all_light_styles_by_offset_into_one_lighting_blob
    lighting = (0...10).to_a.pack("C*").freeze
    map = square_map(
      size: 16.0,
      light_offset: 2,
      lighting: lighting,
      styles: [0, 1, 255, 255].freeze
    )
    prepared = Aogera::Render::BSP29SurfaceBuilder.build(map)
    lightmap = prepared.surfaces.fetch(0).lightmap

    assert_same map.lighting, prepared.lighting
    assert_equal [0, 1], lightmap.styles
    assert_equal 2, lightmap.light_offset
    assert_equal 2, lightmap.width
    assert_equal 2, lightmap.height
  end

  def test_surface_builder_keeps_missing_texture_reference_observable
    map = square_map
    bad_texinfo = map.texinfo.first.with(texture_index: 99, flags: 1)
    map = map.with(texinfo: [bad_texinfo].freeze)

    surface = Aogera::Render::BSP29SurfaceBuilder.build(map).surfaces.fetch(0)

    assert_equal 99, surface.texture_index
    assert_nil surface.texture_name
    assert_equal 1, surface.texinfo_flags
  end

  private


  def tjunction_winding_map(side:)
    vec = Aogera::BSP29::Vec3
    vertices = [
      vec.new(x: 0.0, y: 0.0, z: 0.0),
      vec.new(x: 1.0, y: 0.0, z: 0.0),
      vec.new(x: 2.0, y: 0.0, z: 0.0),
      vec.new(x: 2.0, y: 0.0, z: 2.0),
      vec.new(x: 0.0, y: 0.0, z: 2.0)
    ].freeze
    edges = [
      Aogera::BSP29::Edge.new(vertex_indices: [0, 0].freeze),
      Aogera::BSP29::Edge.new(vertex_indices: [0, 1].freeze),
      Aogera::BSP29::Edge.new(vertex_indices: [1, 2].freeze),
      Aogera::BSP29::Edge.new(vertex_indices: [2, 3].freeze),
      Aogera::BSP29::Edge.new(vertex_indices: [3, 4].freeze),
      Aogera::BSP29::Edge.new(vertex_indices: [4, 0].freeze)
    ].freeze
    surfedges = side.zero? ? [1, 2, 3, 4, 5] : [-5, -4, -3, -2, -1]

    Aogera::BSP29::MapData.new(
      entities: [].freeze,
      planes: [
        Aogera::BSP29::Plane.new(
          normal: vec.new(x: 0.0, y: 1.0, z: 0.0),
          distance: 0.0,
          type: 1
        )
      ].freeze,
      textures: [mip_texture("AOG_GROUND")].freeze,
      vertices: vertices,
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
      faces: [
        Aogera::BSP29::Face.new(
          plane_index: 0,
          side: side,
          first_edge: 0,
          edge_count: 5,
          texinfo_index: 0,
          styles: [0, 255, 255, 255].freeze,
          light_offset: -1
        )
      ].freeze,
      lighting: "".b.freeze,
      clipnodes: [].freeze,
      leaves: [].freeze,
      marksurfaces: [].freeze,
      edges: edges,
      surfedges: surfedges.freeze,
      models: [
        Aogera::BSP29::Model.new(
          bounds: Aogera::BSP29::Bounds.new(
            mins: vec.new(x: 0.0, y: 0.0, z: 0.0),
            maxs: vec.new(x: 2.0, y: 0.0, z: 2.0)
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

  def square_map(
    extra_face: false,
    extra_texture_name: nil,
    size: 1.0,
    light_offset: -1,
    lighting: "".b,
    s_offset: 0.0,
    t_offset: 0.0,
    texinfo_flags: 0,
    styles: [0, 255, 255, 255].freeze
  )
    vec = Aogera::BSP29::Vec3
    face = Aogera::BSP29::Face.new(
      plane_index: 0,
      side: 0,
      first_edge: 0,
      edge_count: 4,
      texinfo_index: 0,
      styles: styles,
      light_offset: light_offset
    )
    faces = [face]
    texinfo = [
      Aogera::BSP29::TexInfo.new(
        s_axis: vec.new(x: 1.0, y: 0.0, z: 0.0),
        s_offset: s_offset,
        t_axis: vec.new(x: 0.0, y: 0.0, z: 1.0),
        t_offset: t_offset,
        texture_index: 0,
        flags: texinfo_flags
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
      mipmaps: [
        ([1] * 256).pack("C*").freeze,
        ([1] * 64).pack("C*").freeze,
        ([1] * 16).pack("C*").freeze,
        ([1] * 4).pack("C*").freeze
      ].freeze
    )
  end

  def test_palette
    bytes = String.new(capacity: Aogera::Quake::PaletteReader::BYTE_SIZE, encoding: Encoding::BINARY)
    256.times do |index|
      bytes << index
      bytes << (255 - index)
      bytes << (index / 2)
    end
    Aogera::Quake::PaletteReader.read_bytes(bytes)
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
