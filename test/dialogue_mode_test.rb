# frozen_string_literal: true

require_relative "test_helper"

class DialogueModeTest < Minitest::Test
  include AogeraTestSupport

  def setup
    level = level_with(spawns: [])
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog
    )
    @mode = Aogera::Mode::Dialogue.new(
      simulation: simulation,
      lines: ["First.", "Second."]
    )
  end

  def test_interact_advances_then_pops_after_last_line
    result = @mode.advance(input: action_input(:interact))

    assert_equal :advanced, result
    assert_equal "Second.", @mode.current_line

    result = @mode.advance(input: action_input(:interact))
    assert_equal :pop, result
  end

  def test_cancel_pops_dialogue
    assert_equal :pop, @mode.advance(input: action_input(:cancel))
  end

  def test_quit_still_quits_application
    assert_equal :quit, @mode.advance(input: action_input(:quit))
  end

  def test_unrelated_input_does_not_advance
    result = @mode.advance(input: action_input(:move_north))

    assert_equal :waiting, result
    assert_equal "First.", @mode.current_line
  end
end
