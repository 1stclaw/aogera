# frozen_string_literal: true

module Aogera
  module Input
    class Tracker
      def initialize
        @held = {}
      end

      def snapshot(actions = [])
        pressed = {}
        released = {}

        actions.each do |action|
          case action.state
          when :pressed
            @held[action.kind] = true
            pressed[action.kind] = true
          when :repeat
            @held[action.kind] = true
          when :released
            @held.delete(action.kind)
            released[action.kind] = true
          else
            raise ArgumentError,
              "unknown input state: #{action.state.inspect}"
          end
        end

        Snapshot.new(
          held: @held,
          pressed: pressed,
          released: released
        )
      end
    end
  end
end
