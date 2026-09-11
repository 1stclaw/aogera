# frozen_string_literal: true

require_relative "test_helper"

class AppBSP29ModeTest < Minitest::Test
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

  def test_unknown_bsp_launch_mode_is_rejected
    error = assert_raises(ArgumentError) do
      Aogera::App.new(bsp29_map: Object.new, bsp29_mode: :play)
    end

    assert_match(/unsupported BSP29 launch mode: :play/, error.message)
  end
end
