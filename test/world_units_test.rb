# frozen_string_literal: true

require_relative "test_helper"

class WorldUnitsTest < Minitest::Test
  include AogeraTestPaths

  def test_grid_cell_uses_quake_compatible_world_unit_magnitude
    assert_in_delta 32.0, Aogera::WorldUnits::GRID_CELL_SIZE
    assert_in_delta 112.0, Aogera::WorldUnits.grid_center(3)
    assert_equal 3, Aogera::WorldUnits.grid_cell(112.0)
  end

  def test_current_runtime_dimensions_scale_proportionally_from_legacy_world
    assert_in_delta 76.8, Aogera::Realtime::PLAYER_SPEED
    assert_in_delta 64.0, Aogera::Realtime::NPC_SPEED
    assert_in_delta 21.76, Aogera::FirstPersonView::DEFAULT_EYE_HEIGHT

    prototypes = Aogera::Prototype::Loader.load(PROTOTYPE_PATH)
    player = prototypes.fetch(:player)
    assert_in_delta 7.04, player.components.fetch(:ground_body).radius
    assert_in_delta 20.8, player.components.fetch(:melee_attack).reach
  end
  def test_loaded_grid_navigation_targets_world_scaled_cell_centers
    prototypes = Aogera::Prototype::Loader.load(PROTOTYPE_PATH)
    authored = Aogera::Level::Readers::Ruby.read(LEVEL_PATH)
    level = Aogera::Level::Loader.load(authored, prototypes: prototypes)
    simulation = Aogera::Simulation.new(level: level, prototypes: prototypes)
    hero = simulation.spawn_character(character_key: :hero, prototype: :player)

    commands = Aogera::RealtimeController.new.build(
      input: Aogera::Input::Snapshot.empty,
      level: level,
      world: simulation.world_view,
      controlled_id: hero,
      tick_number: Aogera::Realtime::NPC_ACTION_INTERVAL
    ).to_a

    moves = commands.grep(Aogera::Simulation::Commands::GroundMove)
    refute_empty moves
    moves.each do |move|
      assert_operator Math.hypot(move.dx, move.dz), :<=, Aogera::WorldUnits::GRID_CELL_SIZE
    end
  end

end
