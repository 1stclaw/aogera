# frozen_string_literal: true

require_relative "test_helper"

class SimulationBindingInvariantTest < Minitest::Test
  include AogeraTestSupport

  def test_duplicate_character_spawn_fails_before_creating_orphan_entity
    level = level_with(
      spawns: [],
      entries: [
        default_entry(key: :first, x: 2, y: 2),
        default_entry(key: :second, x: 3, y: 2)
      ],
      default_entry: :first
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog
    )
    hero_id = simulation.spawn_character(
      character_key: :hero,
      prototype: :player,
      entry: :first
    )
    before_ids = simulation.world_view.entity_ids

    error = assert_raises(ArgumentError) do
      simulation.spawn_character(
        character_key: :hero,
        prototype: :player,
        entry: :second
      )
    end

    assert_match "already spawned", error.message
    assert_equal before_ids, simulation.world_view.entity_ids
    assert_equal hero_id, simulation.entity_id_for_character(:hero)
  end
end
