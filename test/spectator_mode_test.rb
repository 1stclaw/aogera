# frozen_string_literal: true

require_relative "test_helper"

class SpectatorModeTest < Minitest::Test
  include AogeraTestSupport

  def setup
    level = level_with(
      spawns: [],
      entries: [default_entry(x: 2, y: 2, facing: :north)],
      default_entry: :start
    )
    @simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog
    )
    @camera_entity_id = @simulation.spawn_character(
      character_key: :hero,
      prototype: :player
    )
  end

  def test_camera_starts_at_actor_eye_position_without_moving_actor
    view = Aogera::FirstPersonView.for_direction(:north)
    mode = spectator(view: view)
    actor = @simulation.world_view.component(@camera_entity_id, :position)

    assert_equal [actor.x, actor.y + view.eye_height, actor.z], mode.camera_eye
    assert_equal actor,
      @simulation.world_view.component(@camera_entity_id, :position)
  end

  def test_forward_flight_uses_view_direction_and_does_not_use_actor_movement
    view = Aogera::FirstPersonView.for_direction(:east)
    mode = spectator(view: view, speed: 30.0)
    before_actor = @simulation.world_view.component(@camera_entity_id, :position)
    before_camera = mode.camera_eye

    result = mode.advance(input: held_input(:move_forward))

    assert_equal :advanced, result
    assert_equal 1, mode.step_number
    assert_in_delta before_camera[0] + 1.0, mode.camera_eye[0], 1e-9
    assert_in_delta before_camera[1], mode.camera_eye[1], 1e-9
    assert_in_delta before_camera[2], mode.camera_eye[2], 1e-9
    assert_equal before_actor,
      @simulation.world_view.component(@camera_entity_id, :position)
    assert_equal 0, @simulation.step_number
  end

  def test_forward_flight_follows_pitch_and_vertical_controls_use_world_up
    pitch = 30.0 * Math::PI / 180.0
    mode = spectator(
      view: Aogera::FirstPersonView.new(yaw: 0.0, pitch: pitch),
      speed: 30.0
    )
    before = mode.camera_eye

    mode.advance(input: held_input(:move_forward))

    assert_operator mode.camera_eye[1], :>, before[1]
    assert_operator mode.camera_eye[2], :<, before[2]

    before_up = mode.camera_eye
    mode.advance(input: held_input(:move_up))
    assert_in_delta before_up[1] + 1.0, mode.camera_eye[1], 1e-9

    before_down = mode.camera_eye
    mode.advance(input: held_input(:move_down))
    assert_in_delta before_down[1] - 1.0, mode.camera_eye[1], 1e-9
  end

  def test_diagonal_flight_is_normalized_to_configured_speed
    mode = spectator(
      view: Aogera::FirstPersonView.for_direction(:north),
      speed: 30.0
    )
    before = mode.camera_eye

    mode.advance(input: held_input(:move_forward, :strafe_right, :move_up))

    after = mode.camera_eye
    distance = Math.sqrt(
      ((after[0] - before[0]) ** 2) +
      ((after[1] - before[1]) ** 2) +
      ((after[2] - before[2]) ** 2)
    )
    assert_in_delta 1.0, distance, 1e-9
  end

  def test_quit_does_not_advance_spectator_tick
    mode = spectator

    assert_equal :quit, mode.advance(input: pressed_input(:quit))
    assert_equal 0, mode.step_number
  end

  def test_status_identifies_diagnostic_controls
    status = spectator.status_text

    assert_match(/BSP spectator/, status)
    assert_match(/Space up/, status)
    assert_match(/Shift\/C down/, status)
  end

  private

  def spectator(view: Aogera::FirstPersonView.for_direction(:north), speed: 320.0)
    Aogera::Mode::Spectator.new(
      simulation: @simulation,
      view: view,
      camera_entity_id: @camera_entity_id,
      speed: speed
    )
  end

  def held_input(*kinds)
    Aogera::Input::Snapshot.new(
      held: kinds.to_h { |kind| [kind, true] },
      pressed: {},
      released: {}
    )
  end

  def pressed_input(kind)
    Aogera::Input::Snapshot.new(
      held: {kind => true},
      pressed: {kind => true},
      released: {}
    )
  end
end
