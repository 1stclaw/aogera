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
      @mouse_delta = [0.0, 0.0]
    end

    def press(key)
      @pressed[key] = true
    end

    def release(key)
      @released[key] = true
    end

    def move_mouse(dx, dy)
      @mouse_delta = [dx, dy]
    end

    def open_window(**options) = @calls << [:open_window, options]
    def focus_window = @calls << [:focus_window]
    def disable_cursor = @calls << [:disable_cursor]
    def enable_cursor = @calls << [:enable_cursor]
    def close_window = @calls << [:close_window]
    def window_should_close? = false
    def key_pressed?(key) = @pressed.fetch(key, false)
    def key_released?(key) = @released.fetch(key, false)
    def mouse_delta = @mouse_delta
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

  def test_raylib_host_focuses_then_captures_cursor_after_opening
    api = FakeAPI.new
    host = Aogera::Host::Raylib.new(api: api)

    host.open

    assert_equal(:open_window, api.calls[0].first)
    assert_equal([:focus_window], api.calls[1])
    assert_equal([:disable_cursor], api.calls[2])
  end

  def test_raylib_host_releases_cursor_before_closing
    api = FakeAPI.new
    host = Aogera::Host::Raylib.new(api: api)
    host.open

    host.close

    assert_equal([:enable_cursor], api.calls[-2])
    assert_equal([:close_window], api.calls[-1])
  end

  def test_raylib_host_emits_key_and_mouse_events
    api = FakeAPI.new
    api.press(:w)
    api.release(:space)
    api.move_mouse(3.0, -2.0)
    host = Aogera::Host::Raylib.new(api: api)

    events = host.poll_events

    assert(events.any? { |event| event.is_a?(Aogera::Host::KeyEvent) && event.key == :w && event.state == :pressed })
    assert(events.any? { |event| event.is_a?(Aogera::Host::KeyEvent) && event.key == :space && event.state == :released })
    motion = events.find { |event| event.is_a?(Aogera::Host::MouseMotion) }
    assert_in_delta 3.0, motion.dx
    assert_in_delta(-2.0, motion.dy)
  end

  def test_app_applies_mouse_look_at_render_cadence_before_a_simulation_tick
    api = Class.new(FakeAPI) do
      def window_should_close?
        @window_checks ||= 0
        @window_checks += 1
        @window_checks > 1
      end
    end.new
    api.move_mouse(100.0, 0.0)

    Aogera::App.new(clock: -> { 0.0 }, raylib_api: api).run

    camera = api.calls.find { |call| call.first == :begin_mode_3d }.last
    refute_in_delta 3.5, camera[:target][0]
    status = api.calls.find do |call|
      call.first == :draw_text && call.last[:text].include?("Tick 0")
    end
    refute_nil status
  end

  def test_raylib_3d_renderer_wraps_world_drawing_in_first_person_3d_mode
    api = FakeAPI.new
    renderer = Aogera::Render::Raylib3D.new(api: api)
    terrain = Aogera::Level::Terrain.new(width: 1, height: 1)
    level = Aogera::Level.new(
      name: :test,
      terrain: terrain,
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    camera_id = world.spawn(
      position: Aogera::Component::Position.new(x: 0.5, y: 0.0, z: 0.5)
    )

    renderer.draw(
      level: level,
      world: world.view,
      status: "test",
      view: Aogera::FirstPersonView.for_direction(:north),
      camera_entity_id: camera_id
    )

    assert_equal(:begin_drawing, api.calls.first.first)
    assert_equal(:end_drawing, api.calls.last.first)
    assert(api.calls.any? { |call| call.first == :begin_mode_3d })
    assert(api.calls.any? { |call| call.first == :end_mode_3d })
    assert(api.calls.any? { |call| call.first == :draw_cube })
    assert(api.calls.any? { |call| call.first == :draw_text && call.last[:text] == "test" })
  end
end
