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
        key, state = physical_key_and_state(physical_event)
        kind = ACTIONS[key]
        return unless kind

        Action.new(
          kind: kind,
          state: state
        )
      end

      private

      def physical_key_and_state(event)
        if event.respond_to?(:key) && event.respond_to?(:state)
          [event.key, event.state]
        else
          [event, :pressed]
        end
      end
    end
  end
end
