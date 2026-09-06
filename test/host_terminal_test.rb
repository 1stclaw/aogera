# frozen_string_literal: true

require "stringio"
require_relative "test_helper"

class HostTerminalTest < Minitest::Test
  FakeInput = Struct.new(:event) do
    def read_event
      event
    end
  end

  FakeConsole = Struct.new(:mode, :raw_options, keyword_init: true) do
    def tty?
      true
    end

    def console_mode
      mode
    end

    def console_mode=(value)
      self.mode = value
    end

    def raw!(**options)
      self.raw_options = options
    end

    def read(_length)
      nil
    end
  end

  def test_terminal_owns_transport_and_reports_protocol_capabilities
    output = StringIO.new
    host = Aogera::Host::Terminal.new(
      output: output,
      input_adapter: FakeInput.new(:right),
      env: { "TERM" => "xterm-256color" }
    )

    assert_equal :right, host.read_event
    assert_nil host.capabilities.graphics_protocol
    assert_equal :legacy, host.capabilities.keyboard_protocol
  end

  def test_terminal_reports_kitty_graphics_and_keyboard_capabilities
    host = Aogera::Host::Terminal.new(
      output: StringIO.new,
      input_adapter: FakeInput.new(:right),
      env: { "TERM" => "xterm-kitty" }
    )

    assert_equal :kitty, host.capabilities.graphics_protocol
    assert_equal :kitty, host.capabilities.keyboard_protocol
  end

  def test_application_lifecycle_enables_kitty_keyboard_on_alt_screen
    output = StringIO.new
    host = host_with(output)

    host.enter_application
    host.leave_application

    assert_equal(
      "\e[?1049h\e[2J\e[H\e[?25l\e[>10u" \
      "\e[<u\e[?25h\e[?1049l",
      output.string
    )
  end

  def test_application_lifecycle_owns_nonblocking_raw_input_mode
    output = StringIO.new
    input = FakeConsole.new(mode: :original)
    host = Aogera::Host::Terminal.new(
      input: input,
      output: output,
      env: { "TERM" => "xterm-kitty" }
    )

    host.enter_application

    assert_equal({ min: 0, time: 0 }, input.raw_options)

    host.leave_application

    assert_equal :original, input.mode
  end

  def test_status_updates_erase_only_the_status_line
    output = StringIO.new
    host = host_with(output)

    host.write_status(row: 15, text: "Tick 4")

    assert_equal "\e[15;1H\e[2KTick 4", output.string
    refute_includes output.string, "\e[2J"
  end

  def test_synchronized_update_controls_are_exposed
    output = StringIO.new
    host = host_with(output)

    host.begin_synchronized_update
    host.end_synchronized_update

    assert_equal "\e[?2026h\e[?2026l", output.string
  end

  private

  def host_with(output)
    Aogera::Host::Terminal.new(
      output: output,
      input_adapter: FakeInput.new(:right),
      env: { "TERM" => "xterm-kitty" }
    )
  end
end
