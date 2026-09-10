# frozen_string_literal: true

module Aogera
  module BSP29
    # Static ground-clearance query backed by BSP29 compiled hull 1.
    #
    # The compiled hull keeps its fixed Quake dimensions. GroundBody radius is
    # still supplied for policy validation only; it does not resize the BSP
    # hull. One GroundHull adapter is cached per authored radius so navigation
    # can validate different actor bodies without silently reusing a hull bound
    # to another radius.
    class GroundClearance
      def self.for_world(map_data:)
        new(
          clip_hull: ClipHull.for_world(
            map_data: map_data,
            hull_index: GroundHull::HULL_INDEX
          )
        )
      end

      def initialize(clip_hull:)
        @clip_hull = clip_hull
        @ground_hulls = {}
      end

      def trace(
        start_x:,
        start_z:,
        end_x:,
        end_z:,
        feet_y:,
        ground_body_radius:
      )
        hull_for(ground_body_radius).trace(
          start_x: start_x,
          start_z: start_z,
          end_x: end_x,
          end_z: end_z,
          feet_y: feet_y,
          ground_body_radius: ground_body_radius
        )
      end

      def clear?(**arguments)
        trace(**arguments).clear?
      end

      private

      def hull_for(radius)
        radius = Float(radius)
        @ground_hulls[radius] ||= GroundHull.new(
          clip_hull: @clip_hull,
          ground_body_radius: radius
        )
      end
    end
  end
end
