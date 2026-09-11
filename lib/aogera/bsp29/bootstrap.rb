# frozen_string_literal: true

module Aogera
  module BSP29
    # Builds the minimal Aogera runtime shell required to inspect/play a BSP29
    # world without importing the Ruby test_field as authored gameplay data.
    #
    # BSP rendering and collision remain authoritative. The one-cell Terrain is
    # intentionally inert scaffolding for the current Level/Simulation API; BSP
    # movement never consults it while the BSP GroundSpace backends are active.
    module Bootstrap
      ENTRY_KEY = :bsp29_start
      LEVEL_NAME = :bsp29
      DEFAULT_QUAKE_YAW_DEGREES = 0.0

      Result = Data.define(:level, :view)

      module_function

      def build(map_data)
        start = player_start(map_data)
        origin = start.origin
        unless origin
          raise FormatError,
            "info_player_start requires an origin for BSP runtime bootstrap"
        end

        entry = Level::AuthoredEntry.new(
          key: ENTRY_KEY,
          x: origin.x,
          y: origin.y,
          z: origin.z,
          facing: nil
        )

        level = Level.new(
          name: LEVEL_NAME,
          terrain: Level::Terrain.new(width: 1, height: 1),
          spawns: [],
          entries: [entry],
          relations: [],
          default_entry: ENTRY_KEY
        )

        Result.new(
          level: level,
          view: FirstPersonView.new(yaw: aogera_yaw(start))
        )
      end

      def player_start(map_data)
        starts = map_data.entities_named("info_player_start")
        return starts.first unless starts.empty?

        raise FormatError,
          "BSP29 runtime bootstrap requires an info_player_start entity"
      end
      private_class_method :player_start

      # Quake yaw 0 points +X and 90 points +Y. After the reader's
      # (x, y, z) -> (x, z, -y) normalization, Aogera yaw 0 points -Z.
      # Therefore Aogera yaw degrees are 90 - Quake yaw degrees.
      def aogera_yaw(entity)
        quake_yaw = parse_quake_yaw(entity.properties["angle"])
        (90.0 - quake_yaw) * Math::PI / 180.0
      end
      private_class_method :aogera_yaw

      def parse_quake_yaw(value)
        number = value.nil? ? DEFAULT_QUAKE_YAW_DEGREES : Float(value)
        unless number.finite?
          raise ArgumentError, "angle must be finite"
        end

        number
      rescue ArgumentError, TypeError
        raise FormatError,
          "info_player_start angle must be a finite number: #{value.inspect}"
      end
      private_class_method :parse_quake_yaw
    end
  end
end
