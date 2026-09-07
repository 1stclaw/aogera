# frozen_string_literal: true

require_relative "test_helper"

class Render2DContractTest < Minitest::Test
  FakeLevel = Data.define(:width, :height) do
    def render_key_at(x, y)
      x == y ? :grass : :wall
    end

    def glyph_at(x, y)
      x == y ? "." : "#"
    end

    def inside?(x, y)
      x >= 0 && y >= 0 && x < width && y < height
    end
  end

  class EmptyWorld
    def entity_ids = []
  end

  def test_projector_2d_builds_scene_2d
    scene = Aogera::Render::Projector2D.new.project(
      level: FakeLevel.new(width: 2, height: 2),
      world: EmptyWorld.new
    )

    assert_instance_of(Aogera::Render::Scene2D, scene)
    assert_equal(4, scene.tiles.length)
    assert(scene.tiles.frozen?)
    assert(scene.entities.frozen?)
  end
end
