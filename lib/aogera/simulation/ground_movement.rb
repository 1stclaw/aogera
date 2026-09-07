# frozen_string_literal: true

module Aogera
  class Simulation
    class GroundMovement
      RADIUS = 0.22
      MAX_SUBSTEP = RADIUS

      def resolve(level:, world:, entity_id:, position:, dx:, dz:)
        dx = Float(dx)
        dz = Float(dz)
        steps = [
          (dx.abs / MAX_SUBSTEP).ceil,
          (dz.abs / MAX_SUBSTEP).ceil,
          1
        ].max
        step_x = dx / steps
        step_z = dz / steps
        x = position.x
        z = position.z

        steps.times do
          x, z = resolve_step(
            level: level,
            world: world,
            entity_id: entity_id,
            x: x,
            z: z,
            dx: step_x,
            dz: step_z
          )
        end

        Component::GroundPosition.new(x: x, z: z)
      end

      private

      def resolve_step(level:, world:, entity_id:, x:, z:, dx:, dz:)
        candidate_x = x + dx
        if clear?(
          level: level,
          world: world,
          entity_id: entity_id,
          x: candidate_x,
          z: z
        )
          x = candidate_x
        end

        candidate_z = z + dz
        if clear?(
          level: level,
          world: world,
          entity_id: entity_id,
          x: x,
          z: candidate_z
        )
          z = candidate_z
        end

        [x, z]
      end

      def clear?(level:, world:, entity_id:, x:, z:)
        min_x = (x - RADIUS).floor
        max_x = (x + RADIUS).floor
        min_y = (z - RADIUS).floor
        max_y = (z + RADIUS).floor

        (min_y..max_y).each do |grid_y|
          (min_x..max_x).each do |grid_x|
            next unless circle_overlaps_cell?(x, z, grid_x, grid_y)
            next if passable_cell?(
              level: level,
              world: world,
              entity_id: entity_id,
              grid_x: grid_x,
              grid_y: grid_y
            )

            return false
          end
        end

        true
      end

      def passable_cell?(level:, world:, entity_id:, grid_x:, grid_y:)
        return false unless level.passable?(grid_x, grid_y)

        !world.entity_ids.any? do |other_id|
          next false if other_id == entity_id

          collision = world.component(other_id, :collision)
          next false unless collision&.blocks_movement

          position = world.component(other_id, :position)
          position && position.x == grid_x && position.y == grid_y
        end
      end

      def circle_overlaps_cell?(x, z, grid_x, grid_y)
        nearest_x = [[x, grid_x.to_f].max, grid_x + 1.0].min
        nearest_z = [[z, grid_y.to_f].max, grid_y + 1.0].min
        delta_x = x - nearest_x
        delta_z = z - nearest_z

        (delta_x * delta_x) + (delta_z * delta_z) < (RADIUS * RADIUS)
      end
    end
  end
end
