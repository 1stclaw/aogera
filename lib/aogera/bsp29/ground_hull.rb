# frozen_string_literal: true

module Aogera
  module BSP29
    # Ground-movement adapter for Quake's standard compiled player hull.
    #
    # Aogera Position.y is currently the actor's feet height. BSP29 hull 1 is
    # compiled around a Quake-style origin with vertical bounds -24..32, so
    # move the trace point 24 units above the feet before traversing clipnodes.
    #
    # The compiled hull itself defines static-world clearance. GroundBody
    # radius continues to define dynamic actor-vs-actor collision. The adapter
    # records the authored GroundBody radius it is bound to and rejects traces
    # for a different radius so fixed BSP clearance cannot be reused silently
    # for another actor shape.
    class GroundHull
      HULL_INDEX = 1
      RADIUS_EPSILON = 1e-9

      # BSP29 hull 1 is a fixed Quake collision box. These dimensions are
      # collision-source facts, not replacements for Aogera GroundBody radii.
      HORIZONTAL_HALF_EXTENT = 16.0
      MIN_Y = -24.0
      MAX_Y = 32.0
      ORIGIN_ABOVE_FEET = -MIN_Y

      attr_reader :ground_body_radius

      def self.for_world(map_data:, ground_body_radius:)
        new(
          clip_hull: ClipHull.for_world(
            map_data: map_data,
            hull_index: HULL_INDEX
          ),
          ground_body_radius: ground_body_radius
        )
      end

      def initialize(clip_hull:, ground_body_radius:)
        @clip_hull = clip_hull
        @ground_body_radius = Float(ground_body_radius)
        unless @ground_body_radius.positive?
          raise ArgumentError, "ground_body_radius must be positive"
        end
      end

      # Positive means the compiled hull requires more horizontal wall
      # clearance than the actor's authored dynamic GroundBody circle.
      def horizontal_clearance_delta
        HORIZONTAL_HALF_EXTENT - ground_body_radius
      end

      def trace(
        start_x:,
        start_z:,
        end_x:,
        end_z:,
        feet_y:,
        ground_body_radius:
      )
        validate_ground_body_radius!(ground_body_radius)

        origin_y = Float(feet_y) + ORIGIN_ABOVE_FEET
        @clip_hull.trace(
          start_position: Vec3.new(
            x: Float(start_x),
            y: origin_y,
            z: Float(start_z)
          ),
          end_position: Vec3.new(
            x: Float(end_x),
            y: origin_y,
            z: Float(end_z)
          )
        )
      end

      private

      def validate_ground_body_radius!(radius)
        radius = Float(radius)
        return if (radius - ground_body_radius).abs <= RADIUS_EPSILON

        raise ArgumentError,
          "BSP29 ground hull is bound to GroundBody radius " \
          "#{ground_body_radius}, got #{radius}"
      end
    end
  end
end
