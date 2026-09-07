# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/aogera"

class RaylibFrontendTest < Minitest::Test
  Item = Data.define(:x, :y, :render_key, :glyph)
  Scene = Data.define(:width, :height, :tiles, :entities)

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
    def draw_rectangle(**options) = @calls << [:draw_rectangle, options]
    def draw_rectangle_lines(**options) = @calls << [:draw_rectangle_lines, options]
    def draw_text(**options) = @calls << [:draw_text, options]
    def screen_width = 1024
    def screen_height = 768
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

    if defined?(Aogera::Host::KeyEvent)
      assert(events.any? { |event| event.key == :w && event.state == :pressed })
      assert(events.any? { |event| event.key == :space && event.state == :released })
    else
      assert_includes(events, :w)
      refute_includes(events, :space)
    end
  end

  def test_raylib_renderer_draws_existing_scene_shape
    api = FakeAPI.new
    renderer = Aogera::Render::Raylib2D.new(api: api)
    scene = Scene.new(
      width: 2,
      height: 1,
      tiles: [
        Item.new(x: 0, y: 0, render_key: :grass, glyph: "."),
        Item.new(x: 1, y: 0, render_key: :wall, glyph: "#")
      ],
      entities: [
        Item.new(x: 0, y: 0, render_key: :player, glyph: "@")
      ]
    )

    renderer.draw(scene, status: "test")

    assert_equal(:begin_drawing, api.calls.first.first)
    assert_equal(:end_drawing, api.calls.last.first)
    assert_operator(api.calls.count { |call| call.first == :draw_rectangle }, :>=, 4)
    assert(api.calls.any? { |call| call.first == :draw_text && call.last[:text] == "test" })
  end
end
