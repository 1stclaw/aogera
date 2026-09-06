# frozen_string_literal: true

module Aogera
  module Mode
    class Dialogue
      attr_reader :simulation, :lines, :index

      def initialize(simulation:, lines:)
        raise ArgumentError, "dialogue mode requires at least one line" if lines.empty?

        @simulation = simulation
        @lines = lines.dup.freeze
        @index = 0
      end

      def advance(input:)
        return :quit if input.pressed?(:quit)
        return :pop if input.pressed?(:cancel)
        return :waiting unless input.pressed?(:interact)

        if index == lines.length - 1
          :pop
        else
          @index += 1
          :advanced
        end
      end

      def current_line = lines.fetch(index)
      def level = simulation.level
      def world_view = simulation.world_view
      def step_number = simulation.step_number
      def status_text = "#{current_line}  [Enter]"
    end
  end
end
