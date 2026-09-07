# frozen_string_literal: true

require_relative "scene_2d"

module Aogera
  module Render
    # Compatibility name for the 0.2 series. New code should use Scene2D.
    Scene = Scene2D unless const_defined?(:Scene, false)
  end
end
