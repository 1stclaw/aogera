# frozen_string_literal: true

require_relative "test_helper"

class CollisionTest < Minitest::Test
  include AogeraTestSupport

  def test_blocking_entity_prevents_controlled_movement
    level = level_with(
      spawns: [
        Aogera::Level::Spawn.new(
          key: :blocker,
          prototype: :goblin,
          x: 3,
          y: 2
        )
      ],
      entries: [default_entry(x: 2, y: 2, facing: :east)],
      default_entry: :start
    )
    simulation = Aogera::Simulation.new(level: level, prototypes: prototype_catalog)
    hero_id = simulation.spawn_character(character_key: :hero, prototype: :player)

    controller = Aogera::RealtimeController.new(
      npc_interval: 100
    )

    10.times do |index|
      commands = controller.build(
        input: move_input(:move_forward),
        level: level,
        world: simulation.world_view,
        controlled_id: hero_id,
        tick_number: index + 1,
        view: Aogera::FirstPersonView.for_direction(:east)
      )
      simulation.step(commands: commands)
    end

    position = simulation.world_view.component(hero_id, :position)
    assert_operator position.x, :>, 2.5
    assert_operator position.x, :<=, 3.0
    assert_in_delta 0.0, position.y
    assert_in_delta 2.5, position.z
  end
end
