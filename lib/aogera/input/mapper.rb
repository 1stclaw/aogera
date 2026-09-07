# frozen_string_literal: true

module Aogera
  module Input
    class Mapper
      ACTIONS = {
        w: :move_forward,
        up: :move_forward,
        s: :move_backward,
        down: :move_backward,
        a: :strafe_left,
        left: :strafe_left,
        d: :strafe_right,
        right: :strafe_right,
        enter: :interact,
        space: :attack,
        q: :quit,
        escape: :cancel
      }.freeze

      def map(physical_event)
        case physical_event
        when Host::MouseMotion
          LookDelta.new(
            dx: physical_event.dx,
            dy: physical_event.dy
          )
        when Host::KeyEvent
          map_key_event(physical_event)
        end
      end

      private

      def map_key_event(event)
        kind = ACTIONS[event.key]
        return unless kind

        Action.new(
          kind: kind,
          state: event.state
        )
      end
    end
  end
end
