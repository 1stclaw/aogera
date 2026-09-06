# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"

class AssetCatalogTest < Minitest::Test
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b

  def test_catalog_indexes_assets_by_render_key
    Dir.mktmpdir do |directory|
      path = File.join(directory, "hero.png")
      File.binwrite(path, PNG_SIGNATURE + "test")

      asset = Aogera::Render::AssetCatalog::Asset.new(
        render_key: :hero,
        path: path
      )
      catalog = Aogera::Render::AssetCatalog.new([asset])
      assert_equal asset, catalog.fetch(:hero)
      assert_equal path, catalog[:hero].path
      refute_respond_to catalog[:hero], :image_id
    end
  end

  def test_catalog_rejects_missing_asset
    error = assert_raises(ArgumentError) do
      Aogera::Render::AssetCatalog.new(
        [
          Aogera::Render::AssetCatalog::Asset.new(
            render_key: :hero,
            path: "/missing/hero.png"
          )
        ]
      )
    end
    assert_match "missing render asset", error.message
  end

  def test_catalog_rejects_non_png_contents
    Dir.mktmpdir do |directory|
      path = File.join(directory, "hero.png")
      File.binwrite(path, "not a png")

      error = assert_raises(ArgumentError) do
        Aogera::Render::AssetCatalog.new(
          [
            Aogera::Render::AssetCatalog::Asset.new(
              render_key: :hero,
              path: path
            )
          ]
        )
      end
      assert_match "invalid PNG render asset", error.message
    end
  end
end

class DefaultAssetCatalogTest < Minitest::Test
  def test_default_catalog_covers_current_scene_keys
    catalog = Aogera::Render::AssetCatalog.default

    %i[ground grass water wall player goblin villager].each do |render_key|
      assert File.file?(catalog.fetch(render_key).path)
    end
  end
end
