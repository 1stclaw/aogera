# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class ContentVFSTest < Minitest::Test
  def test_later_mounts_override_earlier_sources
    Dir.mktmpdir("aogera-vfs-base") do |base|
      Dir.mktmpdir("aogera-vfs-override") do |override|
        write_content(base, "maps/test.bsp", "base")
        write_content(override, "maps/test.bsp", "override")
        write_content(base, "gfx/palette.lmp", "palette")

        vfs = Aogera::Content::VFS.new
        vfs.mount(Aogera::Content::Directory.new(base))
        vfs.mount(Aogera::Content::Directory.new(override))

        assert_equal "override", vfs.read("maps/test.bsp")
        assert_equal "palette", vfs.read("gfx/palette.lmp")
        assert vfs.exist?("maps/test.bsp")
        refute vfs.exist?("sound/missing.wav")
      end
    end
  end

  def test_missing_virtual_files_raise_content_not_found
    vfs = Aogera::Content::VFS.new

    error = assert_raises(Aogera::Content::NotFound) do
      vfs.read("maps/missing.bsp")
    end
    assert_match(/maps\/missing\.bsp/, error.message)
  end

  private

  def write_content(root, path, bytes)
    full_path = File.join(root, *path.split("/"))
    FileUtils.mkdir_p(File.dirname(full_path))
    File.binwrite(full_path, bytes)
  end
end
