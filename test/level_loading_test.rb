# frozen_string_literal: true

require_relative "test_helper"

class LevelLoadingTest < Minitest::Test
  include AogeraTestPaths

  def setup
    prototypes = Aogera::Prototype::Loader.load(PROTOTYPE_PATH)
    @authored = Aogera::Level::Readers::Ruby.read(LEVEL_PATH)
    @level = Aogera::Level::Loader.load(@authored, prototypes: prototypes)
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
    assert_in_delta 112.0, entry.x
    assert_in_delta 0.0, entry.y
    assert_in_delta 112.0, entry.z
    assert_equal :south, entry.facing
    assert_equal 3, @level.relations.length
    assert @level.relations.all? { |relation| relation.target == :start }
  end

  def test_reader_normalizes_grid_authored_data_to_world_units
    assert_instance_of Aogera::Level::AuthoredData, @authored
    assert_in_delta 32.0, @authored.terrain.cell_size
    villager = @authored.spawns.find { |spawn| spawn.key == :villager }
    assert_in_delta 176.0, villager.x
    assert_in_delta 112.0, villager.z
  end

  def test_loader_rejects_unread_source_definition
    assert_raises(ArgumentError) do
      Aogera::Level::Loader.load(
        Aogera::Level::Definitions::TestField,
        prototypes: Aogera::Prototype::Loader.load(PROTOTYPE_PATH)
      )
    end
  end

  def test_terrain_controls_static_passability
    refute @level.passable?(0, 0)
    assert @level.passable?(3, 3)
  end
end
