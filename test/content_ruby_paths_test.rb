# frozen_string_literal: true

require_relative "test_helper"

class ContentRubyPathsTest < Minitest::Test
  def test_authored_ruby_paths_share_the_content_root
    assert_equal(
      File.join(Aogera::Content::RubyPaths::ROOT, "prototypes", "actors.rb"),
      Aogera::Content::RubyPaths.prototype(:actors)
    )
    assert_equal(
      File.join(Aogera::Content::RubyPaths::ROOT, "levels", "test_field.rb"),
      Aogera::Content::RubyPaths.level(:test_field)
    )
    assert_equal(
      File.join(Aogera::Content::RubyPaths::ROOT, "dialogue", "test_field.rb"),
      Aogera::Content::RubyPaths.dialogue(:test_field)
    )
  end
end
