# frozen_string_literal: true

module Aogera
  class FirstPersonView
    DEFAULT_EYE_HEIGHT = 0.68
    DEFAULT_FOVY = 60.0
    DEFAULT_MOUSE_SENSITIVITY = 0.0025
    MAX_PITCH = Math::PI * 0.47
    FULL_TURN = Math::PI * 2.0
    QUARTER_TURN = Math::PI / 2.0

    YAW_BY_DIRECTION = {
      north: 0.0,
      east: QUARTER_TURN,
      south: Math::PI,
      west: -QUARTER_TURN
    }.freeze

    attr_reader :yaw, :pitch, :eye_height, :fovy

    def self.for_direction(direction, **options)
      yaw = YAW_BY_DIRECTION.fetch(direction) do
        raise ArgumentError, "unknown cardinal direction: #{direction.inspect}"
      end

      new(yaw: yaw, **options)
    end

    def initialize(
      yaw: 0.0,
      pitch: 0.0,
      eye_height: DEFAULT_EYE_HEIGHT,
      fovy: DEFAULT_FOVY,
      mouse_sensitivity: DEFAULT_MOUSE_SENSITIVITY
    )
      @yaw = wrap_yaw(Float(yaw))
      @pitch = clamp_pitch(Float(pitch))
      @eye_height = Float(eye_height)
      @fovy = Float(fovy)
      @mouse_sensitivity = Float(mouse_sensitivity)
    end

    def rotate(dx:, dy:)
      @yaw = wrap_yaw(@yaw + (Float(dx) * @mouse_sensitivity))
      @pitch = clamp_pitch(@pitch - (Float(dy) * @mouse_sensitivity))
      self
    end

    def forward_vector
      horizontal = Math.cos(pitch)

      [
        Math.sin(yaw) * horizontal,
        Math.sin(pitch),
        -Math.cos(yaw) * horizontal
      ].freeze
    end

    def ground_movement_delta(forward:, strafe:, distance:)
      x = (Math.sin(yaw) * forward) + (Math.cos(yaw) * strafe)
      z = (-Math.cos(yaw) * forward) + (Math.sin(yaw) * strafe)
      length = Math.hypot(x, z)
      return [0.0, 0.0].freeze if length.zero?

      scale = Float(distance) / length
      [(x * scale), (z * scale)].freeze
    end

    private

    def wrap_yaw(value)
      ((value + Math::PI) % FULL_TURN) - Math::PI
    end

    def clamp_pitch(value)
      [[value, -MAX_PITCH].max, MAX_PITCH].min
    end
  end
end
