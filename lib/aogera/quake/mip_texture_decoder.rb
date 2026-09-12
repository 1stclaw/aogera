# frozen_string_literal: true

module Aogera
  module Quake
    # Expands one requested BSP29 mip level from palette indices into one packed
    # RGBA byte buffer. The source MipTexture keeps the compact indexed mip chain
    # authoritative; callers can decode only the level they actually need and
    # discard the expanded buffer after GPU upload.
    module MipTextureDecoder
      MIP_LEVEL_COUNT = 4
      RGBA_CHANNEL_COUNT = 4

      FormatError = Class.new(StandardError)

      module_function

      def decode(texture, palette, level: 0)
        unless level.is_a?(Integer) && level >= 0 && level < MIP_LEVEL_COUNT
          raise FormatError, "Quake mip level must be 0..3; got #{level.inspect}"
        end

        width = dimension_at_level(texture.width, level)
        height = dimension_at_level(texture.height, level)
        indices = texture.mipmaps.fetch(level) do
          raise FormatError, "texture #{texture.name.inspect} is missing mip level #{level}"
        end
        expected = width * height
        unless indices.bytesize == expected
          raise FormatError,
            "texture #{texture.name.inspect} mip level #{level} must contain " \
            "#{expected} indices; got #{indices.bytesize}"
        end

        palette_bytes = palette.rgb_bytes
        unless palette_bytes.bytesize == PaletteReader::BYTE_SIZE
          raise FormatError,
            "Quake palette lookup must contain #{PaletteReader::BYTE_SIZE} RGB bytes"
        end

        pixels = String.new(
          capacity: expected * RGBA_CHANNEL_COUNT,
          encoding: Encoding::BINARY
        )
        indices.each_byte do |palette_index|
          palette_offset = palette_index * PaletteReader::CHANNEL_COUNT
          pixels << palette_bytes.getbyte(palette_offset)
          pixels << palette_bytes.getbyte(palette_offset + 1)
          pixels << palette_bytes.getbyte(palette_offset + 2)
          pixels << 255
        end

        MipImage.new(width: width, height: height, pixels: pixels.freeze)
      rescue IndexError
        raise FormatError, "texture #{texture.name.inspect} is missing mip level #{level}"
      end

      def dimension_at_level(dimension, level)
        unless dimension.is_a?(Integer) && dimension.positive?
          raise FormatError, "Quake miptexture dimensions must be positive integers"
        end

        [dimension >> level, 1].max
      end
      private_class_method :dimension_at_level
    end
  end
end
