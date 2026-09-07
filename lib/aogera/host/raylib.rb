# frozen_string_literal: true

module Aogera
  module Host
    class Raylib
      WINDOW_WIDTH = 1024
      WINDOW_HEIGHT = 768
      TARGET_FPS = 60
      TITLE = "Aogera 0.2.0"

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
        @open = true
      end

      def close
        return unless @open

        @api.close_window
        @open = false
      end

      def window_should_close?
        @api.window_should_close?
      end

      # Prefer the richer host event contract when the current Aogera tree
      # provides it. The symbol fallback keeps the adapter compatible with the
      # earlier physical-key mapper without teaching raylib about game actions.
      def poll_events
        if key_event_class
          stateful_events
        else
          pressed_keys
        end
      end

      private

      def key_event_class
        return unless Host.const_defined?(:KeyEvent, false)

        Host.const_get(:KeyEvent)
      end

      def stateful_events
        KEYS.each_with_object([]) do |key, events|
          events << build_key_event(key, :pressed) if @api.key_pressed?(key)
          events << build_key_event(key, :released) if @api.key_released?(key)
        end
      end

      def pressed_keys
        KEYS.select { |key| @api.key_pressed?(key) }
      end

      def build_key_event(key, state)
        key_event_class.new(key: key, state: state)
      rescue ArgumentError
        key_event_class.new(key, state)
      end
    end
  end
end
