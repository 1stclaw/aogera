# frozen_string_literal: true

require_relative "test_helper"

class FirstPersonViewTest < Minitest::Test
  def test_cardinal_direction_matches_initial_authored_facing
    assert_equal :north, Aogera::FirstPersonView.for_direction(:north).cardinal_direction
    assert_equal :east, Aogera::FirstPersonView.for_direction(:east).cardinal_direction
    assert_equal :south, Aogera::FirstPersonView.for_direction(:south).cardinal_direction
    assert_equal :west, Aogera::FirstPersonView.for_direction(:west).cardinal_direction
  end

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

  def test_grid_movement_is_relative_to_current_view_heading
    east = Aogera::FirstPersonView.for_direction(:east)

    assert_equal [1, 0], east.grid_movement_delta(forward: 1, strafe: 0)
    assert_equal [0, 1], east.grid_movement_delta(forward: 0, strafe: 1)
    assert_equal [1, 1], east.grid_movement_delta(forward: 1, strafe: 1)
  end
end
