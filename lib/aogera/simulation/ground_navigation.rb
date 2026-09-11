# frozen_string_literal: true

module Aogera
  class Simulation
    class GroundNavigation
      Decision = Data.define(:status, :heading)

      ARRIVED = :arrived
      DIRECT = :direct
      LOCAL_AVOIDANCE = :local_avoidance
      ROUTE_NEEDED = :route_needed
      STATUSES = [ARRIVED, DIRECT, LOCAL_AVOIDANCE, ROUTE_NEEDED].freeze

      MOTION_EPSILON = 1e-9
      DEFAULT_PROBE_DISTANCE = Realtime::NPC_SPEED / Realtime::TICK_HZ
      TURN_ANGLES = [45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0].freeze
      TURNAROUND_DOT = -0.95
      DUPLICATE_DOT = 0.999_999

      def initialize(
        ground_space: GroundSpace.new,
        probe_distance: DEFAULT_PROBE_DISTANCE
      )
        @ground_space = ground_space
        @probe_distance = validate_positive_number(
          probe_distance,
          :probe_distance
        )
      end

      def query(
        level:,
        world:,
        source_id:,
        goal_x:,
        goal_z:,
        goal_entity_id: nil,
        previous_heading: nil
      )
        source = @ground_space.position(world: world, entity_id: source_id)
        return route_needed unless source

        radius = @ground_space.radius(world: world, entity_id: source_id)
        unless radius.positive?
          raise ArgumentError,
            "ground-navigation source has no positive GroundBody radius"
        end

        to_goal_x = Float(goal_x) - source.x
        to_goal_z = Float(goal_z) - source.z
        goal_distance = Math.hypot(to_goal_x, to_goal_z)
        return decision(ARRIVED) if goal_distance <= MOTION_EPSILON

        direct = GroundHeading.new(dx: to_goal_x, dz: to_goal_z)
        probe_distance = [@probe_distance, goal_distance].min
        direct_trace = probe(
          level: level,
          world: world,
          source_id: source_id,
          source: source,
          radius: radius,
          heading: direct,
          distance: probe_distance,
          goal_entity_id: goal_entity_id
        )
        return decision(DIRECT, direct) if usable_trace?(direct_trace, goal_entity_id)

        alternatives(
          direct: direct,
          previous_heading: previous_heading,
          blocking_trace: direct_trace
        ).each do |heading|
          trace = probe(
            level: level,
            world: world,
            source_id: source_id,
            source: source,
            radius: radius,
            heading: heading,
            distance: probe_distance,
            goal_entity_id: goal_entity_id
          )
          next unless usable_trace?(trace, goal_entity_id)

          return decision(LOCAL_AVOIDANCE, heading)
        end

        route_needed
      end

      private

      def alternatives(direct:, previous_heading:, blocking_trace:)
        headings = []
        previous = normalize_previous(previous_heading)
        if previous && !turnaround?(previous, direct) && dot(previous, direct) < DUPLICATE_DOT
          add_heading(headings, previous)
        end

        if blocking_trace&.hit?
          tangent_a = heading_or_nil(
            dx: -blocking_trace.normal_z,
            dz: blocking_trace.normal_x
          )
          tangent_b = heading_or_nil(
            dx: blocking_trace.normal_z,
            dz: -blocking_trace.normal_x
          )
          [tangent_a, tangent_b]
            .compact
            .sort_by { |heading| -dot(heading, direct) }
            .each { |heading| add_heading(headings, heading) }
        end

        TURN_ANGLES.each do |degrees|
          add_heading(headings, rotate(direct, degrees))
        end

        headings
      end

      def probe(
        level:,
        world:,
        source_id:,
        source:,
        radius:,
        heading:,
        distance:,
        goal_entity_id:
      )
        @ground_space.sweep_circle(
          level: level,
          world: world,
          start_x: source.x,
          start_z: source.z,
          end_x: source.x + (heading.dx * distance),
          end_z: source.z + (heading.dz * distance),
          radius: radius,
          ground_y: source.y,
          ignore_entity_id: source_id,
          entity_filter: movement_blocker(world, goal_entity_id)
        )
      end

      def movement_blocker(world, goal_entity_id)
        lambda do |entity_id|
          return true if entity_id == goal_entity_id

          collision = world.component(entity_id, :collision)
          collision&.blocks_movement || false
        end
      end

      def usable_trace?(trace, goal_entity_id)
        trace.clear? || (!goal_entity_id.nil? && trace.entity_id == goal_entity_id)
      end

      def normalize_previous(previous_heading)
        return unless previous_heading

        GroundHeading.new(
          dx: previous_heading.dx,
          dz: previous_heading.dz
        )
      rescue NoMethodError
        raise ArgumentError, "previous_heading must expose dx and dz"
      end

      def turnaround?(heading, direct)
        dot(heading, direct) <= TURNAROUND_DOT
      end

      def add_heading(headings, candidate)
        return unless candidate
        return if headings.any? { |existing| dot(existing, candidate) >= DUPLICATE_DOT }

        headings << candidate
      end

      def heading_or_nil(dx:, dz:)
        return if Math.hypot(dx, dz) <= MOTION_EPSILON

        GroundHeading.new(dx: dx, dz: dz)
      end

      def rotate(heading, degrees)
        radians = degrees * Math::PI / 180.0
        cosine = Math.cos(radians)
        sine = Math.sin(radians)
        GroundHeading.new(
          dx: (heading.dx * cosine) - (heading.dz * sine),
          dz: (heading.dx * sine) + (heading.dz * cosine)
        )
      end

      def dot(a, b)
        (a.dx * b.dx) + (a.dz * b.dz)
      end

      def decision(status, heading = nil)
        Decision.new(status: status, heading: heading)
      end

      def route_needed
        decision(ROUTE_NEEDED)
      end

      def validate_positive_number(value, name)
        number = Float(value)
        return number if number.positive? && number.finite?

        raise ArgumentError, "#{name} must be positive"
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be positive"
      end
    end
  end
end
