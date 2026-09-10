# frozen_string_literal: true

require_relative "test_helper"

class SpatialNormalizationTest < Minitest::Test
  include AogeraTestSupport

  def test_runtime_exposes_one_position_component_and_one_ground_move_command
    refute Aogera::Component.const_defined?(:GroundPosition, false)
    refute Aogera::Simulation::Commands.const_defined?(:Move, false)
    refute Aogera::Simulation.const_defined?(:Movement, false)
  end

  def test_all_spawned_actor_kinds_use_canonical_xyz_position
    level = level_with(
      spawns: [
        Aogera::Level::Spawn.new(
          key: :goblin,
          prototype: :goblin,
          x: 1,
          y: 2
        ),
        Aogera::Level::Spawn.new(
          key: :villager,
          prototype: :villager,
          x: 4,
          y: 2
        )
      ],
      entries: [default_entry(x: 2, y: 2)],
      default_entry: :start
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog
    )
    player_id = simulation.spawn_character(
      character_key: :hero,
      prototype: :player
    )

    ids = [
      player_id,
      simulation.entity_id_for_spawn(:goblin),
      simulation.entity_id_for_spawn(:villager)
    ]

    ids.each do |entity_id|
      position = simulation.world_view.component(entity_id, :position)
      assert_instance_of Aogera::Component::Position, position
      assert_in_delta 0.0, position.y
      assert_nil simulation.world_view.component(entity_id, :ground_position)
    end

    goblin = simulation.world_view.component(
      simulation.entity_id_for_spawn(:goblin),
      :position
    )
    assert_in_delta 1.5, goblin.x
    assert_in_delta 2.5, goblin.z
  end

  def test_nonadjacent_npc_navigation_produces_same_ground_move_command_as_player
    level = level_with(
      spawns: [
        Aogera::Level::Spawn.new(
          key: :hunter,
          prototype: :goblin,
          x: 1,
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
      prototypes: prototype_catalog
    )
    player_id = simulation.spawn_character(
      character_key: :hero,
      prototype: :player
    )
    hunter_id = simulation.entity_id_for_spawn(:hunter)

    commands = Aogera::RealtimeController.new(npc_interval: 1).build(
      input: Aogera::Input::Snapshot.empty,
      level: level,
      world: simulation.world_view,
      controlled_id: player_id,
      tick_number: 1
    ).to_a
    command = commands.find { |candidate| candidate.is_a?(Aogera::Simulation::Commands::GroundMove) }

    assert_instance_of Aogera::Simulation::Commands::GroundMove, command
    assert_equal hunter_id, command.entity_id
    assert_operator Math.hypot(command.dx, command.dz), :>, 0.0
  end
end
