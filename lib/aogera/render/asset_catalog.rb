# frozen_string_literal: true

module Aogera
  module Render
    class AssetCatalog
      Asset = Data.define(
        :render_key,
        :path
      )

      DEFAULT_FILES = {
        ground: "ground.png",
        grass: "grass.png",
        water: "water.png",
        wall: "wall.png",
        player: "player.png",
        goblin: "goblin.png",
        villager: "villager.png"
      }.freeze

      PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b

      def self.default(root: default_root)
        assets = DEFAULT_FILES.map do |render_key, filename|
          Asset.new(
            render_key: render_key,
            path: File.expand_path(filename, root)
          )
        end

        new(assets)
      end

      def self.default_root
        File.expand_path(
          "../../../content/sprites",
          __dir__
        )
      end

      def initialize(assets)
        @assets = assets.to_h do |asset|
          validate_asset!(asset)
          [asset.render_key, asset]
        end.freeze
      end

      def [](render_key)
        @assets[render_key]
      end

      def fetch(render_key)
        @assets.fetch(render_key)
      end

      def each(&block)
        return enum_for(:each) unless block

        @assets.each_value(&block)
      end

      private

      def validate_asset!(asset)
        unless File.file?(asset.path)
          raise ArgumentError,
            "missing render asset: #{asset.path}"
        end

        unless File.extname(asset.path).downcase == ".png"
          raise ArgumentError,
            "render asset must be PNG: #{asset.path}"
        end

        signature = File.binread(
          asset.path,
          PNG_SIGNATURE.bytesize
        )

        return if signature == PNG_SIGNATURE

        raise ArgumentError,
          "invalid PNG render asset: #{asset.path}"
      end
    end
  end
end
