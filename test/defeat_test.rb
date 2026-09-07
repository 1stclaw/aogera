# frozen_string_literal: true

require_relative "test_helper"

class DefeatTest < Minitest::Test
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

  def test_defeat_retires_zero_health_entity
    world = Aogera::World.new
    entity_id = world.spawn(
      health: Aogera::Component::Health.new(current: 0, max: 4),
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      renderable: Aogera::Component::Renderable.new(
        render_key: :goblin, glyph: "G", layer: 10
      ),
      behavior: Aogera::Component::Behavior.new(kind: :chase),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      combatant: Aogera::Component::Combatant.new(attack: 1)
    )

    execute(world, Aogera::Simulation::Commands::Defeat.new(entity_id: entity_id))

    assert_nil world.component(entity_id, :renderable)
    assert_nil world.component(entity_id, :behavior)
    assert_nil world.component(entity_id, :collision)
    assert_nil world.component(entity_id, :combatant)
    assert world.retired?(entity_id)
    assert_instance_of Aogera::Component::Retired,
      world.component(entity_id, :retired)
    assert_equal 0, world.component(entity_id, :health).current
    assert world.component(entity_id, :position)
  end

  def test_defeat_does_nothing_while_health_is_positive
    world = Aogera::World.new
    entity_id = world.spawn(
      health: Aogera::Component::Health.new(current: 1, max: 4),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    execute(world, Aogera::Simulation::Commands::Defeat.new(entity_id: entity_id))
    assert world.component(entity_id, :collision)
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
