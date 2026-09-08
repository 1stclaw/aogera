# frozen_string_literal: true

module Aogera
  class Level
    class Terrain
      DEFAULT_TILES = {
        " " => Tile.new(
          render_key: :ground,
          glyph: " ",
          passable: true
        )
      }.freeze

      attr_reader :width, :height, :cell_size

      def initialize(width: nil, height: nil, rows: nil, tiles: nil, cell_size: WorldUnits::GRID_CELL_SIZE)
        @cell_size = Float(cell_size)
        raise ArgumentError, "cell_size must be positive" unless @cell_size.positive?

        if rows
          initialize_from_rows(
            rows,
            tiles || DEFAULT_TILES
          )
        else
          initialize_blank(width, height)
        end
      end

      def inside?(x, y)
        x.between?(0, width - 1) &&
          y.between?(0, height - 1)
      end

      def tile_at(x, y)
        return unless inside?(x, y)

        @tiles.fetch(@rows[y][x])
      end

      def glyph_at(x, y)
        tile_at(x, y)&.glyph
      end

      def render_key_at(x, y)
        tile_at(x, y)&.render_key
      end

      def passable?(x, y)
        tile_at(x, y)&.passable || false
      end

      def cell_center(x, y)
        [
          WorldUnits.grid_center(x, cell_size: cell_size),
          WorldUnits.grid_center(y, cell_size: cell_size)
        ].freeze
      end

      def cell_for_world(x, z)
        [
          WorldUnits.grid_cell(x, cell_size: cell_size),
          WorldUnits.grid_cell(z, cell_size: cell_size)
        ].freeze
      end

      def cell_bounds(x, y)
        min_x = Integer(x) * cell_size
        min_z = Integer(y) * cell_size
        [min_x, min_z, min_x + cell_size, min_z + cell_size].freeze
      end

      private

      def initialize_blank(width, height)
        unless width.is_a?(Integer) && width.positive?
          raise ArgumentError,
            "width must be a positive Integer"
        end

        unless height.is_a?(Integer) && height.positive?
          raise ArgumentError,
            "height must be a positive Integer"
        end

        @width = width
        @height = height
        @tiles = DEFAULT_TILES
        @rows = Array.new(height) do
          (" " * width).freeze
        end.freeze
      end

      def initialize_from_rows(rows, tiles)
        raise ArgumentError, "rows cannot be empty" if rows.empty?

        frozen_rows = rows.map do |row|
          String(row).dup.freeze
        end

        width = frozen_rows.first.length

        unless width.positive? &&
               frozen_rows.all? { |row| row.length == width }
          raise ArgumentError,
            "all terrain rows must have the same non-zero width"
        end

        frozen_tiles = tiles.dup.freeze
        unknown = frozen_rows.flat_map(&:chars).uniq -
          frozen_tiles.keys

        unless unknown.empty?
          raise ArgumentError,
            "unknown terrain glyphs: #{unknown.inspect}"
        end

        @width = width
        @height = frozen_rows.length
        @rows = frozen_rows.freeze
        @tiles = frozen_tiles
      end
    end
  end
end
