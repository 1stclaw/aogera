# frozen_string_literal: true

module Aogera
  # Small boundary around raylib-bindings. Core Aogera code deals in Ruby values;
  # only this object talks to the generated FFI binding directly.
  class RaylibAPI
    def initialize
      require "raylib"
      load_native_library!
    end

    def open_window(width:, height:, title:, target_fps:)
      ::Raylib.InitWindow(width, height, title)
      ::Raylib.SetExitKey(::Raylib::KEY_NULL)
      ::Raylib.SetTargetFPS(target_fps)
    end

    def focus_window
      ::Raylib.SetWindowFocused
    end

    def close_window
      ::Raylib.CloseWindow
    end

    def window_should_close?
      ::Raylib.WindowShouldClose
    end

    def key_pressed?(key)
      ::Raylib.IsKeyPressed(key_code(key))
    end

    def key_released?(key)
      ::Raylib.IsKeyReleased(key_code(key))
    end

    def disable_cursor
      ::Raylib.DisableCursor
    end

    def enable_cursor
      ::Raylib.EnableCursor
    end

    def mouse_delta
      delta = ::Raylib.GetMouseDelta
      [delta.x, delta.y]
    end

    def begin_drawing
      ::Raylib.BeginDrawing
    end

    def end_drawing
      ::Raylib.EndDrawing
    end

    def begin_mode_3d(position:, target:, up:, fovy:)
      camera = ::Raylib::Camera3D.new
        .with_position(*position)
        .with_target(*target)
        .with_up(*up)
        .with_fovy(fovy)
        .with_projection(::Raylib::CAMERA_PERSPECTIVE)

      ::Raylib.BeginMode3D(camera)
    end

    def end_mode_3d
      ::Raylib.EndMode3D
    end

    def clear(rgba)
      ::Raylib.ClearBackground(color(rgba))
    end

    def draw_rectangle(x:, y:, width:, height:, rgba:)
      ::Raylib.DrawRectangle(x, y, width, height, color(rgba))
    end

    def draw_rectangle_lines(x:, y:, width:, height:, rgba:)
      ::Raylib.DrawRectangleLines(x, y, width, height, color(rgba))
    end

    def draw_text(text:, x:, y:, size:, rgba:)
      ::Raylib.DrawText(text.to_s, x, y, size, color(rgba))
    end

    def draw_cube(x:, y:, z:, width:, height:, length:, rgba:)
      ::Raylib.DrawCube(
        ::Raylib::Vector3.create(x, y, z),
        width,
        height,
        length,
        color(rgba)
      )
    end

    def draw_triangle_3d(a:, b:, c:, rgba:)
      ::Raylib.DrawTriangle3D(
        ::Raylib::Vector3.create(*a),
        ::Raylib::Vector3.create(*b),
        ::Raylib::Vector3.create(*c),
        color(rgba)
      )
    end

    def screen_width
      ::Raylib.GetScreenWidth
    end

    def screen_height
      ::Raylib.GetScreenHeight
    end

    private

    def load_native_library!
      gem_root = Gem::Specification.find_by_name("raylib-bindings").full_gem_path
      lib_dir = File.join(gem_root, "lib")
      library = case RUBY_PLATFORM
                when /mswin|msys|mingw|cygwin/
                  File.join(lib_dir, "libraylib.dll")
                when /darwin/
                  arch = RUBY_PLATFORM.split("-").first
                  File.join(lib_dir, "libraylib.#{arch}.dylib")
                when /linux/
                  arch = RUBY_PLATFORM.split("-").first
                  File.join(lib_dir, "libraylib.#{arch}.so")
                else
                  raise LoadError, "Unsupported raylib platform: #{RUBY_PLATFORM}"
                end

      raise LoadError, "raylib native library not found: #{library}" unless File.file?(library)

      ::Raylib.load_lib(library)
    end

    def key_code(key)
      ::Raylib.const_get("KEY_#{key.to_s.upcase}")
    rescue NameError
      raise ArgumentError, "Unknown raylib key: #{key.inspect}"
    end

    def color(rgba)
      r, g, b, a = rgba
      ::Raylib::Color.from_u8(r, g, b, a || 255)
    end
  end
end
