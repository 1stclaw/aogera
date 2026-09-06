# frozen_string_literal: true

module Aogera
  module Render
    class Projector
      def project(level:, world:)
        Scene.new(
          width: level.width,
          height: level.height,
          tiles: project_tiles(level),
          entities: project_entities(level, world)
        )
      end

      private

      def project_tiles(level)
        Array.new(level.height) do |y|
          Array.new(level.width) do |x|
            Scene::Tile.new(
              x: x,
              y: y,
              render_key: level.render_key_at(x, y),
              fallback_glyph: level.glyph_at(x, y)
            )
          end
        end.flatten.freeze
      end

      def project_entities(level, world)
        renderables(world).filter_map do |entity_id, position, renderable|
          next unless level.inside?(position.x, position.y)

          Scene::Entity.new(
            entity_id: entity_id,
            x: position.x,
            y: position.y,
            render_key: renderable.render_key,
            fallback_glyph: renderable.glyph,
            layer: renderable.layer
          )
        end.freeze
      end

      def renderables(world)
        world.entity_ids.filter_map do |entity_id|
          position = world.component(entity_id, :position)
          renderable = world.component(entity_id, :renderable)
          next unless position && renderable

          [entity_id, position, renderable]
        end.sort_by { |_entity_id, _position, renderable| renderable.layer }
      end
    end
  end
end
