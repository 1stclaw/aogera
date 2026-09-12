# frozen_string_literal: true

module Aogera
  module Render
    # Static BSP29 world-model renderer. CPU-side BSP interpretation is prepared
    # once by BSP29SurfaceBuilder. With a Quake palette, surfaces are batched by
    # embedded miptexture and rendered with independent base/lightmap UV sets;
    # without one, the established grayscale lightmap-only path remains usable.
    class BSP29World
      LIGHTMAP_ATLAS_PACK_WIDTH = 1024
      LIGHTMAP_PADDING = 1
      WHITE = [255, 255, 255, 255].freeze
      WHITE_PIXEL = [255, 255, 255, 255].pack("C4").b.freeze

      Placement = Data.define(:x, :y, :width, :height)
      Atlas = Data.define(:width, :height, :pixels, :placements)
      Batch = Data.define(:vertices, :texcoords, :texcoords2, :texture_index, :rgba)
      PreparedBatch = Data.define(:model, :rgba)

      attr_reader :batches, :triangle_count, :lightmapped_face_count,
        :lightmap_atlas_width, :lightmap_atlas_height,
        :world_surface_count, :brush_submodel_count, :used_texture_count,
        :missing_texture_face_count

      def batch_count = batches.length
      def textured? = !@palette.nil?

      def initialize(map:, palette: nil)
        @map = map
        @palette = palette
        @prepared_world = BSP29SurfaceBuilder.build(map)
        surfaces = @prepared_world.surfaces
        @world_surface_count = surfaces.length
        @brush_submodel_count = [map.models.length - 1, 0].max
        @used_texture_count, @missing_texture_face_count = texture_diagnostics(surfaces)
        @lightmapped_face_count = surfaces.count(&:lightmap)
        @lightmap_atlas = build_lightmap_atlas(@prepared_world)
        @lightmap_atlas_width = @lightmap_atlas.width
        @lightmap_atlas_height = @lightmap_atlas.height
        @batches = build_batches(surfaces, @lightmap_atlas).freeze
        @triangle_count = batches.sum { |batch| batch.vertices.length / 9 }
        @prepared_batches = nil
        @prepared_textures = nil
        @prepared_shader = nil
      end

      def prepare(api)
        return if prepared?

        prepared = []
        textures = []
        shader = nil
        begin
          if batches.empty?
            @prepared_batches = [].freeze
            @prepared_textures = [].freeze
            return
          end

          lightmap_texture = upload_lightmap(api)
          textures << lightmap_texture
          api.set_texture_wrap(texture: lightmap_texture, mode: :clamp)

          if textured?
            shader = api.create_shader(
              vertex_source: BSP29LightmapShader::VERTEX,
              fragment_source: BSP29LightmapShader::FRAGMENT
            )
            base_textures = upload_base_textures(api, textures)
            prepare_textured_batches(
              api,
              prepared,
              base_textures,
              lightmap_texture,
              shader
            )
          else
            prepare_lightmap_batches(api, prepared, lightmap_texture)
          end

          @prepared_batches = prepared.freeze
          @prepared_textures = textures.freeze
          @prepared_shader = shader
        rescue StandardError
          prepared.each { |batch| api.unload_model(batch.model) }
          textures.reverse_each { |texture| api.unload_texture(texture) }
          api.unload_shader(shader) if shader
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
        @prepared_textures.reverse_each { |texture| api.unload_texture(texture) }
        api.unload_shader(@prepared_shader) if @prepared_shader
        @prepared_batches = nil
        @prepared_textures = nil
        @prepared_shader = nil
      end

      def prepared?
        !@prepared_batches.nil?
      end

      private

      def texture_diagnostics(surfaces)
        used = {}
        missing_faces = 0
        surfaces.each do |surface|
          texture = texture_for(surface.texture_index)
          if texture
            used[surface.texture_index] = true
          else
            missing_faces += 1
          end
        end
        [used.length, missing_faces]
      end

      def build_batches(surfaces, atlas)
        return [] if surfaces.empty?
        return [build_lightmap_batch(surfaces, atlas)] unless textured?

        build_textured_batches(surfaces, atlas)
      end

      def build_lightmap_batch(surfaces, atlas)
        vertices = []
        lightmap_texcoords = []
        surfaces.each_with_index do |surface, surface_index|
          placement = atlas.placements[surface_index]
          append_surface_triangles(
            vertices,
            nil,
            lightmap_texcoords,
            surface,
            nil,
            placement,
            atlas
          )
        end

        Batch.new(
          vertices: vertices.freeze,
          texcoords: lightmap_texcoords.freeze,
          texcoords2: nil,
          texture_index: nil,
          rgba: WHITE
        )
      end

      def build_textured_batches(surfaces, atlas)
        groups = {}
        surfaces.each_with_index do |surface, surface_index|
          texture = texture_for(surface.texture_index)
          key = texture ? surface.texture_index : nil
          group = groups[key] ||= {
            vertices: [],
            texcoords: [],
            texcoords2: []
          }
          placement = atlas.placements[surface_index]
          base_uv = texture && BSP29TextureMapping.normalized_uv(surface, texture)
          append_surface_triangles(
            group.fetch(:vertices),
            group.fetch(:texcoords),
            group.fetch(:texcoords2),
            surface,
            base_uv,
            placement,
            atlas
          )
        end

        groups.map do |texture_index, group|
          Batch.new(
            vertices: group.fetch(:vertices).freeze,
            texcoords: group.fetch(:texcoords).freeze,
            texcoords2: group.fetch(:texcoords2).freeze,
            texture_index: texture_index,
            rgba: WHITE
          )
        end
      end

      def append_surface_triangles(
        vertices,
        base_texcoords,
        lightmap_texcoords,
        surface,
        base_uv,
        placement,
        atlas
      )
        vertex_count = surface.positions.length / 3
        (1...(vertex_count - 1)).each do |index|
          append_vertex_data(
            vertices, base_texcoords, lightmap_texcoords,
            surface, base_uv, 0, placement, atlas
          )
          append_vertex_data(
            vertices, base_texcoords, lightmap_texcoords,
            surface, base_uv, index, placement, atlas
          )
          append_vertex_data(
            vertices, base_texcoords, lightmap_texcoords,
            surface, base_uv, index + 1, placement, atlas
          )
        end
      end

      def append_vertex_data(
        vertices,
        base_texcoords,
        lightmap_texcoords,
        surface,
        base_uv,
        vertex_index,
        placement,
        atlas
      )
        append_position(vertices, surface.positions, vertex_index)
        append_base_uv(base_texcoords, base_uv, vertex_index) if base_texcoords
        append_lightmap_uv(
          lightmap_texcoords,
          surface,
          vertex_index,
          placement,
          atlas
        )
      end

      def append_base_uv(texcoords, base_uv, vertex_index)
        if base_uv
          offset = vertex_index * 2
          texcoords << base_uv.fetch(offset)
          texcoords << base_uv.fetch(offset + 1)
        else
          texcoords << 0.0
          texcoords << 0.0
        end
      end

      def append_lightmap_uv(texcoords, surface, vertex_index, placement, atlas)
        if surface.lightmap && placement
          coordinate_offset = vertex_index * 2
          luxel_s = surface.lightmap_st.fetch(coordinate_offset)
          luxel_t = surface.lightmap_st.fetch(coordinate_offset + 1)
          texcoords << (placement.x + luxel_s + 0.5) / atlas.width
          texcoords << (placement.y + luxel_t + 0.5) / atlas.height
        else
          texcoords << 0.5 / atlas.width
          texcoords << 0.5 / atlas.height
        end
      end

      def upload_lightmap(api)
        api.create_texture_rgba(
          width: @lightmap_atlas.width,
          height: @lightmap_atlas.height,
          pixels: @lightmap_atlas.pixels
        )
      end

      def upload_base_textures(api, textures)
        handles = {}
        batches.each do |batch|
          key = batch.texture_index
          next if handles.key?(key)

          handle = if key
                     texture = @map.textures.fetch(key)
                     image = Quake::MipTextureDecoder.decode(texture, @palette)
                     api.create_texture_rgba(
                       width: image.width,
                       height: image.height,
                       pixels: image.pixels
                     )
                   else
                     api.create_texture_rgba(width: 1, height: 1, pixels: WHITE_PIXEL)
                   end
          textures << handle
          api.set_texture_wrap(texture: handle, mode: :repeat)
          handles[key] = handle
        end
        handles
      end

      def prepare_textured_batches(api, prepared, base_textures, lightmap_texture, shader)
        batches.each do |batch|
          next if batch.vertices.empty?

          model = api.create_static_model(
            vertices: batch.vertices,
            texcoords: batch.texcoords,
            texcoords2: batch.texcoords2
          )
          prepared << PreparedBatch.new(model: model, rgba: batch.rgba)
          api.set_model_shader(model: model, shader: shader)
          api.set_model_texture(
            model: model,
            texture: base_textures.fetch(batch.texture_index),
            slot: :albedo
          )
          api.set_model_texture(
            model: model,
            texture: lightmap_texture,
            slot: :lightmap
          )
        end
      end

      def prepare_lightmap_batches(api, prepared, lightmap_texture)
        batches.each do |batch|
          next if batch.vertices.empty?

          model = api.create_static_model(
            vertices: batch.vertices,
            texcoords: batch.texcoords
          )
          prepared << PreparedBatch.new(model: model, rgba: batch.rgba)
          api.set_model_texture(model: model, texture: lightmap_texture)
        end
      end

      def texture_for(index)
        return unless index.is_a?(Integer) && index >= 0

        @map.textures[index]
      end

      def build_lightmap_atlas(prepared_world)
        surfaces = prepared_world.surfaces
        placements, used_width, used_height = pack_lightmaps(surfaces)
        width = next_power_of_two([used_width, 2].max)
        height = next_power_of_two([used_height, 2].max)
        pixels = (WHITE_PIXEL * (width * height)).b

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
