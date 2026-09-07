# frozen_string_literal: true

module Aogera
  class Simulation
    class GroundMovement
      def initialize(ground_space: GroundSpace.new)
        @ground_space = ground_space
      end

      def resolve(level:, world:, entity_id:, position:, dx:, dz:)
        radius = @ground_space.radius(world: world, entity_id: entity_id)
        unless radius.positive?
          raise ArgumentError,
            "ground-moving entity has no positive GroundBody radius"
        end

        dx = Float(dx)
        dz = Float(dz)
        steps = [
          (dx.abs / radius).ceil,
          (dz.abs / radius).ceil,
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
            radius: radius,
            x: x,
            z: z,
            dx: step_x,
            dz: step_z
          )
        end

        Component::GroundPosition.new(x: x, z: z)
      end

      private

      def resolve_step(level:, world:, entity_id:, radius:, x:, z:, dx:, dz:)
        candidate_x = x + dx
        if clear?(
          level: level,
          world: world,
          entity_id: entity_id,
          radius: radius,
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
          radius: radius,
          x: x,
          z: candidate_z
        )
          z = candidate_z
        end

        [x, z]
      end

      def clear?(level:, world:, entity_id:, radius:, x:, z:)
        clear_terrain?(level: level, x: x, z: z, radius: radius) &&
          clear_entities?(
            world: world,
            entity_id: entity_id,
            x: x,
            z: z,
            radius: radius
          )
      end

      def clear_terrain?(level:, x:, z:, radius:)
        min_x = (x - radius).floor
        max_x = (x + radius).floor
        min_y = (z - radius).floor
        max_y = (z + radius).floor

        (min_y..max_y).each do |grid_y|
          (min_x..max_x).each do |grid_x|
            next unless circle_overlaps_cell?(
              x,
              z,
              radius,
              grid_x,
              grid_y
            )
            return false unless level.passable?(grid_x, grid_y)
          end
        end

        true
      end

      def clear_entities?(world:, entity_id:, x:, z:, radius:)
        world.entity_ids.none? do |other_id|
          next false if other_id == entity_id

          collision = world.component(other_id, :collision)
          next false unless collision&.blocks_movement

          other_radius = @ground_space.radius(world: world, entity_id: other_id)
          unless other_radius.positive?
            raise ArgumentError,
              "blocking ground entity has no positive GroundBody radius"
          end

          @ground_space.overlaps_entity?(
            world: world,
            x: x,
            z: z,
            radius: radius,
            other_id: other_id
          )
        end
      end

      def circle_overlaps_cell?(x, z, radius, grid_x, grid_y)
        nearest_x = [[x, grid_x.to_f].max, grid_x + 1.0].min
        nearest_z = [[z, grid_y.to_f].max, grid_y + 1.0].min
        delta_x = x - nearest_x
        delta_z = z - nearest_z

        (delta_x * delta_x) + (delta_z * delta_z) < (radius * radius)
      end
    end
  end
end
