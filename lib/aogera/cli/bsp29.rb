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
          mode: :spectator,
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
            "Launch the collision-free BSP spectator (default)"
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

      def format_vec(vec)
        return "(none)" unless vec

        "(#{vec.x}, #{vec.y}, #{vec.z})"
      end

      def build_app(map, mode:)
        unless mode == :spectator
          raise ArgumentError, "unsupported BSP29 launch mode: #{mode.inspect}"
        end

        Aogera::App.new(bsp29_map: map)
      end
    end
  end
end
