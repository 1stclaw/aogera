# frozen_string_literal: true

require_relative "test_helper"

class FirstPersonViewTest < Minitest::Test
  def test_mouse_rotation_changes_yaw_and_pitch_without_raylib_types
    view = Aogera::FirstPersonView.new(mouse_sensitivity: 0.01)

    view.rotate(dx: 10, dy: -5)

    assert_in_delta 0.10, view.yaw
    assert_in_delta 0.05, view.pitch
    assert_equal 3, view.forward_vector.length
  end

  def test_pitch_is_clamped_before_camera_can_flip
    view = Aogera::FirstPersonView.new(mouse_sensitivity: 1.0)

    view.rotate(dx: 0, dy: -100)
    assert_in_delta Aogera::FirstPersonView::MAX_PITCH, view.pitch

    view.rotate(dx: 0, dy: 200)
    assert_in_delta(-Aogera::FirstPersonView::MAX_PITCH, view.pitch)
  end

  def test_ground_movement_uses_continuous_yaw
    view = Aogera::FirstPersonView.new(yaw: Math::PI / 4.0)

    dx, dz = view.ground_movement_delta(
      forward: 1,
      strafe: 0,
      distance: 0.3
    )

    assert_in_delta 0.3, Math.hypot(dx, dz)
    assert_operator dx, :>, 0.0
    assert_operator dz, :<, 0.0
    assert_in_delta dx.abs, dz.abs
  end

  def test_diagonal_ground_input_is_normalized_to_player_speed
    view = Aogera::FirstPersonView.for_direction(:east)

    dx, dz = view.ground_movement_delta(
      forward: 1,
      strafe: 1,
      distance: 0.2
    )

    assert_in_delta 0.2, Math.hypot(dx, dz)
  end
end
