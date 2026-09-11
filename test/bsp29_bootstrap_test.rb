# frozen_string_literal: true

require_relative "test_helper"

class BSP29BootstrapTest < Minitest::Test
  def test_builds_minimal_runtime_level_from_first_player_start
    map = map_with_entities([
      entity("worldspawn"),
      entity("info_player_start", origin: vec(112, 24, 96), angle: "90"),
      entity("info_player_start", origin: vec(400, 24, 400), angle: "180")
    ])

    result = Aogera::BSP29::Bootstrap.build(map)
    level = result.level
    entry = level.entry

    assert_equal :bsp29, level.name
    assert_empty level.spawns
    assert_empty level.relations
    assert_equal :bsp29_start, level.default_entry
    assert_equal 112.0, entry.x
    assert_equal 24.0, entry.y
    assert_equal 96.0, entry.z
    assert_nil entry.facing
    assert_equal 1, level.width
    assert_equal 1, level.height
  end

  def test_converts_quake_entity_yaw_to_aogera_view_yaw
    east = Aogera::BSP29::Bootstrap.build(
      map_with_entities([entity("info_player_start", origin: vec(1, 2, 3), angle: "0")])
    ).view
    north = Aogera::BSP29::Bootstrap.build(
      map_with_entities([entity("info_player_start", origin: vec(1, 2, 3), angle: "90")])
    ).view

    east_forward = east.forward_vector
    north_forward = north.forward_vector

    assert_in_delta 1.0, east_forward[0], 1e-9
    assert_in_delta 0.0, east_forward[2], 1e-9
    assert_in_delta 0.0, north_forward[0], 1e-9
    assert_in_delta(-1.0, north_forward[2], 1e-9)
  end

  def test_defaults_missing_quake_angle_to_zero_degrees
    result = Aogera::BSP29::Bootstrap.build(
      map_with_entities([entity("info_player_start", origin: vec(1, 2, 3))])
    )

    forward = result.view.forward_vector
    assert_in_delta 1.0, forward[0], 1e-9
    assert_in_delta 0.0, forward[2], 1e-9
  end

  def test_requires_player_start_with_origin
    error = assert_raises(Aogera::BSP29::FormatError) do
      Aogera::BSP29::Bootstrap.build(map_with_entities([entity("worldspawn")]))
    end
    assert_match(/requires an info_player_start/, error.message)

    error = assert_raises(Aogera::BSP29::FormatError) do
      Aogera::BSP29::Bootstrap.build(
        map_with_entities([entity("info_player_start")])
      )
    end
    assert_match(/requires an origin/, error.message)
  end

  def test_rejects_non_numeric_player_start_angle
    error = assert_raises(Aogera::BSP29::FormatError) do
      Aogera::BSP29::Bootstrap.build(
        map_with_entities([
          entity("info_player_start", origin: vec(1, 2, 3), angle: "east")
        ])
      )
    end

    assert_match(/angle must be a finite number/, error.message)
  end

  private

  def map_with_entities(entities)
    Struct.new(:entities) do
      def entities_named(classname)
        entities.select { |entity| entity.classname == classname }.freeze
      end
    end.new(entities.freeze)
  end

  def entity(classname, origin: nil, angle: nil)
    properties = {"classname" => classname}
    properties["angle"] = angle if angle
    Aogera::BSP29::Entity.new(
      properties: properties.freeze,
      origin: origin
    )
  end

  def vec(x, y, z)
    Aogera::BSP29::Vec3.new(x: x.to_f, y: y.to_f, z: z.to_f)
  end
end
