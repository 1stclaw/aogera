# frozen_string_literal: true

require_relative "test_helper"

class Render3DContractTest < Minitest::Test
  class FakeLevel
    attr_reader :width, :height

    def initialize(width:, height:, tiles: {})
      @width = width
      @height = height
      @tiles = tiles
    end

    def render_key_at(x, y)
      @tiles.fetch([x, y], :ground)
    end

    def cell_size = 1.0

    def cell_center(x, y)
      [x + 0.5, y + 0.5]
    end

    def cell_for_world(x, z)
      [x.floor, z.floor]
    end

    def inside?(x, y)
      x >= 0 && y >= 0 && x < width && y < height
    end
  end

  class FakeAPI
    attr_reader :calls

    def initialize
      @calls = []
    end

    def begin_drawing = @calls << [:begin_drawing]
    def end_drawing = @calls << [:end_drawing]
    def clear(rgba) = @calls << [:clear, rgba]
    def begin_mode_3d(**options) = @calls << [:begin_mode_3d, options]
    def end_mode_3d = @calls << [:end_mode_3d]
    def draw_cube(**options) = @calls << [:draw_cube, options]
    def create_static_model(vertices:, texcoords: nil, texcoords2: nil)
      handle = [:model, @calls.count { |call| call.first == :create_static_model }]
      @calls << [:create_static_model, {vertices: vertices, texcoords: texcoords, texcoords2: texcoords2, handle: handle}]
      handle
    end
    def create_texture_rgba(width:, height:, pixels:)
      handle = [:texture, @calls.count { |call| call.first == :create_texture_rgba }]
      @calls << [:create_texture_rgba, {width: width, height: height, pixels: pixels, handle: handle}]
      handle
    end
    def set_model_texture(model:, texture:, slot: :albedo) = @calls << [:set_model_texture, {model: model, texture: texture, slot: slot}]
    def create_shader(vertex_source:, fragment_source:)
      handle = [:shader, @calls.count { |call| call.first == :create_shader }]
      @calls << [:create_shader, {vertex_source: vertex_source, fragment_source: fragment_source, handle: handle}]
      handle
    end
    def set_model_shader(model:, shader:) = @calls << [:set_model_shader, {model: model, shader: shader}]
    def set_texture_wrap(texture:, mode:) = @calls << [:set_texture_wrap, {texture: texture, mode: mode}]
    def unload_shader(shader) = @calls << [:unload_shader, shader]
    def unload_texture(texture) = @calls << [:unload_texture, texture]
    def draw_model(model:, rgba:) = @calls << [:draw_model, {model: model, rgba: rgba}]
    def unload_model(model) = @calls << [:unload_model, model]
    def draw_rectangle(**options) = @calls << [:draw_rectangle, options]
    def draw_text(**options) = @calls << [:draw_text, options]
    def fps = 57
    def screen_width = 1024
    def screen_height = 768
  end

  def test_first_person_camera_uses_canonical_position_and_y_up
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.25, y: 0.0, z: 2.75),
      renderable: Aogera::Component::Renderable.new(
        render_key: :player,
        glyph: "P",
        layer: 10
      )
    )
    view = Aogera::FirstPersonView.for_direction(:north)

    Aogera::Render::Raylib3D.new(api: api).draw(
      level: FakeLevel.new(width: 4, height: 4),
      world: world.view,
      status: "test",
      view: view,
      camera_entity_id: camera_id
    )

    camera = api.calls.find { |call| call.first == :begin_mode_3d }.last
    assert_equal [0.0, 1.0, 0.0], camera[:up]
    assert_equal [1.25, view.eye_height, 2.75], camera[:position]
    assert_in_delta 1.25, camera[:target][0]
    assert_in_delta view.eye_height, camera[:target][1]
    assert_in_delta 1.75, camera[:target][2]
  end

  def test_explicit_camera_eye_bypasses_entity_eye_origin
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 2.0, z: 3.0)
    )
    view = Aogera::FirstPersonView.for_direction(:north)

    Aogera::Render::Raylib3D.new(api: api).draw(
      level: FakeLevel.new(width: 1, height: 1),
      world: world.view,
      status: "test",
      view: view,
      camera_entity_id: camera_id,
      camera_eye: [10.0, 20.0, 30.0]
    )

    camera = api.calls.find { |call| call.first == :begin_mode_3d }.last
    assert_equal [10.0, 20.0, 30.0], camera[:position]
    assert_equal [10.0, 20.0, 29.0], camera[:target]
  end

  def test_first_person_view_rotates_camera_target_without_raylib_state
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5)
    )
    view = Aogera::FirstPersonView.for_direction(:east)

    Aogera::Render::Raylib3D.new(api: api).draw(
      level: FakeLevel.new(width: 3, height: 3),
      world: world.view,
      status: "test",
      view: view,
      camera_entity_id: camera_id
    )

    camera = api.calls.find { |call| call.first == :begin_mode_3d }.last
    assert_in_delta 2.5, camera[:target][0]
    assert_in_delta view.eye_height, camera[:target][1]
    assert_in_delta 1.5, camera[:target][2]
  end

  def test_wall_tiles_are_vertical_cubes_and_ground_is_a_thin_floor
    api = FakeAPI.new
    level = FakeLevel.new(
      width: 2,
      height: 1,
      tiles: { [1, 0] => :wall }
    )
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 0.5, y: 0.0, z: 0.5)
    )

    Aogera::Render::Raylib3D.new(api: api).draw(
      level: level,
      world: world.view,
      status: "test",
      view: Aogera::FirstPersonView.for_direction(:east),
      camera_entity_id: camera_id
    )

    cubes = api.calls.select { |call| call.first == :draw_cube }.map(&:last)
    floor = cubes.find { |cube| cube[:x] == 0.5 }
    wall = cubes.find { |cube| cube[:x] == 1.5 }

    assert_in_delta(-1.28, floor[:y])
    assert_in_delta(2.56, floor[:height])
    assert_in_delta(16.0, wall[:y])
    assert_in_delta(32.0, wall[:height])
  end

  def test_camera_entity_is_hidden_but_other_renderable_entities_are_drawn
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 0.5, y: 0.0, z: 0.5),
      renderable: Aogera::Component::Renderable.new(
        render_key: :player,
        glyph: "P",
        layer: 10
      )
    )
    world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 0.5),
      renderable: Aogera::Component::Renderable.new(
        render_key: :goblin,
        glyph: "G",
        layer: 10
      )
    )

    Aogera::Render::Raylib3D.new(api: api).draw(
      level: FakeLevel.new(width: 2, height: 1),
      world: world.view,
      status: "test",
      view: Aogera::FirstPersonView.for_direction(:east),
      camera_entity_id: camera_id
    )

    entity_cubes = api.calls
      .select { |call| call.first == :draw_cube }
      .map(&:last)
      .select { |cube| cube[:height] == Aogera::Render::Raylib3D::ENTITY_HEIGHT }

    assert_equal 1, entity_cubes.length
    assert_in_delta 1.5, entity_cubes.first[:x]
  end

  def test_grid_renderer_still_clips_entities_outside_level_bounds
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 0.5, y: 0.0, z: 0.5)
    )
    world.spawn(
      position: Aogera::Component::Position.new(x: 4.5, y: 0.0, z: 0.5),
      renderable: Aogera::Component::Renderable.new(
        render_key: :goblin,
        glyph: "G",
        layer: 10
      )
    )

    Aogera::Render::Raylib3D.new(api: api).draw(
      level: FakeLevel.new(width: 2, height: 1),
      world: world.view,
      status: "test",
      view: Aogera::FirstPersonView.for_direction(:east),
      camera_entity_id: camera_id
    )

    entity_cubes = api.calls
      .select { |call| call.first == :draw_cube }
      .map(&:last)
      .select { |cube| cube[:height] == Aogera::Render::Raylib3D::ENTITY_HEIGHT }

    assert_empty entity_cubes
  end

  def test_bsp_renderer_draws_entities_without_consulting_grid_bounds
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 112.0, y: 0.0, z: 112.0)
    )
    world.spawn(
      position: Aogera::Component::Position.new(x: 2048.0, y: 0.0, z: 2048.0),
      renderable: Aogera::Component::Renderable.new(
        render_key: :goblin,
        glyph: "G",
        layer: 10
      )
    )
    renderer = Aogera::Render::Raylib3D.new(api: api, bsp29_map: empty_bsp29_map)
    renderer.prepare
    renderer.draw(
      level: Object.new,
      world: world.view,
      status: "test",
      view: Aogera::FirstPersonView.for_direction(:east),
      camera_entity_id: camera_id
    )

    entity_cubes = api.calls
      .select { |call| call.first == :draw_cube }
      .map(&:last)
      .select { |cube| cube[:height] == Aogera::Render::Raylib3D::ENTITY_HEIGHT }

    assert_equal 1, entity_cubes.length
    assert_in_delta 2048.0, entity_cubes.first[:x]
    assert_in_delta 2048.0, entity_cubes.first[:z]
  end

  def test_bsp_spectator_draws_compact_diagnostic_overlay
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 2.0, z: 3.0)
    )
    world.spawn(position: Aogera::Component::Position.new(x: 4.0, y: 5.0, z: 6.0))
    view = Aogera::FirstPersonView.for_direction(:east)
    renderer = Aogera::Render::Raylib3D.new(api: api, bsp29_map: empty_bsp29_map)
    renderer.prepare

    renderer.draw(
      level: Object.new,
      world: world.view,
      status: "test",
      view: view,
      camera_entity_id: camera_id,
      camera_eye: [10.0, 20.0, 30.0]
    )

    texts = api.calls
      .select { |call| call.first == :draw_text }
      .map { |call| call.last[:text] }

    assert_includes texts, "FPS 57"
    assert_includes texts, "Camera XYZ 10.00  20.00  30.00"
    assert_includes texts, "View yaw 90.0 deg | pitch 0.0 deg"
    assert_includes texts, "BSP 0 tris | 0 mesh draws"
    assert_includes texts, "World 0 surfaces | 0 submodels skipped"
    assert_includes texts, "Base grayscale fallback | 0 missing faces"
    assert_includes texts, "Entities 2"
    assert_equal 2, api.calls.count { |call| call.first == :draw_rectangle }
  end

  def test_entities_without_renderable_component_are_not_drawn
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 0.5, y: 0.0, z: 0.5)
    )
    world.spawn(position: Aogera::Component::Position.new(x: 0.5, y: 0.0, z: 0.5))

    Aogera::Render::Raylib3D.new(api: api).draw(
      level: FakeLevel.new(width: 1, height: 1),
      world: world.view,
      status: "test",
      view: Aogera::FirstPersonView.for_direction(:north),
      camera_entity_id: camera_id
    )

    cubes = api.calls.select { |call| call.first == :draw_cube }.map(&:last)
    assert_equal 1, cubes.length
    assert_in_delta Aogera::Render::Raylib3D::FLOOR_HEIGHT, cubes.first[:height]
  end

  private

  def empty_bsp29_map
    Aogera::BSP29::MapData.new(
      entities: [].freeze,
      planes: [].freeze,
      textures: [].freeze,
      vertices: [].freeze,
      visibility: "".b.freeze,
      nodes: [].freeze,
      texinfo: [].freeze,
      faces: [].freeze,
      lighting: "".b.freeze,
      clipnodes: [].freeze,
      leaves: [].freeze,
      marksurfaces: [].freeze,
      edges: [].freeze,
      surfedges: [].freeze,
      models: [].freeze
    )
  end
end
