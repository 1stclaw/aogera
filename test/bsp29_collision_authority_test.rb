# frozen_string_literal: true

require_relative "test_helper"

class BSP29CollisionAuthorityTest < Minitest::Test
  FakeGroundHull = Struct.new(:result, :calls) do
    def trace(**arguments)
      calls << arguments
      result
    end
  end

  def test_controlled_water_pinch_has_circle_clearance_but_zero_hull_one_clearance
    prototypes = Aogera::Prototype::Loader.load(AogeraTestPaths::PROTOTYPE_PATH)
    authored = Aogera::Level::Readers::Ruby.read(AogeraTestPaths::LEVEL_PATH)
    level = Aogera::Level::Loader.load(authored, prototypes: prototypes)
    player_radius = prototypes.fetch(:player).components.fetch(:ground_body).radius
    cell_size = level.cell_size

    assert(level.passable?(30, 4))
    refute(level.passable?(30, 3))
    refute(level.passable?(30, 5))

    center_z = level.cell_center(30, 4).fetch(1)
    grid_trace = Aogera::GroundSpace.new.sweep_circle(
      level: level,
      world: Aogera::World.new.view,
      start_x: level.cell_center(29, 4).fetch(0),
      start_z: center_z,
      end_x: level.cell_center(31, 4).fetch(0),
      end_z: center_z,
      radius: player_radius
    )

    assert_predicate(grid_trace, :clear?)

    circle_slack = cell_size - (2.0 * player_radius)
    hull_one_slack = cell_size -
      (2.0 * Aogera::BSP29::GroundHull::HORIZONTAL_HALF_EXTENT)

    assert_in_delta(17.92, circle_slack)
    assert_in_delta(0.0, hull_one_slack)
  end

  def test_retiring_dynamic_blocker_does_not_change_bsp_static_hit
    hull = fake_hull(
      clip_trace(
        fraction: 0.75,
        x: 3.0,
        z: 1.0,
        normal_x: -1.0,
        normal_z: 0.0
      )
    )
    space = Aogera::GroundSpace.new(bsp29_ground_hull: hull)
    world = Aogera::World.new
    blocker_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.0, y: 0.0, z: 1.0),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.25)
    )
    level = open_level

    before_retirement = sweep(space, level, world.view)
    assert_equal(blocker_id, before_retirement.entity_id)
    refute(before_retirement.world_hit)

    world.set_component(blocker_id, :retired, Aogera::Component::Retired.new)

    after_retirement = sweep(space, level, world.view)
    assert_nil(after_retirement.entity_id)
    assert(after_retirement.world_hit)
    assert_in_delta(0.75, after_retirement.fraction)
    assert_equal(2, hull.calls.length)
    assert(hull.calls.all? { |call| call.fetch(:ground_body_radius) == 0.25 })
  end

  private

  def sweep(space, level, world)
    space.sweep_circle(
      level: level,
      world: world,
      start_x: 0.0,
      start_z: 1.0,
      end_x: 4.0,
      end_z: 1.0,
      radius: 0.25
    )
  end

  def open_level
    Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(width: 8, height: 4, cell_size: 1.0),
      spawns: [],
      entries: [],
      relations: []
    )
  end

  def fake_hull(result)
    FakeGroundHull.new(result, [])
  end

  def clip_trace(fraction:, x:, z:, normal_x:, normal_z:)
    Aogera::BSP29::ClipHull::Trace.new(
      fraction: fraction,
      end_position: vec(x, 24.0, z),
      plane_normal: vec(normal_x, 0.0, normal_z),
      start_solid: false,
      all_solid: false
    )
  end

  def vec(x, y, z)
    Aogera::BSP29::Vec3.new(x: Float(x), y: Float(y), z: Float(z))
  end
end
