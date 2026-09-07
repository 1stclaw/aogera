# frozen_string_literal: true

require_relative "test_helper"

class PlayModeTest < Minitest::Test
  include AogeraTestSupport

  def setup
    level = level_with(
      spawns: [
        Aogera::Level::Spawn.new(
          key: :villager,
          prototype: :villager,
          x: 3,
          y: 2
        )
      ],
      entries: [default_entry(x: 2, y: 2)],
      default_entry: :start
    )
    @simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog
    )
    @session = test_session
    @simulation.spawn_character(
      character_key: :hero,
      prototype: :player
    )
    @mode = Aogera::Mode::Play.new(
      simulation: @simulation,
      session: @session,
      player_key: :hero,
      dialogues: dialogue_catalog
    )
  end

  def test_play_mode_decides_when_simulation_advances
    result = @mode.advance(input: move_input(:move_forward))

    assert_equal :advanced, result
    assert_equal 1, @mode.step_number
  end

  def test_controlled_character_binding_is_owned_by_simulation
    hero_id = @mode.controlled_entity_id
    position = @mode.world_view.component(hero_id, :position)

    assert_equal hero_id, @simulation.entity_id_for_character(:hero)
    assert_equal :hero, @simulation.character_key_for_entity(hero_id)
    assert_equal [2, 2], [position.x, position.y]
  end

  def test_controlled_world_entity_has_no_persistent_combat_state
    hero_id = @mode.controlled_entity_id

    assert_nil @mode.world_view.component(hero_id, :health)
    assert_nil @mode.world_view.component(hero_id, :combatant)

    hero = @session.character(:hero)
    assert_equal 10, hero.hp
    assert_equal 2, hero.attack
  end

  def test_status_uses_persistent_character_and_solo_controls
    @session.damage_character(:hero, 3)
    @session.spend_mp(:hero, 1)

    assert_match "Hero HP 7/10 MP 3/4", @mode.status_text
    assert_match "Space attack", @mode.status_text
    assert_match "Enter interact", @mode.status_text
  end

  def test_blocked_strafe_still_changes_legacy_facing
    @mode.advance(input: move_input(:strafe_left))

    hero_id = @mode.controlled_entity_id
    position = @mode.world_view.component(hero_id, :position)
    facing = @mode.world_view.component(hero_id, :facing)

    assert_equal [2, 2], [position.x, position.y]
    assert_equal :east, facing.direction
    assert_equal 1, @mode.step_number
  end

  def test_interaction_uses_current_view_heading_without_advancing_simulation
    mode = Aogera::Mode::Play.new(
      simulation: @simulation,
      session: @session,
      player_key: :hero,
      dialogues: dialogue_catalog,
      view: Aogera::FirstPersonView.for_direction(:east)
    )
    before = mode.step_number

    result = mode.advance(input: action_input(:interact))

    assert_instance_of Aogera::Mode::Push, result
    assert_instance_of Aogera::Mode::Dialogue, result.mode
    assert_equal "First line.", result.mode.current_line
    assert_equal mode.controlled_entity_id, result.mode.camera_entity_id
    assert_equal before, mode.step_number
  end

  def test_interact_without_interactable_target_does_not_pause_world
    result = @mode.advance(input: action_input(:interact))

    assert_equal :advanced, result
    assert_equal 1, @mode.step_number
  end

  def test_quit_and_cancel_do_not_advance_simulation
    assert_equal :quit, @mode.advance(input: action_input(:quit))
    assert_equal 0, @mode.step_number

    assert_equal :quit, @mode.advance(input: action_input(:cancel))
    assert_equal 0, @mode.step_number
  end
end
