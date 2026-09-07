# frozen_string_literal: true

module Aogera
  module Host
    class Raylib
      WINDOW_WIDTH = 1024
      WINDOW_HEIGHT = 768
      TARGET_FPS = 60
      TITLE = "Aogera #{Aogera::VERSION}"

      KEYS = %i[
        w a s d
        up down left right
        space enter escape q
      ].freeze

      def initialize(
        api:,
        width: WINDOW_WIDTH,
        height: WINDOW_HEIGHT,
        title: TITLE,
        target_fps: TARGET_FPS
      )
        @api = api
        @width = width
        @height = height
        @title = title
        @target_fps = target_fps
        @open = false
      end

      def open
        return if @open

        @api.open_window(
          width: @width,
          height: @height,
          title: @title,
          target_fps: @target_fps
        )
        @api.focus_window
        @api.disable_cursor
        @open = true
      end

      def close
        return unless @open

        @api.enable_cursor
        @api.close_window
        @open = false
      end

      def window_should_close?
        @api.window_should_close?
      end

      def poll_events
        events = key_events
        dx, dy = @api.mouse_delta
        events << Host::MouseMotion.new(dx: dx, dy: dy) unless dx.zero? && dy.zero?
        events
      end

      private

      def key_events
        KEYS.each_with_object([]) do |key, events|
          events << build_key_event(key, :pressed) if @api.key_pressed?(key)
          events << build_key_event(key, :released) if @api.key_released?(key)
        end
      end

      def build_key_event(key, state)
        Host::KeyEvent.new(key: key, state: state)
      end
    end
  end
end
