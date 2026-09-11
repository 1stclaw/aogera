# frozen_string_literal: true

require_relative "test_helper"

class GroundSteeringTest < Minitest::Test
  include AogeraTestSupport

  def test_build_emits_one_tick_ground_move_toward_target
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 0.0, z: 2.0),
      steering_target: Aogera::Component::SteeringTarget.new(x: 4.0, z: 6.0)
    )
    steering = Aogera::Simulation::GroundSteering.new(speed: 3.0)

    command = steering.build(world: world.view).to_a.fetch(0)

    assert_instance_of Aogera::Simulation::Commands::GroundMove, command
    assert_equal entity_id, command.entity_id
    assert_in_delta 0.1, Math.hypot(command.dx, command.dz)
    assert_in_delta 0.06, command.dx
    assert_in_delta 0.08, command.dz
  end

  def test_build_caps_move_at_remaining_target_distance
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 0.0, z: 2.0),
      steering_target: Aogera::Component::SteeringTarget.new(x: 1.03, z: 2.04)
    )
    steering = Aogera::Simulation::GroundSteering.new(speed: 3.0)

    command = steering.build(world: world.view).to_a.fetch(0)

    assert_equal entity_id, command.entity_id
    assert_in_delta 0.03, command.dx
    assert_in_delta 0.04, command.dz
  end

  def test_build_clears_target_when_actor_has_arrived
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 0.0, z: 2.0),
      steering_target: Aogera::Component::SteeringTarget.new(x: 1.0, z: 2.0)
    )

    command = Aogera::Simulation::GroundSteering.new.build(
      world: world.view
    ).to_a.fetch(0)

    assert_instance_of Aogera::Simulation::Commands::ClearSteeringTarget, command
    assert_equal entity_id, command.entity_id
  end

  def test_build_ignores_retired_actor
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 0.0, z: 2.0),
      steering_target: Aogera::Component::SteeringTarget.new(x: 2.0, z: 2.0),
      retired: Aogera::Component::Retired.new
    )

    commands = Aogera::Simulation::GroundSteering.new.build(world: world.view)

    assert_empty commands
    assert world.retired?(entity_id)
  end

  def test_simulation_keeps_moving_between_npc_decision_ticks
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
      prototypes: prototype_catalog,
      ground_steering: Aogera::Simulation::GroundSteering.new(speed: 3.0)
    )
    hero_id = simulation.spawn_character(character_key: :hero, prototype: :player)
    hunter_id = simulation.entity_id_for_spawn(:hunter)
    controller = Aogera::RealtimeController.new(npc_interval: 4)

    3.times do |index|
      commands = controller.build(
        input: Aogera::Input::Snapshot.empty,
        level: level,
        world: simulation.world_view,
        controlled_id: hero_id,
        tick_number: index + 1
      )
      assert_empty commands
      simulation.step(commands: commands)
    end

    before = simulation.world_view.component(hunter_id, :position)
    decision = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: level,
      world: simulation.world_view,
      controlled_id: hero_id,
      tick_number: 4
    )
    assert_equal 1, decision.size
    assert_instance_of(
      Aogera::Simulation::Commands::SetSteeringTarget,
      decision.to_a.fetch(0)
    )

    simulation.step(commands: decision)
    after_decision = simulation.world_view.component(hunter_id, :position)
    assert_in_delta 0.1, after_decision.x - before.x

    between = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: level,
      world: simulation.world_view,
      controlled_id: hero_id,
      tick_number: 5
    )
    assert_empty between

    simulation.step(commands: between)
    after_between = simulation.world_view.component(hunter_id, :position)
    assert_in_delta 0.1, after_between.x - after_decision.x
    assert_instance_of(
      Aogera::Component::SteeringTarget,
      simulation.world_view.component(hunter_id, :steering_target)
    )
  end

  def test_clear_command_suppresses_steering_in_the_same_simulation_tick
    level = level_with(
      spawns: [
        Aogera::Level::Spawn.new(
          key: :mover,
          prototype: :goblin,
          x: 1,
          y: 2
        )
      ]
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      ground_steering: Aogera::Simulation::GroundSteering.new(speed: 3.0)
    )
    mover_id = simulation.entity_id_for_spawn(:mover)

    simulation.step(
      commands: Aogera::Simulation::Commands::Buffer.new([
        Aogera::Simulation::Commands::SetSteeringTarget.new(
          entity_id: mover_id,
          x: 3.5,
          z: 2.5
        )
      ])
    )
    before_clear = simulation.world_view.component(mover_id, :position)

    simulation.step(
      commands: Aogera::Simulation::Commands::Buffer.new([
        Aogera::Simulation::Commands::ClearSteeringTarget.new(entity_id: mover_id)
      ])
    )
    after_clear = simulation.world_view.component(mover_id, :position)

    assert_equal before_clear, after_clear
    assert_nil simulation.world_view.component(mover_id, :steering_target)
  end

  def test_invalid_speed_is_rejected
    assert_raises(ArgumentError) do
      Aogera::Simulation::GroundSteering.new(speed: 0)
    end
  end
end
