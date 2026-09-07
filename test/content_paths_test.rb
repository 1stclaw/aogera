# frozen_string_literal: true

require_relative "test_helper"

class ContentPathsTest < Minitest::Test
  def test_authored_ruby_paths_share_the_content_root
    assert_equal(
      File.join(Aogera::Content::Paths::ROOT, "prototypes", "actors.rb"),
      Aogera::Content::Paths.prototype(:actors)
    )
    assert_equal(
      File.join(Aogera::Content::Paths::ROOT, "levels", "test_field.rb"),
      Aogera::Content::Paths.level(:test_field)
    )
    assert_equal(
      File.join(Aogera::Content::Paths::ROOT, "dialogue", "test_field.rb"),
      Aogera::Content::Paths.dialogue(:test_field)
    )
  end
end
