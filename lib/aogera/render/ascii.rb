# frozen_string_literal: true

module Aogera
  module Render
    class Ascii
      def clear_before_render?
        true
      end

      def synchronized_updates?
        false
      end

      def status_row(scene)
        scene.height + 1
      end

      def render(scene)
        cells = Array.new(scene.height) do
          Array.new(scene.width, " ")
        end

        scene.tiles.each do |tile|
          cells[tile.y][tile.x] = tile.fallback_glyph
        end

        scene.entities.sort_by(&:layer).each do |entity|
          cells[entity.y][entity.x] = entity.fallback_glyph
        end

        cells.map(&:join).join("\n")
      end
    end
  end
end
