# frozen_string_literal: true

require_relative "test_helper"

class InputTrackerTest < Minitest::Test
  def test_press_is_edge_and_held_state_persists_across_ticks
    tracker = Aogera::Input::Tracker.new
    press = Aogera::Input::Action.new(
      kind: :move_forward,
      state: :pressed
    )

    first = tracker.snapshot([press])
    second = tracker.snapshot

    assert first.pressed?(:move_forward)
    assert first.held?(:move_forward)
    refute second.pressed?(:move_forward)
    assert second.held?(:move_forward)
  end

  def test_release_clears_held_state
    tracker = Aogera::Input::Tracker.new
    tracker.snapshot([
      Aogera::Input::Action.new(kind: :move_forward, state: :pressed)
    ])

    released = tracker.snapshot([
      Aogera::Input::Action.new(kind: :move_forward, state: :released)
    ])

    assert released.released?(:move_forward)
    refute released.held?(:move_forward)
    refute tracker.snapshot.held?(:move_forward)
  end

  def test_repeat_keeps_key_held_without_creating_a_press_edge
    tracker = Aogera::Input::Tracker.new

    repeated = tracker.snapshot([
      Aogera::Input::Action.new(kind: :move_forward, state: :repeat)
    ])

    assert repeated.held?(:move_forward)
    refute repeated.pressed?(:move_forward)
  end
end
