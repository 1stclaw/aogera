# frozen_string_literal: true

require "optparse"

module Aogera
  module CLI
    BSP29Options = Data.define(:path, :pak_path, :mode, :action)

    class BSP29
      EX_USAGE = 64
      EX_DATAERR = 65
      EX_NOINPUT = 66

      def initialize(
        reader: Aogera::BSP29::Reader.method(:read),
        bytes_reader: Aogera::BSP29::Reader.method(:read_bytes),
        pak_factory: Aogera::Content::Pak.method(:new),
        app_factory: nil,
        stdout: $stdout,
        stderr: $stderr
      )
        @reader = reader
        @bytes_reader = bytes_reader
        @pak_factory = pak_factory
        @app_factory = app_factory || lambda do |map, mode:|
          build_app(map, mode:)
        end
        @stdout = stdout
        @stderr = stderr
        @report = BSP29Report.new(stdout: stdout)
      end

      def run(argv)
        options, parser = parse(argv)
        return print_help(parser) if options.action == :help

        begin
          map, source = load_map(options)
        rescue SystemCallError, Aogera::Content::NotFound => error
          @stderr.puts "aogera-bsp29: input not available: #{error.message}"
          return EX_NOINPUT
        rescue Aogera::Content::InvalidPath => error
          @stderr.puts "aogera-bsp29: invalid content path: #{error.message}"
          return EX_USAGE
        rescue Aogera::Content::Pak::FormatError => error
          @stderr.puts "aogera-bsp29: #{error.message}"
          return EX_DATAERR
        end

        case options.action
        when :run
          @app_factory.call(map, mode: options.mode).run
        when :bsp_info
          @report.bsp_info(map, source: source)
        when :dump_entities
          @report.entities(map, source: source)
        when :dump_textures
          @report.textures(map, source: source)
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
          pak_path: nil,
          mode: nil,
          action: :run
        }
        parser = option_parser(state)
        parser.parse!(args)

        if state[:action] == :help
          return [
            BSP29Options.new(
              path: nil,
              pak_path: state[:pak_path],
              mode: state[:mode],
              action: :help
            ),
            parser
          ]
        end

        path = args.shift
        raise OptionParser::MissingArgument, "BSP" unless path
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
            pak_path: state[:pak_path],
            mode: state[:mode],
            action: state[:action]
          ),
          parser
        ]
      end

      def option_parser(state)
        OptionParser.new do |parser|
          parser.banner = <<~USAGE.chomp
            Usage: bundle exec ruby bin/aogera-bsp29 [options] BSP

            BSP29 launch and inspection commands.
            BSP is a host path by default, or a virtual path with --pak.
          USAGE

          parser.on(
            "--pak PATH",
            "Read BSP from a Quake PAK virtual path"
          ) do |path|
            state[:pak_path] = path
          end

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

      def load_map(options)
        unless options.pak_path
          return [@reader.call(options.path), options.path]
        end

        virtual_path = Aogera::Content::VirtualPath.normalize(options.path)
        vfs = Aogera::Content::VFS.new
        vfs.mount(@pak_factory.call(options.pak_path))
        bytes = vfs.read(virtual_path)
        map = @bytes_reader.call(bytes)
        [map, "#{options.pak_path}:#{virtual_path}"]
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

      def build_app(map, mode:)
        unless mode == :spectator
          raise ArgumentError, "unsupported BSP29 launch mode: #{mode.inspect}"
        end

        Aogera::App.new(bsp29_map: map, bsp29_mode: mode)
      end
    end
  end
end
