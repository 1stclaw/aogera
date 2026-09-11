# frozen_string_literal: true

require_relative "test_helper"

class GroundNavigationTest < Minitest::Test
  class RecordingGroundSpace
    attr_reader :sweeps

    def initialize(source:, radius:, traces: nil, &trace_builder)
      @source = source
      @radius = radius
      @traces = traces&.dup
      @trace_builder = trace_builder
      @sweeps = []
    end

    def position(world:, entity_id:)
      @source
    end

    def radius(world:, entity_id:)
      @radius
    end

    def sweep_circle(**arguments)
      @sweeps << arguments
      return @trace_builder.call(arguments, @sweeps.length) if @trace_builder
      return @traces.shift if @traces && !@traces.empty?

      clear_trace(arguments.fetch(:end_x), arguments.fetch(:end_z))
    end

    private

    def clear_trace(x, z)
      Aogera::GroundTrace.new(
        fraction: 1.0,
        end_x: x,
        end_z: z,
        normal_x: 0.0,
        normal_z: 0.0,
        entity_id: nil,
        world_hit: false,
        start_blocked: false
      )
    end
  end

  def test_ground_heading_normalizes_world_space_direction
    heading = Aogera::GroundHeading.new(dx: 3.0, dz: 4.0)

    assert_in_delta 0.6, heading.dx
    assert_in_delta 0.8, heading.dz
    assert_in_delta 1.0, Math.hypot(heading.dx, heading.dz)
  end

  def test_ground_heading_rejects_zero_and_non_finite_vectors
    assert_raises(ArgumentError) { Aogera::GroundHeading.new(dx: 0.0, dz: 0.0) }
    assert_raises(ArgumentError) { Aogera::GroundHeading.new(dx: Float::INFINITY, dz: 0.0) }
    assert_raises(ArgumentError) { Aogera::GroundHeading.new(dx: Float::NAN, dz: 1.0) }
  end

  def test_arrived_result_needs_no_geometry_probe
    space = RecordingGroundSpace.new(
      source: position(10.0, 20.0),
      radius: 2.0
    )
    navigation = navigation(space)

    result = navigation.query(
      level: Object.new,
      world: Object.new,
      source_id: 7,
      goal_x: 10.0,
      goal_z: 20.0
    )

    assert_equal :arrived, result.status
    assert_nil result.heading
    assert_empty space.sweeps
  end

  def test_open_direct_probe_returns_normalized_direct_heading_without_grid_api
    space = RecordingGroundSpace.new(
      source: position(10.0, 20.0),
      radius: 2.0
    )
    navigation = navigation(space, probe_distance: 3.0)

    result = navigation.query(
      level: Object.new,
      world: Object.new,
      source_id: 7,
      goal_x: 14.0,
      goal_z: 23.0
    )

    assert_equal :direct, result.status
    assert_in_delta 0.8, result.heading.dx
    assert_in_delta 0.6, result.heading.dz
    assert_equal 1, space.sweeps.length
    assert_in_delta 12.4, space.sweeps[0].fetch(:end_x)
    assert_in_delta 21.8, space.sweeps[0].fetch(:end_z)
  end

  def test_blocking_plane_can_produce_local_tangent_heading
    blocked = hit_trace(normal_x: -1.0, normal_z: 0.0)
    clear = clear_trace
    space = RecordingGroundSpace.new(
      source: position(1.0, 1.0),
      radius: 0.28,
      traces: [blocked, clear]
    )

    result = navigation(space).query(
      level: Object.new,
      world: Object.new,
      source_id: 1,
      goal_x: 5.0,
      goal_z: 1.0
    )

    assert_equal :local_avoidance, result.status
    assert_in_delta 0.0, result.heading.dx, 1e-9
    assert_in_delta(-1.0, result.heading.dz, 1e-9)
    assert_equal 2, space.sweeps.length
  end

  def test_previous_heading_is_tried_before_new_turns_when_not_reversing
    blocked = hit_trace(normal_x: 0.0, normal_z: 0.0)
    clear = clear_trace
    space = RecordingGroundSpace.new(
      source: position(1.0, 1.0),
      radius: 0.28,
      traces: [blocked, clear]
    )
    previous = Aogera::GroundHeading.new(dx: 0.0, dz: 1.0)

    result = navigation(space).query(
      level: Object.new,
      world: Object.new,
      source_id: 1,
      goal_x: 5.0,
      goal_z: 1.0,
      previous_heading: previous
    )

    assert_equal :local_avoidance, result.status
    assert_in_delta previous.dx, result.heading.dx
    assert_in_delta previous.dz, result.heading.dz
    assert_in_delta 1.0, space.sweeps[1].fetch(:start_x)
    assert_operator space.sweeps[1].fetch(:end_z), :>, 1.0
  end

  def test_goal_entity_hit_counts_as_usable_direct_pursuit
    target_id = 9
    space = RecordingGroundSpace.new(
      source: position(1.0, 1.0),
      radius: 0.28,
      traces: [hit_trace(entity_id: target_id)]
    )

    result = navigation(space).query(
      level: Object.new,
      world: Object.new,
      source_id: 1,
      goal_x: 2.0,
      goal_z: 1.0,
      goal_entity_id: target_id
    )

    assert_equal :direct, result.status
    assert_in_delta 1.0, result.heading.dx
    assert_in_delta 0.0, result.heading.dz
  end

  def test_route_needed_when_all_local_probes_are_blocked
    space = RecordingGroundSpace.new(
      source: position(1.0, 1.0),
      radius: 0.28
    ) do |arguments, _index|
      hit_trace(
        end_x: arguments.fetch(:start_x),
        end_z: arguments.fetch(:start_z),
        normal_x: -1.0,
        normal_z: 0.0
      )
    end

    result = navigation(space).query(
      level: Object.new,
      world: Object.new,
      source_id: 1,
      goal_x: 5.0,
      goal_z: 1.0
    )

    assert_equal :route_needed, result.status
    assert_nil result.heading
    assert_operator space.sweeps.length, :>, 1
  end

  def test_missing_source_returns_route_needed_without_probe
    space = RecordingGroundSpace.new(source: nil, radius: 0.28)

    result = navigation(space).query(
      level: Object.new,
      world: Object.new,
      source_id: 1,
      goal_x: 5.0,
      goal_z: 1.0
    )

    assert_equal :route_needed, result.status
    assert_empty space.sweeps
  end

  def test_source_requires_positive_ground_body_radius
    space = RecordingGroundSpace.new(
      source: position(1.0, 1.0),
      radius: 0.0
    )

    assert_raises(ArgumentError) do
      navigation(space).query(
        level: Object.new,
        world: Object.new,
        source_id: 1,
        goal_x: 5.0,
        goal_z: 1.0
      )
    end
  end

  private

  def navigation(space, probe_distance: 1.0)
    Aogera::Simulation::GroundNavigation.new(
      ground_space: space,
      probe_distance: probe_distance
    )
  end

  def position(x, z)
    Aogera::Component::Position.new(x: x, y: 0.0, z: z)
  end

  def clear_trace
    Aogera::GroundTrace.new(
      fraction: 1.0,
      end_x: 0.0,
      end_z: 0.0,
      normal_x: 0.0,
      normal_z: 0.0,
      entity_id: nil,
      world_hit: false,
      start_blocked: false
    )
  end

  def hit_trace(
    end_x: 0.0,
    end_z: 0.0,
    normal_x: -1.0,
    normal_z: 0.0,
    entity_id: nil
  )
    Aogera::GroundTrace.new(
      fraction: 0.5,
      end_x: end_x,
      end_z: end_z,
      normal_x: normal_x,
      normal_z: normal_z,
      entity_id: entity_id,
      world_hit: entity_id.nil?,
      start_blocked: false
    )
  end
end
