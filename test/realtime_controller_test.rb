# frozen_string_literal: true

require_relative "test_helper"

class RealtimeControllerTest < Minitest::Test
  include AogeraTestSupport

  def test_held_player_movement_produces_ground_motion_every_simulation_tick
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    controller = Aogera::RealtimeController.new(
      player_speed: 3.0,
      npc_interval: 100
    )
    tracker = Aogera::Input::Tracker.new

    first = tracker.snapshot([
      Aogera::Input::Action.new(kind: :move_forward, state: :pressed)
    ])
    first_command = controller.build(
      input: first,
      level: level_with(spawns: []),
      world: world.view,
      controlled_id: hero_id,
      tick_number: 1
    ).to_a.fetch(0)

    held = tracker.snapshot
    second_command = controller.build(
      input: held,
      level: level_with(spawns: []),
      world: world.view,
      controlled_id: hero_id,
      tick_number: 2
    ).to_a.fetch(0)

    assert_instance_of Aogera::Simulation::Commands::GroundMove, first_command
    assert_instance_of Aogera::Simulation::Commands::GroundMove, second_command
    assert_in_delta 0.1, Math.hypot(first_command.dx, first_command.dz)
    assert_in_delta 0.1, Math.hypot(second_command.dx, second_command.dz)
  end

  def test_player_forward_and_strafe_follow_continuous_view_heading
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    controller = Aogera::RealtimeController.new(
      player_speed: 3.0,
      npc_interval: 100
    )
    view = Aogera::FirstPersonView.for_direction(:east)

    forward = controller.build(
      input: move_input(:move_forward),
      level: level_with(spawns: []),
      world: world.view,
      controlled_id: hero_id,
      tick_number: 1,
      view: view
    ).to_a.fetch(0)

    strafe = controller.build(
      input: move_input(:strafe_right),
      level: level_with(spawns: []),
      world: world.view,
      controlled_id: hero_id,
      tick_number: 2,
      view: view
    ).to_a.fetch(0)

    assert_in_delta 0.1, forward.dx
    assert_in_delta 0.0, forward.dz
    assert_in_delta 0.0, strafe.dx
    assert_in_delta 0.1, strafe.dz
  end

  def test_npc_behaviors_run_only_on_npc_cadence
    world = Aogera::World.new
    goblin_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      melee_attack: Aogera::Component::MeleeAttack.new(reach: 0.65, arc_degrees: 110.0),
      behavior: Aogera::Component::Behavior.new(kind: :chase),
      combatant: Aogera::Component::Combatant.new(attack: 1)
    )
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    world.add_relation(kind: :targets, source_id: goblin_id, target_id: hero_id)

    controller = Aogera::RealtimeController.new(npc_interval: 4)
    level = level_with(spawns: [])

    early = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: level,
      world: world.view,
      controlled_id: hero_id,
      tick_number: 3
    )
    due = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: level,
      world: world.view,
      controlled_id: hero_id,
      tick_number: 4
    ).to_a

    assert_empty early
    assert_equal 2, due.length
    assert_instance_of Aogera::Simulation::Commands::SetSteeringTarget, due.fetch(0)
    assert_instance_of Aogera::Simulation::Commands::Attack, due.fetch(1)
  end

  def test_chase_sets_live_world_space_entity_goal_without_grid_or_pathfinder
    world = Aogera::World.new
    goblin_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      melee_attack: Aogera::Component::MeleeAttack.new(reach: 0.1, arc_degrees: 110.0),
      behavior: Aogera::Component::Behavior.new(kind: :chase),
      combatant: Aogera::Component::Combatant.new(attack: 1)
    )
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 4.5, y: 0.0, z: 2.75),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    world.add_relation(kind: :targets, source_id: goblin_id, target_id: hero_id)

    controller = Aogera::RealtimeController.new(npc_interval: 1)
    commands = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: Object.new,
      world: world.view,
      controlled_id: hero_id,
      tick_number: 1
    ).to_a

    assert_equal 1, commands.length
    target_command = commands.fetch(0)
    assert_instance_of Aogera::Simulation::Commands::SetSteeringTarget, target_command
    assert_equal goblin_id, target_command.entity_id
    assert_equal hero_id, target_command.goal_entity_id
    assert_in_delta 4.5, target_command.x
    assert_in_delta 2.75, target_command.z
    refute controller.instance_variable_defined?(:@pathfinder)
  end

  def test_melee_intent_preserves_pursuit_until_attack_is_validated
    world = Aogera::World.new
    goblin_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      steering_target: Aogera::Component::SteeringTarget.new(x: 3.5, z: 2.5),
      melee_attack: Aogera::Component::MeleeAttack.new(reach: 0.65, arc_degrees: 110.0),
      behavior: Aogera::Component::Behavior.new(kind: :chase),
      combatant: Aogera::Component::Combatant.new(attack: 1)
    )
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    world.add_relation(kind: :targets, source_id: goblin_id, target_id: hero_id)

    commands = Aogera::RealtimeController.new(npc_interval: 1).build(
      input: Aogera::Input::Snapshot.empty,
      level: level_with(spawns: []),
      world: world.view,
      controlled_id: hero_id,
      tick_number: 1
    ).to_a

    assert_equal 2, commands.length
    target_command = commands.fetch(0)
    assert_instance_of Aogera::Simulation::Commands::SetSteeringTarget, target_command
    assert_equal hero_id, target_command.goal_entity_id
    assert_instance_of Aogera::Simulation::Commands::Attack, commands.fetch(1)
    refute commands.any? { |command| command.is_a?(Aogera::Simulation::Commands::ClearSteeringTarget) }
  end

  def test_player_command_precedes_npc_goal_and_attack_when_both_are_due
    world = Aogera::World.new
    goblin_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      melee_attack: Aogera::Component::MeleeAttack.new(reach: 0.65, arc_degrees: 110.0),
      behavior: Aogera::Component::Behavior.new(kind: :chase),
      combatant: Aogera::Component::Combatant.new(attack: 1)
    )
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    world.add_relation(kind: :targets, source_id: goblin_id, target_id: hero_id)

    commands = Aogera::RealtimeController.new(npc_interval: 1).build(
      input: move_input(:move_forward),
      level: level_with(spawns: []),
      world: world.view,
      controlled_id: hero_id,
      tick_number: 1
    ).to_a

    assert_equal 3, commands.length
    assert_instance_of Aogera::Simulation::Commands::GroundMove, commands.fetch(0)
    assert_equal hero_id, commands.fetch(0).entity_id
    assert_instance_of Aogera::Simulation::Commands::SetSteeringTarget, commands.fetch(1)
    assert_equal goblin_id, commands.fetch(1).entity_id
    assert_instance_of Aogera::Simulation::Commands::Attack, commands.fetch(2)
    assert_equal goblin_id, commands.fetch(2).attacker_id
  end
end
