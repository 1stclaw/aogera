# frozen_string_literal: true

require "io/wait"

module Aogera
  module Host
    class TerminalInput
      ESCAPE = "\e"
      ESCAPE_TIMEOUT = 0.04
      MAX_ESCAPE_BYTES = 64

      SIMPLE_KEYS = {
        "w" => :w,
        "W" => :w,
        "a" => :a,
        "A" => :a,
        "s" => :s,
        "S" => :s,
        "d" => :d,
        "D" => :d,
        "q" => :q,
        "Q" => :q,
        "\r" => :enter,
        "\n" => :enter,
        " " => :space,
        "\u0003" => :q
      }.freeze

      KITTY_KEY_CODES = {
        119 => :w,
        97 => :a,
        115 => :s,
        100 => :d,
        113 => :q,
        32 => :space,
        13 => :enter,
        27 => :escape
      }.freeze

      ARROW_FINALS = {
        "A" => :up,
        "B" => :down,
        "C" => :right,
        "D" => :left
      }.freeze

      EVENT_STATES = {
        1 => :pressed,
        2 => :repeat,
        3 => :released
      }.freeze

      def initialize(
        input: $stdin,
        keyboard_protocol: :legacy,
        escape_timeout: ESCAPE_TIMEOUT
      )
        @input = input
        @keyboard_protocol = keyboard_protocol
        @escape_timeout = escape_timeout
        @buffer = +""
        @pending_events = []
      end

      def read_event
        if @keyboard_protocol == :kitty
          loop do
            return @pending_events.shift unless @pending_events.empty?

            @pending_events.concat(poll_events)
            return @pending_events.shift unless @pending_events.empty?
            wait_for_input(timeout: nil)
          end
        end

        key = read_legacy_event
        key && KeyEvent.new(key: key, state: :pressed)
      end

      def poll_events
        return poll_legacy_events unless @keyboard_protocol == :kitty

        fill_buffer_nonblocking
        extract_kitty_events
      end

      def wait_for_input(timeout:)
        if @input.respond_to?(:wait_readable)
          !!@input.wait_readable(timeout)
        elsif @input.respond_to?(:eof?)
          !@input.eof?
        else
          sleep(timeout) if timeout && timeout.positive?
          true
        end
      end

      private

      def poll_legacy_events
        return [] unless input_available?

        event = read_legacy_event
        event ? [KeyEvent.new(key: event, state: :pressed)] : []
      end

      def fill_buffer_nonblocking
        if @input.respond_to?(:read_nonblock)
          loop do
            chunk = @input.read_nonblock(4096, exception: false)
            break if chunk == :wait_readable || chunk.nil?
            @buffer << chunk
          end
          return
        end

        while input_available?
          byte = @input.read(1)
          break unless byte
          @buffer << byte
        end
      end

      def extract_kitty_events
        events = []

        loop do
          parsed = extract_kitty_event
          break if parsed == :incomplete

          event, consumed = parsed
          @buffer.slice!(0, consumed)
          events << event if event
        end

        events
      end

      def extract_kitty_event
        return :incomplete if @buffer.empty?

        unless @buffer.start_with?(ESCAPE)
          key = SIMPLE_KEYS[@buffer[0]]
          event = key && KeyEvent.new(key: key, state: :pressed)
          return [event, 1]
        end

        return :incomplete if @buffer.bytesize < 2
        return [nil, 1] unless @buffer.start_with?("\e[")

        final_index = csi_final_index(@buffer)
        return :incomplete unless final_index

        sequence = @buffer.byteslice(0, final_index + 1)
        [decode_kitty_sequence(sequence), final_index + 1]
      end

      def csi_final_index(sequence)
        index = 2
        while index < sequence.bytesize && index < MAX_ESCAPE_BYTES
          byte = sequence.getbyte(index)
          return index if byte && byte.between?(0x40, 0x7e)
          index += 1
        end
        nil
      end

      def decode_kitty_sequence(sequence)
        if (match = sequence.match(/\A\e\[(\d+)(?:;([^u]*))?u\z/))
          return decode_kitty_u_event(
            key_code: match[1].to_i,
            modifier_field: match[2]
          )
        end

        if (match = sequence.match(/\A\e\[1(?:;(\d+)(?::([123]))?)?([ABCD])\z/))
          state = EVENT_STATES.fetch((match[2] || "1").to_i)
          return KeyEvent.new(
            key: ARROW_FINALS.fetch(match[3]),
            state: state
          )
        end

        if (match = sequence.match(/\A\e\[([ABCD])\z/))
          return KeyEvent.new(
            key: ARROW_FINALS.fetch(match[1]),
            state: :pressed
          )
        end

        nil
      end

      def decode_kitty_u_event(key_code:, modifier_field:)
        modifier_value, event_type = parse_modifier_field(modifier_field)
        key = kitty_key_for(key_code, modifier_value)
        return unless key

        KeyEvent.new(
          key: key,
          state: EVENT_STATES.fetch(event_type)
        )
      end

      def parse_modifier_field(field)
        return [1, 1] if field.nil? || field.empty?

        modifier, event_type = field.split(":", 2)
        [(modifier || "1").to_i, (event_type || "1").to_i]
      end

      def kitty_key_for(key_code, modifier_value)
        # Ctrl+C remains a quit shortcut in raw mode. Kitty encodes Ctrl as
        # modifier bit 0b100, stored as 1 + bitfield.
        modifier_bits = modifier_value - 1
        return :q if key_code == 99 && (modifier_bits & 0b100).positive?

        KITTY_KEY_CODES[key_code]
      end

      def read_legacy_event
        first = read_byte
        return unless first

        mapped = SIMPLE_KEYS[first]
        return mapped if mapped
        return unless first == ESCAPE

        read_escape_event
      end

      def read_escape_event
        return :escape unless continuation_available?

        sequence = +ESCAPE
        next_byte = read_byte
        return :escape unless next_byte

        sequence << next_byte
        return unless sequence.end_with?("[", "O")

        while sequence.bytesize < MAX_ESCAPE_BYTES
          return decode_legacy_escape(sequence) if escape_complete?(sequence)
          break unless continuation_available?

          byte = read_byte
          break unless byte

          sequence << byte
        end

        decode_legacy_escape(sequence)
      end

      def read_byte
        @input.read(1)
      end

      def input_available?
        if @input.respond_to?(:wait_readable)
          !!@input.wait_readable(0)
        elsif @input.respond_to?(:eof?)
          !@input.eof?
        else
          true
        end
      end

      def continuation_available?
        if @input.respond_to?(:wait_readable)
          !!@input.wait_readable(@escape_timeout)
        elsif @input.respond_to?(:eof?)
          !@input.eof?
        else
          true
        end
      end

      def escape_complete?(sequence)
        return false if sequence.bytesize < 3

        final = sequence.getbyte(-1)
        final && final.between?(0x40, 0x7e)
      end

      def decode_legacy_escape(sequence)
        match = sequence.match(/\A\e(?:\[[0-9;:?]*|O)([ABCD])\z/)
        return unless match

        ARROW_FINALS[match[1]]
      end
    end
  end
end
