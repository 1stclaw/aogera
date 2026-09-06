# frozen_string_literal: true

require_relative "test_helper"

class BehaviorDispatchTest < Minitest::Test
  include AogeraTestSupport

  def test_unknown_behavior_kind_raises_argument_error_when_npc_tick_is_due
    prototypes = prototype_catalog(goblin_behavior: :unknown)
    level = level_with(
      spawns: [
        Aogera::Level::Spawn.new(
          key: :strange,
          prototype: :goblin,
          x: 3,
          y: 2
        )
      ],
      entries: [default_entry(x: 1, y: 2)],
      default_entry: :start
    )
    simulation = Aogera::Simulation.new(level: level, prototypes: prototypes)
    hero_id = simulation.spawn_character(character_key: :hero, prototype: :player)
    controller = Aogera::RealtimeController.new(npc_interval: 1)

    error = assert_raises(ArgumentError) do
      controller.build(
        input: Aogera::Input::Snapshot.empty,
        level: level,
        world: simulation.world_view,
        controlled_id: hero_id,
        tick_number: 1
      )
    end

    assert_match "unknown behavior", error.message
  end
end
