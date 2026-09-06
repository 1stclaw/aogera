# frozen_string_literal: true

require_relative "test_helper"

class AttackTest < Minitest::Test
  def setup
    @level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(width: 5, height: 5),
      spawns: [],
      relations: []
    )
    @executor = Aogera::Simulation::Executor.new
    @bindings = Aogera::Simulation::Bindings.new
  end

  def test_adjacent_attack_reduces_local_health
    world = Aogera::World.new
    attacker = world.spawn(
      position: Aogera::Component::Position.new(x: 1, y: 1)
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 2, y: 1),
      health: Aogera::Component::Health.new(current: 10, max: 10)
    )

    effects = execute(
      world,
      Aogera::Simulation::Commands::Attack.new(
        attacker_id: attacker,
        target_id: target,
        damage: 1
      )
    )

    assert_equal 9, world.component(target, :health).current
    assert_empty effects
  end

  def test_adjacent_attack_on_bound_character_emits_persistent_damage
    world = Aogera::World.new
    attacker = world.spawn(
      position: Aogera::Component::Position.new(x: 1, y: 1)
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 2, y: 1)
    )
    @bindings.bind(character_key: :hero, entity_id: target)

    effects = execute(
      world,
      Aogera::Simulation::Commands::Attack.new(
        attacker_id: attacker,
        target_id: target,
        damage: 2
      )
    )

    assert_equal 1, effects.length
    effect = effects.first
    assert_instance_of Aogera::Effect::DamageCharacter, effect
    assert_equal :hero, effect.character_key
    assert_equal 2, effect.amount
    assert_nil world.component(target, :health)
  end

  def test_attack_is_rejected_when_target_is_not_adjacent
    world = Aogera::World.new
    attacker = world.spawn(
      position: Aogera::Component::Position.new(x: 1, y: 1)
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 3, y: 1),
      health: Aogera::Component::Health.new(current: 10, max: 10)
    )

    assert_empty execute(
      world,
      Aogera::Simulation::Commands::Attack.new(
        attacker_id: attacker,
        target_id: target,
        damage: 1
      )
    )
    assert_equal 10, world.component(target, :health).current
  end

  private

  def execute(world, command)
    @executor.execute(
      world: world,
      level: @level,
      bindings: @bindings,
      commands: Aogera::Simulation::Commands::Buffer.new([command])
    )
  end
end
