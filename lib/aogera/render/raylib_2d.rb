# frozen_string_literal: true

module Aogera
  module Render
    class Raylib2D
      CELL_SIZE = 32
      MAP_MARGIN = 24
      STATUS_HEIGHT = 48
      GLYPH_SIZE = 18
      STATUS_FONT_SIZE = 20

      BACKGROUND = [18, 20, 24, 255].freeze
      GRID = [37, 40, 45, 255].freeze
      STATUS_BACKGROUND = [11, 12, 15, 255].freeze
      STATUS_TEXT = [224, 226, 230, 255].freeze
      GLYPH = [240, 240, 236, 255].freeze
      DEFAULT_TERRAIN = [72, 70, 68, 255].freeze
      DEFAULT_ENTITY = [166, 105, 92, 255].freeze

      TERRAIN = {
        grass: [54, 84, 54, 255],
        ground: [75, 70, 58, 255],
        floor: [82, 78, 70, 255],
        wall: [92, 92, 98, 255],
        water: [40, 78, 110, 255]
      }.freeze

      ENTITIES = {
        player: [214, 194, 92, 255],
        goblin: [102, 158, 84, 255]
      }.freeze

      def initialize(api:, cell_size: CELL_SIZE)
        @api = api
        @cell_size = cell_size
      end

      def draw(scene, status:)
        @api.begin_drawing
        @api.clear(BACKGROUND)

        origin_x, origin_y = map_origin(scene)
        scene.tiles.each { |tile| draw_tile(tile, origin_x, origin_y) }
        scene.entities.each { |entity| draw_entity(entity, origin_x, origin_y) }
        draw_status(status)
      ensure
        @api.end_drawing
      end

      private

      def draw_tile(tile, origin_x, origin_y)
        x, y = screen_position(tile, origin_x, origin_y)
        color = TERRAIN.fetch(tile.render_key, DEFAULT_TERRAIN)

        @api.draw_rectangle(
          x: x,
          y: y,
          width: @cell_size,
          height: @cell_size,
          rgba: color
        )
        @api.draw_rectangle_lines(
          x: x,
          y: y,
          width: @cell_size,
          height: @cell_size,
          rgba: GRID
        )
        draw_glyph(tile, x, y)
      end

      def draw_entity(entity, origin_x, origin_y)
        x, y = screen_position(entity, origin_x, origin_y)
        inset = [(@cell_size * 0.12).round, 2].max
        color = ENTITIES.fetch(entity.render_key, DEFAULT_ENTITY)

        @api.draw_rectangle(
          x: x + inset,
          y: y + inset,
          width: @cell_size - (inset * 2),
          height: @cell_size - (inset * 2),
          rgba: color
        )
        @api.draw_rectangle_lines(
          x: x + inset,
          y: y + inset,
          width: @cell_size - (inset * 2),
          height: @cell_size - (inset * 2),
          rgba: GLYPH
        )
        draw_glyph(entity, x, y)
      end

      def draw_glyph(item, x, y)
        glyph = glyph_for(item)
        return if glyph.empty?

        @api.draw_text(
          text: glyph,
          x: x + 8,
          y: y + 6,
          size: GLYPH_SIZE,
          rgba: GLYPH
        )
      end

      def draw_status(status)
        y = @api.screen_height - STATUS_HEIGHT
        @api.draw_rectangle(
          x: 0,
          y: y,
          width: @api.screen_width,
          height: STATUS_HEIGHT,
          rgba: STATUS_BACKGROUND
        )
        @api.draw_text(
          text: status,
          x: MAP_MARGIN,
          y: y + 13,
          size: STATUS_FONT_SIZE,
          rgba: STATUS_TEXT
        )
      end

      def map_origin(scene)
        width = scene.width * @cell_size
        height = scene.height * @cell_size
        usable_height = @api.screen_height - STATUS_HEIGHT

        [
          [(@api.screen_width - width) / 2, MAP_MARGIN].max,
          [(usable_height - height) / 2, MAP_MARGIN].max
        ]
      end

      def screen_position(item, origin_x, origin_y)
        [
          origin_x + (item.x * @cell_size),
          origin_y + (item.y * @cell_size)
        ]
      end

      def glyph_for(item)
        value = item.fallback_glyph
        value = item.render_key.to_s[0] if value.nil? || value.to_s.empty?
        value.to_s[0]
      end
    end
  end
end
