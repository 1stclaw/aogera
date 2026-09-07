# frozen_string_literal: true

require_relative "test_helper"

class GroundTraceTest < Minitest::Test
  def setup
    @space = Aogera::GroundSpace.new
  end

  def test_unobstructed_segment_reaches_full_destination
    level = blank_level(width: 6, height: 4)
    world = Aogera::World.new

    trace = @space.trace_segment(
      level: level,
      world: world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5
    )

    assert trace.clear?
    assert_in_delta 1.0, trace.fraction
    assert_in_delta 4.5, trace.end_x
    assert_in_delta 1.5, trace.end_z
    assert_equal false, trace.world_hit
    assert_nil trace.entity_id
  end

  def test_segment_returns_first_wall_and_contact_normal
    level = row_level("     ", "   | ", "     ")
    world = Aogera::World.new

    trace = @space.trace_segment(
      level: level,
      world: world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5
    )

    assert trace.hit?
    assert trace.world_hit
    assert_in_delta 0.5, trace.fraction
    assert_in_delta 3.0, trace.end_x
    assert_in_delta(-1.0, trace.normal_x)
    assert_in_delta 0.0, trace.normal_z
  end

  def test_segment_can_hit_dynamic_ground_body
    level = blank_level(width: 6, height: 4)
    world = Aogera::World.new
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.3)
    )

    trace = @space.trace_segment(
      level: level,
      world: world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5
    )

    assert_equal target, trace.entity_id
    refute trace.world_hit
    assert_operator trace.fraction, :<, 1.0
    assert_in_delta(-1.0, trace.normal_x)
  end

  def test_ignore_entity_prevents_self_hit
    level = blank_level(width: 6, height: 4)
    world = Aogera::World.new
    source = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.3)
    )

    trace = @space.trace_segment(
      level: level,
      world: world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5,
      ignore_entity_id: source
    )

    assert trace.clear?
  end

  def test_static_and_dynamic_candidates_choose_earliest_hit
    level = row_level("      ", "    | ", "      ")
    world = Aogera::World.new
    blocker = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.25)
    )

    trace = @space.trace_segment(
      level: level,
      world: world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 5.5,
      end_z: 1.5
    )

    assert_equal blocker, trace.entity_id
    refute trace.world_hit
  end

  def test_swept_circle_cannot_tunnel_through_wall
    level = row_level("      ", "   |  ", "      ")
    world = Aogera::World.new

    trace = @space.sweep_circle(
      level: level,
      world: world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 5.5,
      end_z: 1.5,
      radius: 0.22
    )

    assert trace.hit?
    assert trace.world_hit
    assert_in_delta 2.78, trace.end_x
    assert_in_delta(-1.0, trace.normal_x)
  end

  def test_swept_circle_hits_dynamic_ground_body
    level = blank_level(width: 6, height: 4)
    world = Aogera::World.new
    blocker = world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.3)
    )

    trace = @space.sweep_circle(
      level: level,
      world: world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5,
      radius: 0.2
    )

    assert_equal blocker, trace.entity_id
    refute trace.world_hit
    assert_in_delta(-1.0, trace.normal_x)
    assert_in_delta 3.0, trace.end_x
  end

  def test_swept_circle_returns_diagonal_normal_for_cell_corner
    level = row_level("     ", "     ", "     ", "   | ", "     ")
    world = Aogera::World.new

    trace = @space.sweep_circle(
      level: level,
      world: world.view,
      start_x: 2.5,
      start_z: 2.5,
      end_x: 3.2,
      end_z: 3.2,
      radius: 0.22
    )

    expected = -Math.sqrt(0.5)
    assert trace.hit?
    assert_in_delta expected, trace.normal_x, 1e-6
    assert_in_delta expected, trace.normal_z, 1e-6
  end

  def test_swept_circle_can_move_tangent_to_wall
    level = row_level("     ", "   | ", "     ", "     ")
    world = Aogera::World.new

    trace = @space.sweep_circle(
      level: level,
      world: world.view,
      start_x: 2.779,
      start_z: 1.2,
      end_x: 2.779,
      end_z: 2.7,
      radius: 0.22
    )

    assert trace.clear?
    assert_in_delta 2.7, trace.end_z
  end

  def test_starting_inside_wall_has_defined_blocked_result
    level = row_level("     ", "   | ", "     ")
    world = Aogera::World.new

    trace = @space.sweep_circle(
      level: level,
      world: world.view,
      start_x: 3.5,
      start_z: 1.5,
      end_x: 4.0,
      end_z: 1.5,
      radius: 0.22
    )

    assert trace.hit?
    assert trace.start_blocked
    assert trace.world_hit
    assert_in_delta 0.0, trace.fraction
    assert_in_delta 3.5, trace.end_x
  end

  private

  def blank_level(width:, height:)
    Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(width: width, height: height),
      spawns: [],
      relations: []
    )
  end

  def row_level(*rows)
    tiles = {
      " " => Aogera::Level::Tile.new(render_key: :ground, glyph: " ", passable: true),
      "|" => Aogera::Level::Tile.new(render_key: :wall, glyph: "|", passable: false)
    }.freeze
    Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(rows: rows, tiles: tiles),
      spawns: [],
      relations: []
    )
  end
end
