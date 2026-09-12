# frozen_string_literal: true

module Aogera
  module Render
    # Minimal two-texture shader for BSP29 world surfaces. The base miptexture
    # remains detailed/repeating on UV0 while the original low-resolution baked
    # lightmap atlas is sampled independently on UV1 and multiplied on the GPU.
    module BSP29LightmapShader
      VERTEX = <<~GLSL.freeze
        #version 330

        in vec3 vertexPosition;
        in vec2 vertexTexCoord;
        in vec2 vertexTexCoord2;

        uniform mat4 mvp;

        out vec2 fragTexCoord;
        out vec2 fragLightmapCoord;

        void main()
        {
            fragTexCoord = vertexTexCoord;
            fragLightmapCoord = vertexTexCoord2;
            gl_Position = mvp*vec4(vertexPosition, 1.0);
        }
      GLSL

      FRAGMENT = <<~GLSL.freeze
        #version 330

        in vec2 fragTexCoord;
        in vec2 fragLightmapCoord;

        uniform sampler2D texture0;
        uniform sampler2D texture1;

        out vec4 finalColor;

        void main()
        {
            vec4 base = texture(texture0, fragTexCoord);
            vec4 baked = texture(texture1, fragLightmapCoord);
            finalColor = base*baked;
        }
      GLSL
    end
  end
end
