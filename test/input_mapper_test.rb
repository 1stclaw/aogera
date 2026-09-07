# frozen_string_literal: true

require_relative "test_helper"

class InputMapperTest < Minitest::Test
  def setup
    @mapper = Aogera::Input::Mapper.new
  end

  def test_escape_maps_to_cancel
    action = @mapper.map(key_event(:escape))

    assert_equal :cancel, action.kind
    assert_equal :pressed, action.state
  end

  def test_enter_maps_to_interact_and_space_maps_to_attack
    assert_equal :interact, @mapper.map(key_event(:enter)).kind
    assert_equal :attack, @mapper.map(key_event(:space)).kind
  end

  def test_mapper_preserves_key_event_state
    action = @mapper.map(key_event(:w, state: :released))

    assert_equal :move_north, action.kind
    assert_equal :released, action.state
  end

  def test_q_maps_to_quit
    assert_equal :quit, @mapper.map(key_event(:q)).kind
  end

  private

  def key_event(key, state: :pressed)
    Aogera::Host::KeyEvent.new(key: key, state: state)
  end
end
