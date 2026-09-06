# frozen_string_literal: true

require_relative "test_helper"

class ComponentTableTest < Minitest::Test
  def test_values_are_indexed_by_entity_id
    table = Aogera::World::ComponentTable.new
    position = Aogera::Component::Position.new(x: 2, y: 3)

    table[4] = position
    assert_equal position, table[4]
  end

  def test_negative_entity_id_is_rejected
    table = Aogera::World::ComponentTable.new

    assert_raises(ArgumentError) { table[-1] = :bad }
  end
end
