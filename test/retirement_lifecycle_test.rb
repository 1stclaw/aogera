# frozen_string_literal: true

require_relative "test_helper"

class RetirementLifecycleTest < Minitest::Test
  def setup
    @level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 6, height: 5),
      spawns: [],
      relations: []
    )
    @executor = Aogera::Simulation::Executor.new
    @bindings = Aogera::Simulation::Bindings.new
  end

  def test_retirement_is_explicit_while_entity_and_retained_state_remain
    world = Aogera::World.new
    entity_id = world.spawn(
      health: Aogera::Component::Health.new(current: 0, max: 4),
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      steering_target: Aogera::Component::SteeringTarget.new(x: 3.5, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    execute(
      world,
      Aogera::Simulation::Commands::Defeat.new(entity_id: entity_id)
    )

    assert world.entity?(entity_id)
    assert_includes world.entity_ids, entity_id
    assert world.retired?(entity_id)
    assert world.view.retired?(entity_id)
    assert_instance_of Aogera::Component::Retired,
      world.component(entity_id, :retired)
    assert world.component(entity_id, :position)
    assert world.component(entity_id, :ground_body)
    assert_nil world.component(entity_id, :collision)
    assert_nil world.component(entity_id, :steering_target)
  end

  def test_retired_entity_can_be_explicitly_despawned
    world = Aogera::World.new
    entity_id = world.spawn(
      health: Aogera::Component::Health.new(current: 0, max: 1),
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    execute_buffer(
      world,
      [
        Aogera::Simulation::Commands::Defeat.new(entity_id: entity_id),
        Aogera::Simulation::Commands::Despawn.new(entity_id: entity_id)
      ]
    )

    refute world.entity?(entity_id)
    refute_includes world.entity_ids, entity_id
  end

  def test_ground_move_planned_before_lethal_attack_does_not_execute_after_retirement
    world = Aogera::World.new
    attacker = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      melee_attack: Aogera::Component::MeleeAttack.new(reach: 0.65, arc_degrees: 110.0)
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      health: Aogera::Component::Health.new(current: 1, max: 1),
      behavior: Aogera::Component::Behavior.new(kind: :chase),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      combatant: Aogera::Component::Combatant.new(attack: 1)
    )

    execute_buffer(
      world,
      [
        Aogera::Simulation::Commands::Attack.new(
          attacker_id: attacker,
          target_id: target,
          damage: 1
        ),
        Aogera::Simulation::Commands::GroundMove.new(
          entity_id: target,
          dx: 1.0,
          dz: 0.0
        )
      ]
    )

    position = world.component(target, :position)
    assert world.retired?(target)
    assert_in_delta 2.5, position.x
    assert_in_delta 1.5, position.z
  end

  def test_steering_target_buffered_after_defeat_is_ignored
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      health: Aogera::Component::Health.new(current: 0, max: 1),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    execute_buffer(
      world,
      [
        Aogera::Simulation::Commands::Defeat.new(entity_id: entity_id),
        Aogera::Simulation::Commands::SetSteeringTarget.new(
          entity_id: entity_id,
          x: 4.5,
          z: 2.5
        )
      ]
    )

    assert world.retired?(entity_id)
    assert_nil world.component(entity_id, :steering_target)
  end

  def test_ground_move_buffered_after_defeat_is_ignored
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      health: Aogera::Component::Health.new(current: 0, max: 1),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    execute_buffer(
      world,
      [
        Aogera::Simulation::Commands::Defeat.new(entity_id: entity_id),
        Aogera::Simulation::Commands::GroundMove.new(
          entity_id: entity_id,
          dx: 0.5,
          dz: 0.0
        )
      ]
    )

    ground = world.component(entity_id, :position)
    assert world.retired?(entity_id)
    assert_in_delta 2.5, ground.x
    assert_in_delta 2.5, ground.z
  end

  def test_killing_blocker_while_moving_does_not_lock_player
    world = Aogera::World.new
    player = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      melee_attack: Aogera::Component::MeleeAttack.new(
        reach: 0.65,
        arc_degrees: 110.0
      ),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )
    goblin = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      health: Aogera::Component::Health.new(current: 1, max: 1),
      behavior: Aogera::Component::Behavior.new(kind: :chase),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      combatant: Aogera::Component::Combatant.new(attack: 1)
    )

    execute_buffer(
      world,
      [
        Aogera::Simulation::Commands::Attack.new(
          attacker_id: player,
          target_id: goblin,
          damage: 1
        ),
        Aogera::Simulation::Commands::GroundMove.new(
          entity_id: player,
          dx: 0.8,
          dz: 0.0
        )
      ]
    )

    after_kill = world.component(player, :position)
    assert world.retired?(goblin)
    assert_operator after_kill.x, :>, 2.0

    execute(
      world,
      Aogera::Simulation::Commands::GroundMove.new(
        entity_id: player,
        dx: 0.2,
        dz: 0.0
      )
    )

    after_followup = world.component(player, :position)
    assert_operator after_followup.x, :>, after_kill.x
  end

  def test_arc_query_ignores_retired_target
    world = Aogera::World.new
    source = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    retired = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      retired: Aogera::Component::Retired.new
    )

    hits = Aogera::GroundSpace.new.arc_hits(
      world: world.view,
      source_id: source,
      target_ids: [retired],
      forward_x: 1.0,
      forward_z: 0.0,
      reach: 2.0,
      arc_degrees: 110.0
    )

    assert_empty hits
  end

  def test_default_ground_trace_ignores_retired_body
    world = Aogera::World.new
    retired = world.spawn(
      position: Aogera::Component::Position.new(x: 3.0, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.3),
      retired: Aogera::Component::Retired.new
    )

    trace = Aogera::GroundSpace.new.trace_segment(
      level: @level,
      world: world.view,
      start_x: 1.5,
      start_z: 1.5,
      end_x: 4.5,
      end_z: 1.5
    )

    assert world.retired?(retired)
    assert trace.clear?
  end

  private

  def execute(world, command)
    execute_buffer(world, [command])
  end

  def execute_buffer(world, commands)
    @executor.execute(
      world: world,
      level: @level,
      bindings: @bindings,
      commands: Aogera::Simulation::Commands::Buffer.new(commands)
    )
  end
