# frozen_string_literal: true

require_relative "test_helper"

class PrototypeLoadingTest < Minitest::Test
  include AogeraTestPaths

  def test_loader_returns_prototype_catalog
    prototypes = Aogera::Prototype::Loader.load(PROTOTYPE_PATH)

    assert_instance_of Aogera::Prototype::Catalog, prototypes
    assert prototypes.include?(:player)
    assert prototypes.include?(:goblin)
    assert prototypes.include?(:villager)
  end
end
