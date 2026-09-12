# frozen_string_literal: true

module Aogera
  module Quake
    PALETTE_PATH = "gfx/palette.lmp".freeze

    PaletteColor = Data.define(:r, :g, :b)

    Palette = Data.define(:colors) do
      def [](index)
        colors.fetch(index)
      end

      def size
        colors.size
      end
    end
  end
end
