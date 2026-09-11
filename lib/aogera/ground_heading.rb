# frozen_string_literal: true

module Aogera
  GroundHeading = Data.define(:dx, :dz) do
    def initialize(dx:, dz:)
      dx = Float(dx)
      dz = Float(dz)
      magnitude = Math.hypot(dx, dz)
      unless dx.finite? && dz.finite? && magnitude.positive? && magnitude.finite?
        raise ArgumentError, "ground heading must be non-zero"
      end

      super(dx: dx / magnitude, dz: dz / magnitude)
    rescue ArgumentError, TypeError
      raise ArgumentError, "ground heading must be a finite non-zero vector"
    end
  end
end
