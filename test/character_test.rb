# frozen_string_literal: true

require_relative "test_helper"

class CharacterTest < Minitest::Test
  def test_character_is_flat_persistent_rpg_state
    character = Aogera::Character.new(
      hp: 10, max_hp: 10,
      mp: 4, max_mp: 4,
      attack: 2
    )

    assert_equal 10, character.hp
    assert_equal 4, character.mp
    assert_equal 2, character.attack
  end

  def test_with_returns_new_validated_character
    character = Aogera::Character.new(
      hp: 10, max_hp: 10,
      mp: 4, max_mp: 4,
      attack: 2
    )
    replacement = character.with(hp: 7)

    assert_equal 10, character.hp
    assert_equal 7, replacement.hp
    assert_equal 2, replacement.attack
  end

  def test_character_is_a_data_value
    character = Aogera::Character.new(
      hp: 10, max_hp: 10,
      mp: 4, max_mp: 4,
      attack: 2
    )
    equivalent = Aogera::Character.new(
      hp: 10, max_hp: 10,
      mp: 4, max_mp: 4,
      attack: 2
    )

    assert_instance_of Aogera::Character, character
    assert_equal equivalent, character
    assert character.frozen?
  end

  def test_with_revalidates_character_state
    character = Aogera::Character.new(
      hp: 10, max_hp: 10,
      mp: 4, max_mp: 4,
      attack: 2
    )

    error = assert_raises(ArgumentError) do
      character.with(hp: 11)
    end

    assert_match(/hp is outside/, error.message)
  end
end
