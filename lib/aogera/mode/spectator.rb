# frozen_string_literal: true

module Aogera
  module Mode
    # BSP development mode with a camera that is intentionally detached from
    # gameplay collision and actor locomotion. It exists to inspect arbitrary
    # BSP29 geometry before Quake-style vertical ground physics is available.
    class Spectator
      DEFAULT_SPEED = 320.0

      attr_reader :simulation, :view, :camera_entity_id, :step_number

      def initialize(
        simulation:,
        view:,
        camera_entity_id:,
        speed: DEFAULT_SPEED
      )
        @simulation = simulation
        @view = view
        @camera_entity_id = camera_entity_id
        @step_distance = validate_speed(speed) / Realtime::TICK_HZ
        @step_number = 0

        position = world_view.component(camera_entity_id, :position)
        raise ArgumentError, "camera entity has no position" unless position

        @camera_x = position.x
        @camera_y = position.y + view.eye_height
        @camera_z = position.z
      end

      def advance(input:)
        return :quit if input.pressed?(:quit)
        return :quit if input.pressed?(:cancel)

        move_camera(input)
        @step_number += 1
        :advanced
      end

      def level = simulation.level
      def world_view = simulation.world_view

      def camera_eye
        [@camera_x, @camera_y, @camera_z].freeze
      end

      def status_text
        "BSP spectator | Mouse look. WASD/arrows fly. " \
          "Space up. Shift/C down. Q or Esc quit. Tick #{step_number}"
      end

      private

      def move_camera(input)
        forward = 0
        strafe = 0
        vertical = 0

        forward += 1 if input.held?(:move_forward)
        forward -= 1 if input.held?(:move_backward)
        strafe -= 1 if input.held?(:strafe_left)
        strafe += 1 if input.held?(:strafe_right)
        vertical += 1 if input.held?(:move_up)
        vertical -= 1 if input.held?(:move_down)

        return if forward.zero? && strafe.zero? && vertical.zero?

        dx, dy, dz = view.flight_movement_delta(
          forward: forward,
          strafe: strafe,
          vertical: vertical,
          distance: @step_distance
        )
        @camera_x += dx
        @camera_y += dy
        @camera_z += dz
      end

      def validate_speed(value)
        speed = Float(value)
        return speed if speed.positive? && speed.finite?

        raise ArgumentError, "speed must be a positive finite number"
      rescue ArgumentError, TypeError
        raise ArgumentError, "speed must be a positive finite number"
      end
    end
  end
end
