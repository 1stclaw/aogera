# frozen_string_literal: true

require_relative "test_helper"

class RealtimeControllerTest < Minitest::Test
  include AogeraTestSupport

  def test_pressed_movement_executes_immediately_then_repeats_on_cadence
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2, y: 2)
    )
    controller = Aogera::RealtimeController.new(
      player_move_interval: 3,
      npc_interval: 10
    )
    tracker = Aogera::Input::Tracker.new

    first = tracker.snapshot([
      Aogera::Input::Action.new(kind: :move_east, state: :pressed)
    ])
    commands = controller.build(
      input: first,
      level: level_with(spawns: []),
      world: world.view,
      controlled_id: hero_id,
      tick_number: 1
    )
    assert_equal 1, commands.size

    held = tracker.snapshot
    commands = controller.build(
      input: held,
      level: level_with(spawns: []),
      world: world.view,
      controlled_id: hero_id,
      tick_number: 2
    )
    assert_empty commands

    commands = controller.build(
      input: held,
      level: level_with(spawns: []),
      world: world.view,
      controlled_id: hero_id,
      tick_number: 4
    )
    assert_equal 1, commands.size
  end

  def test_npc_behaviors_run_only_on_npc_cadence
    world = Aogera::World.new
    goblin_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1, y: 2),
      behavior: Aogera::Component::Behavior.new(kind: :chase),
      combatant: Aogera::Component::Combatant.new(attack: 1)
    )
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2, y: 2)
    )
    world.add_relation(
      kind: :targets,
      source_id: goblin_id,
      target_id: hero_id
    )

    controller = Aogera::RealtimeController.new(
      player_move_interval: 2,
      npc_interval: 4
    )
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
    )

    assert_empty early
    assert_equal 1, due.size
    assert_instance_of Aogera::Simulation::Commands::Attack, due.to_a.first
  end

  def test_player_command_precedes_npc_command_when_both_are_due
    world = Aogera::World.new
    goblin_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1, y: 2),
      behavior: Aogera::Component::Behavior.new(kind: :chase),
      combatant: Aogera::Component::Combatant.new(attack: 1)
    )
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2, y: 2)
    )
    world.add_relation(
      kind: :targets,
      source_id: goblin_id,
      target_id: hero_id
    )

    controller = Aogera::RealtimeController.new(
      player_move_interval: 1,
      npc_interval: 1
    )
    commands = controller.build(
      input: move_input(:move_east),
      level: level_with(spawns: []),
      world: world.view,
      controlled_id: hero_id,
      tick_number: 1
    ).to_a

    assert_instance_of Aogera::Simulation::Commands::Move, commands.fetch(0)
    assert_equal hero_id, commands.fetch(0).entity_id
    assert_instance_of Aogera::Simulation::Commands::Attack, commands.fetch(1)
    assert_equal goblin_id, commands.fetch(1).attacker_id
  end
end
