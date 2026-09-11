# frozen_string_literal: true

require_relative "test_helper"

class PathfindingChaseTest < Minitest::Test
  include AogeraTestSupport

  def test_chaser_locally_avoids_blocking_entity_without_grid_pathfinding
    level = level_with(
      width: 8,
      height: 6,
      spawns: [
        Aogera::Level::Spawn.new(
          key: :hunter,
          prototype: :goblin,
          x: 1,
          y: 2
        ),
        Aogera::Level::Spawn.new(
          key: :blocker,
          prototype: :villager,
          x: 2,
          y: 2
        )
      ],
      entries: [default_entry(x: 5, y: 2)],
      default_entry: :start,
      relations: [
        Aogera::Level::Relation.new(
          kind: :targets,
          source: :hunter,
          target: :start
        )
      ]
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      ground_steering: Aogera::Simulation::GroundSteering.new(speed: 2.0)
    )
    hero_id = simulation.spawn_character(character_key: :hero, prototype: :player)
    hunter_id = simulation.entity_id_for_spawn(:hunter)
    controller = Aogera::RealtimeController.new(npc_interval: 1)

    decision = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: level,
      world: simulation.world_view,
      controlled_id: hero_id,
      tick_number: 1
    )
    simulation.step(commands: decision)

    14.times do
      simulation.step(commands: Aogera::Simulation::Commands::Buffer.new([]))
    end

    position = simulation.world_view.component(hunter_id, :position)
    assert_operator position.x, :>, 1.9
    assert_operator (position.z - 2.5).abs, :>, 0.1
    assert_instance_of Aogera::GroundHeading,
      simulation.world_view.component(hunter_id, :ground_heading)
    refute controller.instance_variable_defined?(:@pathfinder)
  end
end
