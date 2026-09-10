# frozen_string_literal: true

require_relative "test_helper"

class BSP29PointGroundSpaceTest < Minitest::Test
  FakePointHull = Struct.new(:result, :calls) do
    def trace(**arguments)
      calls << arguments
      result
    end
  end

  def setup
    @world = Aogera::World.new
    @level = wall_level
  end

  def test_point_hull_replaces_grid_static_collision_for_zero_radius_trace
    hull = fake_hull(clear_point_trace(4.5, 16.0, 1.5))
    space = Aogera::GroundSpace.new(bsp29_point_hull: hull)

    trace = space.trace_segment(
      level: @level,
      world: @world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5
    )

    assert_predicate(trace, :clear?)
    assert_equal(1, hull.calls.length)
    start_position = hull.calls.first.fetch(:start_position)
    end_position = hull.calls.first.fetch(:end_position)
    assert_equal(vec(1.5, 16.0, 1.5), start_position)
    assert_equal(vec(4.5, 16.0, 1.5), end_position)
  end

  def test_point_hull_trace_uses_ground_y_plus_action_height
    hull = fake_hull(clear_point_trace(4.5, 21.0, 1.5))
    space = Aogera::GroundSpace.new(bsp29_point_hull: hull)

    space.trace_segment(
      level: @level,
      world: @world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5,
      ground_y: 5.0
    )

    start_position = hull.calls.first.fetch(:start_position)
    assert_in_delta(21.0, start_position.y)
    assert_in_delta(16.0, Aogera::GroundSpace::BSP29_OBSTRUCTION_HEIGHT)
  end

  def test_point_hull_hit_is_adapted_to_ground_trace
    hull = fake_hull(
      point_trace(
        fraction: 0.5,
        x: 3.0,
        y: 16.0,
        z: 1.5,
        normal_x: -1.0,
        normal_z: 0.0
      )
    )
    space = Aogera::GroundSpace.new(bsp29_point_hull: hull)

    trace = space.trace_segment(
      level: @level,
      world: @world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5
    )

    assert_predicate(trace, :hit?)
    assert(trace.world_hit)
    assert_in_delta(0.5, trace.fraction)
    assert_in_delta(3.0, trace.end_x)
    assert_in_delta(-1.0, trace.normal_x)
  end

  def test_dynamic_actor_can_be_earlier_than_bsp_point_world_hit
    hull = fake_hull(
      point_trace(
        fraction: 0.8,
        x: 3.9,
        y: 16.0,
        z: 1.5,
        normal_x: -1.0,
        normal_z: 0.0
      )
    )
    space = Aogera::GroundSpace.new(bsp29_point_hull: hull)
    blocker_id = @world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.25)
    )

    trace = space.trace_segment(
      level: @level,
      world: @world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5,
      entity_filter: ->(entity_id) { entity_id == blocker_id }
    )

    assert_equal(blocker_id, trace.entity_id)
    refute(trace.world_hit)
    assert_operator(trace.fraction, :<, 0.8)
  end

  def test_positive_radius_sweep_does_not_use_point_hull
    hull = fake_hull(clear_point_trace(4.5, 16.0, 1.5))
    space = Aogera::GroundSpace.new(bsp29_point_hull: hull)

    trace = space.sweep_circle(
      level: @level,
      world: @world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5,
      radius: 0.25
    )

    assert_predicate(trace, :hit?)
    assert(trace.world_hit)
    assert_empty(hull.calls)
  end

  private

  def fake_hull(result)
    FakePointHull.new(result, [])
  end

  def clear_point_trace(x, y, z)
    Aogera::BSP29::PointHull::Trace.new(
      fraction: 1.0,
      end_position: vec(x, y, z),
      plane_normal: nil,
      start_solid: false,
      all_solid: false
    )
  end

  def point_trace(fraction:, x:, y:, z:, normal_x:, normal_z:)
    Aogera::BSP29::PointHull::Trace.new(
      fraction: fraction,
      end_position: vec(x, y, z),
      plane_normal: vec(normal_x, 0.0, normal_z),
      start_solid: false,
      all_solid: false
    )
  end

  def vec(x, y, z)
    Aogera::BSP29::Vec3.new(x: Float(x), y: Float(y), z: Float(z))
  end

  def wall_level
    tiles = {
      " " => Aogera::Level::Tile.new(render_key: :ground, glyph: " ", passable: true),
      "|" => Aogera::Level::Tile.new(render_key: :wall, glyph: "|", passable: false)
    }.freeze

    Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(
        cell_size: 1.0,
        rows: ["     ", "  |  ", "     "],
        tiles: tiles
      ),
      spawns: [],
      relations: []
    )
  end
end
