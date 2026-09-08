# frozen_string_literal: true

module Aogera
  module BSP29
    module Coordinates
      module_function

      # Quake is Z-up. Aogera is Y-up with +Z pointing south.
      # Unit magnitude is intentionally unchanged.
      def vector(x, y, z)
        Vec3.new(x: Float(x), y: Float(z), z: -Float(y))
      end

      def bounds(mins, maxs)
        corners = [mins[0], maxs[0]].product(
          [mins[1], maxs[1]],
          [mins[2], maxs[2]]
        ).map do |x, y, z|
          vector(x, y, z)
        end

        Bounds.new(
          mins: Vec3.new(
            x: corners.map(&:x).min,
            y: corners.map(&:y).min,
            z: corners.map(&:z).min
          ),
          maxs: Vec3.new(
            x: corners.map(&:x).max,
            y: corners.map(&:y).max,
            z: corners.map(&:z).max
          )
        )
      end
    end
  end
end
