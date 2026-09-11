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

  def test_wasd_and_arrows_map_to_first_person_movement_actions
    assert_equal :move_forward, @mapper.map(key_event(:w)).kind
    assert_equal :move_backward, @mapper.map(key_event(:s)).kind
    assert_equal :strafe_left, @mapper.map(key_event(:a)).kind
    assert_equal :strafe_right, @mapper.map(key_event(:d)).kind
    assert_equal :move_forward, @mapper.map(key_event(:up)).kind
    assert_equal :strafe_right, @mapper.map(key_event(:right)).kind
  end

  def test_mapper_preserves_key_event_state
    action = @mapper.map(key_event(:w, state: :released))

    assert_equal :move_forward, action.kind
    assert_equal :released, action.state
  end

  def test_mouse_motion_maps_to_value_bearing_look_delta
    look = @mapper.map(
      Aogera::Host::MouseMotion.new(dx: 4.5, dy: -2.0)
    )

    assert_instance_of Aogera::Input::LookDelta, look
    assert_in_delta 4.5, look.dx
    assert_in_delta(-2.0, look.dy)
  end

  def test_q_maps_to_quit
    assert_equal :quit, @mapper.map(key_event(:q)).kind
  end

  def test_spectator_mapping_reuses_space_for_up_and_adds_two_down_keys
    mapper = Aogera::Input::Mapper.spectator

    assert_equal :move_up, mapper.map(key_event(:space)).kind
    assert_equal :move_down, mapper.map(key_event(:c)).kind
    assert_equal :move_down, mapper.map(key_event(:left_shift)).kind
    assert_equal :move_forward, mapper.map(key_event(:w)).kind
    assert_equal :quit, mapper.map(key_event(:q)).kind
  end

  def test_default_mapping_does_not_gain_spectator_down_controls
    assert_nil @mapper.map(key_event(:c))
    assert_nil @mapper.map(key_event(:left_shift))
    assert_equal :attack, @mapper.map(key_event(:space)).kind
  end

  private

  def key_event(key, state: :pressed)
    Aogera::Host::KeyEvent.new(key: key, state: state)
  end
end
