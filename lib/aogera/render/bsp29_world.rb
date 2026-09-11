# frozen_string_literal: true

module Aogera
  module Render
    # Static BSP29 world-model renderer. BSP face polygons are reconstructed on
    # the Ruby side once, assigned UVs into one grayscale baked-lighting atlas,
    # then uploaded to persistent raylib model/mesh resources after the graphics
    # context opens. Only world model 0 is rendered here.
    class BSP29World
      LIGHTMAP_SCALE = 16.0
      LIGHTMAP_ATLAS_PACK_WIDTH = 1024
      LIGHTMAP_PADDING = 1
      WHITE = [255, 255, 255, 255].freeze

      Surface = Data.define(:polygon, :texinfo, :lightmap)
      Lightmap = Data.define(:min_s, :min_t, :width, :height, :samples)
      Placement = Data.define(:x, :y, :width, :height)
      Atlas = Data.define(:width, :height, :pixels, :placements)
      Batch = Data.define(:vertices, :texcoords, :rgba)
      PreparedBatch = Data.define(:model, :rgba)

      attr_reader :batches, :triangle_count, :lightmapped_face_count,
        :lightmap_atlas_width, :lightmap_atlas_height

      def batch_count = batches.length

      def initialize(map:)
        @map = map
        surfaces = build_surfaces.freeze
        @lightmapped_face_count = surfaces.count(&:lightmap)
        @lightmap_atlas = build_lightmap_atlas(surfaces)
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

      def build_surfaces
        model = @map.world_model
        return [] unless model

        faces = @map.faces.slice(model.first_face, model.face_count) || []
        faces.filter_map do |face|
          polygon = face_vertices(face)
          next if polygon.length < 3

          polygon = oriented_polygon(face, polygon)
          texinfo = fetch(@map.texinfo, face.texinfo_index, "texinfo")
          Surface.new(
            polygon: polygon.freeze,
            texinfo: texinfo,
            lightmap: face_lightmap(face, polygon, texinfo)
          )
        end
      end

      def build_batches(surfaces, atlas)
        return [] if surfaces.empty?

        vertices = []
        texcoords = []
        surfaces.each_with_index do |surface, surface_index|
          polygon = surface.polygon
          anchor = polygon.first
          placement = atlas.placements[surface_index]

          (1...(polygon.length - 1)).each do |index|
            append_vertex_and_uv(vertices, texcoords, anchor, surface, placement, atlas)
            append_vertex_and_uv(vertices, texcoords, polygon[index], surface, placement, atlas)
            append_vertex_and_uv(vertices, texcoords, polygon[index + 1], surface, placement, atlas)
          end
        end

        [Batch.new(
          vertices: vertices.freeze,
          texcoords: texcoords.freeze,
          rgba: WHITE
        )]
      end

      def face_lightmap(face, polygon, texinfo)
        return if face.light_offset.negative?
        return if @map.lighting.empty?
        return if face.styles.first == 255

        s_values = polygon.map { |vertex| texture_coordinate(vertex, texinfo.s_axis, texinfo.s_offset) }
        t_values = polygon.map { |vertex| texture_coordinate(vertex, texinfo.t_axis, texinfo.t_offset) }
        min_s = (s_values.min / LIGHTMAP_SCALE).floor
        min_t = (t_values.min / LIGHTMAP_SCALE).floor
        max_s = (s_values.max / LIGHTMAP_SCALE).ceil
        max_t = (t_values.max / LIGHTMAP_SCALE).ceil
        width = (max_s - min_s) + 1
        height = (max_t - min_t) + 1
        sample_count = width * height
        style_count = face.styles.take_while { |style| style != 255 }.length
        required = sample_count * [style_count, 1].max
        last_byte = face.light_offset + required

        if face.light_offset > @map.lighting.bytesize || last_byte > @map.lighting.bytesize
          raise BSP29::FormatError,
            "face lightmap is outside lighting lump: offset=#{face.light_offset}, " \
            "samples=#{required}, size=#{@map.lighting.bytesize}"
        end

        # Aogera's first lightmap preview freezes the first stored Quake light
        # style. Quake's default style uses 8.8 scale 256 and later shifts by 7,
        # which is approximately sample * 2 clamped to 255 for visible intensity.
        source = @map.lighting.byteslice(face.light_offset, sample_count)
        samples = source.bytes.map { |sample| [sample * 2, 255].min }.pack("C*").freeze

        Lightmap.new(
          min_s: min_s,
          min_t: min_t,
          width: width,
          height: height,
          samples: samples
        )
      end

      def build_lightmap_atlas(surfaces)
        placements, used_width, used_height = pack_lightmaps(surfaces)
        width = next_power_of_two([used_width, 2].max)
        height = next_power_of_two([used_height, 2].max)
        pixels = ([255, 255, 255, 255].pack("C4") * (width * height)).b

        surfaces.each_with_index do |surface, index|
          lightmap = surface.lightmap
          placement = placements[index]
          next unless lightmap && placement

          write_lightmap(pixels, width, lightmap, placement)
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

      def write_lightmap(pixels, atlas_width, lightmap, placement)
        (-LIGHTMAP_PADDING...(lightmap.height + LIGHTMAP_PADDING)).each do |local_y|
          source_y = [[local_y, 0].max, lightmap.height - 1].min
          (-LIGHTMAP_PADDING...(lightmap.width + LIGHTMAP_PADDING)).each do |local_x|
            source_x = [[local_x, 0].max, lightmap.width - 1].min
            brightness = lightmap.samples.getbyte((source_y * lightmap.width) + source_x)
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

      def append_vertex_and_uv(vertices, texcoords, vertex, surface, placement, atlas)
        append_vertex(vertices, vertex)
        if surface.lightmap && placement
          lightmap = surface.lightmap
          s = texture_coordinate(vertex, surface.texinfo.s_axis, surface.texinfo.s_offset)
          t = texture_coordinate(vertex, surface.texinfo.t_axis, surface.texinfo.t_offset)
          luxel_s = (s / LIGHTMAP_SCALE) - lightmap.min_s
          luxel_t = (t / LIGHTMAP_SCALE) - lightmap.min_t
          texcoords << (placement.x + luxel_s + 0.5) / atlas.width
          texcoords << (placement.y + luxel_t + 0.5) / atlas.height
        else
          # Pixel (0, 0) is kept fullbright for BSP surfaces without baked data
          # (sky/turbulent/special surfaces and maps with no lighting lump).
          texcoords << 0.5 / atlas.width
          texcoords << 0.5 / atlas.height
        end
      end

      def texture_coordinate(vertex, axis, offset)
        dot(vertex, axis) + offset
      end

      def next_power_of_two(value)
        power = 1
        power <<= 1 while power < value
        power
      end

      def face_vertices(face)
        Array.new(face.edge_count) do |offset|
          surfedge_index = face.first_edge + offset
          surfedge = fetch(@map.surfedges, surfedge_index, "surfedge")
          edge = fetch(@map.edges, surfedge.abs, "edge")
          vertex_index = if surfedge >= 0
            edge.vertex_indices[0]
          else
            edge.vertex_indices[1]
          end

          fetch(@map.vertices, vertex_index, "vertex")
        end
      end

      # The reader's axis conversion preserves handedness. Compare the
      # reconstructed winding against the normalized BSP face plane and reverse
      # only when required so the uploaded mesh faces the correct direction.
      def oriented_polygon(face, polygon)
        return polygon if polygon.length < 3

        plane = fetch(@map.planes, face.plane_index, "plane")
        normal = face.side.zero? ? plane.normal : negate(plane.normal)
        cross = cross_product(
          subtract(polygon[1], polygon[0]),
          subtract(polygon[2], polygon[0])
        )

        dot(cross, normal).negative? ? polygon.reverse : polygon
      end

      def fetch(values, index, label)
        unless index.is_a?(Integer) && index >= 0 && index < values.length
          raise BSP29::FormatError, "#{label} index is out of range: #{index}"
        end

        value = values[index]
        return value if value

        raise BSP29::FormatError, "#{label} index is missing: #{index}"
      end

      def subtract(a, b)
        BSP29::Vec3.new(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
      end

      def cross_product(a, b)
        BSP29::Vec3.new(
          x: (a.y * b.z) - (a.z * b.y),
          y: (a.z * b.x) - (a.x * b.z),
          z: (a.x * b.y) - (a.y * b.x)
        )
      end

      def negate(vector)
        BSP29::Vec3.new(x: -vector.x, y: -vector.y, z: -vector.z)
      end

      def dot(a, b)
        (a.x * b.x) + (a.y * b.y) + (a.z * b.z)
      end

      def append_vertex(vertices, value)
        vertices << value.x << value.y << value.z
      end
    end
  end
end
