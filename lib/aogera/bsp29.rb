# frozen_string_literal: true

module Aogera
  module BSP29
    VERSION = 29
    HEADER_LUMP_COUNT = 15
    HEADER_SIZE = 4 + (HEADER_LUMP_COUNT * 8)

    LUMP_NAMES = %i[
      entities
      planes
      textures
      vertices
      visibility
      nodes
      texinfo
      faces
      lighting
      clipnodes
      leaves
      marksurfaces
      edges
      surfedges
      models
    ].freeze

    FormatError = Class.new(StandardError)

    Vec3 = Data.define(:x, :y, :z)
    Bounds = Data.define(:mins, :maxs)
    Lump = Data.define(:offset, :length)

    Plane = Data.define(:normal, :distance, :type)
    Node = Data.define(:plane_index, :children, :bounds, :first_face, :face_count)
    TexInfo = Data.define(
      :s_axis,
      :s_offset,
      :t_axis,
      :t_offset,
      :texture_index,
      :flags
    )
    Face = Data.define(
      :plane_index,
      :side,
      :first_edge,
      :edge_count,
      :texinfo_index,
      :styles,
      :light_offset
    )
    ClipNode = Data.define(:plane_index, :children)
    Leaf = Data.define(
      :contents,
      :visibility_offset,
      :bounds,
      :first_marksurface,
      :marksurface_count,
      :ambient_levels
    )
    Edge = Data.define(:vertex_indices)
    Model = Data.define(
      :bounds,
      :origin,
      :headnodes,
      :visible_leaf_count,
      :first_face,
      :face_count
    )
    MipTexture = Data.define(:name, :width, :height, :mipmaps)

    Entity = Data.define(:properties, :origin) do
      def classname
        properties["classname"]
      end
    end

    MapData = Data.define(
      :entities,
      :planes,
      :textures,
      :vertices,
      :visibility,
      :nodes,
      :texinfo,
      :faces,
      :lighting,
      :clipnodes,
      :leaves,
      :marksurfaces,
      :edges,
      :surfedges,
      :models
    ) do
      def world_model
        models.first
      end

      def entities_named(classname)
        entities.select { |entity| entity.classname == classname }.freeze
      end
    end
  end
end
