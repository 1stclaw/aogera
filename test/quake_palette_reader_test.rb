# frozen_string_literal: true

require "tempfile"
require_relative "test_helper"

class QuakePaletteReaderTest < Minitest::Test
  def test_decodes_256_rgb_entries_from_exact_palette_bytes
    bytes = palette_bytes

    palette = Aogera::Quake::PaletteReader.read_bytes(bytes)

    assert_equal 256, palette.size
    assert_equal Aogera::Quake::PaletteColor.new(r: 0, g: 1, b: 2), palette[0]
    assert_equal Aogera::Quake::PaletteColor.new(r: 129, g: 130, b: 131), palette[43]
    assert_equal Aogera::Quake::PaletteColor.new(r: 253, g: 254, b: 255), palette[255]
    assert palette.colors.frozen?
    assert_predicate palette.rgb_bytes, :frozen?
    assert_equal bytes, palette.rgb_bytes
  end

  def test_palette_lookup_uses_array_bounds
    palette = Aogera::Quake::PaletteReader.read_bytes(palette_bytes)

    assert_raises(IndexError) { palette[256] }
  end

  def test_rejects_short_or_oversized_palette_data
    short = "\0".b * (Aogera::Quake::PaletteReader::BYTE_SIZE - 1)
    long = "\0".b * (Aogera::Quake::PaletteReader::BYTE_SIZE + 1)

    short_error = assert_raises(Aogera::Quake::PaletteReader::FormatError) do
      Aogera::Quake::PaletteReader.read_bytes(short)
    end
    long_error = assert_raises(Aogera::Quake::PaletteReader::FormatError) do
      Aogera::Quake::PaletteReader.read_bytes(long)
    end

    assert_match(/exactly 768 bytes/, short_error.message)
    assert_match(/got 767/, short_error.message)
    assert_match(/exactly 768 bytes/, long_error.message)
    assert_match(/got 769/, long_error.message)
  end

  def test_palette_data_is_independent_from_the_input_string
    bytes = palette_bytes
    palette = Aogera::Quake::PaletteReader.read_bytes(bytes)

    bytes.setbyte(0, 255)

    assert_equal 0, palette[0].r
    assert_equal 0, palette.rgb_bytes.getbyte(0)
  end

  def test_decodes_palette_bytes_read_through_vfs_from_pak
    bytes = palette_bytes

    with_pak(Aogera::Quake::PALETTE_PATH => bytes) do |pak_path|
      vfs = Aogera::Content::VFS.new
      vfs.mount(Aogera::Content::Pak.new(pak_path))

      palette = Aogera::Quake::PaletteReader.read_bytes(
        vfs.read(Aogera::Quake::PALETTE_PATH)
      )

      assert_equal 256, palette.size
      assert_equal Aogera::Quake::PaletteColor.new(r: 0, g: 1, b: 2), palette[0]
      assert_equal Aogera::Quake::PaletteColor.new(r: 253, g: 254, b: 255), palette[255]
    end
  end

  private

  def palette_bytes
    Array.new(Aogera::Quake::PaletteReader::BYTE_SIZE) { |index| index & 0xff }.pack("C*")
  end

  def with_pak(entries)
    payload = +"".b
    records = entries.map do |name, bytes|
      bytes = bytes.b
      offset = Aogera::Content::Pak::HEADER_SIZE + payload.bytesize
      payload << bytes
      pak_directory_entry(name, offset, bytes.bytesize)
    end
    directory = records.join.b
    directory_offset = Aogera::Content::Pak::HEADER_SIZE + payload.bytesize
    archive =
      "PACK".b + [directory_offset, directory.bytesize].pack("V2") + payload + directory

    Tempfile.create(["aogera-palette", ".pak"]) do |file|
      file.binmode
      file.write(archive)
      file.flush
      yield file.path
    end
  end

  def pak_directory_entry(name, offset, length)
    name_bytes = name.b
    name_bytes.ljust(Aogera::Content::Pak::NAME_SIZE, "\0") +
      [offset, length].pack("V2")
  end
end
