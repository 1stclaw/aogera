# frozen_string_literal: true

require_relative "test_helper"

class AppBSP29ModeTest < Minitest::Test
  include AogeraTestSupport
  def test_bsp_map_requires_explicit_launch_mode
    error = assert_raises(ArgumentError) do
      Aogera::App.new(bsp29_map: Object.new)
    end

    assert_match(/launch mode is required/, error.message)
  end

  def test_bsp_launch_mode_requires_bsp_map_data
    error = assert_raises(ArgumentError) do
      Aogera::App.new(bsp29_mode: :spectator)
    end

    assert_match(/requires BSP29 map data/, error.message)
  end

  def test_bsp_palette_requires_bsp_map_data
    error = assert_raises(ArgumentError) do
      Aogera::App.new(bsp29_palette: Object.new)
    end

    assert_match(/palette requires BSP29 map data/, error.message)
  end


  def test_bsp_two_sided_diagnostic_requires_bsp_map_data
    error = assert_raises(ArgumentError) do
      Aogera::App.new(bsp29_two_sided: true)
    end

    assert_match(/two-sided diagnostic requires BSP29 map data/, error.message)
  end

  def test_initial_mode_builds_player_bound_walkthrough
    level = level_with(
      spawns: [],
      entries: [default_entry],
      default_entry: :start
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog
    )
    player_id = simulation.spawn_character(
      character_key: Aogera::App::PLAYER_KEY,
      prototype: :player
    )
    app = Aogera::App.allocate
    app.instance_variable_set(
      :@view,
      Aogera::FirstPersonView.for_direction(:north)
    )

    mode = app.send(
      :initial_mode,
      bsp29_mode: :walkthrough,
      simulation: simulation,
      dialogues: Aogera::Dialogue::Catalog.new({}),
      ground_space: Aogera::GroundSpace.new
    )

    assert_instance_of Aogera::Mode::Walkthrough, mode
    assert_equal player_id, mode.camera_entity_id
  end

  def test_walkthrough_is_a_supported_bsp_launch_mode
    app = Aogera::App.allocate

    assert_nil app.send(
      :validate_bsp29_launch!,
      Object.new,
      :walkthrough,
      nil
    )
  end

  def test_unknown_bsp_launch_mode_is_rejected
    error = assert_raises(ArgumentError) do
      Aogera::App.new(bsp29_map: Object.new, bsp29_mode: :play)
    end

    assert_match(/unsupported BSP29 launch mode: :play/, error.message)
  end
end
