# frozen_string_literal: true

require "io/console"

module Aogera
  module Host
    class Terminal
      CLEAR_SCREEN = "\e[2J\e[H"
      ERASE_LINE = "\e[2K"
      HIDE_CURSOR = "\e[?25l"
      SHOW_CURSOR = "\e[?25h"
      ENTER_ALT_SCREEN = "\e[?1049h"
      EXIT_ALT_SCREEN = "\e[?1049l"
      BEGIN_SYNC_UPDATE = "\e[?2026h"
      END_SYNC_UPDATE = "\e[?2026l"

      # Kitty keyboard protocol flags:
      #   0b0010 report press/repeat/release event types
      #   0b1000 report text-producing keys (WASD, Space, Enter) as key events
      KITTY_KEYBOARD_FLAGS = 0b1010
      ENABLE_KITTY_KEYBOARD = "\e[>#{KITTY_KEYBOARD_FLAGS}u"
      DISABLE_KITTY_KEYBOARD = "\e[<u"

      attr_reader :capabilities

      def initialize(
        input: $stdin,
        output: $stdout,
        input_adapter: nil,
        env: ENV
      )
        @input = input
        @output = output
        @capabilities = TerminalCapabilities.detect(env: env)
        @manage_input_mode = input_adapter.nil?
        @input_adapter = input_adapter || TerminalInput.new(
          input: input,
          keyboard_protocol: @capabilities.keyboard_protocol
        )
        @saved_console_mode = nil
        @application_active = false
      end

      def read_event
        @input_adapter.read_event
      end

      def poll_events
        return @input_adapter.poll_events if @input_adapter.respond_to?(:poll_events)

        event = @input_adapter.read_event
        event ? [event] : []
      end

      def wait_for_input(timeout:)
        if @input_adapter.respond_to?(:wait_for_input)
          @input_adapter.wait_for_input(timeout: timeout)
        elsif timeout && timeout.positive?
          sleep(timeout)
        end
      end

      def enter_application
        return if @application_active

        enter_raw_input
        @application_active = true
        write(
          ENTER_ALT_SCREEN +
          CLEAR_SCREEN +
          HIDE_CURSOR +
          keyboard_enable_sequence
        )
      end

      def leave_application
        return unless @application_active

        begin
          write(
            keyboard_disable_sequence +
            SHOW_CURSOR +
            EXIT_ALT_SCREEN
          )
        ensure
          restore_input_mode
          @application_active = false
        end
      end

      def begin_synchronized_update
        write(BEGIN_SYNC_UPDATE)
      end

      def end_synchronized_update
        write(END_SYNC_UPDATE)
      end

      def clear
        write(CLEAR_SCREEN)
      end

      def write_status(row:, text:)
        write(
          "\e[#{row};1H" +
          ERASE_LINE +
          text
        )
      end

      def write(text)
        @output.write(text)
        @output.flush
      end

      private

      def keyboard_enable_sequence
        return "" unless capabilities.keyboard_protocol == :kitty

        ENABLE_KITTY_KEYBOARD
      end

      def keyboard_disable_sequence
        return "" unless capabilities.keyboard_protocol == :kitty

        DISABLE_KITTY_KEYBOARD
      end

      def enter_raw_input
        return unless @manage_input_mode
        return unless console_input?

        @saved_console_mode = @input.console_mode
        @input.raw!(min: 0, time: 0)
      end

      def restore_input_mode
        return unless @saved_console_mode

        @input.console_mode = @saved_console_mode
        @saved_console_mode = nil
      end

      def console_input?
        return false if @input.respond_to?(:tty?) && !@input.tty?

        @input.respond_to?(:console_mode) &&
          @input.respond_to?(:raw!) &&
          @input.respond_to?(:console_mode=)
      end
    end
  end
end
