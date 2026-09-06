# frozen_string_literal: true

module Aogera
  class Simulation
    class Movement
      def traversable?(level:, world:, x:, y:, except_id: nil)
        return false unless level.passable?(x, y)

        !occupied?(world: world, x: x, y: y, except_id: except_id)
      end

      def occupied?(world:, x:, y:, except_id: nil)
        world.entity_ids.any? do |entity_id|
          next false if entity_id == except_id

          collision = world.component(entity_id, :collision)
          next false unless collision&.blocks_movement

          position = world.component(entity_id, :position)
          position && position.x == x && position.y == y
        end
      end
    end
  end
end
