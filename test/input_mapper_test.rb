# frozen_string_literal: true

require_relative "test_helper"

class InputMapperTest < Minitest::Test
  def setup
    @mapper = Aogera::Input::Mapper.new
  end

  def test_escape_maps_to_cancel
    action = @mapper.map(:escape)

    assert_equal :cancel, action.kind
    assert_equal :pressed, action.state
  end

  def test_enter_maps_to_interact_and_space_maps_to_attack
    assert_equal :interact, @mapper.map(:enter).kind
    assert_equal :attack, @mapper.map(:space).kind
  end

  def test_mapper_preserves_kitty_event_state
    physical = Aogera::Host::KeyEvent.new(
      key: :w,
      state: :released
    )

    action = @mapper.map(physical)

    assert_equal :move_north, action.kind
    assert_equal :released, action.state
  end

  def test_q_still_maps_to_quit
    assert_equal :quit, @mapper.map(:q).kind
  end
end
