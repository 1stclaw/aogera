# frozen_string_literal: true

module Aogera
  module Render
    class Raylib3D
      FLOOR_HEIGHT = 2.56
      WALL_HEIGHT = 32.0
      ENTITY_WIDTH = 17.6
      ENTITY_HEIGHT = 25.6

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
        x, z = level.cell_center(grid_x, grid_y)
        tile_size = level.cell_size

        if render_key == :wall
          @api.draw_cube(
            x: x,
            y: WALL_HEIGHT / 2.0,
            z: z,
            width: tile_size,
            height: WALL_HEIGHT,
            length: tile_size,
            rgba: color
          )
        else
          @api.draw_cube(
            x: x,
            y: -(FLOOR_HEIGHT / 2.0),
            z: z,
            width: tile_size,
            height: FLOOR_HEIGHT,
            length: tile_size,
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
          grid_x, grid_z = level.cell_for_world(position.x, position.z)
          next unless level.inside?(grid_x, grid_z)

          @api.draw_cube(
            x: position.x,
            y: position.y + (ENTITY_HEIGHT / 2.0),
            z: position.z,
            width: ENTITY_WIDTH,
            height: ENTITY_HEIGHT,
            length: ENTITY_WIDTH,
            rgba: ENTITIES.fetch(renderable.render_key, DEFAULT_ENTITY)
          )
        end
      end

      def camera_for(world:, view:, camera_entity_id:)
        position = world.component(camera_entity_id, :position)
        raise ArgumentError, "camera entity has no position" unless position

        x = position.x
        z = position.z
        eye_y = position.y + view.eye_height
        eye = [x, eye_y, z]
        forward_x, forward_y, forward_z = view.forward_vector

        {
          position: eye,
          target: [
            x + forward_x,
            eye_y + forward_y,
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
