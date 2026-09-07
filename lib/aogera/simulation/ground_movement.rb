# frozen_string_literal: true

module Aogera
  class Simulation
    class GroundMovement
      MAX_CONTACTS = 4
      MOTION_EPSILON = 1e-9
      NORMAL_EPSILON = 1e-7
      FRACTION_EPSILON = 1e-9

      def initialize(ground_space: GroundSpace.new)
        @ground_space = ground_space
      end

      def resolve(level:, world:, entity_id:, position:, dx:, dz:)
        radius = @ground_space.radius(world: world, entity_id: entity_id)
        unless radius.positive?
          raise ArgumentError,
            "ground-moving entity has no positive GroundBody radius"
        end

        start_x = Float(position.x)
        start_z = Float(position.z)
        x = start_x
        z = start_z
        remaining_x = Float(dx)
        remaining_z = Float(dz)
        contact_normals = []
        blocker = movement_blocker(world)

        MAX_CONTACTS.times do
          break if motion_finished?(remaining_x, remaining_z)

          trace = @ground_space.sweep_circle(
            level: level,
            world: world,
            start_x: x,
            start_z: z,
            end_x: x + remaining_x,
            end_z: z + remaining_z,
            radius: radius,
            ignore_entity_id: entity_id,
            entity_filter: blocker
          )

          # A movement command should begin from valid state. If a later
          # internal sweep reports otherwise, do not commit a penetrated
          # position produced by this command.
          return Component::Position.new(x: start_x, y: position.y, z: start_z) if trace.start_blocked

          x = trace.end_x
          z = trace.end_z
          break unless trace.hit?

          remaining_fraction = 1.0 - trace.fraction
          remaining_x *= remaining_fraction
          remaining_z *= remaining_fraction

          duplicate_contact = add_contact_normal(
            contact_normals,
            trace.normal_x,
            trace.normal_z
          )

          remaining_x, remaining_z = constrained_motion(
            remaining_x,
            remaining_z,
            contact_normals
          )

          # Exact-contact traces should not repeatedly report the same
          # surface when the remaining motion is tangent to or away from it.
          # If floating-point noise does so anyway, stopping this command is
          # safer than exhausting contacts while nudging into another surface.
          if duplicate_contact && trace.fraction <= FRACTION_EPSILON
            remaining_x = 0.0
            remaining_z = 0.0
          end
        end

        resolved = Component::Position.new(x: x, y: position.y, z: z)
        return resolved if contact_normals.empty?
        return resolved unless blocked_position?(
          level: level,
          world: world,
          entity_id: entity_id,
          position: resolved,
          radius: radius,
          entity_filter: blocker
        )

        Component::Position.new(x: start_x, y: position.y, z: start_z)
      end

      private

      def motion_finished?(x, z)
        Math.hypot(x, z) <= MOTION_EPSILON
      end

      def add_contact_normal(normals, x, z)
        normal = [Float(x), Float(z)]
        duplicate = normals.any? do |existing|
          ((existing[0] * normal[0]) + (existing[1] * normal[1])) >=
            (1.0 - NORMAL_EPSILON)
        end
        normals << normal unless duplicate
        duplicate
      end

      def constrained_motion(x, z, normals)
        return [x, z] if allowed_by_all_contacts?(x, z, normals)

        normals.each do |normal_x, normal_z|
          candidate_x, candidate_z = clip_into_surface(
            x,
            z,
            normal_x,
            normal_z
          )
          if allowed_by_all_contacts?(candidate_x, candidate_z, normals)
            return [candidate_x, candidate_z]
          end
        end

        [0.0, 0.0]
      end

      def clip_into_surface(x, z, normal_x, normal_z)
        into_surface = (x * normal_x) + (z * normal_z)
        return [x, z] unless into_surface < 0.0

        [
          x - (normal_x * into_surface),
          z - (normal_z * into_surface)
        ]
      end

      def allowed_by_all_contacts?(x, z, normals)
        normals.all? do |normal_x, normal_z|
          ((x * normal_x) + (z * normal_z)) >= -MOTION_EPSILON
        end
      end

      def blocked_position?(level:, world:, entity_id:, position:, radius:, entity_filter:)
        trace = @ground_space.sweep_circle(
          level: level,
          world: world,
          start_x: position.x,
          start_z: position.z,
          end_x: position.x,
          end_z: position.z,
          radius: radius,
          ignore_entity_id: entity_id,
          entity_filter: entity_filter
        )

        trace.start_blocked
      end

      def movement_blocker(world)
        lambda do |entity_id|
          collision = world.component(entity_id, :collision)
          next false unless collision&.blocks_movement

          radius = @ground_space.radius(world: world, entity_id: entity_id)
          unless radius.positive?
            raise ArgumentError,
              "blocking ground entity has no positive GroundBody radius"
          end

          true
        end
      end
    end
  end
end
