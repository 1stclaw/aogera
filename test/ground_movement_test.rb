# frozen_string_literal: true

require_relative "test_helper"

class GroundMovementTest < Minitest::Test
  def test_wall_blocks_one_axis_while_allowing_slide_on_the_other
    tiles = {
      " " => Aogera::Level::Tile.new(render_key: :ground, glyph: " ", passable: true),
      "|" => Aogera::Level::Tile.new(render_key: :wall, glyph: "|", passable: false)
    }.freeze
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(
        rows: ["     ", "   | ", "     "],
        tiles: tiles
      ),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2, y: 1),
      ground_position: Aogera::Component::GroundPosition.new(x: 2.5, z: 1.5)
    )

    resolved = Aogera::Simulation::GroundMovement.new.resolve(
      level: level,
      world: world.view,
      entity_id: hero_id,
      position: world.component(hero_id, :ground_position),
      dx: 0.4,
      dz: 0.2
    )

    assert_operator resolved.x, :>, 2.5
    assert_operator resolved.x, :<, 3.0
    assert_in_delta 1.7, resolved.z
  end

  def test_blocking_entity_cell_is_solid_to_continuous_player_motion
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(width: 5, height: 5),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2, y: 2),
      ground_position: Aogera::Component::GroundPosition.new(x: 2.5, z: 2.5)
    )
    world.spawn(
      position: Aogera::Component::Position.new(x: 3, y: 2),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    resolved = Aogera::Simulation::GroundMovement.new.resolve(
      level: level,
      world: world.view,
      entity_id: hero_id,
      position: world.component(hero_id, :ground_position),
      dx: 0.4,
      dz: 0.0
    )

    assert_operator resolved.x, :>, 2.5
    assert_operator resolved.x, :<, 3.0
    assert_in_delta 2.5, resolved.z
  end
end

class GroundMovementSubstepTest < Minitest::Test
  def test_large_motion_cannot_tunnel_through_a_wall_cell
    tiles = {
      " " => Aogera::Level::Tile.new(render_key: :ground, glyph: " ", passable: true),
      "|" => Aogera::Level::Tile.new(render_key: :wall, glyph: "|", passable: false)
    }.freeze
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(
        rows: ["     ", "   | ", "     "],
        tiles: tiles
      ),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2, y: 1),
      ground_position: Aogera::Component::GroundPosition.new(x: 2.5, z: 1.5)
    )

    resolved = Aogera::Simulation::GroundMovement.new.resolve(
      level: level,
      world: world.view,
      entity_id: hero_id,
      position: world.component(hero_id, :ground_position),
      dx: 2.0,
      dz: 0.0
    )

    assert_operator resolved.x, :<, 3.0
  end
end
