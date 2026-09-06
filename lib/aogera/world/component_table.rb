# frozen_string_literal: true

module Aogera
  class World
    class ComponentTable
      def initialize
        @entries = []
      end

      def [](entity_id)
        @entries[entity_id]
      end

      def []=(entity_id, value)
        validate_entity_id!(entity_id)
        @entries[entity_id] = value
      end

      def delete(entity_id)
        validate_entity_id!(entity_id)
        @entries[entity_id] = nil
      end

      private

      def validate_entity_id!(entity_id)
        return if entity_id.is_a?(Integer) && entity_id >= 0

        raise ArgumentError,
          "entity_id must be a non-negative Integer"
      end
    end
  end
end
