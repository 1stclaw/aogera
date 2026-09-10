# frozen_string_literal: true

require_relative "test_helper"

class BSP29ClipHullTest < Minitest::Test
  Vec3 = Aogera::BSP29::Vec3
  Plane = Aogera::BSP29::Plane
  ClipNode = Aogera::BSP29::ClipNode

  def test_point_contents_follows_plane_children
    hull = x_plane_hull

    assert_equal(-1, hull.point_contents(vec(1, 0, 0)))
    assert_equal(-2, hull.point_contents(vec(-1, 0, 0)))
    assert_equal(-1, hull.point_contents(vec(0, 0, 0)))
  end

  def test_clear_trace_reaches_end_position
    hull = x_plane_hull

    trace = hull.trace(
      start_position: vec(4, 2, 3),
      end_position: vec(1, 4, 5)
    )

    assert_predicate(trace, :clear?)
    assert_in_delta(1.0, trace.fraction)
    assert_equal(vec(1, 4, 5), trace.end_position)
    assert_nil(trace.plane_normal)
    refute(trace.start_solid)
    refute(trace.all_solid)
  end

  def test_trace_hits_solid_at_plane
    hull = x_plane_hull

    trace = hull.trace(
      start_position: vec(2, 0, 0),
      end_position: vec(-2, 0, 0)
    )

    assert_predicate(trace, :hit?)
    assert_in_delta(0.5, trace.fraction)
    assert_equal(vec(0, 0, 0), trace.end_position)
    assert_equal(vec(1, 0, 0), trace.plane_normal)
    refute(trace.start_solid)
    refute(trace.all_solid)
  end

  def test_trace_reports_start_solid_when_starting_inside_solid
    hull = x_plane_hull

    trace = hull.trace(
      start_position: vec(-2, 0, 0),
      end_position: vec(2, 0, 0)
    )

    assert_predicate(trace, :hit?)
    assert(trace.start_solid)
    refute(trace.all_solid)
    assert_in_delta(1.0, trace.fraction)
    assert_equal(vec(2, 0, 0), trace.end_position)
  end

  def test_trace_reports_all_solid_when_whole_segment_is_solid
    hull = x_plane_hull

    trace = hull.trace(
      start_position: vec(-3, 0, 0),
      end_position: vec(-1, 0, 0)
    )

    assert_predicate(trace, :hit?)
    assert(trace.start_solid)
    assert(trace.all_solid)
    assert_in_delta(1.0, trace.fraction)
  end

  def test_trace_normal_flips_when_solid_is_front_child
    hull = Aogera::BSP29::ClipHull.new(
      planes: [x_plane],
      clipnodes: [ClipNode.new(plane_index: 0, children: [-2, -1].freeze)],
      headnode: 0
    )

    trace = hull.trace(
      start_position: vec(-2, 0, 0),
      end_position: vec(2, 0, 0)
    )

    assert_in_delta(0.5, trace.fraction)
    assert_equal(vec(-1, 0, 0), trace.plane_normal)
  end

  def test_non_solid_contents_are_traversable
    hull = Aogera::BSP29::ClipHull.new(
      planes: [x_plane],
      clipnodes: [ClipNode.new(plane_index: 0, children: [-1, -3].freeze)],
      headnode: 0
    )

    trace = hull.trace(
      start_position: vec(2, 0, 0),
      end_position: vec(-2, 0, 0)
    )

    assert_predicate(trace, :clear?)
    assert_equal(-3, hull.point_contents(vec(-1, 0, 0)))
  end

  def test_nested_clipnodes_find_first_solid_boundary
    planes = [
      Plane.new(normal: vec(1, 0, 0), distance: 0.0, type: 0),
      Plane.new(normal: vec(0, 0, 1), distance: 0.0, type: 2)
    ]
    clipnodes = [
      ClipNode.new(plane_index: 0, children: [1, -1].freeze),
      ClipNode.new(plane_index: 1, children: [-1, -2].freeze)
    ]
    hull = Aogera::BSP29::ClipHull.new(
      planes: planes,
      clipnodes: clipnodes,
      headnode: 0
    )

    trace = hull.trace(
      start_position: vec(2, 0, 2),
      end_position: vec(2, 0, -2)
    )

    assert_in_delta(0.5, trace.fraction)
    assert_equal(vec(0, 0, 1), trace.plane_normal)
  end

  def test_invalid_plane_reference_raises_format_error
    hull = Aogera::BSP29::ClipHull.new(
      planes: [x_plane],
      clipnodes: [ClipNode.new(plane_index: 1, children: [-1, -2].freeze)],
      headnode: 0
    )

    error = assert_raises(Aogera::BSP29::FormatError) do
      hull.point_contents(vec(1, 0, 0))
    end

    assert_match(/plane index 1/, error.message)
  end

  def test_invalid_positive_child_reference_raises_format_error
    hull = Aogera::BSP29::ClipHull.new(
      planes: [x_plane],
      clipnodes: [ClipNode.new(plane_index: 0, children: [2, -2].freeze)],
      headnode: 0
    )

    error = assert_raises(Aogera::BSP29::FormatError) do
      hull.point_contents(vec(1, 0, 0))
    end

    assert_match(/clipnode index 2/, error.message)
  end

  def test_for_world_selects_explicit_compiled_hull
    model = Aogera::BSP29::Model.new(
      bounds: nil,
      origin: vec(0, 0, 0),
      headnodes: [-1, 0, -2, -1].freeze,
      visible_leaf_count: 0,
      first_face: 0,
      face_count: 0
    )
    map_data = Struct.new(:planes, :clipnodes, :world_model).new(
      [x_plane],
      [ClipNode.new(plane_index: 0, children: [-1, -2].freeze)],
      model
    )

    hull = Aogera::BSP29::ClipHull.for_world(
      map_data: map_data,
      hull_index: 1
    )

    assert_equal(-1, hull.point_contents(vec(1, 0, 0)))
    assert_equal(-2, hull.point_contents(vec(-1, 0, 0)))
  end

  private

  def x_plane_hull
    Aogera::BSP29::ClipHull.new(
      planes: [x_plane],
      clipnodes: [ClipNode.new(plane_index: 0, children: [-1, -2].freeze)],
      headnode: 0
    )
  end

  def x_plane
    Plane.new(normal: vec(1, 0, 0), distance: 0.0, type: 0)
  end

  def vec(x, y, z)
    Vec3.new(x: Float(x), y: Float(y), z: Float(z))
  end
end
