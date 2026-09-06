# frozen_string_literal: true

require_relative "test_helper"

class FixedStepTest < Minitest::Test
  def test_reports_due_steps_at_fixed_rate
    fixed = Aogera::FixedStep.new(hz: 10).start(100.0)

    assert_equal 0, fixed.due_steps(100.05)
    assert_equal 1, fixed.due_steps(100.10)
    assert_equal 2, fixed.due_steps(100.31)
  end

  def test_reports_wait_time_until_next_tick
    fixed = Aogera::FixedStep.new(hz: 10).start(100.0)

    assert_in_delta 0.075, fixed.wait_time(100.025), 0.000_001
  end

  def test_caps_catch_up_after_long_stall
    fixed = Aogera::FixedStep.new(
      hz: 10,
      max_catch_up_steps: 3
    ).start(100.0)

    assert_equal 3, fixed.due_steps(101.0)
    assert_in_delta 0.1, fixed.wait_time(101.0), 0.000_001
  end
end
