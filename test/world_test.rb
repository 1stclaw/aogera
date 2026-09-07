# frozen_string_literal: true

require_relative "test_helper"

class WorldTest < Minitest::Test
  def test_world_is_canonical_runtime_container
    world = Aogera::World.new
    entity_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 3.5)
    )

    assert_equal [entity_id], world.entity_ids
    position = world.component(entity_id, :position)
    assert_equal [2.5, 0.0, 3.5], [position.x, position.y, position.z]
  end

  def test_view_is_read_only
    world = Aogera::World.new
    world.spawn(position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5))

    refute_respond_to world.view, :set_component
    assert_equal [0], world.view.entity_ids
  end
  def test_view_is_cached
    world = Aogera::World.new

    assert_same world.view, world.view
  end

  def test_entity_ids_are_cached_until_lifecycle_changes
    world = Aogera::World.new
    first_id = world.spawn

    first_snapshot = world.entity_ids
    assert_same first_snapshot, world.entity_ids
    assert first_snapshot.frozen?

    second_id = world.spawn
    second_snapshot = world.entity_ids
    refute_same first_snapshot, second_snapshot
    assert_equal [first_id, second_id], second_snapshot

    world.despawn(first_id)
    third_snapshot = world.entity_ids
    refute_same second_snapshot, third_snapshot
    assert_equal [second_id], third_snapshot
  end

end
