# frozen_string_literal: true

require_relative "test_helper"

class SimulationLoadingTest < Minitest::Test
  include AogeraTestSupport

  def setup
    level = level_with(
      spawns: [
        Aogera::Level::Spawn.new(
          key: :hunter,
          prototype: :goblin,
          x: 4,
          y: 2
        )
      ],
      entries: [default_entry(x: 2, y: 2)],
      default_entry: :start,
      relations: [
        Aogera::Level::Relation.new(
          kind: :targets,
          source: :hunter,
          target: :start
        )
      ]
    )
    @simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog
    )
    @hero_id = @simulation.spawn_character(
      character_key: :hero,
      prototype: :player
    )
  end

  def test_spawn_key_resolves_to_runtime_entity
    hunter_id = @simulation.entity_id_for_spawn(:hunter)
    ref = @simulation.world_view.component(hunter_id, :prototype_ref)

    assert_equal :goblin, ref.name
    assert_equal @hero_id, @simulation.entity_id_for_character(:hero)
    assert_equal :hero, @simulation.character_key_for_entity(@hero_id)
  end

  def test_static_relation_resolves_after_entry_is_occupied
    hunter_id = @simulation.entity_id_for_spawn(:hunter)

    assert_equal [@hero_id], @simulation.world_view.relation_targets(
      kind: :targets,
      source_id: hunter_id
    )
  end

  def test_character_world_entity_has_no_local_health
    assert_nil @simulation.world_view.component(@hero_id, :health)
  end
end
