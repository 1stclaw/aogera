# frozen_string_literal: true

module Aogera
  module Input
    class Handoff
      def initialize
        @write_buffer = []
        @read_buffer = []
      end

      def push(action)
        @write_buffer << action
      end

      def flip!
        unless @read_buffer.empty?
          raise(
            "completed input batch must be consumed " \
            "before the next handoff"
          )
        end

        @write_buffer, @read_buffer =
          @read_buffer, @write_buffer

        self
      end

      def take_completed
        completed = @read_buffer.dup.freeze
        @read_buffer.clear
        completed
      end
    end
  end
end
