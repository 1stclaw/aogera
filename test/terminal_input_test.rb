# frozen_string_literal: true

require "stringio"
require_relative "test_helper"

class TerminalInputTest < Minitest::Test
  def test_reads_legacy_letter_keys_as_pressed_events
    assert_event :w, :pressed, read_legacy("w")
    assert_event :a, :pressed, read_legacy("A")
    assert_event :q, :pressed, read_legacy("q")
  end

  def test_reads_legacy_interaction_and_arrow_keys
    assert_event :enter, :pressed, read_legacy("\r")
    assert_event :space, :pressed, read_legacy(" ")
    assert_event :up, :pressed, read_legacy("\e[A")
    assert_event :left, :pressed, read_legacy("\e[1;5D")
  end

  def test_reads_bare_escape_and_ctrl_c_in_legacy_mode
    assert_event :escape, :pressed, read_legacy("\e")
    assert_event :q, :pressed, read_legacy("\u0003")
  end

  def test_kitty_protocol_reports_press_repeat_and_release_for_wasd
    events = poll_kitty(
      "\e[119;1:1u" \
      "\e[119;1:2u" \
      "\e[119;1:3u"
    )

    assert_equal 3, events.length
    assert_event :w, :pressed, events[0]
    assert_event :w, :repeat, events[1]
    assert_event :w, :released, events[2]
  end

  def test_kitty_protocol_reports_space_enter_escape_and_arrows
    events = poll_kitty(
      "\e[32;1:1u" \
      "\e[13;1:1u" \
      "\e[27;1:1u" \
      "\e[A" \
      "\e[1;1:3A"
    )

    assert_event :space, :pressed, events[0]
    assert_event :enter, :pressed, events[1]
    assert_event :escape, :pressed, events[2]
    assert_event :up, :pressed, events[3]
    assert_event :up, :released, events[4]
  end

  def test_kitty_ctrl_c_maps_to_quit
    event = poll_kitty("\e[99;5:1u").fetch(0)

    assert_event :q, :pressed, event
  end

  def test_unknown_kitty_key_is_ignored
    assert_empty poll_kitty("\e[120;1:1u")
  end

  private

  def read_legacy(bytes)
    input = StringIO.new(bytes)
    Aogera::Host::TerminalInput.new(
      input: input,
      keyboard_protocol: :legacy,
      escape_timeout: 0
    ).read_event
  end

  def poll_kitty(bytes)
    input = StringIO.new(bytes)
    Aogera::Host::TerminalInput.new(
      input: input,
      keyboard_protocol: :kitty
    ).poll_events
  end

  def assert_event(key, state, event)
    assert_instance_of Aogera::Host::KeyEvent, event
    assert_equal key, event.key
    assert_equal state, event.state
  end
end
