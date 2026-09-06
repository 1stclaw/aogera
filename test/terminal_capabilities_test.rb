# frozen_string_literal: true

require_relative "test_helper"

class TerminalCapabilitiesTest < Minitest::Test
  def test_detects_kitty_from_window_id
    capabilities = Aogera::Host::TerminalCapabilities.detect(
      env: {
        "KITTY_WINDOW_ID" => "17",
        "TERM" => "xterm-256color"
      }
    )

    assert_equal :kitty, capabilities.graphics_protocol
    assert_equal :kitty, capabilities.keyboard_protocol
  end

  def test_detects_kitty_from_term
    capabilities = Aogera::Host::TerminalCapabilities.detect(
      env: { "TERM" => "xterm-kitty" }
    )

    assert_equal :kitty, capabilities.graphics_protocol
    assert_equal :kitty, capabilities.keyboard_protocol
  end

  def test_unknown_terminal_reports_legacy_keyboard_protocol
    capabilities = Aogera::Host::TerminalCapabilities.detect(
      env: { "TERM" => "xterm-256color" }
    )

    assert_nil capabilities.graphics_protocol
    assert_equal :legacy, capabilities.keyboard_protocol
  end
end
