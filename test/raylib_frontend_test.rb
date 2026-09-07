# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/aogera"

class RaylibFrontendTest < Minitest::Test
  class FakeAPI
    attr_reader :calls

    def initialize
      @calls = []
      @pressed = {}
      @released = {}
    end

    def press(key)
      @pressed[key] = true
    end

    def release(key)
      @released[key] = true
    end

    def open_window(**options) = @calls << [:open_window, options]
    def focus_window = @calls << [:focus_window]
    def close_window = @calls << [:close_window]
    def window_should_close? = false
    def key_pressed?(key) = @pressed.fetch(key, false)
    def key_released?(key) = @released.fetch(key, false)
    def begin_drawing = @calls << [:begin_drawing]
    def end_drawing = @calls << [:end_drawing]
    def clear(rgba) = @calls << [:clear, rgba]
    def begin_mode_3d(**options) = @calls << [:begin_mode_3d, options]
    def end_mode_3d = @calls << [:end_mode_3d]
    def draw_cube(**options) = @calls << [:draw_cube, options]
    def draw_rectangle(**options) = @calls << [:draw_rectangle, options]
    def draw_text(**options) = @calls << [:draw_text, options]
    def screen_width = 1024
    def screen_height = 768
  end

  def test_raylib_host_uses_version_in_default_title
    api = FakeAPI.new
    host = Aogera::Host::Raylib.new(api: api)

    host.open

    assert_equal("Aogera #{Aogera::VERSION}", api.calls[0].last[:title])
  end

  def test_raylib_host_focuses_window_after_opening
    api = FakeAPI.new
    host = Aogera::Host::Raylib.new(api: api)

    host.open

    assert_equal(:open_window, api.calls[0].first)
    assert_equal([:focus_window], api.calls[1])
  end

  def test_raylib_host_emits_press_and_release_events
    api = FakeAPI.new
    api.press(:w)
    api.release(:space)
    host = Aogera::Host::Raylib.new(api: api)

    events = host.poll_events

    assert(events.any? { |event| event.key == :w && event.state == :pressed })
    assert(events.any? { |event| event.key == :space && event.state == :released })
  end

  def test_raylib_3d_renderer_wraps_world_drawing_in_3d_mode
    api = FakeAPI.new
    renderer = Aogera::Render::Raylib3D.new(api: api)
    level = Aogera::Level::Terrain.new(width: 1, height: 1)
    level = Aogera::Level.new(
      name: :test,
      terrain: level,
      spawns: [],
      relations: []
    )

    renderer.draw(
      level: level,
      world: Aogera::World.new.view,
      status: "test"
    )

    assert_equal(:begin_drawing, api.calls.first.first)
    assert_equal(:end_drawing, api.calls.last.first)
    assert(api.calls.any? { |call| call.first == :begin_mode_3d })
    assert(api.calls.any? { |call| call.first == :end_mode_3d })
    assert(api.calls.any? { |call| call.first == :draw_cube })
    assert(api.calls.any? { |call| call.first == :draw_text && call.last[:text] == "test" })
  end
end
