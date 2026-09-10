# frozen_string_literal: true

module Aogera
  module BSP29
    # Point/line collision through BSP29 model headnode 0.
    #
    # Unlike compiled clip hulls 1..3, hull 0 is represented by the BSP node
    # tree and terminates in leaves. Only CONTENTS_SOLID blocks the current
    # obstruction query; other contents remain traversable until Aogera gains
    # explicit contents/mask semantics.
    class PointHull
      CONTENTS_SOLID = -2

      Trace = Data.define(
        :fraction,
        :end_position,
        :plane_normal,
        :start_solid,
        :all_solid
      ) do
        def hit?
          start_solid || fraction < 1.0
        end

        def clear?
          !hit?
        end
      end

      def self.for_model(map_data:, model:)
        unless model.headnodes.length.positive?
          raise FormatError, "BSP29 model has no hull-0 headnode"
        end

        new(
          planes: map_data.planes,
          nodes: map_data.nodes,
          leaves: map_data.leaves,
          headnode: model.headnodes.fetch(0)
        )
      end

      def self.for_world(map_data:)
        model = map_data.world_model
        raise FormatError, "BSP29 map has no world model" unless model

        for_model(map_data: map_data, model: model)
      end

      def initialize(planes:, nodes:, leaves:, headnode:)
        @planes = planes
        @nodes = nodes
        @leaves = leaves
        @headnode = Integer(headnode)
        validate_reference!(@headnode, 0)
      end

      def point_contents(position)
        contents_at(@headnode, vector(position), 0)
      end

      def trace(start_position:, end_position:)
        start_position = vector(start_position)
        end_position = vector(end_position)
        state = TraceState.new(
          fraction: 1.0,
          plane_normal: nil,
          start_solid: false,
          all_solid: true
        )

        recursive_trace(
          @headnode,
          0.0,
          1.0,
          start_position,
          end_position,
          state,
          0
        )

        fraction = [[state.fraction, 0.0].max, 1.0].min
        Trace.new(
          fraction: fraction,
          end_position: interpolate(start_position, end_position, fraction),
          plane_normal: state.plane_normal,
          start_solid: state.start_solid,
          all_solid: state.all_solid
        )
      end

      private

      TraceState = Struct.new(
        :fraction,
        :plane_normal,
        :start_solid,
        :all_solid,
        keyword_init: true
      )

      def recursive_trace(reference, start_fraction, end_fraction, start_position, end_position, state, depth)
        if reference.negative?
          contents = fetch_leaf(reference).contents
          if contents == CONTENTS_SOLID
            state.start_solid = true if start_fraction.zero?
          else
            state.all_solid = false
          end
          return true
        end

        node = fetch_node(reference, depth)
        plane = fetch_plane(node.plane_index)
        start_distance = plane_distance(plane, start_position)
        end_distance = plane_distance(plane, end_position)

        if start_distance >= 0.0 && end_distance >= 0.0
          return recursive_trace(
            node.children.fetch(0),
            start_fraction,
            end_fraction,
            start_position,
            end_position,
            state,
            depth + 1
          )
        end

        if start_distance < 0.0 && end_distance < 0.0
          return recursive_trace(
            node.children.fetch(1),
            start_fraction,
            end_fraction,
            start_position,
            end_position,
            state,
            depth + 1
          )
        end

        denominator = start_distance - end_distance
        split_fraction = denominator.zero? ? 0.0 : (start_distance / denominator)
        split_fraction = [[split_fraction, 0.0].max, 1.0].min
        middle_fraction = start_fraction + ((end_fraction - start_fraction) * split_fraction)
        middle_position = interpolate(start_position, end_position, split_fraction)
        near_side = start_distance < 0.0 ? 1 : 0
        far_side = 1 - near_side

        return false unless recursive_trace(
          node.children.fetch(near_side),
          start_fraction,
          middle_fraction,
          start_position,
          middle_position,
          state,
          depth + 1
        )

        far_child = node.children.fetch(far_side)
        unless contents_at(far_child, middle_position, depth + 1) == CONTENTS_SOLID
          return recursive_trace(
            far_child,
            middle_fraction,
            end_fraction,
            middle_position,
            end_position,
            state,
            depth + 1
          )
        end

        return false if state.all_solid

        if middle_fraction < state.fraction
          state.fraction = middle_fraction
          state.plane_normal = if far_side.zero?
            negate(plane.normal)
          else
            plane.normal
          end
        end
        false
      end

      def contents_at(reference, position, depth)
        current = reference
        current_depth = depth

        until current.negative?
          node = fetch_node(current, current_depth)
          plane = fetch_plane(node.plane_index)
          side = plane_distance(plane, position).negative? ? 1 : 0
          current = node.children.fetch(side)
          current_depth += 1
        end

        fetch_leaf(current).contents
      end

      def fetch_node(index, depth)
        if depth > @nodes.length
          raise FormatError, "BSP29 node tree contains a cycle"
        end
        if index.negative? || index >= @nodes.length
          raise FormatError, "BSP29 node index #{index} is outside the nodes lump"
        end

        @nodes.fetch(index)
      end

      def fetch_leaf(reference)
        unless reference.negative?
          raise FormatError, "BSP29 leaf reference #{reference} is not negative"
        end

        index = -reference - 1
        if index.negative? || index >= @leaves.length
          raise FormatError, "BSP29 leaf index #{index} is outside the leaves lump"
        end

        @leaves.fetch(index)
      end

      def fetch_plane(index)
        if index.negative? || index >= @planes.length
          raise FormatError, "BSP29 plane index #{index} is outside the planes lump"
        end

        @planes.fetch(index)
      end

      def validate_reference!(reference, depth)
        if reference.negative?
          fetch_leaf(reference)
        else
          fetch_node(reference, depth)
        end
      end

      def plane_distance(plane, position)
        (plane.normal.x * position.x) +
          (plane.normal.y * position.y) +
          (plane.normal.z * position.z) -
          plane.distance
      end

      def interpolate(start_position, end_position, fraction)
        Vec3.new(
          x: start_position.x + ((end_position.x - start_position.x) * fraction),
          y: start_position.y + ((end_position.y - start_position.y) * fraction),
          z: start_position.z + ((end_position.z - start_position.z) * fraction)
        )
      end

      def negate(vector)
        Vec3.new(x: -vector.x, y: -vector.y, z: -vector.z)
      end

      def vector(value)
        return value if value.is_a?(Vec3)
        unless value.respond_to?(:x) && value.respond_to?(:y) && value.respond_to?(:z)
          raise ArgumentError, "position must provide x, y, and z"
        end

        Vec3.new(x: Float(value.x), y: Float(value.y), z: Float(value.z))
      end
    end
  end
end
