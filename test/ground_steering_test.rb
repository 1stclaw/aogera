# frozen_string_literal: true

require_relative "test_helper"

class GroundSteeringTest < Minitest::Test
  include AogeraTestSupport

  def test_build_emits_heading_and_one_tick_ground_move_toward_static_goal
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 0.0, z: 2.0),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      steering_target: Aogera::Component::SteeringTarget.new(x: 4.0, z: 6.0)
    )
    steering = Aogera::Simulation::GroundSteering.new(speed: 3.0)

    commands = steering.build(
      level: level_with(spawns: []),
      world: world.view
    ).to_a
    heading = commands.grep(Aogera::Simulation::Commands::SetGroundHeading).fetch(0)
    move = commands.grep(Aogera::Simulation::Commands::GroundMove).fetch(0)

    assert_equal entity_id, heading.entity_id
    assert_in_delta 0.6, heading.dx
    assert_in_delta 0.8, heading.dz
    assert_equal entity_id, move.entity_id
    assert_in_delta 0.1, Math.hypot(move.dx, move.dz)
    assert_in_delta 0.06, move.dx
    assert_in_delta 0.08, move.dz
  end

  def test_build_caps_move_at_remaining_static_goal_distance
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 0.0, z: 2.0),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      steering_target: Aogera::Component::SteeringTarget.new(x: 1.03, z: 2.04)
    )
    steering = Aogera::Simulation::GroundSteering.new(speed: 3.0)

    move = steering.build(
      level: level_with(spawns: []),
      world: world.view
    ).to_a.grep(Aogera::Simulation::Commands::GroundMove).fetch(0)

    assert_equal entity_id, move.entity_id
    assert_in_delta 0.03, move.dx
    assert_in_delta 0.04, move.dz
  end

  def test_build_clears_target_when_actor_has_arrived
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 0.0, z: 2.0),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      steering_target: Aogera::Component::SteeringTarget.new(x: 1.0, z: 2.0),
      ground_heading: Aogera::GroundHeading.new(dx: 1.0, dz: 0.0)
    )

    commands = Aogera::Simulation::GroundSteering.new.build(
      level: level_with(spawns: []),
      world: world.view
    ).to_a

    assert_equal 1, commands.length
    assert_instance_of Aogera::Simulation::Commands::ClearSteeringTarget, commands.fetch(0)
    assert_equal entity_id, commands.fetch(0).entity_id
  end

  def test_build_ignores_retired_actor
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 0.0, z: 2.0),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      steering_target: Aogera::Component::SteeringTarget.new(x: 2.0, z: 2.0),
      retired: Aogera::Component::Retired.new
    )

    commands = Aogera::Simulation::GroundSteering.new.build(
      level: level_with(spawns: []),
      world: world.view
    )

    assert_empty commands
    assert world.retired?(entity_id)
  end

  def test_live_goal_entity_position_is_resolved_every_steering_tick
    world = Aogera::World.new
    hunter_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 0.0, z: 2.0),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      steering_target: Aogera::Component::SteeringTarget.new(
        x: 4.0,
        z: 2.0,
        goal_entity_id: 1
      )
    )
    target_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 0.0, z: 5.0),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )
    assert_equal target_id, world.component(hunter_id, :steering_target).goal_entity_id

    commands = Aogera::Simulation::GroundSteering.new(speed: 3.0).build(
      level: level_with(spawns: []),
      world: world.view
    ).to_a
    move = commands.grep(Aogera::Simulation::Commands::GroundMove).fetch(0)

    assert_in_delta 0.0, move.dx
    assert_operator move.dz, :>, 0.0
  end

  def test_route_needed_keeps_goal_but_clears_previous_heading
    route_needed = Struct.new(:status, :heading).new(:route_needed, nil)
    navigation = Struct.new(:decision) do
      def query(**)
        decision
      end
    end.new(route_needed)
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.0, y: 0.0, z: 2.0),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      steering_target: Aogera::Component::SteeringTarget.new(x: 4.0, z: 2.0),
      ground_heading: Aogera::GroundHeading.new(dx: 1.0, dz: 0.0)
    )
    steering = Aogera::Simulation::GroundSteering.new(
      speed: 3.0,
      ground_navigation: navigation
    )

    commands = steering.build(level: Object.new, world: world.view).to_a

    assert_equal 1, commands.length
    assert_instance_of Aogera::Simulation::Commands::ClearGroundHeading, commands.fetch(0)
    assert_equal entity_id, commands.fetch(0).entity_id
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
    target_command = decision.to_a.fetch(0)
    assert_instance_of Aogera::Simulation::Commands::SetSteeringTarget, target_command
    assert_equal hero_id, target_command.goal_entity_id

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
    assert_instance_of Aogera::Component::SteeringTarget,
      simulation.world_view.component(hunter_id, :steering_target)
    assert_instance_of Aogera::GroundHeading,
      simulation.world_view.component(hunter_id, :ground_heading)
  end

  def test_clear_command_suppresses_navigation_and_steering_in_same_tick
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
    assert simulation.world_view.component(mover_id, :ground_heading)

    simulation.step(
      commands: Aogera::Simulation::Commands::Buffer.new([
        Aogera::Simulation::Commands::ClearSteeringTarget.new(entity_id: mover_id)
      ])
    )
    after_clear = simulation.world_view.component(mover_id, :position)

    assert_equal before_clear, after_clear
    assert_nil simulation.world_view.component(mover_id, :steering_target)
    assert_nil simulation.world_view.component(mover_id, :ground_heading)
  end

  def test_rejected_attack_keeps_pursuit_and_moves_in_same_tick
    level = level_with(
      spawns: [
        Aogera::Level::Spawn.new(key: :hunter, prototype: :goblin, x: 1, y: 2)
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
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      ground_steering: Aogera::Simulation::GroundSteering.new(speed: 3.0)
    )
    hero_id = simulation.spawn_character(character_key: :hero, prototype: :player)
    hunter_id = simulation.entity_id_for_spawn(:hunter)
    world = simulation.instance_variable_get(:@world)
    world.set_component(
      hunter_id,
      :position,
      Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 2.5)
    )
    world.set_component(
      hero_id,
      :position,
      Aogera::Component::Position.new(x: 2.6, y: 0.0, z: 2.5)
    )

    controller = Aogera::RealtimeController.new(
      npc_interval: 1,
      player_speed: 3.0
    )
    commands = controller.build(
      input: move_input(:move_forward),
      level: level,
      world: simulation.world_view,
      controlled_id: hero_id,
      tick_number: 1,
      view: Aogera::FirstPersonView.for_direction(:east)
    )

    before = simulation.world_view.component(hunter_id, :position)
    result = simulation.step(commands: commands)
    after = simulation.world_view.component(hunter_id, :position)

    assert_empty result.effects
    assert_operator after.x, :>, before.x
    assert simulation.world_view.component(hunter_id, :steering_target)
    assert simulation.world_view.component(hunter_id, :ground_heading)
  end

  def test_invalid_speed_is_rejected
    assert_raises(ArgumentError) do
      Aogera::Simulation::GroundSteering.new(speed: 0)
    end
  end
end
