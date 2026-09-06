# frozen_string_literal: true

module Aogera
  class FixedStep
    def initialize(hz:, max_catch_up_steps: 5)
      unless hz.is_a?(Numeric) && hz.positive?
        raise ArgumentError, "hz must be positive"
      end

      unless max_catch_up_steps.is_a?(Integer) && max_catch_up_steps.positive?
        raise ArgumentError, "max_catch_up_steps must be a positive Integer"
      end

      @interval = 1.0 / hz
      @max_catch_up_steps = max_catch_up_steps
      @next_tick = nil
    end

    def start(now)
      @next_tick = now + @interval
      self
    end

    def due_steps(now)
      raise "fixed step has not been started" unless @next_tick

      count = 0
      while now >= @next_tick && count < @max_catch_up_steps
        count += 1
        @next_tick += @interval
      end

      # Do not spiral forever after a debugger stop or terminal stall.
      if count == @max_catch_up_steps && now >= @next_tick
        @next_tick = now + @interval
      end

      count
    end

    def wait_time(now)
      raise "fixed step has not been started" unless @next_tick

      [@next_tick - now, 0.0].max
    end
  end
end
