# frozen_string_literal: true

module Aogera
  module Quake
    PALETTE_PATH = "gfx/palette.lmp".freeze

    PaletteColor = Data.define(:r, :g, :b)

    # Keeps both convenient color records and the original compact 768-byte RGB
    # lookup table. Runtime texture expansion can use rgb_bytes directly without
    # constructing per-pixel Ruby objects.
    Palette = Data.define(:colors, :rgb_bytes) do
      def [](index)
        colors.fetch(index)
      end

      def size
        colors.size
      end
    end

    MipImage = Data.define(:width, :height, :pixels)
  end
end
