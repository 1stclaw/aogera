# frozen_string_literal: true

require_relative "test_helper"

class InputHandoffTest < Minitest::Test
  def test_events_after_handoff_belong_to_next_batch
    handoff = Aogera::Input::Handoff.new
    forward = Aogera::Input::Action.new(kind: :move_forward, state: :pressed)
    strafe = Aogera::Input::Action.new(kind: :strafe_right, state: :pressed)

    handoff.push(forward)
    handoff.flip!
    handoff.push(strafe)

    assert_equal [forward], handoff.take_completed

    handoff.flip!

    assert_equal [strafe], handoff.take_completed
  end
end
