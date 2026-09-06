# frozen_string_literal: true

module Aogera
  class ModeStack
    def initialize
      @modes = []
    end

    def push(mode)
      @modes << mode
      mode
    end

    def pop
      raise "mode stack is empty" if empty?

      @modes.pop
    end

    def current
      @modes.last || raise("mode stack is empty")
    end

    def empty?
      @modes.empty?
    end

    def size
      @modes.size
    end
  end
end
