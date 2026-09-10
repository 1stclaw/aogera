# frozen_string_literal: true

require_relative "test_helper"

class BSP29GroundSpaceTest < Minitest::Test
  FakeGroundHull = Struct.new(:result, :calls) do
    def trace(**arguments)
      calls << arguments
      result
    end
  end

  def setup
    @world = Aogera::World.new
    @level = wall_level
  end

  def test_bsp_ground_hull_replaces_grid_static_collision_for_swept_movement
    hull = fake_hull(clear_clip_trace(4.5, 1.5))
    space = Aogera::GroundSpace.new(bsp29_ground_hull: hull)

    trace = space.sweep_circle(
      level: @level,
      world: @world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5,
      radius: 0.25
    )

    assert_predicate(trace, :clear?)
    assert_equal(1, hull.calls.length)
  end

  def test_bsp_ground_hit_is_adapted_to_existing_ground_trace
    hull = fake_hull(
      clip_trace(
        fraction: 0.25,
        x: 2.25,
        z: 1.5,
        normal_x: -1.0,
        normal_z: 0.0
      )
    )
    space = Aogera::GroundSpace.new(bsp29_ground_hull: hull)

    trace = space.sweep_circle(
      level: @level,
      world: @world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5,
      radius: 0.25,
      ground_y: 3.0
    )

    assert_predicate(trace, :hit?)
    assert(trace.world_hit)
    assert_in_delta(0.25, trace.fraction)
    assert_in_delta(2.25, trace.end_x)
    assert_in_delta(-1.0, trace.normal_x)
    assert_in_delta(0.0, trace.normal_z)
    assert_in_delta(3.0, hull.calls.first.fetch(:feet_y))
    assert_in_delta(0.25, hull.calls.first.fetch(:ground_body_radius))
  end

  def test_start_solid_becomes_start_blocked_at_zero_fraction
    hull = fake_hull(
      Aogera::BSP29::ClipHull::Trace.new(
        fraction: 1.0,
        end_position: vec(2.0, 24.0, 2.0),
        plane_normal: nil,
        start_solid: true,
        all_solid: false
      )
    )
    space = Aogera::GroundSpace.new(bsp29_ground_hull: hull)

    trace = space.sweep_circle(
      level: @level,
      world: @world.view,
      start_x: 2.0,
      start_z: 2.0,
      end_x: 3.0,
      end_z: 2.0,
      radius: 0.25
    )

    assert(trace.start_blocked)
    assert_in_delta(0.0, trace.fraction)
    assert_in_delta(2.0, trace.end_x)
  end

  def test_dynamic_actor_collision_remains_active_with_bsp_static_collision
    hull = fake_hull(clear_clip_trace(4.5, 1.5))
    space = Aogera::GroundSpace.new(bsp29_ground_hull: hull)
    blocker_id = @world.spawn(
      position: Aogera::Component::Position.new(x: 3.0, y: 0.0, z: 1.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.25)
    )

    trace = space.sweep_circle(
      level: @level,
      world: @world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5,
      radius: 0.25,
      entity_filter: ->(entity_id) { entity_id == blocker_id }
    )

    assert_equal(blocker_id, trace.entity_id)
    refute(trace.world_hit)
    assert_operator(trace.fraction, :<, 1.0)
  end

  def test_zero_radius_segment_trace_stays_on_grid_backend_for_now
    hull = fake_hull(clear_clip_trace(4.5, 1.5))
    space = Aogera::GroundSpace.new(bsp29_ground_hull: hull)

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
    assert_empty(hull.calls)
  end

  private

  def fake_hull(result)
    FakeGroundHull.new(result, [])
  end

  def clear_clip_trace(x, z)
    Aogera::BSP29::ClipHull::Trace.new(
      fraction: 1.0,
      end_position: vec(x, 24.0, z),
      plane_normal: nil,
      start_solid: false,
      all_solid: false
    )
  end

  def clip_trace(fraction:, x:, z:, normal_x:, normal_z:)
    Aogera::BSP29::ClipHull::Trace.new(
      fraction: fraction,
      end_position: vec(x, 24.0, z),
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
