# frozen_string_literal: true

module Aogera
  class Session
    def initialize(characters:)
      @characters = normalize_characters(characters)
    end

    def character(character_key)
      @characters.fetch(normalize_key(character_key))
    end

    def character_keys
      @characters.keys.freeze
    end

    def apply_effect(effect)
      case effect
      in Effect::DamageCharacter
        damage_character(effect.character_key, effect.amount)
      else
        raise ArgumentError,
          "unsupported persistent effect: #{effect.inspect}"
      end
    end

    def apply_effects(effects)
      effects.each { |effect| validate_effect!(effect) }
      effects.each { |effect| apply_effect(effect) }
    end

    def damage_character(character_key, amount)
      validate_amount!(amount)
      current = character(character_key)
      replace_character(
        character_key,
        current.replace(hp: [current.hp - amount, 0].max)
      )
    end

    def heal_character(character_key, amount)
      validate_amount!(amount)
      current = character(character_key)
      replace_character(
        character_key,
        current.replace(hp: [current.hp + amount, current.max_hp].min)
      )
    end

    def spend_mp(character_key, amount)
      validate_amount!(amount)
      current = character(character_key)
      return false if amount > current.mp

      replace_character(
        character_key,
        current.replace(mp: current.mp - amount)
      )
      true
    end

    def restore_mp(character_key, amount)
      validate_amount!(amount)
      current = character(character_key)
      replace_character(
        character_key,
        current.replace(mp: [current.mp + amount, current.max_mp].min)
      )
    end

    private

    def normalize_characters(characters)
      unless characters.is_a?(Hash)
        raise ArgumentError, "session characters must be a Hash"
      end
      characters.each_with_object({}) do |(key, value), result|
        normalized = normalize_key(key)
        raise ArgumentError, "duplicate character: #{normalized.inspect}" if result.key?(normalized)
        unless value.is_a?(Character)
          raise ArgumentError, "invalid character for #{normalized.inspect}: #{value.inspect}"
        end
        result[normalized] = value
      end
    end

    def validate_effect!(effect)
      case effect
      in Effect::DamageCharacter
        character(effect.character_key)
        validate_amount!(effect.amount)
      else
        raise ArgumentError,
          "unsupported persistent effect: #{effect.inspect}"
      end
    end

    def validate_amount!(amount)
      return if amount.is_a?(Integer) && amount >= 0

      raise ArgumentError,
        "character state change amount must be a non-negative Integer"
    end

    def normalize_key(key)
      key.to_sym
    end

    def replace_character(character_key, replacement)
      @characters[normalize_key(character_key)] = replacement
      replacement
    end
  end
end
