# frozen_string_literal: true

require_relative "test_helper"

class RenderSceneTest < Minitest::Test
  def test_ascii_renderer_consumes_backend_neutral_scene
    scene = Aogera::Render::Scene.new(
      width: 3,
      height: 2,
      tiles: [
        Aogera::Render::Scene::Tile.new(
          x: 0,
          y: 0,
          render_key: :ground,
          fallback_glyph: "."
        ),
        Aogera::Render::Scene::Tile.new(
          x: 1,
          y: 0,
          render_key: :ground,
          fallback_glyph: "."
        ),
        Aogera::Render::Scene::Tile.new(
          x: 2,
          y: 0,
          render_key: :ground,
          fallback_glyph: "."
        ),
        Aogera::Render::Scene::Tile.new(
          x: 0,
          y: 1,
          render_key: :ground,
          fallback_glyph: "."
        ),
        Aogera::Render::Scene::Tile.new(
          x: 1,
          y: 1,
          render_key: :ground,
          fallback_glyph: "."
        ),
        Aogera::Render::Scene::Tile.new(
          x: 2,
          y: 1,
          render_key: :ground,
          fallback_glyph: "."
        )
      ],
      entities: [
        Aogera::Render::Scene::Entity.new(
          entity_id: 7,
          x: 1,
          y: 0,
          render_key: :hero,
          fallback_glyph: "P",
          layer: 10
        )
      ]
    )

    assert_equal ".P.\n...", Aogera::Render::Ascii.new.render(scene)
    assert_equal 7, scene.entities.first.entity_id
    assert_equal :hero, scene.entities.first.render_key
  end
end
