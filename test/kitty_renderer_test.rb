# frozen_string_literal: true

require "base64"
require "tmpdir"
require_relative "test_helper"

class KittyRendererTest < Minitest::Test
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b

  def test_renderer_transmits_png_bytes_and_places_scene_items
    Dir.mktmpdir do |directory|
      png_data = PNG_SIGNATURE + "aogera"
      path = File.join(directory, "hero.png")
      File.binwrite(path, png_data)

      renderer = renderer_for(catalog_for(path))
      output = renderer.render(scene_with_hero)
      encoded = Base64.strict_encode64(png_data)

      assert_includes output,
        "a=t,t=d,f=100,i=1390000001,m=0,q=2;#{encoded}"
      assert_includes output,
        "a=p,i=1390000001,p=1490000001,c=2,r=1,C=1,z=10,q=2"
      assert_includes output, "\e[1;1H"
    end
  end

  def test_renderer_chunks_large_direct_transfers
    Dir.mktmpdir do |directory|
      png_data = PNG_SIGNATURE + ("x" * 5_000)
      path = File.join(directory, "hero.png")
      File.binwrite(path, png_data)

      renderer = renderer_for(catalog_for(path))
      output = renderer.render(scene_with_hero)
      encoded = Base64.strict_encode64(png_data)
      first_chunk = encoded[0, 4096]
      second_chunk = encoded[4096..]

      assert_includes output,
        "a=t,t=d,f=100,i=1390000001,m=1,q=2;#{first_chunk}"
      assert_includes output,
        "m=0,q=2;#{second_chunk}"
    end
  end

  def test_identical_second_frame_emits_no_graphics_updates
    Dir.mktmpdir do |directory|
      path = File.join(directory, "hero.png")
      File.binwrite(path, PNG_SIGNATURE + "aogera")

      renderer = renderer_for(catalog_for(path))
      renderer.render(scene_with_hero)

      assert_equal "", renderer.render(scene_with_hero)
    end
  end

  def test_moved_instance_reuses_stable_placement_id
    Dir.mktmpdir do |directory|
      path = File.join(directory, "hero.png")
      File.binwrite(path, PNG_SIGNATURE + "aogera")

      renderer = renderer_for(catalog_for(path))
      renderer.render(scene_with_hero)
      moved = renderer.render(scene_with_hero(x: 1))

      assert_includes moved, "\e[1;3H"
      assert_includes moved,
        "a=p,i=1390000001,p=1490000001,c=2,r=1,C=1,z=10,q=2"
      refute_includes moved, "a=d,d=i"
      refute_includes moved, "a=t,t=d"
    end
  end

  def test_removed_instance_deletes_only_its_placement
    Dir.mktmpdir do |directory|
      path = File.join(directory, "hero.png")
      File.binwrite(path, PNG_SIGNATURE + "aogera")

      renderer = renderer_for(catalog_for(path))
      renderer.render(scene_with_hero)
      empty_scene = Aogera::Render::Scene.new(
        width: 1,
        height: 1,
        tiles: [],
        entities: []
      )
      output = renderer.render(empty_scene)

      assert_includes output,
        "a=d,d=i,i=1390000001,p=1490000001,q=2"
    end
  end

  def test_finish_deletes_uploaded_image_data
    Dir.mktmpdir do |directory|
      path = File.join(directory, "hero.png")
      File.binwrite(path, PNG_SIGNATURE + "aogera")

      renderer = renderer_for(catalog_for(path))
      renderer.render(scene_with_hero)

      assert_includes renderer.finish,
        "a=d,d=I,i=1390000001,q=2"
    end
  end

  def test_renderer_uses_fallback_glyph_for_missing_asset
    renderer = renderer_for(
      Aogera::Render::AssetCatalog.new([])
    )

    scene = Aogera::Render::Scene.new(
      width: 1,
      height: 1,
      tiles: [
        Aogera::Render::Scene::Tile.new(
          x: 0,
          y: 0,
          render_key: :unknown,
          fallback_glyph: "."
        )
      ],
      entities: []
    )

    assert_includes renderer.render(scene), "\e[1;1H."
  end

  def test_renderer_declares_persistent_synchronized_frame_policy
    renderer = renderer_for(
      Aogera::Render::AssetCatalog.new([])
    )
    scene = Aogera::Render::Scene.new(
      width: 2,
      height: 3,
      tiles: [],
      entities: []
    )

    refute renderer.clear_before_render?
    assert renderer.synchronized_updates?
    assert_equal 4, renderer.status_row(scene)
  end

  private

  def catalog_for(path)
    Aogera::Render::AssetCatalog.new(
      [
        Aogera::Render::AssetCatalog::Asset.new(
          render_key: :hero,
          path: path
        )
      ]
    )
  end

  def renderer_for(catalog)
    Aogera::Render::Kitty.new(
      assets: catalog,
      tile_columns: 2,
      tile_rows: 1
    )
  end

  def scene_with_hero(x: 0)
    Aogera::Render::Scene.new(
      width: 2,
      height: 1,
      tiles: [],
      entities: [
        Aogera::Render::Scene::Entity.new(
          entity_id: 5,
          x: x,
          y: 0,
          render_key: :hero,
          fallback_glyph: "P",
          layer: 10
        )
      ]
    )
  end
end
