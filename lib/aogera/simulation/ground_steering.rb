# frozen_string_literal: true

module Aogera
  class Simulation
    class GroundSteering
      MOTION_EPSILON = 1e-9

      def initialize(
        speed: Realtime::NPC_SPEED,
        ground_space: GroundSpace.new,
        ground_navigation: nil
      )
        @step = validate_positive_number(speed, :speed) / Realtime::TICK_HZ
        @ground_navigation = ground_navigation || GroundNavigation.new(
          ground_space: ground_space,
          probe_distance: @step
        )
      end

      def build(level:, world:)
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

          goal = resolve_goal(world, target)
          unless goal
            commands << clear_target(entity_id)
            next
          end

          goal_x, goal_z, goal_entity_id = goal
          decision = @ground_navigation.query(
            level: level,
            world: world,
            source_id: entity_id,
            goal_x: goal_x,
            goal_z: goal_z,
            goal_entity_id: goal_entity_id,
            previous_heading: world.component(entity_id, :ground_heading)
          )

          case decision.status
          when GroundNavigation::ARRIVED
            commands << clear_target(entity_id)
          when GroundNavigation::DIRECT, GroundNavigation::LOCAL_AVOIDANCE
            heading = decision.heading
            previous = world.component(entity_id, :ground_heading)
            unless previous == heading
              commands << Commands::SetGroundHeading.new(
                entity_id: entity_id,
                dx: heading.dx,
                dz: heading.dz
              )
            end

            distance = Math.hypot(goal_x - position.x, goal_z - position.z)
            step = [@step, distance].min
            commands << Commands::GroundMove.new(
              entity_id: entity_id,
              dx: heading.dx * step,
              dz: heading.dz * step
            )
          when GroundNavigation::ROUTE_NEEDED
            if world.component(entity_id, :ground_heading)
              commands << Commands::ClearGroundHeading.new(entity_id: entity_id)
            end
          else
            raise ArgumentError,
              "unknown ground-navigation status: #{decision.status.inspect}"
          end
        end

        Commands::Buffer.new(commands)
      end

      private

      def resolve_goal(world, target)
        goal_entity_id = target.goal_entity_id
        return [target.x, target.z, nil] unless goal_entity_id
        return unless world.entity?(goal_entity_id)
        return if world.respond_to?(:retired?) && world.retired?(goal_entity_id)

        position = world.component(goal_entity_id, :position)
        return unless position

        [position.x, position.z, goal_entity_id]
      end

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
