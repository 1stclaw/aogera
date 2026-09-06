# frozen_string_literal: true

require_relative "test_helper"

class RenderSelectorTest < Minitest::Test
  def test_builds_kitty_renderer_when_capability_is_present
    renderer = Aogera::Render::Selector.build(
      capabilities: Aogera::Host::Capabilities.new(
        graphics_protocol: :kitty,
        keyboard_protocol: :legacy
      )
    )

    assert_instance_of Aogera::Render::Kitty, renderer
  end

  def test_rejects_terminal_without_kitty_graphics
    error = assert_raises(
      Aogera::Render::Selector::UnsupportedTerminal
    ) do
      Aogera::Render::Selector.build(
        capabilities: Aogera::Host::Capabilities.new(
          graphics_protocol: nil,
          keyboard_protocol: :legacy
        )
      )
    end

    assert_equal(
      "Aogera v0.1.0 requires Kitty graphics protocol support",
      error.message
    )
  end
end
