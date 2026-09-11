# frozen_string_literal: true

module Aogera
  class Simulation
    class GroundSteering
      MOTION_EPSILON = 1e-9

      def initialize(speed: Realtime::NPC_SPEED)
        @step = validate_positive_number(speed, :speed) / Realtime::TICK_HZ
      end

      def build(world:)
        commands = []

        world.entity_ids.each do |entity_id|
          next if world.respond_to?(:retired?) && world.retired?(entity_id)

          target = world.component(entity_id, :steering_target)
          next unless target

          position = world.component(entity_id, :position)
          unless position
            commands << clear_target(entity_id)
            next
          end

          dx = target.x - position.x
          dz = target.z - position.z
          distance = Math.hypot(dx, dz)

          if distance <= MOTION_EPSILON
            commands << clear_target(entity_id)
            next
          end

          scale = [@step / distance, 1.0].min
          commands << Commands::GroundMove.new(
            entity_id: entity_id,
            dx: dx * scale,
            dz: dz * scale
          )
        end

        Commands::Buffer.new(commands)
      end

      private

      def clear_target(entity_id)
        Commands::ClearSteeringTarget.new(entity_id: entity_id)
      end

      def validate_positive_number(value, name)
        number = Float(value)
        return number if number.positive?

        raise ArgumentError, "#{name} must be positive"
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be positive"
      end
    end
  end
end
