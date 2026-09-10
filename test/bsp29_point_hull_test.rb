# frozen_string_literal: true

require_relative "test_helper"

class BSP29PointHullTest < Minitest::Test
  Vec3 = Aogera::BSP29::Vec3
  Plane = Aogera::BSP29::Plane
  Node = Aogera::BSP29::Node
  Leaf = Aogera::BSP29::Leaf

  def test_point_contents_uses_node_leaf_tree
    hull = x_plane_hull

    assert_equal(-1, hull.point_contents(vec(2, 0, 0)))
    assert_equal(-2, hull.point_contents(vec(-2, 0, 0)))
  end

  def test_clear_trace_remains_in_non_solid_leaf
    trace = x_plane_hull.trace(
      start_position: vec(2, 0, 0),
      end_position: vec(1, 0, 0)
    )

    assert_predicate(trace, :clear?)
    assert_in_delta(1.0, trace.fraction)
    assert_equal(vec(1, 0, 0), trace.end_position)
    assert_nil(trace.plane_normal)
    refute(trace.start_solid)
    refute(trace.all_solid)
  end

  def test_trace_reports_first_solid_leaf_boundary
    trace = x_plane_hull.trace(
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

  def test_trace_marks_start_solid_when_exiting_solid_leaf
    trace = x_plane_hull.trace(
      start_position: vec(-2, 0, 0),
      end_position: vec(2, 0, 0)
    )

    assert_predicate(trace, :hit?)
    assert(trace.start_solid)
    refute(trace.all_solid)
  end

  def test_trace_marks_all_solid_when_segment_never_leaves_solid_leaf
    trace = x_plane_hull.trace(
      start_position: vec(-2, 0, 0),
      end_position: vec(-1, 0, 0)
    )

    assert_predicate(trace, :hit?)
    assert(trace.start_solid)
    assert(trace.all_solid)
  end

  def test_nested_nodes_find_deeper_solid_boundary
    planes = [
      plane(1, 0, 0, 0),
      plane(0, 0, 1, 0)
    ]
    nodes = [
      node(0, [-2, 1]),
      node(1, [-2, -1])
    ]
    leaves = [leaf(-2), leaf(-1)]
    hull = Aogera::BSP29::PointHull.new(
      planes: planes,
      nodes: nodes,
      leaves: leaves,
      headnode: 0
    )

    assert_equal(-1, hull.point_contents(vec(-1, 0, 1)))
    assert_equal(-2, hull.point_contents(vec(-1, 0, -1)))
  end

  def test_for_world_uses_model_headnode_zero
    model = Aogera::BSP29::Model.new(
      bounds: nil,
      origin: vec(0, 0, 0),
      headnodes: [0, 99, 99, 99].freeze,
      visible_leaf_count: 0,
      first_face: 0,
      face_count: 0
    )
    map_data = Struct.new(:planes, :nodes, :leaves, :world_model).new(
      [plane(1, 0, 0, 0)],
      [node(0, [-2, -1])],
      [leaf(-2), leaf(-1)],
      model
    )

    trace = Aogera::BSP29::PointHull.for_world(map_data: map_data).trace(
      start_position: vec(2, 0, 0),
      end_position: vec(-2, 0, 0)
    )

    assert_in_delta(0.5, trace.fraction)
    assert_equal(vec(1, 0, 0), trace.plane_normal)
  end

  def test_invalid_plane_reference_raises_format_error
    hull = Aogera::BSP29::PointHull.new(
      planes: [plane(1, 0, 0, 0)],
      nodes: [node(4, [-2, -1])],
      leaves: [leaf(-2), leaf(-1)],
      headnode: 0
    )

    error = assert_raises(Aogera::BSP29::FormatError) do
      hull.point_contents(vec(1, 0, 0))
    end
    assert_match(/plane index 4/, error.message)
  end

  def test_invalid_node_reference_raises_format_error
    hull = Aogera::BSP29::PointHull.new(
      planes: [plane(1, 0, 0, 0)],
      nodes: [node(0, [8, -1])],
      leaves: [leaf(-2), leaf(-1)],
      headnode: 0
    )

    error = assert_raises(Aogera::BSP29::FormatError) do
      hull.point_contents(vec(1, 0, 0))
    end
    assert_match(/node index 8/, error.message)
  end

  def test_invalid_leaf_reference_raises_format_error
    hull = Aogera::BSP29::PointHull.new(
      planes: [plane(1, 0, 0, 0)],
      nodes: [node(0, [-8, -1])],
      leaves: [leaf(-2), leaf(-1)],
      headnode: 0
    )

    error = assert_raises(Aogera::BSP29::FormatError) do
      hull.point_contents(vec(1, 0, 0))
    end
    assert_match(/leaf index 7/, error.message)
  end

  private

  def x_plane_hull
    Aogera::BSP29::PointHull.new(
      planes: [plane(1, 0, 0, 0)],
      nodes: [node(0, [-2, -1])],
      leaves: [leaf(-2), leaf(-1)],
      headnode: 0
    )
  end

  def plane(x, y, z, distance)
    Plane.new(
      normal: vec(x, y, z),
      distance: Float(distance),
      type: 0
    )
  end

  def node(plane_index, children)
    Node.new(
      plane_index: plane_index,
      children: children.freeze,
      bounds: nil,
      first_face: 0,
      face_count: 0
    )
  end

  def leaf(contents)
    Leaf.new(
      contents: contents,
      visibility_offset: -1,
      bounds: nil,
      first_marksurface: 0,
      marksurface_count: 0,
      ambient_levels: [0, 0, 0, 0].freeze
    )
  end

  def vec(x, y, z)
    Vec3.new(x: Float(x), y: Float(y), z: Float(z))
  end
end
