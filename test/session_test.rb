# frozen_string_literal: true

require_relative "test_helper"

class SessionTest < Minitest::Test
  include AogeraTestSupport

  def test_session_owns_persistent_characters_without_party_policy
    session = test_session

    assert_equal [:hero, :mage], session.character_keys
    assert_equal 10, session.character(:hero).hp
    assert_equal 4, session.character(:hero).mp
    assert_equal 2, session.character(:hero).attack
  end

  def test_public_mutation_surface_is_effect_batch_only
    session = test_session

    assert_respond_to session, :apply_effects
    refute_respond_to session, :apply_effect
    refute_respond_to session, :damage_character
    refute_respond_to session, :heal_character
    refute_respond_to session, :spend_mp
    refute_respond_to session, :restore_mp
  end

  def test_persistent_damage_is_applied_through_effects
    session = test_session
    original = session.character(:hero)

    session.apply_effects([
      Aogera::Effect::DamageCharacter.new(
        character_key: :hero,
        amount: 3
      )
    ])

    damaged = session.character(:hero)
    refute_same original, damaged
    assert_equal 7, damaged.hp
    assert_equal 4, damaged.mp
  end

  def test_persistent_damage_clamps_at_zero
    session = test_session

    session.apply_effects([
      Aogera::Effect::DamageCharacter.new(
        character_key: :hero,
        amount: 99
      )
    ])

    assert_equal 0, session.character(:hero).hp
  end

  def test_effect_batch_is_validated_before_mutation
    session = test_session
    effects = [
      Aogera::Effect::DamageCharacter.new(
        character_key: :hero,
        amount: 2
      ),
      Aogera::Effect::DamageCharacter.new(
        character_key: :unknown,
        amount: 1
      )
    ]

    assert_raises(KeyError) { session.apply_effects(effects) }
    assert_equal 10, session.character(:hero).hp
  end

  def test_effect_amount_is_validated_before_mutation
    session = test_session
    effect = Aogera::Effect::DamageCharacter.new(
      character_key: :hero,
      amount: -1
    )

    assert_raises(ArgumentError) { session.apply_effects([effect]) }
    assert_equal 10, session.character(:hero).hp
  end
end
