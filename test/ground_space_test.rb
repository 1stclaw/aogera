# frozen_string_literal: true

require_relative "test_helper"

class GroundSpaceTest < Minitest::Test
  def setup
    @space = Aogera::GroundSpace.new
    @world = Aogera::World.new
  end

  def test_position_returns_canonical_world_position
    entity_id = @world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 4.5)
    )

    position = @space.position(world: @world.view, entity_id: entity_id)

    assert_in_delta 3.5, position.x
    assert_in_delta 4.5, position.z
  end

  def test_position_preserves_continuous_coordinates
    entity_id = @world.spawn(
      position: Aogera::Component::Position.new(x: 3.2, y: 0.0, z: 4.8)
    )

    position = @space.position(world: @world.view, entity_id: entity_id)

    assert_in_delta 3.2, position.x
    assert_in_delta 4.8, position.z
  end

  def test_separation_accounts_for_authored_body_radii
    source = @world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.2)
    )
    target = @world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.3)
    )

    assert_in_delta 0.5, @space.separation(
      world: @world.view,
      source_id: source,
      target_id: target
    )
  end

  def test_arc_hits_use_continuous_heading_instead_of_cardinal_cells
    source = @world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.2)
    )
    east = @world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.3)
    )
    west = @world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.3)
    )
    yaw = 40.0 * Math::PI / 180.0

    hits = @space.arc_hits(
      world: @world.view,
      source_id: source,
      target_ids: [east, west],
      forward_x: Math.sin(yaw),
      forward_z: -Math.cos(yaw),
      reach: 0.65,
      arc_degrees: 110.0
    )

    assert_includes hits.map(&:entity_id), east
    refute_includes hits.map(&:entity_id), west
  end
end
