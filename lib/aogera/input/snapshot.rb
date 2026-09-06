# frozen_string_literal: true

module Aogera
  module Input
    class Snapshot
      def self.from(actions)
        Tracker.new.snapshot(actions)
      end

      def self.empty
        new(
          held: {},
          pressed: {},
          released: {}
        )
      end

      def initialize(held:, pressed:, released:)
        @held = held.dup.freeze
        @pressed = pressed.dup.freeze
        @released = released.dup.freeze
      end

      def held?(kind)
        @held.key?(kind)
      end

      def pressed?(kind)
        @pressed.key?(kind)
      end

      def released?(kind)
        @released.key?(kind)
      end
    end
  end
end
