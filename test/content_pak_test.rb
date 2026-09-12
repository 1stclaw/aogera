# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"

class ContentPakTest < Minitest::Test
  def test_reads_entries_without_extracting_the_archive
    with_pak(
      "maps/test.bsp" => "BSP\x00DATA".b,
      "gfx/palette.lmp" => "PAL".b
    ) do |path|
      pak = Aogera::Content::Pak.new(path)

      assert_equal ["maps/test.bsp", "gfx/palette.lmp"], pak.entries.map(&:path)
      assert pak.exist?("maps/test.bsp")
      assert_equal "BSP\x00DATA".b, pak.read("maps/test.bsp")
      assert_equal "PAL".b, pak.read("gfx/palette.lmp")
      refute pak.exist?("progs.dat")
    end
  end

  def test_duplicate_entries_use_the_first_directory_entry
    with_pak_entries([
      ["maps/test.bsp", "first"],
      ["maps/test.bsp", "second"]
    ]) do |path|
      pak = Aogera::Content::Pak.new(path)

      assert_equal ["maps/test.bsp", "maps/test.bsp"], pak.entries.map(&:path)
      assert_equal "first", pak.read("maps/test.bsp")
    end
  end

  def test_missing_entry_raises_content_not_found
    with_pak("maps/test.bsp" => "data") do |path|
      pak = Aogera::Content::Pak.new(path)

      assert_raises(Aogera::Content::NotFound) do
        pak.read("gfx/palette.lmp")
      end
    end
  end

  def test_rejects_truncated_header_bad_magic_and_misaligned_directory_length
    with_bytes("PACK".b) do |path|
      error = assert_raises(Aogera::Content::Pak::FormatError) do
        Aogera::Content::Pak.new(path)
      end
      assert_match(/header is truncated/, error.message)
    end

    with_bytes("NOPE".b + [12, 0].pack("V2")) do |path|
      assert_raises(Aogera::Content::Pak::FormatError) do
        Aogera::Content::Pak.new(path)
      end
    end

    with_bytes("PACK".b + [12, 1].pack("V2") + "x") do |path|
      error = assert_raises(Aogera::Content::Pak::FormatError) do
        Aogera::Content::Pak.new(path)
      end
      assert_match(/multiple of 64/, error.message)
    end
  end

  def test_rejects_directory_and_entry_ranges_outside_the_file
    with_bytes("PACK".b + [1024, 64].pack("V2")) do |path|
      error = assert_raises(Aogera::Content::Pak::FormatError) do
        Aogera::Content::Pak.new(path)
      end
      assert_match(/directory range/, error.message)
    end

    directory = pak_directory_entry("maps/test.bsp", 4096, 8)
    with_bytes("PACK".b + [12, directory.bytesize].pack("V2") + directory) do |path|
      error = assert_raises(Aogera::Content::Pak::FormatError) do
        Aogera::Content::Pak.new(path)
      end
      assert_match(/maps\/test\.bsp/, error.message)
      assert_match(/exceeds file size/, error.message)
    end
  end

  def test_rejects_invalid_virtual_paths_in_the_directory
    directory = pak_directory_entry("../escape.dat", 12 + 64, 0)
    with_bytes("PACK".b + [12, directory.bytesize].pack("V2") + directory) do |path|
      error = assert_raises(Aogera::Content::Pak::FormatError) do
        Aogera::Content::Pak.new(path)
      end
      assert_match(/invalid PAK entry path/, error.message)
    end
  end

  private

  def with_pak(entries)
    with_pak_entries(entries.to_a) { |path| yield path }
  end

  def with_pak_entries(entries)
    payload = +"".b
    records = entries.map do |name, bytes|
      bytes = bytes.b
      offset = Aogera::Content::Pak::HEADER_SIZE + payload.bytesize
      payload << bytes
      pak_directory_entry(name, offset, bytes.bytesize)
    end
    directory = records.join.b
    directory_offset = Aogera::Content::Pak::HEADER_SIZE + payload.bytesize
    bytes = "PACK".b + [directory_offset, directory.bytesize].pack("V2") + payload + directory

    with_bytes(bytes) { |path| yield path }
  end

  def pak_directory_entry(name, offset, length)
    name_bytes = name.b
    raise "test PAK name too long" if name_bytes.bytesize > Aogera::Content::Pak::NAME_SIZE

    name_bytes.ljust(Aogera::Content::Pak::NAME_SIZE, "\0") + [offset, length].pack("V2")
  end

  def with_bytes(bytes)
    Tempfile.create(["aogera-content", ".pak"]) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      yield file.path
    end
  end
end