end

class RetirementWallContactRegressionTest < Minitest::Test
  def test_killing_actor_at_wall_contact_does_not_leave_player_locked
    tiles = {
      " " => Aogera::Level::Tile.new(render_key: :ground, glyph: " ", passable: true),
      "|" => Aogera::Level::Tile.new(render_key: :wall, glyph: "|", passable: false)
    }.freeze
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0,
        rows: Array.new(5, "   |  "),
        tiles: tiles
      ),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    player = world.spawn(
      position: Aogera::Component::Position.new(x: 2.7799998, y: 0.0, z: 1.8),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
      melee_attack: Aogera::Component::MeleeAttack.new(reach: 0.65, arc_degrees: 110.0)
    )
    goblin = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      health: Aogera::Component::Health.new(current: 1, max: 1),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28)
    )
    executor = Aogera::Simulation::Executor.new
    bindings = Aogera::Simulation::Bindings.new

    execute = lambda do |commands|
      executor.execute(
        world: world,
        level: level,
        bindings: bindings,
        commands: Aogera::Simulation::Commands::Buffer.new(commands)
      )
    end

    execute.call([
      Aogera::Simulation::Commands::GroundMove.new(
        entity_id: player,
        dx: 0.0,
        dz: 0.5
      )
    ])
    at_contact = world.component(player, :position)
    assert_operator at_contact.x, :<=, 2.78

    execute.call([
      Aogera::Simulation::Commands::Attack.new(
        attacker_id: player,
        target_id: goblin,
        damage: 1
      ),
      Aogera::Simulation::Commands::GroundMove.new(
        entity_id: player,
        dx: 0.0,
        dz: -0.2
      )
    ])

    after_kill = world.component(player, :position)
    assert world.retired?(goblin)
    assert_operator after_kill.z, :<, at_contact.z

    execute.call([
      Aogera::Simulation::Commands::GroundMove.new(
        entity_id: player,
        dx: 0.0,
        dz: -0.2
      )
    ])

    after_followup = world.component(player, :position)
    assert_operator after_followup.z, :<, after_kill.z
  end
end
