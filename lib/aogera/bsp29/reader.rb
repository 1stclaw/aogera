# frozen_string_literal: true

module Aogera
  module BSP29
    module Reader
      RECORD_SIZES = {
        planes: 20,
        vertices: 12,
        nodes: 24,
        texinfo: 40,
        faces: 20,
        clipnodes: 8,
        leaves: 28,
        marksurfaces: 2,
        edges: 4,
        surfedges: 4,
        models: 64
      }.freeze

      module_function

      def read(path)
        read_bytes(File.binread(path))
      rescue Errno::ENOENT => error
        raise FormatError, "BSP29 file not found: #{error.message}"
      end

      def read_bytes(bytes)
        source = String(bytes).b
        lumps = read_header(source)

        MapData.new(
          entities: read_entities(source, lumps.fetch(:entities)),
          planes: read_planes(source, lumps.fetch(:planes)),
          textures: read_textures(source, lumps.fetch(:textures)),
          vertices: read_vertices(source, lumps.fetch(:vertices)),
          visibility: read_blob(source, lumps.fetch(:visibility)),
          nodes: read_nodes(source, lumps.fetch(:nodes)),
          texinfo: read_texinfo(source, lumps.fetch(:texinfo)),
          faces: read_faces(source, lumps.fetch(:faces)),
          lighting: read_blob(source, lumps.fetch(:lighting)),
          clipnodes: read_clipnodes(source, lumps.fetch(:clipnodes)),
          leaves: read_leaves(source, lumps.fetch(:leaves)),
          marksurfaces: read_marksurfaces(source, lumps.fetch(:marksurfaces)),
          edges: read_edges(source, lumps.fetch(:edges)),
          surfedges: read_surfedges(source, lumps.fetch(:surfedges)),
          models: read_models(source, lumps.fetch(:models))
        )
      end

      def read_header(source)
        if source.bytesize < HEADER_SIZE
          raise FormatError,
            "BSP29 header is truncated: expected at least #{HEADER_SIZE} bytes, got #{source.bytesize}"
        end

        version = source.unpack1("l<")
        unless version == VERSION
          raise FormatError, "unsupported BSP version #{version}; expected #{VERSION}"
        end

        LUMP_NAMES.each_with_index.to_h do |name, index|
          offset, length = source.byteslice(4 + (index * 8), 8).unpack("l<l<")
          validate_lump_bounds!(name, offset, length, source.bytesize)
          [name, Lump.new(offset: offset, length: length)]
        end.freeze
      end
      private_class_method :read_header

      def validate_lump_bounds!(name, offset, length, source_size)
        if offset.negative? || length.negative?
          raise FormatError, "#{name} lump has negative offset/length"
        end
        if length.positive? && offset < HEADER_SIZE
          raise FormatError, "#{name} lump overlaps the BSP header"
        end
        return if offset <= source_size && length <= (source_size - offset)

        raise FormatError,
          "#{name} lump is outside the file: offset=#{offset}, length=#{length}, size=#{source_size}"
      end
      private_class_method :validate_lump_bounds!

      def read_blob(source, lump)
        source.byteslice(lump.offset, lump.length).dup.freeze
      end
      private_class_method :read_blob

      def records(source, lump, name)
        size = RECORD_SIZES.fetch(name)
        unless (lump.length % size).zero?
          raise FormatError,
            "#{name} lump length #{lump.length} is not a multiple of record size #{size}"
        end

        count = lump.length / size
        Array.new(count) do |index|
          source.byteslice(lump.offset + (index * size), size)
        end
      end
      private_class_method :records

      def read_planes(source, lump)
        records(source, lump, :planes).map do |record|
          x, y, z, distance, type = record.unpack("eeee l<")
          Plane.new(
            normal: Coordinates.vector(x, y, z),
            distance: distance,
            type: Coordinates.plane_type(type)
          )
        end.freeze
      end
      private_class_method :read_planes

      def read_vertices(source, lump)
        records(source, lump, :vertices).map do |record|
          Coordinates.vector(*record.unpack("eee"))
        end.freeze
      end
      private_class_method :read_vertices

      def read_nodes(source, lump)
        records(source, lump, :nodes).map do |record|
          planenum, child0, child1,
            min_x, min_y, min_z, max_x, max_y, max_z,
            first_face, face_count = record.unpack("l<s<s<s<s<s<s<s<s<S<S<")

          Node.new(
            plane_index: planenum,
            children: [child0, child1].freeze,
            bounds: Coordinates.bounds(
              [min_x, min_y, min_z],
              [max_x, max_y, max_z]
            ),
            first_face: first_face,
            face_count: face_count
          )
        end.freeze
      end
      private_class_method :read_nodes

      def read_texinfo(source, lump)
        records(source, lump, :texinfo).map do |record|
          values = record.unpack("eeeeeeee l<l<")
          TexInfo.new(
            s_axis: Coordinates.vector(values[0], values[1], values[2]),
            s_offset: values[3],
            t_axis: Coordinates.vector(values[4], values[5], values[6]),
            t_offset: values[7],
            texture_index: values[8],
            flags: values[9]
          )
        end.freeze
      end
      private_class_method :read_texinfo

      def read_faces(source, lump)
        records(source, lump, :faces).map do |record|
          plane_index, side, first_edge, edge_count, texinfo_index,
            style0, style1, style2, style3, light_offset =
              record.unpack("s<s<l<s<s<CCCC l<")

          Face.new(
            plane_index: plane_index,
            side: side,
            first_edge: first_edge,
            edge_count: edge_count,
            texinfo_index: texinfo_index,
            styles: [style0, style1, style2, style3].freeze,
            light_offset: light_offset
          )
        end.freeze
      end
      private_class_method :read_faces

      def read_clipnodes(source, lump)
        records(source, lump, :clipnodes).map do |record|
          planenum, child0, child1 = record.unpack("l<s<s<")
          ClipNode.new(
            plane_index: planenum,
            children: [child0, child1].freeze
          )
        end.freeze
      end
      private_class_method :read_clipnodes

      def read_leaves(source, lump)
        records(source, lump, :leaves).map do |record|
          contents, visibility_offset,
            min_x, min_y, min_z, max_x, max_y, max_z,
            first_marksurface, marksurface_count,
            ambient0, ambient1, ambient2, ambient3 =
              record.unpack("l<l<s<s<s<s<s<s<S<S<CCCC")

          Leaf.new(
            contents: contents,
            visibility_offset: visibility_offset,
            bounds: Coordinates.bounds(
              [min_x, min_y, min_z],
              [max_x, max_y, max_z]
            ),
            first_marksurface: first_marksurface,
            marksurface_count: marksurface_count,
            ambient_levels: [ambient0, ambient1, ambient2, ambient3].freeze
          )
        end.freeze
      end
      private_class_method :read_leaves

      def read_marksurfaces(source, lump)
        records(source, lump, :marksurfaces).map do |record|
          record.unpack1("S<")
        end.freeze
      end
      private_class_method :read_marksurfaces

      def read_edges(source, lump)
        records(source, lump, :edges).map do |record|
          Edge.new(vertex_indices: record.unpack("S<S<").freeze)
        end.freeze
      end
      private_class_method :read_edges

      def read_surfedges(source, lump)
        records(source, lump, :surfedges).map do |record|
          record.unpack1("l<")
        end.freeze
      end
      private_class_method :read_surfedges

      def read_models(source, lump)
        records(source, lump, :models).map do |record|
          values = record.unpack("eeeeee eee l<l<l<l< l<l<l<")
          Model.new(
            bounds: Coordinates.bounds(values[0, 3], values[3, 3]),
            origin: Coordinates.vector(*values[6, 3]),
            headnodes: values[9, 4].freeze,
            visible_leaf_count: values[13],
            first_face: values[14],
            face_count: values[15]
          )
        end.freeze
      end
      private_class_method :read_models

      def read_textures(source, lump)
        return [].freeze if lump.length.zero?
        if lump.length < 4
          raise FormatError, "textures lump is too small for a texture count"
        end

        bytes = source.byteslice(lump.offset, lump.length)
        count = bytes.unpack1("l<")
        raise FormatError, "textures lump has a negative texture count" if count.negative?

        directory_size = 4 + (count * 4)
        if directory_size > bytes.bytesize
          raise FormatError, "textures lump directory is truncated"
        end

        offsets = bytes.byteslice(4, count * 4).unpack("l<#{count}")
        offsets.map.with_index do |offset, index|
          next if offset == -1

          read_texture(bytes, offset, index)
        end.freeze
      end
      private_class_method :read_textures

      def read_texture(bytes, offset, index)
        if offset.negative? || offset + 40 > bytes.bytesize
          raise FormatError, "texture #{index} header is outside the textures lump"
        end

        header = bytes.byteslice(offset, 40)
        raw_name = header.byteslice(0, 16)
        width, height, mip0, mip1, mip2, mip3 = header.byteslice(16, 24).unpack("V6")
        if width.zero? || height.zero?
          raise FormatError, "texture #{index} has zero dimensions"
        end

        mip_offsets = [mip0, mip1, mip2, mip3]
        mipmaps = mip_offsets.each_with_index.map do |mip_offset, level|
          width_at_level = [width >> level, 1].max
          height_at_level = [height >> level, 1].max
          size = width_at_level * height_at_level
          absolute = offset + mip_offset
          if mip_offset.zero? || absolute.negative? || absolute + size > bytes.bytesize
            raise FormatError, "texture #{index} mip level #{level} is outside the textures lump"
          end
          bytes.byteslice(absolute, size).dup.freeze
        end.freeze

        MipTexture.new(
          name: raw_name.delete("\0").dup.freeze,
          width: width,
          height: height,
          mipmaps: mipmaps
        )
      end
      private_class_method :read_texture

      def read_entities(source, lump)
        text = source.byteslice(lump.offset, lump.length).delete_suffix("\0")
        EntityParser.parse(text)
      rescue ArgumentError => error
        raise FormatError, "invalid entities lump: #{error.message}"
      end
      private_class_method :read_entities

      module EntityParser
        module_function

        def parse(text)
          cursor = Cursor.new(text)
          entities = []

          until cursor.eof?
            cursor.skip_whitespace
            break if cursor.eof?
            cursor.expect!("{")
            properties = {}

            loop do
              cursor.skip_whitespace
              break if cursor.consume?("}")

              key = cursor.quoted_string
              cursor.skip_whitespace
              value = cursor.quoted_string
              properties[key] = value
            end

            frozen_properties = properties.transform_values { |value| value.dup.freeze }.freeze
            entities << Entity.new(
              properties: frozen_properties,
              origin: parse_origin(frozen_properties["origin"])
            )
          end

          entities.freeze
        end

        def parse_origin(value)
          return if value.nil?

          parts = value.split
          unless parts.length == 3
            raise ArgumentError, "entity origin must contain exactly three numbers: #{value.inspect}"
          end

          Coordinates.vector(*parts.map { |part| Float(part) })
        end
        private_class_method :parse_origin

        class Cursor
          def initialize(text)
            @text = text
            @index = 0
          end

          def eof?
            @index >= @text.length
          end

          def skip_whitespace
            @index += 1 while !eof? && @text.getbyte(@index)&.chr&.match?(/\s/)
          end

          def consume?(character)
            return false unless @text[@index] == character

            @index += 1
            true
          end

          def expect!(character)
            skip_whitespace
            return if consume?(character)

            raise ArgumentError, "expected #{character.inspect} at byte #{@index}"
          end

          def quoted_string
            skip_whitespace
            unless consume?("\"")
              raise ArgumentError, "expected quoted string at byte #{@index}"
            end

            result = +""
            until eof?
              character = @text[@index]
              @index += 1

              if character == "\""
                return result
              end

              if character == "\\" && !eof?
                result << @text[@index]
                @index += 1
              else
                result << character
              end
            end

            raise ArgumentError, "unterminated quoted string"
          end
        end
      end
      private_constant :EntityParser
    end
  end
end
