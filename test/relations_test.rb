# frozen_string_literal: true

require_relative "test_helper"

class RelationsTest < Minitest::Test
  def test_world_stores_runtime_relation_between_instances
    world = Aogera::World.new
    source_id = world.spawn
    target_id = world.spawn

    world.add_relation(
      kind: :targets,
      source_id: source_id,
      target_id: target_id
    )

    assert_equal(
      [target_id],
      world.view.relation_targets(
        kind: :targets,
        source_id: source_id
      )
    )
  end

  def test_view_cannot_add_relations
    refute_respond_to Aogera::World.new.view, :add_relation
  end
end
