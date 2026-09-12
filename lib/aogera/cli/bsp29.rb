# frozen_string_literal: true

require "optparse"

module Aogera
  module CLI
    BSP29Options = Data.define(:path, :pak_path, :mode, :action, :two_sided)
    LoadedBSP29 = Data.define(:map, :source, :vfs)

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
        @app_factory = app_factory || lambda do |map, mode:, palette:, two_sided:|
          build_app(map, mode:, palette:, two_sided:)
        end
        @stdout = stdout
        @stderr = stderr
        @report = BSP29Report.new(stdout: stdout)
      end

      def run(argv)
        options, parser = parse(argv)
        return print_help(parser) if options.action == :help

        begin
          loaded = load_map(options)
          palette = options.action == :run ? load_palette(loaded.vfs) : nil
        rescue SystemCallError, Aogera::Content::NotFound => error
          @stderr.puts "aogera-bsp29: input not available: #{error.message}"
          return EX_NOINPUT
        rescue Aogera::Content::InvalidPath => error
          @stderr.puts "aogera-bsp29: invalid content path: #{error.message}"
          return EX_USAGE
        rescue Aogera::Content::Pak::FormatError, Aogera::Quake::PaletteReader::FormatError => error
          @stderr.puts "aogera-bsp29: #{error.message}"
          return EX_DATAERR
        end

        case options.action
        when :run
          @app_factory.call(
            loaded.map,
            mode: options.mode,
            palette: palette,
            two_sided: options.two_sided
          ).run
        when :bsp_info
          @report.bsp_info(loaded.map, source: loaded.source)
        when :dump_entities
          @report.entities(loaded.map, source: loaded.source)
        when :dump_textures
          @report.textures(loaded.map, source: loaded.source)
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
          action: :run,
          two_sided: false
        }
        parser = option_parser(state)
        parser.parse!(args)

        if state[:action] == :help
          return [
            BSP29Options.new(
              path: nil,
              pak_path: state[:pak_path],
              mode: state[:mode],
              action: :help,
              two_sided: state[:two_sided]
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
            "launch mode required; use --spectator or --walkthrough"
        end
        if state[:two_sided] && state[:action] != :run
          raise OptionParser::InvalidArgument,
            "--bsp-two-sided requires a runtime launch mode"
        end

        [
          BSP29Options.new(
            path: path,
            pak_path: state[:pak_path],
            mode: state[:mode],
            action: state[:action],
            two_sided: state[:two_sided]
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
            select_mode!(state, :spectator, "--spectator")
          end

          parser.on(
            "--walkthrough",
            "Launch horizontal player movement with BSP collision"
          ) do
            select_mode!(state, :walkthrough, "--walkthrough")
          end

          parser.on(
            "--bsp-two-sided",
            "Duplicate reversed world triangles for culling diagnosis"
          ) do
            state[:two_sided] = true
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
          return LoadedBSP29.new(
            map: @reader.call(options.path),
            source: options.path,
            vfs: nil
          )
        end

        virtual_path = Aogera::Content::VirtualPath.normalize(options.path)
        vfs = Aogera::Content::VFS.new
        vfs.mount(@pak_factory.call(options.pak_path))
        bytes = vfs.read(virtual_path)
        LoadedBSP29.new(
          map: @bytes_reader.call(bytes),
          source: "#{options.pak_path}:#{virtual_path}",
          vfs: vfs
        )
      end

      def load_palette(vfs)
        return unless vfs

        bytes = vfs.read(Aogera::Quake::PALETTE_PATH)
        Aogera::Quake::PaletteReader.read_bytes(bytes)
      end

      def select_mode!(state, mode, option)
        current = state[:mode]
        if current && current != mode
          raise OptionParser::InvalidOption,
            "#{option} conflicts with --#{current}"
        end

        state[:mode] = mode
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

      def build_app(map, mode:, palette:, two_sided:)
        unless %i[spectator walkthrough].include?(mode)
          raise ArgumentError, "unsupported BSP29 launch mode: #{mode.inspect}"
        end

        Aogera::App.new(
          bsp29_map: map,
          bsp29_mode: mode,
          bsp29_palette: palette,
          bsp29_two_sided: two_sided
        )
      end
    end
  end
end
