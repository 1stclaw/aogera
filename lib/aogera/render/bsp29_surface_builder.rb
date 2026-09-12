# frozen_string_literal: true

module Aogera
  module Render
    # Converts BSP29 world-model faces into stable CPU-side surface data once at
    # map load. The representation deliberately preserves Quake base-texture
    # coordinates and baked-lightmap coordinates as separate domains; atlas/GPU
    # placement remains a renderer concern.
    module BSP29SurfaceBuilder
      LIGHTMAP_SCALE = 16.0

      Lightmap = Data.define(
        :min_s,
        :min_t,
        :width,
        :height,
        :styles,
        :light_offset
      )

      Surface = Data.define(
        :face_index,
        :positions,
        :texture_st,
        :lightmap_st,
        :texture_index,
        :texture_name,
        :texinfo_flags,
        :lightmap
      )

      BuildDiagnostics = Data.define(
        :world_face_count,
        :prepared_surface_count,
        :dropped_face_count,
        :reversed_face_count,
        :source_triangle_count,
        :degenerate_triangle_count
      )

      PreparedWorld = Data.define(:surfaces, :lighting, :diagnostics)

      module_function

      def build(map)
        model = map.world_model
        lighting = map.lighting
        lighting = lighting.dup.freeze unless lighting.frozen?
        surfaces, diagnostics = if model
          build_world_surfaces(map, model, lighting)
        else
          [
            [].freeze,
            BuildDiagnostics.new(
              world_face_count: 0,
              prepared_surface_count: 0,
              dropped_face_count: 0,
              reversed_face_count: 0,
              source_triangle_count: 0,
              degenerate_triangle_count: 0
            )
          ]
        end

        PreparedWorld.new(
          surfaces: surfaces,
          lighting: lighting,
          diagnostics: diagnostics
        )
      end

      def build_world_surfaces(map, model, lighting)
        faces = map.faces.slice(model.first_face, model.face_count) || []
        surfaces = []
        dropped_face_count = 0
        reversed_face_count = 0
        source_triangle_count = 0
        degenerate_triangle_count = 0

        faces.each_with_index do |face, local_index|
          polygon = face_vertices(map, face)
          if polygon.length < 3
            dropped_face_count += 1
            next
          end

          fetch(map.planes, face.plane_index, "plane")
          polygon = raylib_polygon(polygon)
          reversed_face_count += 1
          source_triangle_count += polygon.length - 2
          degenerate_triangle_count += degenerate_triangle_count_for(polygon)

          texinfo = fetch(map.texinfo, face.texinfo_index, "texinfo")
          texture_st = texture_coordinates(polygon, texinfo)
          lightmap = face_lightmap(face, texture_st, lighting)

          surfaces << Surface.new(
            face_index: model.first_face + local_index,
            positions: flatten_positions(polygon),
            texture_st: texture_st,
            lightmap_st: lightmap && lightmap_coordinates(texture_st, lightmap),
            texture_index: texinfo.texture_index,
            texture_name: texture_name(map, texinfo.texture_index),
            texinfo_flags: texinfo.flags,
            lightmap: lightmap
          )
        end

        frozen_surfaces = surfaces.freeze
        diagnostics = BuildDiagnostics.new(
          world_face_count: faces.length,
          prepared_surface_count: frozen_surfaces.length,
          dropped_face_count: dropped_face_count,
          reversed_face_count: reversed_face_count,
          source_triangle_count: source_triangle_count,
          degenerate_triangle_count: degenerate_triangle_count
        )
        [frozen_surfaces, diagnostics]
      end
      private_class_method :build_world_surfaces

      def face_vertices(map, face)
        Array.new(face.edge_count) do |offset|
          surfedge_index = face.first_edge + offset
          surfedge = fetch(map.surfedges, surfedge_index, "surfedge")
          edge = fetch(map.edges, surfedge.abs, "edge")
          vertex_index = surfedge >= 0 ? edge.vertex_indices[0] : edge.vertex_indices[1]
          fetch(map.vertices, vertex_index, "vertex")
        end
      end
      private_class_method :face_vertices

      # Quake BSP surfedges already encode the face polygon in the winding used
      # by the original renderer. GLQuake submits that order directly and culls
      # front faces; raylib uses the conventional back-face-culling direction.
      # The BSP->Aogera coordinate transform preserves handedness, so convert the
      # source winding exactly once by reversing the complete polygon.
      #
      # Do not infer orientation from the first three points: QBSP's T-junction
      # fixing can insert collinear boundary vertices, making an otherwise valid
      # face begin with a zero-area triple.
      def raylib_polygon(polygon)
        polygon.reverse
      end
      private_class_method :raylib_polygon

      def degenerate_triangle_count_for(polygon)
        origin = polygon.fetch(0)
        count = 0
        (1...(polygon.length - 1)).each do |index|
          count += 1 if triangle_degenerate?(origin, polygon[index], polygon[index + 1])
        end
        count
      end
      private_class_method :degenerate_triangle_count_for

      def triangle_degenerate?(a, b, c)
        ab_x = b.x - a.x
        ab_y = b.y - a.y
        ab_z = b.z - a.z
        ac_x = c.x - a.x
        ac_y = c.y - a.y
        ac_z = c.z - a.z
        cross_x = (ab_y * ac_z) - (ab_z * ac_y)
        cross_y = (ab_z * ac_x) - (ab_x * ac_z)
        cross_z = (ab_x * ac_y) - (ab_y * ac_x)
        magnitude_squared =
          (cross_x * cross_x) + (cross_y * cross_y) + (cross_z * cross_z)
        magnitude_squared <= 1.0e-12
      end
      private_class_method :triangle_degenerate?

      def flatten_positions(polygon)
        positions = []
        polygon.each do |vertex|
          positions << vertex.x << vertex.y << vertex.z
        end
        positions.freeze
      end
      private_class_method :flatten_positions

      # Preserve Quake texture-space S/T exactly. Values may be negative or
      # extend far beyond one miptexture width/height because world textures tile.
      def texture_coordinates(polygon, texinfo)
        coordinates = []
        polygon.each do |vertex|
          coordinates << texture_coordinate(vertex, texinfo.s_axis, texinfo.s_offset)
          coordinates << texture_coordinate(vertex, texinfo.t_axis, texinfo.t_offset)
        end
        coordinates.freeze
      end
      private_class_method :texture_coordinates

      # Lightmap coordinates remain local luxel-space coordinates. Atlas
      # placement and normalized GPU UVs are deliberately not part of a Surface.
      def lightmap_coordinates(texture_st, lightmap)
        coordinates = []
        texture_st.each_slice(2) do |s, t|
          coordinates << (s / LIGHTMAP_SCALE) - lightmap.min_s
          coordinates << (t / LIGHTMAP_SCALE) - lightmap.min_t
        end
        coordinates.freeze
      end
      private_class_method :lightmap_coordinates

      def face_lightmap(face, texture_st, lighting)
        return if face.light_offset.negative?
        return if lighting.empty?

        styles = face.styles.take_while { |style| style != 255 }.freeze
        return if styles.empty?

        first_s = texture_st.fetch(0)
        first_t = texture_st.fetch(1)
        min_texture_s = max_texture_s = first_s
        min_texture_t = max_texture_t = first_t
        index = 2
        while index < texture_st.length
          s = texture_st[index]
          t = texture_st[index + 1]
          min_texture_s = s if s < min_texture_s
          max_texture_s = s if s > max_texture_s
          min_texture_t = t if t < min_texture_t
          max_texture_t = t if t > max_texture_t
          index += 2
        end

        min_s = (min_texture_s / LIGHTMAP_SCALE).floor
        min_t = (min_texture_t / LIGHTMAP_SCALE).floor
        max_s = (max_texture_s / LIGHTMAP_SCALE).ceil
        max_t = (max_texture_t / LIGHTMAP_SCALE).ceil
        width = (max_s - min_s) + 1
        height = (max_t - min_t) + 1
        sample_count = width * height
        required = sample_count * styles.length
        last_byte = face.light_offset + required

        if face.light_offset > lighting.bytesize || last_byte > lighting.bytesize
          raise BSP29::FormatError,
            "face lightmap is outside lighting lump: offset=#{face.light_offset}, " \
            "samples=#{required}, size=#{lighting.bytesize}"
        end

        Lightmap.new(
          min_s: min_s,
          min_t: min_t,
          width: width,
          height: height,
          styles: styles,
          light_offset: face.light_offset
        )
      end
      private_class_method :face_lightmap

      def texture_name(map, index)
        return unless index.is_a?(Integer) && index >= 0 && index < map.textures.length

        map.textures[index]&.name
      end
      private_class_method :texture_name

      def texture_coordinate(vertex, axis, offset)
        (vertex.x * axis.x) + (vertex.y * axis.y) + (vertex.z * axis.z) + offset
      end
      private_class_method :texture_coordinate

      def fetch(values, index, label)
        unless index.is_a?(Integer) && index >= 0 && index < values.length
          raise BSP29::FormatError, "#{label} index is out of range: #{index}"
        end

        value = values[index]
        return value if value

        raise BSP29::FormatError, "#{label} index is missing: #{index}"
      end
      private_class_method :fetch
    end
  end
end
