# frozen_string_literal: true

require_relative "test_helper"

class PlayCombatTest < Minitest::Test
  include AogeraTestSupport

  def test_space_attacks_adjacent_combatant_without_paired_retaliation
    mode, simulation, session, goblin_id = build_play

    result = mode.advance(input: action_input(:attack))

    assert_equal :advanced, result
    assert_equal 1, mode.step_number
    assert_equal 2, simulation.world_view.component(goblin_id, :health).current
    assert_equal 10, session.character(:hero).hp
  end

  def test_melee_uses_continuous_view_arc_instead_of_cardinal_facing
    yaw = 40.0 * Math::PI / 180.0
    view = Aogera::FirstPersonView.new(yaw: yaw)
    mode, simulation, _session, goblin_id = build_play(view: view)

    mode.advance(input: action_input(:attack))

    assert_equal 2, simulation.world_view.component(goblin_id, :health).current
  end

  def test_melee_does_not_hit_target_outside_authored_arc
    yaw = 20.0 * Math::PI / 180.0
    view = Aogera::FirstPersonView.new(yaw: yaw)
    mode, simulation, _session, goblin_id = build_play(view: view)

    mode.advance(input: action_input(:attack))

    assert_equal 4, simulation.world_view.component(goblin_id, :health).current
  end

  def test_melee_cannot_reach_target_through_static_wall
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
      spawns: [
        Aogera::Level::Spawn.new(
          key: :goblin,
          prototype: :goblin,
          x: 3,
          y: 1
        )
      ],
      entries: [default_entry(x: 1, y: 1, facing: :east)],
      default_entry: :start,
      relations: []
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog(melee_reach: 2.0)
    )
    session = test_session
    simulation.spawn_character(character_key: :hero, prototype: :player)
    goblin_id = simulation.entity_id_for_spawn(:goblin)
    mode = Aogera::Mode::Play.new(
      simulation: simulation,
      session: session,
      player_key: :hero,
      dialogues: dialogue_catalog,
      view: Aogera::FirstPersonView.for_direction(:east)
    )

    mode.advance(input: action_input(:attack))

    assert_equal 4, simulation.world_view.component(goblin_id, :health).current
  end

  def test_blocking_actor_occludes_melee_target
    level = level_with(
      width: 6,
      height: 4,
      spawns: [
        Aogera::Level::Spawn.new(
          key: :villager,
          prototype: :villager,
          x: 2,
          y: 1
        ),
        Aogera::Level::Spawn.new(
          key: :goblin,
          prototype: :goblin,
          x: 3,
          y: 1
        )
      ],
      entries: [default_entry(x: 1, y: 1, facing: :east)],
      default_entry: :start
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog(melee_reach: 2.0)
    )
    session = test_session
    simulation.spawn_character(character_key: :hero, prototype: :player)
    goblin_id = simulation.entity_id_for_spawn(:goblin)
    mode = Aogera::Mode::Play.new(
      simulation: simulation,
      session: session,
      player_key: :hero,
      dialogues: dialogue_catalog,
      view: Aogera::FirstPersonView.for_direction(:east)
    )

    mode.advance(input: action_input(:attack))

    assert_equal 4, simulation.world_view.component(goblin_id, :health).current
  end

  def test_second_attack_defeats_goblin
    mode, simulation, session, goblin_id = build_play

    mode.advance(input: action_input(:attack))
    result = mode.advance(input: action_input(:attack))

    assert_equal :advanced, result
    assert_equal 2, mode.step_number
    assert_equal 0, simulation.world_view.component(goblin_id, :health).current
    assert_equal 10, session.character(:hero).hp
    assert_nil simulation.world_view.component(goblin_id, :renderable)
    assert_nil simulation.world_view.component(goblin_id, :collision)
    assert_nil simulation.world_view.component(goblin_id, :behavior)
    assert_nil simulation.world_view.component(goblin_id, :combatant)
  end

  def test_adjacent_enemy_attacks_autonomously_when_npc_cadence_is_due
    controller = Aogera::RealtimeController.new(
      npc_interval: 3
    )
    mode, _simulation, session, _goblin_id = build_play(
      controller: controller
    )

    2.times do
      mode.advance(input: Aogera::Input::Snapshot.empty)
    end
    assert_equal 10, session.character(:hero).hp

    mode.advance(input: Aogera::Input::Snapshot.empty)

    assert_equal 9, session.character(:hero).hp
    assert_equal 3, mode.step_number
  end

  def test_lethal_player_attack_invalidates_due_enemy_attack_same_tick
    controller = Aogera::RealtimeController.new(
      npc_interval: 1
    )
    mode, simulation, session, goblin_id = build_play(
      controller: controller,
      player_attack: 4
    )

    mode.advance(input: action_input(:attack))

    assert_equal 0, simulation.world_view.component(goblin_id, :health).current
    assert_equal 10, session.character(:hero).hp
  end

  def test_attack_without_target_still_consumes_a_world_tick
    level = level_with(
      spawns: [],
      entries: [default_entry(x: 2, y: 2, facing: :east)],
      default_entry: :start
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog
    )
    session = test_session
    simulation.spawn_character(character_key: :hero, prototype: :player)
    mode = Aogera::Mode::Play.new(
      simulation: simulation,
      session: session,
      player_key: :hero,
      dialogues: dialogue_catalog
    )

    result = mode.advance(input: action_input(:attack))

    assert_equal :advanced, result
    assert_equal 1, mode.step_number
  end

  def test_enter_does_not_start_combat_and_world_still_ticks
    mode, simulation, _session, goblin_id = build_play

    result = mode.advance(input: action_input(:interact))

    assert_equal :advanced, result
    assert_equal 1, mode.step_number
    assert_equal 4, simulation.world_view.component(goblin_id, :health).current
  end

  private

  def build_play(
    controller: Aogera::RealtimeController.new,
    player_attack: 2,
    view: nil
  )
    level = level_with(
      spawns: [
        Aogera::Level::Spawn.new(
          key: :goblin,
          prototype: :goblin,
          x: 3,
          y: 2
        )
      ],
      entries: [default_entry(x: 2, y: 2, facing: :east)],
      default_entry: :start,
      relations: [
        Aogera::Level::Relation.new(
          kind: :targets,
          source: :goblin,
          target: :start
        )
      ]
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog
    )
    session = Aogera::Session.new(
      characters: {
        hero: Aogera::Character.new(
          hp: 10,
          max_hp: 10,
          mp: 4,
          max_mp: 4,
          attack: player_attack
        )
      }
    )
    simulation.spawn_character(character_key: :hero, prototype: :player)
    goblin_id = simulation.entity_id_for_spawn(:goblin)
    mode = Aogera::Mode::Play.new(
      simulation: simulation,
      session: session,
      player_key: :hero,
      dialogues: dialogue_catalog,
      controller: controller,
      view: view
    )

    [mode, simulation, session, goblin_id]
  end
end
