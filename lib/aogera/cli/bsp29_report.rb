# frozen_string_literal: true

module Aogera
  module CLI
    class BSP29Report
      def initialize(stdout: $stdout)
        @stdout = stdout
      end

      def bsp_info(map, source:)
        world = map.world_model

        @stdout.puts "BSP29: #{source}"
        @stdout.puts "entities:     #{map.entities.length}"
        @stdout.puts "planes:       #{map.planes.length}"
        @stdout.puts "textures:     #{map.textures.length}"
        @stdout.puts "vertices:     #{map.vertices.length}"
        @stdout.puts "nodes:        #{map.nodes.length}"
        @stdout.puts "faces:        #{map.faces.length}"
        @stdout.puts "clipnodes:    #{map.clipnodes.length}"
        @stdout.puts "leaves:       #{map.leaves.length}"
        @stdout.puts "edges:        #{map.edges.length}"
        @stdout.puts "surfedges:    #{map.surfedges.length}"
        @stdout.puts "models:       #{map.models.length}"
        @stdout.puts "world faces:  #{world ? world.face_count : 0}"
        @stdout.puts "submodels:    #{[map.models.length - 1, 0].max}"
        @stdout.puts "vis bytes:    #{map.visibility.bytesize}"
        @stdout.puts "light bytes:  #{map.lighting.bytesize}"

        if world
          @stdout.puts(
            "world bounds:  #{format_vec(world.bounds.mins)} -> " \
            "#{format_vec(world.bounds.maxs)}"
          )
        end

        starts = map.entities_named("info_player_start")
        @stdout.puts "player starts: #{starts.length}"
        starts.each_with_index do |entity, index|
          @stdout.puts "  #{index}: #{format_vec(entity.origin)}"
        end
      end

      def entities(map, source:)
        @stdout.puts "BSP29 entities: #{source}"
        @stdout.puts "count: #{map.entities.length}"

        map.entities.each_with_index do |entity, index|
          @stdout.puts
          @stdout.puts "[#{index}] #{entity.classname || '(no classname)'}"
          entity.properties.each do |key, value|
            @stdout.puts "  #{key}=#{value.inspect}"
          end
          if entity.origin
            @stdout.puts "  normalized_origin=#{format_vec(entity.origin)}"
          end
        end
      end

      def textures(map, source:)
        world = map.world_model
        faces = if world
          map.faces.slice(world.first_face, world.face_count) || []
        else
          []
        end

        counts = Hash.new(0)
        faces.each do |face|
          index = face.texinfo_index
          if index.negative? || index >= map.texinfo.length
            raise Aogera::BSP29::FormatError,
              "world face references missing texinfo #{index}"
          end

          counts[map.texinfo[index].texture_index] += 1
        end

        used = []
        missing = []
        counts.each do |texture_index, face_count|
          texture = if texture_index >= 0 && texture_index < map.textures.length
            map.textures[texture_index]
          end
          if texture
            used << [texture.name, texture.width, texture.height, face_count, texture_index]
          else
            missing << [texture_index, face_count]
          end
        end

        used.sort_by! { |name, _width, _height, _faces, _index| name }
        missing.sort_by!(&:first)
        used_indices = counts.keys.to_h { |index| [index, true] }
        unused = map.textures.each_with_index.filter_map do |texture, index|
          next unless texture
          next if used_indices[index]

          [texture.name, texture.width, texture.height, index]
        end
        unused.sort_by! { |name, _width, _height, _index| name }

        embedded_count = map.textures.count { |texture| texture }
        @stdout.puts "BSP29 textures: #{source}"
        @stdout.puts "texture slots:       #{map.textures.length}"
        @stdout.puts "embedded textures:   #{embedded_count}"
        @stdout.puts "world face refs:      #{faces.length}"
        @stdout.puts "unique used textures: #{used.length}"
        @stdout.puts "missing used slots:   #{missing.length}"

        @stdout.puts
        @stdout.puts "World-model textures:"
        if used.empty?
          @stdout.puts "  (none)"
        else
          used.each do |name, width, height, face_count, index|
            @stdout.puts format(
              "  %-16s %4dx%-4d faces=%-4d index=%d",
              name, width, height, face_count, index
            )
          end
        end

        unless missing.empty?
          @stdout.puts
          @stdout.puts "Missing texture slots referenced by world faces:"
          missing.each do |index, face_count|
            @stdout.puts "  index=#{index} faces=#{face_count}"
          end
        end

        unless unused.empty?
          @stdout.puts
          @stdout.puts "Embedded but unused by world model:"
          unused.each do |name, width, height, index|
            @stdout.puts format(
              "  %-16s %4dx%-4d index=%d",
              name, width, height, index
            )
          end
        end
      end

      private

      def format_vec(vec)
        return "(none)" unless vec

        "(#{vec.x}, #{vec.y}, #{vec.z})"
      end
    end
  end
end
