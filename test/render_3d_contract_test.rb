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

  def test_renderer_uses_y_up_camera_and_maps_grid_y_to_world_z
    api = FakeAPI.new
    world = Aogera::World.new
    world.spawn(
      position: Aogera::Component::Position.new(x: 1, y: 2),
      renderable: Aogera::Component::Renderable.new(
        render_key: :player,
        glyph: "P",
        layer: 10
      )
    )

    Aogera::Render::Raylib3D.new(api: api).draw(
      level: FakeLevel.new(width: 4, height: 4),
      world: world.view,
      status: "test"
    )

    camera = api.calls.find { |call| call.first == :begin_mode_3d }.last
    assert_equal [0.0, 1.0, 0.0], camera[:up]

    entity = api.calls
      .select { |call| call.first == :draw_cube }
      .map(&:last)
      .find { |cube| cube[:height] == Aogera::Render::Raylib3D::ENTITY_HEIGHT }

    assert_in_delta 1.5, entity[:x]
    assert_in_delta 0.4, entity[:y]
    assert_in_delta 2.5, entity[:z]
  end

  def test_wall_tiles_are_vertical_cubes_and_ground_is_a_thin_floor
    api = FakeAPI.new
    level = FakeLevel.new(
      width: 2,
      height: 1,
      tiles: { [1, 0] => :wall }
    )

    Aogera::Render::Raylib3D.new(api: api).draw(
      level: level,
      world: Aogera::World.new.view,
      status: "test"
    )

    cubes = api.calls.select { |call| call.first == :draw_cube }.map(&:last)
    floor = cubes.find { |cube| cube[:x] == 0.5 }
    wall = cubes.find { |cube| cube[:x] == 1.5 }

    assert_in_delta(-0.04, floor[:y])
    assert_in_delta(0.08, floor[:height])
    assert_in_delta(0.5, wall[:y])
    assert_in_delta(1.0, wall[:height])
  end

  def test_entities_without_renderable_component_are_not_drawn
    api = FakeAPI.new
    world = Aogera::World.new
    world.spawn(position: Aogera::Component::Position.new(x: 0, y: 0))

    Aogera::Render::Raylib3D.new(api: api).draw(
      level: FakeLevel.new(width: 1, height: 1),
      world: world.view,
      status: "test"
    )

    cubes = api.calls.select { |call| call.first == :draw_cube }.map(&:last)
    assert_equal 1, cubes.length
    assert_in_delta Aogera::Render::Raylib3D::FLOOR_HEIGHT, cubes.first[:height]
  end
end
