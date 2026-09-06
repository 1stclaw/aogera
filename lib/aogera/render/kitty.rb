# frozen_string_literal: true

require "base64"

module Aogera
  module Render
    class Kitty
      APC = "\e_G"
      ST = "\e\\"

      TILE_COLUMNS = 2
      TILE_ROWS = 1
      TERRAIN_Z = -100
      IMAGE_ID_BASE = 1_390_000_000
      PLACEMENT_ID_BASE = 1_490_000_000
      PAYLOAD_CHUNK_SIZE = 4096

      Placement = Data.define(
        :image_id,
        :placement_id,
        :x,
        :y,
        :z
      )

      Fallback = Data.define(
        :x,
        :y,
        :glyph
      )

      def initialize(assets:, tile_columns: TILE_COLUMNS, tile_rows: TILE_ROWS)
        @assets = assets
        @tile_columns = tile_columns
        @tile_rows = tile_rows
        @image_ids = {}
        @next_image_id = IMAGE_ID_BASE + 1
        @uploaded = {}
        @placement_ids = {}
        @next_placement_id = PLACEMENT_ID_BASE + 1
        @active_placements = {}
        @active_fallbacks = {}
      end

      def clear_before_render?
        false
      end

      def synchronized_updates?
        true
      end

      def status_row(scene)
        scene.height * @tile_rows + 1
      end

      def render(scene)
        output = +""
        upload_scene_assets(scene, output)

        desired_placements = {}
        desired_fallbacks = {}

        scene.tiles.each do |tile|
          collect_item(
            desired_placements,
            desired_fallbacks,
            key: [:tile, tile.x, tile.y],
            x: tile.x,
            y: tile.y,
            render_key: tile.render_key,
            fallback_glyph: tile.fallback_glyph,
            z: TERRAIN_Z
          )
        end

        scene.entities.sort_by(&:layer).each do |entity|
          collect_item(
            desired_placements,
            desired_fallbacks,
            key: [:entity, entity.entity_id],
            x: entity.x,
            y: entity.y,
            render_key: entity.render_key,
            fallback_glyph: entity.fallback_glyph,
            z: entity.layer
          )
        end

        update_graphics(output, desired_placements)
        update_fallbacks(output, desired_fallbacks)

        @active_placements = desired_placements
        @active_fallbacks = desired_fallbacks
        output
      end

      def finish
        output = +""

        @uploaded.each_key do |render_key|
          output << command(
            "a=d,d=I,i=#{image_id_for(render_key)},q=2"
          )
        end

        reset_state
        output
      end

      private

      def collect_item(
        placements,
        fallbacks,
        key:,
        x:,
        y:,
        render_key:,
        fallback_glyph:,
        z:
      )
        asset = @assets[render_key]

        if asset && @uploaded[render_key]
          placements[key] = Placement.new(
            image_id: image_id_for(render_key),
            placement_id: placement_id_for(key),
            x: x,
            y: y,
            z: z
          )
        else
          fallbacks[key] = Fallback.new(
            x: x,
            y: y,
            glyph: fallback_glyph.to_s
          )
        end
      end

      def update_graphics(output, desired)
        (@active_placements.keys - desired.keys).each do |key|
          output << delete_placement(@active_placements.fetch(key))
        end

        desired.each do |key, placement|
          previous = @active_placements[key]

          if previous && previous.image_id != placement.image_id
            output << delete_placement(previous)
            previous = nil
          end

          next if previous == placement

          output << cursor_to(placement.x, placement.y)
          output << command(
            "a=p,i=#{placement.image_id},p=#{placement.placement_id}," \
            "c=#{@tile_columns},r=#{@tile_rows},C=1," \
            "z=#{placement.z},q=2"
          )
        end
      end

      def update_fallbacks(output, desired)
        (@active_fallbacks.keys - desired.keys).each do |key|
          clear_fallback(output, @active_fallbacks.fetch(key))
        end

        desired.each do |key, fallback|
          previous = @active_fallbacks[key]

          if previous && previous != fallback
            clear_fallback(output, previous)
          end

          next if previous == fallback

          output << cursor_to(fallback.x, fallback.y)
          output << fallback.glyph
        end
      end

      def clear_fallback(output, fallback)
        output << cursor_to(fallback.x, fallback.y)
        output << (" " * @tile_columns)
      end

      def delete_placement(placement)
        command(
          "a=d,d=i,i=#{placement.image_id}," \
          "p=#{placement.placement_id},q=2"
        )
      end

      def upload_scene_assets(scene, output)
        render_keys = scene.tiles.map(&:render_key) +
          scene.entities.map(&:render_key)

        render_keys.uniq.each do |render_key|
          asset = @assets[render_key]
          next unless asset
          next if @uploaded[render_key]

          transmit_png(
            output,
            image_id: image_id_for(render_key),
            path: asset.path
          )
          @uploaded[render_key] = true
        end
      end

      def transmit_png(output, image_id:, path:)
        encoded = Base64.strict_encode64(
          File.binread(path)
        )
        chunks = encoded.scan(
          /.{1,#{PAYLOAD_CHUNK_SIZE}}/m
        )

        chunks.each_with_index do |chunk, index|
          more = index == chunks.length - 1 ? 0 : 1

          control = if index.zero?
            "a=t,t=d,f=100,i=#{image_id},m=#{more},q=2"
          else
            "m=#{more},q=2"
          end

          output << command(control, chunk)
        end
      end

      def image_id_for(render_key)
        @image_ids[render_key] ||= begin
          image_id = @next_image_id
          @next_image_id += 1
          image_id
        end
      end

      def placement_id_for(key)
        @placement_ids[key] ||= begin
          placement_id = @next_placement_id
          @next_placement_id += 1
          placement_id
        end
      end

      def reset_state
        @uploaded.clear
        @image_ids.clear
        @next_image_id = IMAGE_ID_BASE + 1
        @placement_ids.clear
        @next_placement_id = PLACEMENT_ID_BASE + 1
        @active_placements.clear
        @active_fallbacks.clear
      end

      def cursor_to(x, y)
        row = y * @tile_rows + 1
        column = x * @tile_columns + 1
        "\e[#{row};#{column}H"
      end

      def command(control, payload = nil)
        if payload
          "#{APC}#{control};#{payload}#{ST}"
        else
          "#{APC}#{control}#{ST}"
        end
      end
    end
  end
end
