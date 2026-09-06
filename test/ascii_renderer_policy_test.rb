# frozen_string_literal: true

require_relative "test_helper"

class AsciiRendererPolicyTest < Minitest::Test
  def test_ascii_keeps_full_redraw_policy
    renderer = Aogera::Render::Ascii.new
    scene = Aogera::Render::Scene.new(
      width: 2,
      height: 3,
      tiles: [],
      entities: []
    )

    assert renderer.clear_before_render?
    refute renderer.synchronized_updates?
    assert_equal 4, renderer.status_row(scene)
  end
end
