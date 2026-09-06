# frozen_string_literal: true

require_relative "test_helper"

class WorldTest < Minitest::Test
  def test_world_is_canonical_runtime_container
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2, y: 3)
    )

    assert_equal [entity_id], world.entity_ids
    position = world.component(entity_id, :position)
    assert_equal [2, 3], [position.x, position.y]
  end

  def test_view_is_read_only
    world = Aogera::World.new
    world.spawn(position: Aogera::Component::Position.new(x: 1, y: 1))

    refute_respond_to world.view, :set_component
    assert_equal [0], world.view.entity_ids
  end
end
