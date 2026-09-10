# frozen_string_literal: true

module Aogera
  module Render
    # Minimal BSP29 static-world renderer used by the controlled test-field
    # fixture. It draws only world model 0. Navigation and authored gameplay
    # still use the current Level; BSP movement collision is handled elsewhere.
    class BSP29World
      Triangle = Data.define(:a, :b, :c, :texture_name)

      DEFAULT_COLOR = [92, 88, 80, 255].freeze
      TEXTURE_COLORS = {
        "AOG_GROUND" => [82, 76, 62, 255],
        "AOG_GRASS" => [58, 88, 58, 255],
        "AOG_WATER" => [42, 82, 118, 255],
        "AOG_WALL" => [102, 102, 110, 255]
      }.freeze

      attr_reader :triangles

      def initialize(map:)
        @map = map
        @triangles = build_triangles.freeze
      end

      def draw(api)
        triangles.each do |triangle|
          api.draw_triangle_3d(
            a: vector(triangle.a),
            b: vector(triangle.b),
            c: vector(triangle.c),
            rgba: TEXTURE_COLORS.fetch(triangle.texture_name, DEFAULT_COLOR)
          )
        end
      end

      private

      def build_triangles
        model = @map.world_model
        return [] unless model

        faces = @map.faces.slice(model.first_face, model.face_count) || []
        faces.flat_map do |face|
          polygon = face_vertices(face)
          next [] if polygon.length < 3

          polygon = oriented_polygon(face, polygon)
          texture_name = texture_name(face)
          anchor = polygon.first

          (1...(polygon.length - 1)).map do |index|
            Triangle.new(
              a: anchor,
              b: polygon[index],
              c: polygon[index + 1],
              texture_name: texture_name
            )
          end
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

      # DrawTriangle3D expects counter-clockwise vertices. The reader's axis
      # conversion preserves handedness, so compare the reconstructed winding
      # against the BSP face plane and reverse only when required.
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

      def vector(value)
        [value.x, value.y, value.z]
      end
    end
  end
end
