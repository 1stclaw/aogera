# frozen_string_literal: true

module Aogera
  module Render
    # Converts preserved Quake texture-space S/T into normalized repeating base
    # texture coordinates. Coordinates deliberately remain unwrapped: negative
    # values and values above 1.0 carry Quake's tiling semantics to the GPU.
    module BSP29TextureMapping
      module_function

      def normalized_uv(surface, texture)
        width = texture.width
        height = texture.height
        unless width.is_a?(Integer) && width.positive? &&
            height.is_a?(Integer) && height.positive?
          raise BSP29::FormatError,
            "BSP miptexture dimensions must be positive: #{width.inspect}x#{height.inspect}"
        end

        coordinates = []
        surface.texture_st.each_slice(2) do |s, t|
          coordinates << s / width.to_f
          coordinates << t / height.to_f
        end
        coordinates.freeze
      end
    end
  end
end
