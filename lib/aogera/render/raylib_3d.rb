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

      DIAGNOSTIC_MARGIN = 16
      DIAGNOSTIC_PADDING = 10
      DIAGNOSTIC_WIDTH = 360
      DIAGNOSTIC_FONT_SIZE = 18
      DIAGNOSTIC_LINE_HEIGHT = 22
      DIAGNOSTIC_BACKGROUND = [11, 12, 15, 205].freeze
      DIAGNOSTIC_TEXT = [224, 226, 230, 255].freeze

      def initialize(
        api:, bsp29_map: nil, bsp29_palette: nil, bsp29_two_sided: false
      )
        @api = api
        @bsp29_world = bsp29_map && BSP29World.new(
          map: bsp29_map,
          palette: bsp29_palette,
          two_sided: bsp29_two_sided
        )
      end

      def prepare
        @bsp29_world&.prepare(@api)
      end

      def close
        @bsp29_world&.close(@api)
      end

      def draw(
        level:, world:, status:, view:, camera_entity_id:, camera_eye: nil
      )
        resolved_camera_eye = camera_eye || entity_camera_eye(
          world: world,
          view: view,
          camera_entity_id: camera_entity_id
        )

        @api.begin_drawing
        @api.clear(BACKGROUND)
        @api.begin_mode_3d(
          **camera_for(view: view, camera_eye: resolved_camera_eye)
        )

        draw_static_world(level)
        draw_entities(level, world, hidden_entity_id: camera_entity_id)

        @api.end_mode_3d
        draw_diagnostics(
          world: world,
          view: view,
          camera_eye: resolved_camera_eye
        )
        draw_status(status)
      ensure
        @api.end_drawing
      end

      private

      def draw_static_world(level)
        if @bsp29_world
          @bsp29_world.draw(@api)
        else
          draw_level(level)
        end
      end

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
          next unless entity_position_visible?(level, position)

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

      def entity_position_visible?(level, position)
        return true if @bsp29_world

        grid_x, grid_z = level.cell_for_world(position.x, position.z)
        level.inside?(grid_x, grid_z)
      end

      def entity_camera_eye(world:, view:, camera_entity_id:)
        position = world.component(camera_entity_id, :position)
        raise ArgumentError, "camera entity has no position" unless position

        [
          position.x,
          position.y + view.eye_height,
          position.z
        ]
      end

      def camera_for(view:, camera_eye:)
        x, eye_y, z = camera_eye
        forward_x, forward_y, forward_z = view.forward_vector

        {
          position: camera_eye,
          target: [
            x + forward_x,
            eye_y + forward_y,
            z + forward_z
          ],
          up: [0.0, 1.0, 0.0],
          fovy: view.fovy
        }
      end

      def draw_diagnostics(world:, view:, camera_eye:)
        return unless @bsp29_world && camera_eye

        x, y, z = camera_eye
        lines = [
          "FPS #{@api.fps}",
          format("Camera XYZ %.2f  %.2f  %.2f", x, y, z),
          format(
            "View yaw %.1f deg | pitch %.1f deg",
            radians_to_degrees(view.yaw),
            radians_to_degrees(view.pitch)
          ),
          "BSP #{@bsp29_world.triangle_count} submitted tris | " \
            "#{@bsp29_world.batch_count} mesh draws",
          "Faces #{@bsp29_world.world_surface_count}/#{@bsp29_world.world_face_count} prepared | " \
            "#{@bsp29_world.dropped_surface_count} dropped",
          "Raylib winding #{@bsp29_world.reversed_surface_count} flipped | " \
            "#{@bsp29_world.degenerate_triangle_count} degenerate tris",
          "Source #{@bsp29_world.source_triangle_count} tris | " \
            "two-sided #{@bsp29_world.two_sided? ? 'ON' : 'off'}",
          "Brush #{@bsp29_world.brush_submodel_count} submodels skipped",
          base_texture_diagnostic,
          "Lightmaps #{@bsp29_world.lightmapped_face_count} faces | " \
            "#{@bsp29_world.lightmap_atlas_width}x" \
            "#{@bsp29_world.lightmap_atlas_height}",
          "Entities #{world.entity_ids.length}"
        ]
        height = (DIAGNOSTIC_PADDING * 2) +
          (lines.length * DIAGNOSTIC_LINE_HEIGHT)

        @api.draw_rectangle(
          x: DIAGNOSTIC_MARGIN,
          y: DIAGNOSTIC_MARGIN,
          width: DIAGNOSTIC_WIDTH,
          height: height,
          rgba: DIAGNOSTIC_BACKGROUND
        )
        lines.each_with_index do |line, index|
          @api.draw_text(
            text: line,
            x: DIAGNOSTIC_MARGIN + DIAGNOSTIC_PADDING,
            y: DIAGNOSTIC_MARGIN + DIAGNOSTIC_PADDING +
              (index * DIAGNOSTIC_LINE_HEIGHT),
            size: DIAGNOSTIC_FONT_SIZE,
            rgba: DIAGNOSTIC_TEXT
          )
        end
      end

      def base_texture_diagnostic
        base = if @bsp29_world.textured?
          "#{@bsp29_world.used_texture_count} textures"
        else
          "grayscale fallback"
        end
        "Base #{base} | #{@bsp29_world.missing_texture_face_count} missing faces"
      end

      def radians_to_degrees(value)
        value * 180.0 / Math::PI
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
