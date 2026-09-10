# frozen_string_literal: true

require_relative "test_helper"

class BSP29GroundHullTest < Minitest::Test
  Vec3 = Aogera::BSP29::Vec3
  Plane = Aogera::BSP29::Plane
  ClipNode = Aogera::BSP29::ClipNode

  RecordingClipHull = Struct.new(:trace_result, :arguments) do
    def trace(start_position:, end_position:)
      self.arguments = [start_position, end_position]
      trace_result
    end
  end

  def test_hull_one_dimensions_are_explicit_collision_source_facts
    assert_in_delta(16.0, Aogera::BSP29::GroundHull::HORIZONTAL_HALF_EXTENT)
    assert_in_delta(-24.0, Aogera::BSP29::GroundHull::MIN_Y)
    assert_in_delta(32.0, Aogera::BSP29::GroundHull::MAX_Y)
    assert_in_delta(24.0, Aogera::BSP29::GroundHull::ORIGIN_ABOVE_FEET)
  end

  def test_ground_hull_records_authored_radius_without_resizing_compiled_hull
    clip_hull = RecordingClipHull.new(clear_clip_trace(vec(0, 24, 0)))
    hull = Aogera::BSP29::GroundHull.new(
      clip_hull: clip_hull,
      ground_body_radius: 7.04
    )

    assert_in_delta(7.04, hull.ground_body_radius)
    assert_in_delta(8.96, hull.horizontal_clearance_delta)
    assert_in_delta(16.0, Aogera::BSP29::GroundHull::HORIZONTAL_HALF_EXTENT)
  end

  def test_trace_converts_feet_height_to_quake_hull_origin_height
    result = clear_clip_trace(vec(20, 29, 40))
    clip_hull = RecordingClipHull.new(result)
    hull = Aogera::BSP29::GroundHull.new(
      clip_hull: clip_hull,
      ground_body_radius: 7.04
    )

    returned = hull.trace(
      start_x: 10,
      start_z: 30,
      end_x: 20,
      end_z: 40,
      feet_y: 5,
      ground_body_radius: 7.04
    )

    start_position, end_position = clip_hull.arguments
    assert_equal(vec(10, 29, 30), start_position)
    assert_equal(vec(20, 29, 40), end_position)
    assert_same(result, returned)
  end

  def test_trace_rejects_a_different_ground_body_radius
    clip_hull = RecordingClipHull.new(clear_clip_trace(vec(0, 24, 0)))
    hull = Aogera::BSP29::GroundHull.new(
      clip_hull: clip_hull,
      ground_body_radius: 7.04
    )

    error = assert_raises(ArgumentError) do
      hull.trace(
        start_x: 0,
        start_z: 0,
        end_x: 1,
        end_z: 0,
        feet_y: 0,
        ground_body_radius: 8.96
      )
    end

    assert_match(/bound to GroundBody radius 7\.04/, error.message)
    assert_nil(clip_hull.arguments)
  end

  def test_ground_body_radius_must_be_positive
    clip_hull = RecordingClipHull.new(clear_clip_trace(vec(0, 24, 0)))

    error = assert_raises(ArgumentError) do
      Aogera::BSP29::GroundHull.new(
        clip_hull: clip_hull,
        ground_body_radius: 0.0
      )
    end

    assert_match(/must be positive/, error.message)
  end

  def test_for_world_selects_compiled_hull_one
    model = Aogera::BSP29::Model.new(
      bounds: nil,
      origin: vec(0, 0, 0),
      headnodes: [99, 0, -1, -1].freeze,
      visible_leaf_count: 0,
      first_face: 0,
      face_count: 0
    )
    map_data = Struct.new(:planes, :clipnodes, :world_model).new(
      [Plane.new(normal: vec(1, 0, 0), distance: 0.0, type: 0)],
      [ClipNode.new(plane_index: 0, children: [-1, -2].freeze)],
      model
    )

    hull = Aogera::BSP29::GroundHull.for_world(
      map_data: map_data,
      ground_body_radius: 7.04
    )
    trace = hull.trace(
      start_x: 2,
      start_z: 0,
      end_x: -2,
      end_z: 0,
      feet_y: 0,
      ground_body_radius: 7.04
    )

    assert_in_delta(0.5, trace.fraction)
    assert_equal(vec(1, 0, 0), trace.plane_normal)
  end

  private

  def clear_clip_trace(end_position)
    Aogera::BSP29::ClipHull::Trace.new(
      fraction: 1.0,
      end_position: end_position,
      plane_normal: nil,
      start_solid: false,
      all_solid: false
    )
  end

  def vec(x, y, z)
    Vec3.new(x: Float(x), y: Float(y), z: Float(z))
  end
end
