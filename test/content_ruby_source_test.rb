# frozen_string_literal: true

require_relative "test_helper"

class ContentRubySourceTest < Minitest::Test
  def test_constant_name_is_derived_from_source_filename
    name = Aogera::Content::RubySource.constant_name_for(
      "/tmp/test_field.rb"
    )

    assert_equal "TestField", name
  end
end
