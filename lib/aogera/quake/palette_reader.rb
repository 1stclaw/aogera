# frozen_string_literal: true

module Aogera
  module Quake
    module PaletteReader
      COLOR_COUNT = 256
      CHANNEL_COUNT = 3
      BYTE_SIZE = COLOR_COUNT * CHANNEL_COUNT

      FormatError = Class.new(StandardError)

      module_function

      def read_bytes(bytes)
        source = String(bytes).dup.force_encoding(Encoding::BINARY)
        unless source.bytesize == BYTE_SIZE
          raise FormatError,
            "Quake palette must be exactly #{BYTE_SIZE} bytes; got #{source.bytesize}"
        end

        source.freeze
        colors = Array.new(COLOR_COUNT) do |index|
          offset = index * CHANNEL_COUNT
          PaletteColor.new(
            r: source.getbyte(offset),
            g: source.getbyte(offset + 1),
            b: source.getbyte(offset + 2)
          )
        end.freeze

        Palette.new(colors: colors, rgb_bytes: source)
      end
    end
  end
end
