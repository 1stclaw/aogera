# frozen_string_literal: true

module Aogera
  module Render
    # Static BSP29 world-model renderer. CPU-side BSP interpretation is prepared
    # once by BSP29SurfaceBuilder; this class owns the current lightmap atlas,
    # persistent raylib model/mesh resources, drawing, and GPU cleanup.
    #
    # Base texture S/T and lightmap S/T remain separate in the prepared surface
    # data. This v0.3.5 checkpoint still uploads only the grayscale baked-light
    # atlas, so rendered output is intentionally unchanged from v0.3.4.
    class BSP29World
      LIGHTMAP_ATLAS_PACK_WIDTH = 1024
      LIGHTMAP_PADDING = 1
      WHITE = [255, 255, 255, 255].freeze

      Placement = Data.define(:x, :y, :width, :height)
      Atlas = Data.define(:width, :height, :pixels, :placements)
      Batch = Data.define(:vertices, :texcoords, :rgba)
      PreparedBatch = Data.define(:model, :rgba)

      attr_reader :batches, :triangle_count, :lightmapped_face_count,
        :lightmap_atlas_width, :lightmap_atlas_height

      def batch_count = batches.length

      def initialize(map:)
        @prepared_world = BSP29SurfaceBuilder.build(map)
        surfaces = @prepared_world.surfaces
        @lightmapped_face_count = surfaces.count(&:lightmap)
        @lightmap_atlas = build_lightmap_atlas(@prepared_world)
        @lightmap_atlas_width = @lightmap_atlas.width
        @lightmap_atlas_height = @lightmap_atlas.height
        @batches = build_batches(surfaces, @lightmap_atlas).freeze
        @triangle_count = batches.sum { |batch| batch.vertices.length / 9 }
        @prepared_batches = nil
        @prepared_texture = nil
      end

      def prepare(api)
        return if prepared?

        prepared = []
        texture = nil
        begin
          if batches.empty?
            @prepared_batches = [].freeze
            return
          end

          texture = api.create_texture_rgba(
            width: @lightmap_atlas.width,
            height: @lightmap_atlas.height,
            pixels: @lightmap_atlas.pixels
          )
          batches.each do |batch|
            next if batch.vertices.empty?

            model = api.create_static_model(
              vertices: batch.vertices,
              texcoords: batch.texcoords
            )
            prepared << PreparedBatch.new(model: model, rgba: batch.rgba)
            api.set_model_texture(model: model, texture: texture)
          end
          @prepared_texture = texture
          @prepared_batches = prepared.freeze
        rescue StandardError
          prepared.each { |batch| api.unload_model(batch.model) }
          api.unload_texture(texture) if texture
          raise
        end
      end

      def draw(api)
        raise "BSP29 world renderer is not prepared" unless prepared?

        @prepared_batches.each do |batch|
          api.draw_model(model: batch.model, rgba: batch.rgba)
        end
      end

      def close(api)
        return unless prepared?

        @prepared_batches.each { |batch| api.unload_model(batch.model) }
        api.unload_texture(@prepared_texture) if @prepared_texture
        @prepared_batches = nil
        @prepared_texture = nil
      end

      def prepared?
        !@prepared_batches.nil?
      end

      private

      def build_batches(surfaces, atlas)
        return [] if surfaces.empty?

        vertices = []
        texcoords = []
        surfaces.each_with_index do |surface, surface_index|
          placement = atlas.placements[surface_index]

          vertex_count = surface.positions.length / 3
          (1...(vertex_count - 1)).each do |index|
            append_vertex_and_uv(vertices, texcoords, surface, 0, placement, atlas)
            append_vertex_and_uv(vertices, texcoords, surface, index, placement, atlas)
            append_vertex_and_uv(vertices, texcoords, surface, index + 1, placement, atlas)
          end
        end

        [Batch.new(
          vertices: vertices.freeze,
          texcoords: texcoords.freeze,
          rgba: WHITE
        )]
      end

      def build_lightmap_atlas(prepared_world)
        surfaces = prepared_world.surfaces
        placements, used_width, used_height = pack_lightmaps(surfaces)
        width = next_power_of_two([used_width, 2].max)
        height = next_power_of_two([used_height, 2].max)
        pixels = ([255, 255, 255, 255].pack("C4") * (width * height)).b

        surfaces.each_with_index do |surface, index|
          lightmap = surface.lightmap
          placement = placements[index]
          next unless lightmap && placement

          write_lightmap(
            pixels,
            width,
            prepared_world.lighting,
            lightmap,
            placement
          )
        end

        Atlas.new(
          width: width,
          height: height,
          pixels: pixels.freeze,
          placements: placements.freeze
        )
      end

      def pack_lightmaps(surfaces)
        placements = Array.new(surfaces.length)
        x = 1
        y = 1
        row_height = 0
        used_width = 1

        surfaces.each_with_index do |surface, index|
          lightmap = surface.lightmap
          next unless lightmap

          outer_width = lightmap.width + (LIGHTMAP_PADDING * 2)
          outer_height = lightmap.height + (LIGHTMAP_PADDING * 2)
          if outer_width + 2 > LIGHTMAP_ATLAS_PACK_WIDTH
            raise BSP29::FormatError,
              "face lightmap is too wide for atlas: #{lightmap.width} samples"
          end

          if x + outer_width + 1 > LIGHTMAP_ATLAS_PACK_WIDTH
            x = 1
            y += row_height
            row_height = 0
          end

          placements[index] = Placement.new(
            x: x + LIGHTMAP_PADDING,
            y: y + LIGHTMAP_PADDING,
            width: lightmap.width,
            height: lightmap.height
          )
          x += outer_width
          row_height = [row_height, outer_height].max
          used_width = [used_width, x + 1].max
        end

        used_height = y + row_height + 1
        [placements, used_width, used_height]
      end

      def write_lightmap(pixels, atlas_width, lighting, lightmap, placement)
        (-LIGHTMAP_PADDING...(lightmap.height + LIGHTMAP_PADDING)).each do |local_y|
          source_y = [[local_y, 0].max, lightmap.height - 1].min
          (-LIGHTMAP_PADDING...(lightmap.width + LIGHTMAP_PADDING)).each do |local_x|
            source_x = [[local_x, 0].max, lightmap.width - 1].min
            sample_index = (source_y * lightmap.width) + source_x
            sample = lighting.getbyte(lightmap.light_offset + sample_index)
            brightness = [sample * 2, 255].min
            atlas_x = placement.x + local_x
            atlas_y = placement.y + local_y
            write_grayscale_pixel(pixels, atlas_width, atlas_x, atlas_y, brightness)
          end
        end
      end

      def write_grayscale_pixel(pixels, width, x, y, brightness)
        offset = ((y * width) + x) * 4
        pixels.setbyte(offset, brightness)
        pixels.setbyte(offset + 1, brightness)
        pixels.setbyte(offset + 2, brightness)
        pixels.setbyte(offset + 3, 255)
      end

      def append_vertex_and_uv(vertices, texcoords, surface, vertex_index, placement, atlas)
        append_position(vertices, surface.positions, vertex_index)
        if surface.lightmap && placement
          coordinate_offset = vertex_index * 2
          luxel_s = surface.lightmap_st.fetch(coordinate_offset)
          luxel_t = surface.lightmap_st.fetch(coordinate_offset + 1)
          texcoords << (placement.x + luxel_s + 0.5) / atlas.width
          texcoords << (placement.y + luxel_t + 0.5) / atlas.height
        else
          # Pixel (0, 0) is kept fullbright for BSP surfaces without baked data
          # (sky/turbulent/special surfaces and maps with no lighting lump).
          texcoords << 0.5 / atlas.width
          texcoords << 0.5 / atlas.height
        end
      end

      def append_position(vertices, positions, vertex_index)
        offset = vertex_index * 3
        vertices << positions.fetch(offset)
        vertices << positions.fetch(offset + 1)
        vertices << positions.fetch(offset + 2)
      end

      def next_power_of_two(value)
        power = 1
        power <<= 1 while power < value
        power
      end
    end
  end
end
