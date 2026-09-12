# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class ContentDirectoryTest < Minitest::Test
  def test_reads_binary_files_from_virtual_paths
    Dir.mktmpdir("aogera-content") do |root|
      FileUtils.mkdir_p(File.join(root, "maps"))
      File.binwrite(File.join(root, "maps", "test.bsp"), "\x00\xFFBSP".b)
      source = Aogera::Content::Directory.new(root)

      assert source.exist?("maps/test.bsp")
      assert_equal "\x00\xFFBSP".b, source.read("maps/test.bsp")
      refute source.exist?("maps/missing.bsp")
    end
  end

  def test_missing_files_raise_content_not_found
    Dir.mktmpdir("aogera-content") do |root|
      source = Aogera::Content::Directory.new(root)

      error = assert_raises(Aogera::Content::NotFound) do
        source.read("maps/missing.bsp")
      end
      assert_match(/maps\/missing\.bsp/, error.message)
    end
  end
end
