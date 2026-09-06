# frozen_string_literal: true

require_relative "test_helper"

class MovementTest < Minitest::Test
  def test_blocking_entity_makes_cell_untraversable
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(width: 5, height: 5),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    world.spawn(
      position: Aogera::Component::Position.new(x: 2, y: 2),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    movement = Aogera::Simulation::Movement.new
    refute movement.traversable?(level: level, world: world, x: 2, y: 2)
    assert movement.traversable?(level: level, world: world, x: 3, y: 2)
  end
end
