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
  def test_melee_attack_within_reach_reduces_local_health
    world = Aogera::World.new
    attacker = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      melee_attack: Aogera::Component::MeleeAttack.new(
        reach: 0.65, arc_degrees: 110.0
      )
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
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

  def test_lethal_local_attack_retires_target
    world = Aogera::World.new
    attacker = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      melee_attack: Aogera::Component::MeleeAttack.new(
        reach: 0.65, arc_degrees: 110.0
      )
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      health: Aogera::Component::Health.new(current: 2, max: 2),
      renderable: Aogera::Component::Renderable.new(
        render_key: :goblin, glyph: "G", layer: 10
      ),
      behavior: Aogera::Component::Behavior.new(kind: :chase),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      combatant: Aogera::Component::Combatant.new(attack: 1)
    )

    effects = execute(
      world,
      Aogera::Simulation::Commands::Attack.new(
        attacker_id: attacker,
        target_id: target,
        damage: 2
      )
    )

    assert_equal 0, world.component(target, :health).current
    assert_nil world.component(target, :renderable)
    assert_nil world.component(target, :behavior)
    assert_nil world.component(target, :collision)
    assert_nil world.component(target, :combatant)
    assert world.component(target, :position)
    assert_empty effects
  end

  def test_melee_attack_on_bound_character_emits_persistent_damage
    world = Aogera::World.new
    attacker = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      melee_attack: Aogera::Component::MeleeAttack.new(
        reach: 0.65, arc_degrees: 110.0
      )
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28)
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
  def test_continuous_attacker_uses_authored_melee_reach
    world = Aogera::World.new
    attacker = world.spawn(
      position: Aogera::Component::Position.new(x: 1.1, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      melee_attack: Aogera::Component::MeleeAttack.new(
        reach: 0.65,
        arc_degrees: 110.0
      )
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
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

    world.set_component(
      attacker,
      :position,
      Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5)
    )
    execute(
      world,
      Aogera::Simulation::Commands::Attack.new(
        attacker_id: attacker,
        target_id: target,
        damage: 1
      )
    )

    assert_equal 9, world.component(target, :health).current
  end

  def test_continuous_attack_is_rejected_when_static_wall_blocks_path
    tiles = {
      " " => Aogera::Level::Tile.new(render_key: :ground, glyph: " ", passable: true),
      "|" => Aogera::Level::Tile.new(render_key: :wall, glyph: "|", passable: false)
    }.freeze
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(
        rows: ["     ", "  |  ", "     "],
        tiles: tiles
      ),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    attacker = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      melee_attack: Aogera::Component::MeleeAttack.new(
        reach: 2.0,
        arc_degrees: 110.0
      )
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      health: Aogera::Component::Health.new(current: 10, max: 10)
    )

    execute(
      world,
      Aogera::Simulation::Commands::Attack.new(
        attacker_id: attacker,
        target_id: target,
        damage: 1
      ),
      level: level
    )

    assert_equal 10, world.component(target, :health).current
  end

  def test_attack_is_rejected_when_target_is_out_of_melee_reach
    world = Aogera::World.new
    attacker = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      melee_attack: Aogera::Component::MeleeAttack.new(
        reach: 0.65, arc_degrees: 110.0
      )
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
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

  def execute(world, command, level: @level)
    @executor.execute(
      world: world,
      level: level,
      bindings: @bindings,
      commands: Aogera::Simulation::Commands::Buffer.new([command])
    )
  end
end
