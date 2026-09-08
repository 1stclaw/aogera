# frozen_string_literal: true

require_relative "test_helper"

class PathfinderTest < Minitest::Test
  def test_finds_step_around_blocked_terrain
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 5, height: 5),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    source = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )
    world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    step = Aogera::Simulation::Pathfinder.new.next_step(
      level: level, world: world,
      source_id: source, target_id: target
    )

    assert_includes [[0, -1], [0, 1]], step
  end

  def test_returns_current_navigation_cell_when_source_is_already_in_goal_cell
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 5, height: 5),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    source = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    assert_equal [0, 0], Aogera::Simulation::Pathfinder.new.next_step(
      level: level, world: world,
      source_id: source, target_id: target
    )
  end
end
