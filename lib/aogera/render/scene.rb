# frozen_string_literal: true

module Aogera
  module Render
    class Scene
      Tile = Data.define(:x, :y, :render_key, :fallback_glyph)
      Entity = Data.define(
        :entity_id, :x, :y, :render_key, :fallback_glyph, :layer
      )

      attr_reader :width, :height, :tiles, :entities

      def initialize(width:, height:, tiles:, entities:)
        @width = width
        @height = height
        @tiles = tiles.dup.freeze
        @entities = entities.dup.freeze
      end
    end
  end
end
