# frozen_string_literal: true

require_relative "test_helper"

class WorldLifecycleTest < Minitest::Test
  def test_despawn_removes_entity_components_and_relations_without_reusing_id
    world = Aogera::World.new
    source_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1, y: 1)
    )
    target_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2, y: 1)
    )
    world.add_relation(
      kind: :targets,
      source_id: source_id,
      target_id: target_id
    )

    assert_equal target_id, world.despawn(target_id)
    refute world.entity?(target_id)
    assert_equal [source_id], world.entity_ids
    assert_empty world.relation_targets(kind: :targets, source_id: source_id)
    assert_raises(ArgumentError) do
      world.component(target_id, :position)
    end

    replacement_id = world.spawn
    assert_operator replacement_id, :>, target_id
  end
end
