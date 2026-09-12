# frozen_string_literal: true

module Aogera
  module Content
    class Pak
      HEADER_SIZE = 12
      DIRECTORY_ENTRY_SIZE = 64
      NAME_SIZE = 56
      MAGIC = "PACK".b.freeze

      FormatError = Class.new(Error)
      Entry = Data.define(:path, :offset, :length)

      attr_reader :path, :entries

      def initialize(path)
        @path = File.expand_path(path).freeze
        @entries, @lookup = read_directory
      end

      def exist?(path)
        @lookup.key?(VirtualPath.normalize(path))
      end

      def read(path)
        path = VirtualPath.normalize(path)
        entry = @lookup[path]
        raise NotFound, "content not found: #{path}" unless entry

        File.open(@path, "rb") do |file|
          file.seek(entry.offset)
          bytes = file.read(entry.length)
          unless bytes && bytes.bytesize == entry.length
            raise FormatError,
              "PAK entry #{entry.path.inspect} is truncated in #{@path}"
          end
          bytes.b
        end
      end

      private

      def read_directory
        File.open(@path, "rb") do |file|
          file_size = file.stat.size
          header = file.read(HEADER_SIZE)
          unless header && header.bytesize == HEADER_SIZE
            raise FormatError, "PAK header is truncated: #{@path}"
          end
          unless header.byteslice(0, 4) == MAGIC
            raise FormatError, "invalid PAK magic in #{@path}"
          end

          directory_offset, directory_length = header.byteslice(4, 8).unpack("V2")
          validate_directory_range!(file_size, directory_offset, directory_length)

          file.seek(directory_offset)
          directory = file.read(directory_length)
          unless directory && directory.bytesize == directory_length
            raise FormatError, "PAK directory is truncated: #{@path}"
          end

          parse_entries(directory, file_size)
        end
      end

      def validate_directory_range!(file_size, offset, length)
        unless (length % DIRECTORY_ENTRY_SIZE).zero?
          raise FormatError,
            "PAK directory length #{length} is not a multiple of #{DIRECTORY_ENTRY_SIZE}"
        end
        if offset < HEADER_SIZE || offset > file_size || length > file_size - offset
          raise FormatError,
            "PAK directory range #{offset}+#{length} exceeds file size #{file_size}"
        end
      end

      def parse_entries(directory, file_size)
        entries = []
        lookup = {}

        entry_count = directory.bytesize / DIRECTORY_ENTRY_SIZE
        entry_count.times do |index|
          raw = directory.byteslice(index * DIRECTORY_ENTRY_SIZE, DIRECTORY_ENTRY_SIZE)
          raw_name = raw.byteslice(0, NAME_SIZE)
          nul = raw_name.index("\0")
          raw_name = raw_name.byteslice(0, nul) if nul
          name = raw_name.dup

          begin
            virtual_path = VirtualPath.normalize(name)
          rescue InvalidPath => error
            raise FormatError,
              "invalid PAK entry path #{name.inspect}: #{error.message}"
          end

          offset, length = raw.byteslice(NAME_SIZE, 8).unpack("V2")
          if offset > file_size || length > file_size - offset
            raise FormatError,
              "PAK entry #{virtual_path.inspect} range #{offset}+#{length} " \
              "exceeds file size #{file_size}"
          end

          entry = Entry.new(path: virtual_path.freeze, offset: offset, length: length)
          entries << entry
          lookup[virtual_path] ||= entry
        end

        [entries.freeze, lookup.freeze]
      end
    end
  end
end
