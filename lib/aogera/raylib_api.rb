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

    def create_static_model(vertices:, texcoords: nil, texcoords2: nil)
      unless vertices.length.positive? && (vertices.length % 9).zero?
        raise ArgumentError, "static model vertices must contain complete triangles"
      end

      vertex_count = vertices.length / 3
      texcoords ||= Array.new(vertex_count * 2, 0.0)
      unless texcoords.length == vertex_count * 2
        raise ArgumentError, "static model texcoords must contain one UV pair per vertex"
      end
      if texcoords2 && texcoords2.length != vertex_count * 2
        raise ArgumentError, "static model texcoords2 must contain one UV pair per vertex"
      end

      vertex_data = nil
      texcoord_data = nil
      texcoord2_data = nil
      mesh = nil
      uploaded = false

      vertex_data = ::Raylib.MemAlloc(vertices.length * FFI.type_size(:float))
      texcoord_data = ::Raylib.MemAlloc(texcoords.length * FFI.type_size(:float))
      texcoord2_data = if texcoords2
                         ::Raylib.MemAlloc(texcoords2.length * FFI.type_size(:float))
                       end
      raise NoMemoryError, "raylib vertex allocation failed" if vertex_data.null?
      raise NoMemoryError, "raylib texcoord allocation failed" if texcoord_data.null?
      if texcoord2_data&.null?
        raise NoMemoryError, "raylib secondary texcoord allocation failed"
      end

      vertex_data.write_array_of_float(vertices)
      texcoord_data.write_array_of_float(texcoords)
      texcoord2_data&.write_array_of_float(texcoords2)

      mesh = ::Raylib::Mesh.new
      mesh.vertexCount = vertex_count
      mesh.triangleCount = vertex_count / 3
      mesh.vertices = vertex_data
      mesh.texcoords = texcoord_data
      mesh.texcoords2 = texcoord2_data if texcoord2_data
      ::Raylib.UploadMesh(mesh.pointer, false)
      uploaded = true
      ::Raylib.LoadModelFromMesh(mesh)
    rescue StandardError, NoMemoryError
      if uploaded && mesh
        ::Raylib.UnloadMesh(mesh)
      else
        ::Raylib.MemFree(vertex_data) if vertex_data && !vertex_data.null?
        ::Raylib.MemFree(texcoord_data) if texcoord_data && !texcoord_data.null?
        ::Raylib.MemFree(texcoord2_data) if texcoord2_data && !texcoord2_data.null?
      end
      raise
    end

    def create_texture_rgba(width:, height:, pixels:)
      expected = width * height * 4
      unless width.positive? && height.positive? && pixels.bytesize == expected
        raise ArgumentError, "RGBA texture data must match width * height * 4"
      end

      pixel_data = nil
      image = nil
      texture = nil
      pixel_data = ::Raylib.MemAlloc(expected)
      raise NoMemoryError, "raylib texture allocation failed" if pixel_data.null?

      pixel_data.put_bytes(0, pixels)
      image = ::Raylib::Image.new
      image.data = pixel_data
      image.width = width
      image.height = height
      image.mipmaps = 1
      image.format = ::Raylib::PIXELFORMAT_UNCOMPRESSED_R8G8B8A8
      texture = ::Raylib.LoadTextureFromImage(image)
      ::Raylib.SetTextureFilter(texture, ::Raylib::TEXTURE_FILTER_BILINEAR)
      ::Raylib.UnloadImage(image)
      image = nil
      pixel_data = nil
      texture
    rescue StandardError, NoMemoryError
      if image
        ::Raylib.UnloadImage(image)
      elsif pixel_data && !pixel_data.null?
        ::Raylib.MemFree(pixel_data)
      end
      ::Raylib.UnloadTexture(texture) if texture
      raise
    end

    def create_shader(vertex_source:, fragment_source:)
      ::Raylib.LoadShaderFromMemory(vertex_source, fragment_source)
    end

    def set_model_shader(model:, shader:)
      model.material(0).shader = shader
    end

    def set_model_texture(model:, texture:, slot: :albedo)
      map_type = case slot
                 when :albedo
                   ::Raylib::MATERIAL_MAP_ALBEDO
                 when :lightmap
                   ::Raylib::MATERIAL_MAP_METALNESS
                 else
                   raise ArgumentError, "unknown material texture slot: #{slot.inspect}"
                 end

      ::Raylib.SetMaterialTexture(model.material(0), map_type, texture)
    end

    def set_texture_wrap(texture:, mode:)
      wrap = case mode
             when :repeat
               ::Raylib::TEXTURE_WRAP_REPEAT
             when :clamp
               ::Raylib::TEXTURE_WRAP_CLAMP
             else
               raise ArgumentError, "unknown texture wrap mode: #{mode.inspect}"
             end
      ::Raylib.SetTextureWrap(texture, wrap)
    end

    def unload_shader(shader)
      ::Raylib.UnloadShader(shader)
    end

    def unload_texture(texture)
      ::Raylib.UnloadTexture(texture)
    end

    def draw_model(model:, rgba:)
      ::Raylib.DrawModel(
        model,
        ::Raylib::Vector3.create(0.0, 0.0, 0.0),
        1.0,
        color(rgba)
      )
    end

    def unload_model(model)
      ::Raylib.UnloadModel(model)
    end

    def fps
      ::Raylib.GetFPS
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
