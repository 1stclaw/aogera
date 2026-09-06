# frozen_string_literal: true

require_relative "test_helper"

class ModeStackTest < Minitest::Test
  def test_push_and_pop_change_current_mode
    stack = Aogera::ModeStack.new
    exploration = Object.new
    menu = Object.new

    stack.push(exploration)
    stack.push(menu)

    assert_same menu, stack.current
    assert_same menu, stack.pop
    assert_same exploration, stack.current
  end
end
