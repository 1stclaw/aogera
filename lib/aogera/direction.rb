# frozen_string_literal: true

module Aogera
  module Direction
    DELTAS = {
      north: [0, -1].freeze,
      east: [1, 0].freeze,
      south: [0, 1].freeze,
      west: [-1, 0].freeze
    }.freeze

    ORDER = %i[north east south west].freeze
    VECTORS = ORDER.map { |direction| DELTAS.fetch(direction) }.freeze
    BY_DELTA = DELTAS.to_h { |direction, delta| [delta, direction] }.freeze

    module_function

    def delta(direction)
      DELTAS[direction]
    end

    def for_delta(dx, dy)
      BY_DELTA[[dx, dy]]
    end
  end
end
