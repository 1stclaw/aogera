# frozen_string_literal: true

require_relative "test_helper"

class LevelLoadingTest < Minitest::Test
  include AogeraTestPaths

  def setup
    prototypes = Aogera::Prototype::Loader.load(PROTOTYPE_PATH)
    @level = Aogera::Level::Loader.load(LEVEL_PATH, prototypes: prototypes)
  end

  def test_loader_returns_complete_level
    assert_equal :test_field, @level.name
    assert_equal 44, @level.width
    assert_equal 14, @level.height
    assert_equal 4, @level.spawns.length
    assert_equal 1, @level.entries.length
  end

  def test_level_owns_entry_points_and_static_relations
    assert_equal :start, @level.default_entry
    entry = @level.entry
    assert_equal [3, 3, :south], [entry.x, entry.y, entry.facing]
    assert_equal 3, @level.relations.length
    assert @level.relations.all? { |relation| relation.target == :start }
  end

  def test_terrain_controls_static_passability
    refute @level.passable?(0, 0)
    assert @level.passable?(3, 3)
  end
end
