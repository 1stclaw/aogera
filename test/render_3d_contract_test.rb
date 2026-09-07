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
    def draw_rectangle(**options) = @calls << [:draw_rectangle, options]
    def draw_text(**options) = @calls << [:draw_text, options]
    def screen_width = 1024
    def screen_height = 768
  end

  def test_first_person_camera_uses_continuous_ground_position_and_y_up
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1, y: 2),
      ground_position: Aogera::Component::GroundPosition.new(x: 1.25, z: 2.75),
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

  def test_first_person_view_rotates_camera_target_without_raylib_state
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1, y: 1),
      ground_position: Aogera::Component::GroundPosition.new(x: 1.5, z: 1.5)
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
      position: Aogera::Component::Position.new(x: 0, y: 0),
      ground_position: Aogera::Component::GroundPosition.new(x: 0.5, z: 0.5)
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

    assert_in_delta(-0.04, floor[:y])
    assert_in_delta(0.08, floor[:height])
    assert_in_delta(0.5, wall[:y])
    assert_in_delta(1.0, wall[:height])
  end

  def test_camera_entity_is_hidden_but_other_renderable_entities_are_drawn
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 0, y: 0),
      ground_position: Aogera::Component::GroundPosition.new(x: 0.5, z: 0.5),
      renderable: Aogera::Component::Renderable.new(
        render_key: :player,
        glyph: "P",
        layer: 10
      )
    )
    world.spawn(
      position: Aogera::Component::Position.new(x: 1, y: 0),
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

  def test_entities_without_renderable_component_are_not_drawn
    api = FakeAPI.new
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 0, y: 0),
      ground_position: Aogera::Component::GroundPosition.new(x: 0.5, z: 0.5)
    )
    world.spawn(position: Aogera::Component::Position.new(x: 0, y: 0))

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
end
