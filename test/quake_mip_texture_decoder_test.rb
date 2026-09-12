# frozen_string_literal: true

require_relative "test_helper"

class QuakeMipTextureDecoderTest < Minitest::Test
  def test_decodes_requested_indexed_mip_level_into_packed_rgba
    palette = palette_with_known_colors
    texture = mip_texture(
      width: 4,
      height: 4,
      levels: [
        (0...16).to_a.pack("C*"),
        [1, 2, 3, 4].pack("C*"),
        [5].pack("C*"),
        [6].pack("C*")
      ]
    )

    image = Aogera::Quake::MipTextureDecoder.decode(texture, palette, level: 1)

    assert_equal 2, image.width
    assert_equal 2, image.height
    assert_equal 16, image.pixels.bytesize
    assert_equal [
      11, 12, 13, 255,
      21, 22, 23, 255,
      31, 32, 33, 255,
      41, 42, 43, 255
    ], image.pixels.bytes
    assert_predicate image.pixels, :frozen?
  end

  def test_each_mip_level_keeps_quake_dimensions_without_expanding_the_chain
    palette = palette_with_known_colors
    texture = mip_texture(
      width: 8,
      height: 4,
      levels: [
        "\x00".b * 32,
        "\x01".b * 8,
        "\x02".b * 2,
        "\x03".b
      ]
    )

    dimensions = 4.times.map do |level|
      image = Aogera::Quake::MipTextureDecoder.decode(texture, palette, level: level)
      [image.width, image.height, image.pixels.bytesize]
    end

    assert_equal [
      [8, 4, 128],
      [4, 2, 32],
      [2, 1, 8],
      [1, 1, 4]
    ], dimensions
  end

  def test_palette_index_255_is_an_opaque_quake_color_not_transparency
    palette_bytes = "\0".b * Aogera::Quake::PaletteReader::BYTE_SIZE
    palette_bytes.setbyte(255 * 3, 7)
    palette_bytes.setbyte((255 * 3) + 1, 8)
    palette_bytes.setbyte((255 * 3) + 2, 9)
    palette = Aogera::Quake::PaletteReader.read_bytes(palette_bytes)
    texture = mip_texture(
      width: 1,
      height: 1,
      levels: ["\xff".b, "\xff".b, "\xff".b, "\xff".b]
    )

    image = Aogera::Quake::MipTextureDecoder.decode(texture, palette)

    assert_equal [7, 8, 9, 255], image.pixels.bytes
  end

  def test_rejects_invalid_level_and_wrong_mip_size
    palette = palette_with_known_colors
    texture = mip_texture(
      width: 4,
      height: 4,
      levels: ["\0".b * 15, "\0".b * 4, "\0".b, "\0".b]
    )

    level_error = assert_raises(Aogera::Quake::MipTextureDecoder::FormatError) do
      Aogera::Quake::MipTextureDecoder.decode(texture, palette, level: 4)
    end
    size_error = assert_raises(Aogera::Quake::MipTextureDecoder::FormatError) do
      Aogera::Quake::MipTextureDecoder.decode(texture, palette, level: 0)
    end

    assert_match(/0\.\.3/, level_error.message)
    assert_match(/16 indices; got 15/, size_error.message)
  end

  def test_decoding_does_not_replace_or_mutate_the_compact_indexed_source
    palette = palette_with_known_colors
    indices = [1, 2, 3, 4].pack("C*").freeze
    texture = mip_texture(
      width: 2,
      height: 2,
      levels: [indices, "\0".b, "\0".b, "\0".b]
    )

    image = Aogera::Quake::MipTextureDecoder.decode(texture, palette)

    assert_same indices, texture.mipmaps.fetch(0)
    assert_equal [1, 2, 3, 4], texture.mipmaps.fetch(0).bytes
    assert_raises(FrozenError) { image.pixels.setbyte(0, 99) }
  end

  private

  def palette_with_known_colors
    bytes = "\0".b * Aogera::Quake::PaletteReader::BYTE_SIZE
    256.times do |index|
      offset = index * 3
      bytes.setbyte(offset, (index * 10 + 1) & 0xff)
      bytes.setbyte(offset + 1, (index * 10 + 2) & 0xff)
      bytes.setbyte(offset + 2, (index * 10 + 3) & 0xff)
    end
    Aogera::Quake::PaletteReader.read_bytes(bytes)
  end

  def mip_texture(width:, height:, levels:)
    Aogera::BSP29::MipTexture.new(
      name: "TEST",
      width: width,
      height: height,
      mipmaps: levels.map { |level| level.frozen? ? level : level.b.freeze }.freeze
    )
  end
end
