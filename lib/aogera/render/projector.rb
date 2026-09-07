# frozen_string_literal: true

require_relative "projector_2d"

module Aogera
  module Render
    # Compatibility name for the 0.2 series. New code should use Projector2D.
    Projector = Projector2D unless const_defined?(:Projector, false)
  end
end
