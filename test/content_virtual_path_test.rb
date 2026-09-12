# frozen_string_literal: true

require_relative "test_helper"

class ContentVirtualPathTest < Minitest::Test
  def test_normalizes_separators_without_hiding_dot_segments
    assert_equal "maps/e1m3.bsp", Aogera::Content::VirtualPath.normalize("maps//e1m3.bsp")
    assert_equal "maps/e1m3.bsp", Aogera::Content::VirtualPath.normalize("maps\\e1m3.bsp")
  end

  def test_rejects_absolute_traversal_directory_and_nul_paths
    invalid = [
      "",
      "/maps/e1m3.bsp",
      "C:\\quake\\id1\\pak0.pak",
      "C:quake/id1/pak0.pak",
      "maps/../gfx/palette.lmp",
      "./maps/e1m3.bsp",
      "maps/",
      "maps/evil\0name.bsp"
    ]

    invalid.each do |path|
      assert_raises(Aogera::Content::InvalidPath, path.inspect) do
        Aogera::Content::VirtualPath.normalize(path)
      end
    end
  end
end
