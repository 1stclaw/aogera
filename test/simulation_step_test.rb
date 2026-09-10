# frozen_string_literal: true

require_relative "test_helper"

class SimulationStepTest < Minitest::Test
  include AogeraTestSupport

  def setup
    level = level_with(
      spawns: [],
      entries: [default_entry(x: 2, y: 2)],
      default_entry: :start
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

  def test_step_returns_explicit_result
    commands = Aogera::Simulation::Commands::Buffer.new([
      Aogera::Simulation::Commands::GroundMove.new(
        entity_id: @hero_id,
        dx: 1.0,
        dz: 0.0
      )
    ])

    result = @simulation.step(commands: commands)
    position = @simulation.world_view.component(@hero_id, :position)

    assert_instance_of Aogera::Simulation::StepResult, result
    assert_equal 1, result.number
    assert_empty result.effects
    assert_in_delta 3.5, position.x
    assert_in_delta 2.5, position.z
  end

  def test_ground_move_updates_canonical_position
    commands = Aogera::Simulation::Commands::Buffer.new([
      Aogera::Simulation::Commands::GroundMove.new(
        entity_id: @hero_id,
        dx: 0.7,
        dz: 0.0
      )
    ])

    @simulation.step(commands: commands)
    position = @simulation.world_view.component(@hero_id, :position)

    assert_in_delta 3.2, position.x
    assert_in_delta 0.0, position.y
    assert_in_delta 2.5, position.z
  end

  def test_step_returns_persistent_effects
    enemy_id = world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      melee_attack: Aogera::Component::MeleeAttack.new(reach: 0.65, arc_degrees: 110.0)
    )
    commands = Aogera::Simulation::Commands::Buffer.new([
      Aogera::Simulation::Commands::Attack.new(
        attacker_id: enemy_id,
        target_id: @hero_id,
        damage: 1
      )
    ])

    result = @simulation.step(commands: commands)

    assert_equal 1, result.number
    assert_equal 1, result.effects.length
    assert_instance_of Aogera::Effect::DamageCharacter, result.effects.first
    assert_equal :hero, result.effects.first.character_key
  end

  def test_steering_target_commands_update_runtime_component_data
    set_target = Aogera::Simulation::Commands::SetSteeringTarget.new(
      entity_id: @hero_id,
      x: 4.25,
      z: 3.75
    )

    @simulation.step(
      commands: Aogera::Simulation::Commands::Buffer.new([set_target])
    )
    target = @simulation.world_view.component(@hero_id, :steering_target)

    assert_instance_of Aogera::Component::SteeringTarget, target
    assert_in_delta 4.25, target.x
    assert_in_delta 3.75, target.z

    @simulation.step(
      commands: Aogera::Simulation::Commands::Buffer.new([
        Aogera::Simulation::Commands::ClearSteeringTarget.new(entity_id: @hero_id)
      ])
    )

    assert_nil @simulation.world_view.component(@hero_id, :steering_target)
  end

  def test_planning_is_outside_simulation_and_does_not_advance_world
    controller = Aogera::RealtimeController.new(
      npc_interval: 1
    )
    commands = controller.build(
      input: move_input(:move_forward),
      level: @simulation.level,
      world: @simulation.world_view,
      controlled_id: @hero_id,
      tick_number: 1
    )
    position = @simulation.world_view.component(
      @hero_id,
      :position
    )

    assert_equal 1, commands.size
    assert_in_delta 2.5, position.x
    assert_in_delta 2.5, position.z
    assert_equal 0, @simulation.step_number
    refute_respond_to @simulation, :plan
  end

  def test_world_view_has_no_mutation_api
    refute_respond_to @simulation.world_view, :set_component
  end

  private

  def world
    @simulation.instance_variable_get(:@world)
  end
end
