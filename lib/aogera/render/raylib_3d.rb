# frozen_string_literal: true

module Aogera
  module Render
    class Raylib3D
      TILE_SIZE = 1.0
      FLOOR_HEIGHT = 0.08
      WALL_HEIGHT = 1.0
      ENTITY_WIDTH = 0.55
      ENTITY_HEIGHT = 0.8

      BACKGROUND = [24, 28, 34, 255].freeze
      STATUS_BACKGROUND = [11, 12, 15, 230].freeze
      STATUS_TEXT = [224, 226, 230, 255].freeze
      DEFAULT_TERRAIN = [84, 80, 72, 255].freeze
      DEFAULT_ENTITY = [166, 105, 92, 255].freeze

      TERRAIN = {
        grass: [58, 88, 58, 255],
        ground: [82, 76, 62, 255],
        floor: [92, 88, 80, 255],
        wall: [102, 102, 110, 255],
        water: [42, 82, 118, 255]
      }.freeze

      ENTITIES = {
        player: [214, 194, 92, 255],
        goblin: [102, 158, 84, 255],
        villager: [116, 146, 184, 255]
      }.freeze

      STATUS_MARGIN = 24
      STATUS_FONT_SIZE = 20
      STATUS_HEIGHT = 48

      def initialize(api:)
        @api = api
      end

      def draw(level:, world:, status:, view:, camera_entity_id:)
        @api.begin_drawing
        @api.clear(BACKGROUND)
        @api.begin_mode_3d(
          **camera_for(
            world: world,
            view: view,
            camera_entity_id: camera_entity_id
          )
        )

        draw_level(level)
        draw_entities(level, world, hidden_entity_id: camera_entity_id)

        @api.end_mode_3d
        draw_status(status)
      ensure
        @api.end_drawing
      end

      private

      def draw_level(level)
        level.height.times do |grid_y|
          level.width.times do |grid_x|
            draw_tile(level, grid_x, grid_y)
          end
        end
      end

      def draw_tile(level, grid_x, grid_y)
        render_key = level.render_key_at(grid_x, grid_y)
        color = TERRAIN.fetch(render_key, DEFAULT_TERRAIN)
        x, z = grid_center(grid_x, grid_y)

        if render_key == :wall
          @api.draw_cube(
            x: x,
            y: WALL_HEIGHT / 2.0,
            z: z,
            width: TILE_SIZE,
            height: WALL_HEIGHT,
            length: TILE_SIZE,
            rgba: color
          )
        else
          @api.draw_cube(
            x: x,
            y: -(FLOOR_HEIGHT / 2.0),
            z: z,
            width: TILE_SIZE,
            height: FLOOR_HEIGHT,
            length: TILE_SIZE,
            rgba: color
          )
        end
      end

      def draw_entities(level, world, hidden_entity_id:)
        world.entity_ids.each do |entity_id|
          next if entity_id == hidden_entity_id

          position = world.component(entity_id, :position)
          renderable = world.component(entity_id, :renderable)
          next unless position && renderable
          next unless level.inside?(position.x, position.y)

          x, z = grid_center(position.x, position.y)
          @api.draw_cube(
            x: x,
            y: ENTITY_HEIGHT / 2.0,
            z: z,
            width: ENTITY_WIDTH,
            height: ENTITY_HEIGHT,
            length: ENTITY_WIDTH,
            rgba: ENTITIES.fetch(renderable.render_key, DEFAULT_ENTITY)
          )
        end
      end

      def grid_center(grid_x, grid_y)
        [
          (grid_x * TILE_SIZE) + (TILE_SIZE / 2.0),
          (grid_y * TILE_SIZE) + (TILE_SIZE / 2.0)
        ]
      end

      def camera_for(world:, view:, camera_entity_id:)
        position = world.component(camera_entity_id, :position)
        raise ArgumentError, "camera entity has no position" unless position

        x, z = grid_center(position.x, position.y)
        eye = [x, view.eye_height, z]
        forward_x, forward_y, forward_z = view.forward_vector

        {
          position: eye,
          target: [
            x + forward_x,
            view.eye_height + forward_y,
            z + forward_z
          ],
          up: [0.0, 1.0, 0.0],
          fovy: view.fovy
        }
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
          x: STATUS_MARGIN,
          y: y + 13,
          size: STATUS_FONT_SIZE,
          rgba: STATUS_TEXT
        )
      end
    end
  end
end
