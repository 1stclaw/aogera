# frozen_string_literal: true

module Aogera
  module Input
    class Mapper
      ACTIONS = {
        w: :move_north,
        up: :move_north,
        s: :move_south,
        down: :move_south,
        a: :move_west,
        left: :move_west,
        d: :move_east,
        right: :move_east,
        enter: :interact,
        space: :attack,
        q: :quit,
        escape: :cancel
      }.freeze

      def map(physical_event)
        kind = ACTIONS[physical_event.key]
        return unless kind

        Action.new(
          kind: kind,
          state: physical_event.state
        )
      end
    end
  end
end
