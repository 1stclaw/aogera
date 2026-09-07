# frozen_string_literal: true

require_relative "test_helper"

class ChaseBehaviorTest < Minitest::Test
  include AogeraTestSupport

  def test_adjacent_chaser_damages_bound_persistent_character_on_npc_tick
    simulation, session, hero_id = build_simulation(
      hero_position: [3, 3],
      goblin_position: [2, 3]
    )

    result = plan_and_step(simulation, hero_id)
    session.apply_effects(result.effects)

    assert_equal 9, session.character(:hero).hp
    assert_nil simulation.world_view.component(hero_id, :health)
  end

  def test_chaser_moves_toward_non_adjacent_target_on_npc_tick
    simulation, _session, hero_id = build_simulation(
      hero_position: [4, 3],
      goblin_position: [2, 3]
    )
    goblin_id = entity_id_for(simulation, :goblin)

    plan_and_step(simulation, hero_id)
    position = simulation.world_view.component(goblin_id, :position)

    assert_operator position.x, :>, 2.5
    assert_in_delta 3.5, position.z
  end

  def test_chaser_uses_combatant_attack_value
    prototypes = prototype_catalog
    goblin = prototypes.fetch(:goblin)
    stronger = Aogera::Prototype.new(
      name: :strong_goblin,
      components: goblin.components.merge(
        combatant: Aogera::Component::Combatant.new(attack: 3)
      ).freeze
    )
    prototypes = Aogera::Prototype::Catalog.new([
      prototypes.fetch(:player), stronger
    ])
    level = level_with(
      spawns: [
        Aogera::Level::Spawn.new(
          key: :hunter,
          prototype: :strong_goblin,
          x: 2,
          y: 3
        )
      ],
      entries: [default_entry(x: 3, y: 3)],
      default_entry: :start,
      relations: [
        Aogera::Level::Relation.new(
          kind: :targets,
          source: :hunter,
          target: :start
        )
      ]
    )
    simulation = Aogera::Simulation.new(level: level, prototypes: prototypes)
    hero_id = simulation.spawn_character(character_key: :hero, prototype: :player)

    result = plan_and_step(simulation, hero_id)
    assert_equal 3, result.effects.first.amount
  end

  private

  def build_simulation(hero_position:, goblin_position:)
    level = level_with(
      spawns: [
        Aogera::Level::Spawn.new(
          key: :hunter,
          prototype: :goblin,
          x: goblin_position[0],
          y: goblin_position[1]
        )
      ],
      entries: [default_entry(x: hero_position[0], y: hero_position[1])],
      default_entry: :start,
      relations: [
        Aogera::Level::Relation.new(
          kind: :targets,
          source: :hunter,
          target: :start
        )
      ]
    )
    simulation = Aogera::Simulation.new(level: level, prototypes: prototype_catalog)
    hero_id = simulation.spawn_character(character_key: :hero, prototype: :player)
    [simulation, test_session, hero_id]
  end

  def plan_and_step(simulation, hero_id)
    controller = Aogera::RealtimeController.new(npc_interval: 1)
    commands = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: simulation.level,
      world: simulation.world_view,
      controlled_id: hero_id,
      tick_number: 1
    )
    simulation.step(commands: commands)
  end
end
