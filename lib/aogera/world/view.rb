# frozen_string_literal: true

module Aogera
  class World
    class View
      def initialize(world)
        @world = world
      end

      def entity?(entity_id)
        @world.entity?(entity_id)
      end

      def entity_ids
        @world.entity_ids
      end

      def component(entity_id, name)
        @world.component(entity_id, name)
      end

      def relation_targets(kind:, source_id:)
        @world.relation_targets(kind: kind, source_id: source_id)
      end
    end
  end
end
