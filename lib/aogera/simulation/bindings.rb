# frozen_string_literal: true

module Aogera
  class Simulation
    class Bindings
      def initialize
        @character_to_entity = {}
        @entity_to_character = {}
      end

      def bind(character_key:, entity_id:)
        key = character_key.to_sym
        if @character_to_entity.key?(key)
          raise ArgumentError, "character already bound: #{key.inspect}"
        end
        if @entity_to_character.key?(entity_id)
          raise ArgumentError, "entity already bound: #{entity_id.inspect}"
        end

        @character_to_entity[key] = entity_id
        @entity_to_character[entity_id] = key
        entity_id
      end

      def entity_for(character_key)
        @character_to_entity.fetch(character_key.to_sym)
      end

      def character_for(entity_id)
        @entity_to_character[entity_id]
      end

      def bound_character?(character_key)
        @character_to_entity.key?(character_key.to_sym)
      end

      def bound_entity?(entity_id)
        @entity_to_character.key?(entity_id)
      end
    end
  end
end
