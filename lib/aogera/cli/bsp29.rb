# frozen_string_literal: true

require "optparse"

module Aogera
  module CLI
    BSP29Options = Data.define(:path, :mode, :action)

    class BSP29
      EX_USAGE = 64
      EX_DATAERR = 65

      def initialize(
        reader: Aogera::BSP29::Reader.method(:read),
        app_factory: nil,
        stdout: $stdout,
        stderr: $stderr
      )
        @reader = reader
        @app_factory = app_factory || lambda do |map, mode:|
          build_app(map, mode:)
        end
        @stdout = stdout
        @stderr = stderr
      end

      def run(argv)
        options, parser = parse(argv)
        return print_help(parser) if options.action == :help

        map = @reader.call(options.path)

        case options.action
        when :run
          @app_factory.call(map, mode: options.mode).run
        when :bsp_info
          print_bsp_info(map, options.path)
        when :dump_entities
          print_entities(map, options.path)
        when :dump_textures
          print_textures(map, options.path)
        else
          raise ArgumentError, "unknown BSP29 CLI action: #{options.action.inspect}"
        end

        0
      rescue OptionParser::ParseError => error
        @stderr.puts "aogera-bsp29: #{error.message}"
        @stderr.puts "Try 'bundle exec ruby bin/aogera-bsp29 --help' for usage."
        EX_USAGE
      rescue Aogera::BSP29::FormatError => error
        @stderr.puts "aogera-bsp29: #{error.message}"
        EX_DATAERR
      end

      private

      def parse(argv)
        args = argv.dup
        state = {
          mode: nil,
          action: :run
        }
        parser = option_parser(state)
        parser.parse!(args)

        if state[:action] == :help
          return [
            BSP29Options.new(path: nil, mode: state[:mode], action: :help),
            parser
          ]
        end

        path = args.shift
        raise OptionParser::MissingArgument, "PATH.bsp" unless path
        unless args.empty?
          raise OptionParser::InvalidArgument,
            "unexpected arguments: #{args.join(' ')}"
        end

        if state[:action] == :run && state[:mode].nil?
          raise OptionParser::InvalidArgument,
            "launch mode required; use --spectator"
        end

        [
          BSP29Options.new(
            path: path,
            mode: state[:mode],
            action: state[:action]
          ),
          parser
        ]
      end

      def option_parser(state)
        OptionParser.new do |parser|
          parser.banner = <<~USAGE.chomp
            Usage: bundle exec ruby bin/aogera-bsp29 [options] PATH.bsp

            BSP29 launch and inspection commands.
          USAGE

          parser.on(
            "--spectator",
            "Launch the collision-free BSP spectator"
          ) do
            state[:mode] = :spectator
          end

          parser.on(
            "--bsp-info",
            "Print BSP structural information and exit"
          ) do
            select_action!(state, :bsp_info, "--bsp-info")
          end

          parser.on(
            "--dump-entities",
            "Print parsed BSP entities and exit"
          ) do
            select_action!(state, :dump_entities, "--dump-entities")
          end

          parser.on(
            "--dump-textures",
            "Print BSP world-model texture usage and exit"
          ) do
            select_action!(state, :dump_textures, "--dump-textures")
          end

          parser.on("-h", "--help", "Show this help and exit") do
            state[:action] = :help
          end
        end
      end

      def select_action!(state, action, option)
        current = state[:action]
        if current != :run && current != action
          raise OptionParser::InvalidOption,
            "#{option} conflicts with another exit command"
        end

        state[:action] = action
      end

      def print_help(parser)
        @stdout.puts parser
        0
      end

      def print_bsp_info(map, path)
        world = map.world_model

        @stdout.puts "BSP29: #{File.expand_path(path)}"
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

      def print_entities(map, path)
        @stdout.puts "BSP29 entities: #{File.expand_path(path)}"
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

      def print_textures(map, path)
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
        @stdout.puts "BSP29 textures: #{File.expand_path(path)}"
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

      def format_vec(vec)
        return "(none)" unless vec

        "(#{vec.x}, #{vec.y}, #{vec.z})"
      end

      def build_app(map, mode:)
        unless mode == :spectator
          raise ArgumentError, "unsupported BSP29 launch mode: #{mode.inspect}"
        end

        Aogera::App.new(bsp29_map: map, bsp29_mode: mode)
      end
    end
  end
end
