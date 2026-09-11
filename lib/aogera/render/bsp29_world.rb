# frozen_string_literal: true

module Aogera
  module Render
    # Static BSP29 world-model renderer. BSP face polygons are reconstructed on
    # the Ruby side once, grouped into a small number of diagnostic-color
    # batches, then uploaded to persistent raylib model/mesh resources after the
    # graphics context opens. Only world model 0 is rendered here.
    class BSP29World
      Batch = Data.define(:vertices, :rgba)
      PreparedBatch = Data.define(:model, :rgba)

      DEFAULT_COLOR = [92, 88, 80, 255].freeze
      TEXTURE_COLORS = {
        "AOG_GROUND" => [82, 76, 62, 255],
        "AOG_GRASS" => [58, 88, 58, 255],
        "AOG_WATER" => [42, 82, 118, 255],
        "AOG_WALL" => [102, 102, 110, 255]
      }.freeze

      attr_reader :batches, :triangle_count

      def batch_count = batches.length

      def initialize(map:)
        @map = map
        @batches = build_batches.freeze
        @triangle_count = batches.sum { |batch| batch.vertices.length / 9 }
        @prepared_batches = nil
      end

      def prepare(api)
        return if prepared?

        prepared = []
        begin
          batches.each do |batch|
            next if batch.vertices.empty?

            prepared << PreparedBatch.new(
              model: api.create_static_model(vertices: batch.vertices),
              rgba: batch.rgba
            )
          end
          @prepared_batches = prepared.freeze
        rescue StandardError
          prepared.each { |batch| api.unload_model(batch.model) }
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
        @prepared_batches = nil
      end

      def prepared?
        !@prepared_batches.nil?
      end

      private

      def build_batches
        vertices_by_color = Hash.new { |groups, rgba| groups[rgba] = [] }
        model = @map.world_model
        return [] unless model

        faces = @map.faces.slice(model.first_face, model.face_count) || []
        faces.each do |face|
          polygon = face_vertices(face)
          next if polygon.length < 3

          polygon = oriented_polygon(face, polygon)
          rgba = TEXTURE_COLORS.fetch(texture_name(face), DEFAULT_COLOR)
          anchor = polygon.first

          (1...(polygon.length - 1)).each do |index|
            append_vertex(vertices_by_color[rgba], anchor)
            append_vertex(vertices_by_color[rgba], polygon[index])
            append_vertex(vertices_by_color[rgba], polygon[index + 1])
          end
        end

        vertices_by_color.map do |rgba, vertices|
          Batch.new(vertices: vertices.freeze, rgba: rgba)
        end
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

      def texture_name(face)
        info = fetch(@map.texinfo, face.texinfo_index, "texinfo")
        texture = fetch(@map.textures, info.texture_index, "texture", allow_nil: true)
        texture&.name
      end

      def fetch(values, index, label, allow_nil: false)
        unless index.is_a?(Integer) && index >= 0 && index < values.length
          raise BSP29::FormatError, "#{label} index is out of range: #{index}"
        end

        value = values[index]
        return value if value || allow_nil

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
