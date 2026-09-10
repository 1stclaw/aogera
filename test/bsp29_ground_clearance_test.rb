# frozen_string_literal: true

require_relative "test_helper"

class BSP29GroundClearanceTest < Minitest::Test
  RecordingClipHull = Struct.new(:result, :calls) do
    def trace(**arguments)
      calls << arguments
      result
    end
  end

  def test_clearance_can_validate_different_authored_radii_without_reusing_binding
    clip_hull = RecordingClipHull.new(clear_trace, [])
    clearance = Aogera::BSP29::GroundClearance.new(clip_hull: clip_hull)

    assert(clearance.clear?(**trace_arguments(radius: 7.04)))
    assert(clearance.clear?(**trace_arguments(radius: 8.96)))
    assert_equal(2, clip_hull.calls.length)
  end

  def test_clearance_reports_compiled_hull_collision
    clip_hull = RecordingClipHull.new(blocked_trace, [])
    clearance = Aogera::BSP29::GroundClearance.new(clip_hull: clip_hull)

    refute(clearance.clear?(**trace_arguments(radius: 8.96)))
    assert_equal(1, clip_hull.calls.length)
  end

  def test_for_world_uses_compiled_hull_one
    clearance = Aogera::BSP29::GroundClearance.for_world(
      map_data: bsp_map_with_solid_box
    )

    refute(clearance.clear?(
      start_x: 1.5,
      start_z: 2.5,
      end_x: 2.5,
      end_z: 2.5,
      feet_y: 0.0,
      ground_body_radius: 8.96
    ))
    assert(clearance.clear?(
      start_x: 1.5,
      start_z: 1.5,
      end_x: 2.5,
      end_z: 1.5,
      feet_y: 0.0,
      ground_body_radius: 8.96
    ))
  end

  private

  def trace_arguments(radius:)
    {
      start_x: 1.0,
      start_z: 2.0,
      end_x: 3.0,
      end_z: 2.0,
      feet_y: 0.0,
      ground_body_radius: radius
    }
  end

  def clear_trace
    Aogera::BSP29::ClipHull::Trace.new(
      fraction: 1.0,
      end_position: vec(3.0, 24.0, 2.0),
      plane_normal: nil,
      start_solid: false,
      all_solid: false
    )
  end

  def blocked_trace
    Aogera::BSP29::ClipHull::Trace.new(
      fraction: 0.5,
      end_position: vec(2.0, 24.0, 2.0),
      plane_normal: vec(-1.0, 0.0, 0.0),
      start_solid: false,
      all_solid: false
    )
  end

  def bsp_map_with_solid_box
    planes = [
      plane(1.0, 0.0, 0.0, 2.0),
      plane(-1.0, 0.0, 0.0, -3.0),
      plane(0.0, 0.0, 1.0, 2.0),
      plane(0.0, 0.0, -1.0, -3.0)
    ].freeze
    clipnodes = [
      clipnode(0, 1, -1),
      clipnode(1, 2, -1),
      clipnode(2, 3, -1),
      clipnode(3, -2, -1)
    ].freeze
    model = Aogera::BSP29::Model.new(
      bounds: nil,
      origin: vec(0, 0, 0),
      headnodes: [99, 0, -1, -1].freeze,
      visible_leaf_count: 0,
      first_face: 0,
      face_count: 0
    )

    Struct.new(:planes, :clipnodes, :world_model).new(
      planes,
      clipnodes,
      model
    )
  end

  def plane(x, y, z, distance)
    Aogera::BSP29::Plane.new(
      normal: vec(x, y, z),
      distance: Float(distance),
      type: 0
    )
  end

  def clipnode(plane_index, front, back)
    Aogera::BSP29::ClipNode.new(
      plane_index: plane_index,
      children: [front, back].freeze
    )
  end

  def vec(x, y, z)
    Aogera::BSP29::Vec3.new(x: Float(x), y: Float(y), z: Float(z))
  end
end
