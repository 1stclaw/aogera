# frozen_string_literal: true

require_relative "test_helper"

class PathfinderTest < Minitest::Test
  RecordingGroundClearance = Struct.new(:blocked_segments, :calls) do
    def clear?(**arguments)
      calls << arguments
      segment = arguments.values_at(:start_x, :start_z, :end_x, :end_z)
      !blocked_segments.include?(segment)
    end
  end

  def test_finds_world_space_waypoint_around_blocked_terrain
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 5, height: 5),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    source = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )
    world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    waypoint = Aogera::Simulation::Pathfinder.new.next_waypoint(
      level: level, world: world,
      source_id: source, target_id: target
    )

    assert_instance_of Aogera::Simulation::Pathfinder::Waypoint, waypoint
    assert_in_delta 1.5, waypoint.x
    assert_includes [1.5, 3.5], waypoint.z
  end

  def test_returns_current_cell_center_waypoint_when_source_is_already_in_goal_cell
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 5, height: 5),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    source = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    waypoint = Aogera::Simulation::Pathfinder.new.next_waypoint(
      level: level, world: world,
      source_id: source, target_id: target
    )

    assert_equal Aogera::Simulation::Pathfinder::Waypoint.new(x: 1.5, z: 1.5), waypoint
  end

  def test_bsp_ground_clearance_can_reject_direct_grid_transition
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 5, height: 5),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    source = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 3.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28)
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 3.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )
    clearance = RecordingGroundClearance.new(
      [[1.5, 2.5, 2.5, 2.5]],
      []
    )

    waypoint = Aogera::Simulation::Pathfinder.new(
      ground_clearance: clearance
    ).next_waypoint(
      level: level, world: world.view,
      source_id: source, target_id: target
    )

    assert_in_delta 1.5, waypoint.x
    assert_includes [1.5, 3.5], waypoint.z
    direct = clearance.calls.find do |call|
      call.values_at(:start_x, :start_z, :end_x, :end_z) == [1.5, 2.5, 2.5, 2.5]
    end
    refute_nil(direct)
    assert_in_delta(3.0, direct.fetch(:feet_y))
    assert_in_delta(0.28, direct.fetch(:ground_body_radius))
  end



  def test_reuses_static_bsp_transition_clearance_across_searches
    level = open_level
    world, source, target = navigation_world
    clearance = RecordingGroundClearance.new([], [])
    pathfinder = Aogera::Simulation::Pathfinder.new(ground_clearance: clearance)

    first = pathfinder.next_waypoint(
      level: level, world: world.view,
      source_id: source, target_id: target
    )
    first_call_count = clearance.calls.length
    second = pathfinder.next_waypoint(
      level: level, world: world.view,
      source_id: source, target_id: target
    )

    assert_equal(Aogera::Simulation::Pathfinder::Waypoint.new(x: 2.5, z: 2.5), first)
    assert_equal(first, second)
    assert_operator(first_call_count, :>, 0)
    assert_equal(first_call_count, clearance.calls.length)
  end

  def test_dynamic_cell_occupancy_is_rechecked_when_static_clearance_is_cached
    level = open_level
    world, source, target = navigation_world
    clearance = RecordingGroundClearance.new([], [])
    pathfinder = Aogera::Simulation::Pathfinder.new(ground_clearance: clearance)

    assert_equal(
      Aogera::Simulation::Pathfinder::Waypoint.new(x: 2.5, z: 2.5),
      pathfinder.next_waypoint(
        level: level, world: world.view,
        source_id: source, target_id: target
      )
    )
    direct_segment = [1.5, 2.5, 2.5, 2.5]
    direct_calls_before = clearance.calls.count do |call|
      call.values_at(:start_x, :start_z, :end_x, :end_z) == direct_segment
    end

    world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    rerouted = pathfinder.next_waypoint(
      level: level, world: world.view,
      source_id: source, target_id: target
    )
    direct_calls_after = clearance.calls.count do |call|
      call.values_at(:start_x, :start_z, :end_x, :end_z) == direct_segment
    end

    assert_in_delta 1.5, rerouted.x
    assert_includes [1.5, 3.5], rerouted.z
    assert_equal(direct_calls_before, direct_calls_after)
  end

  def test_static_clearance_cache_distinguishes_level_radius_height_and_direction
    level = open_level
    clearance = RecordingGroundClearance.new([], [])
    pathfinder = Aogera::Simulation::Pathfinder.new(ground_clearance: clearance)

    world, source, target = navigation_world
    pathfinder.next_waypoint(
      level: level, world: world.view,
      source_id: source, target_id: target
    )
    baseline = clearance.calls.length

    radius_world, radius_source, radius_target = navigation_world(radius: 0.35)
    pathfinder.next_waypoint(
      level: level, world: radius_world.view,
      source_id: radius_source, target_id: radius_target
    )
    after_radius = clearance.calls.length

    height_world, height_source, height_target = navigation_world(feet_y: 1.0)
    pathfinder.next_waypoint(
      level: level, world: height_world.view,
      source_id: height_source, target_id: height_target
    )
    after_height = clearance.calls.length

    reverse_world, reverse_source, reverse_target = navigation_world(
      source_x: 3.5,
      target_x: 1.5
    )
    pathfinder.next_waypoint(
      level: level, world: reverse_world.view,
      source_id: reverse_source, target_id: reverse_target
    )
    after_direction = clearance.calls.length

    pathfinder.next_waypoint(
      level: open_level(name: :other), world: world.view,
      source_id: source, target_id: target
    )

    assert_operator(after_radius, :>, baseline)
    assert_operator(after_height, :>, after_radius)
    assert_operator(after_direction, :>, after_height)
    assert_operator(clearance.calls.length, :>, after_direction)
    assert(clearance.calls.any? { |call| call.fetch(:ground_body_radius) == 0.35 })
    assert(clearance.calls.any? { |call| call.fetch(:feet_y) == 1.0 })
    assert(clearance.calls.any? do |call|
      call.values_at(:start_x, :start_z, :end_x, :end_z) == [3.5, 2.5, 2.5, 2.5]
    end)
  end

  private

  def open_level(name: :test)
    Aogera::Level.new(
      name: name,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 5, height: 5),
      spawns: [],
      relations: []
    )
  end

  def navigation_world(source_x: 1.5, target_x: 3.5, feet_y: 0.0, radius: 0.28)
    world = Aogera::World.new
    source = world.spawn(
      position: Aogera::Component::Position.new(x: source_x, y: feet_y, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      ground_body: Aogera::Component::GroundBody.new(radius: radius)
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: target_x, y: feet_y, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )

    [world, source, target]
  end

end
