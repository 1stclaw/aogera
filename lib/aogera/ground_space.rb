# frozen_string_literal: true

module Aogera
  class GroundSpace
    ArcHit = Data.define(:entity_id, :separation, :alignment)

    EPSILON = 1e-9
    BSP29_OBSTRUCTION_HEIGHT = 16.0

    def initialize(bsp29_ground_hull: nil, bsp29_point_hull: nil)
      @bsp29_ground_hull = bsp29_ground_hull
      @bsp29_point_hull = bsp29_point_hull
    end

    def position(world:, entity_id:)
      world.component(entity_id, :position)
    end

    def radius(world:, entity_id:)
      body = world.component(entity_id, :ground_body)
      return 0.0 unless body

      Float(body.radius)
    end

    def center_distance(world:, source_id:, target_id:)
      source = position(world: world, entity_id: source_id)
      target = position(world: world, entity_id: target_id)
      return unless source && target

      Math.hypot(target.x - source.x, target.z - source.z)
    end

    def separation(world:, source_id:, target_id:)
      distance = center_distance(
        world: world,
        source_id: source_id,
        target_id: target_id
      )
      return unless distance

      [
        distance - radius(world: world, entity_id: source_id) -
          radius(world: world, entity_id: target_id),
        0.0
      ].max
    end

    def overlaps_entity?(world:, x:, z:, radius:, other_id:)
      other_position = position(world: world, entity_id: other_id)
      return false unless other_position

      other_radius = self.radius(world: world, entity_id: other_id)
      return false unless other_radius.positive?

      Math.hypot(
        other_position.x - Float(x),
        other_position.z - Float(z)
      ) < (Float(radius) + other_radius)
    end

    def arc_hits(
      world:,
      source_id:,
      target_ids:,
      forward_x:,
      forward_z:,
      reach:,
      arc_degrees:
    )
      return [].freeze if retired_entity?(world, source_id)

      source = position(world: world, entity_id: source_id)
      return [].freeze unless source

      reach = Float(reach)
      arc_degrees = Float(arc_degrees)
      raise ArgumentError, "reach must not be negative" if reach.negative?
      unless arc_degrees.positive? && arc_degrees <= 360.0
        raise ArgumentError, "arc_degrees must be greater than 0 and at most 360"
      end

      forward_x, forward_z = normalize(Float(forward_x), Float(forward_z))
      minimum_alignment = Math.cos((arc_degrees * Math::PI / 180.0) / 2.0)

      target_ids.filter_map do |target_id|
        next if target_id == source_id
        next if retired_entity?(world, target_id)

        target = position(world: world, entity_id: target_id)
        next unless target

        dx = target.x - source.x
        dz = target.z - source.z
        center_distance = Math.hypot(dx, dz)
        alignment = if center_distance.zero?
          1.0
        else
          ((dx / center_distance) * forward_x) +
            ((dz / center_distance) * forward_z)
        end
        next if alignment < minimum_alignment

        target_separation = [
          center_distance - radius(world: world, entity_id: source_id) -
            radius(world: world, entity_id: target_id),
          0.0
        ].max
        next if target_separation > reach

        ArcHit.new(
          entity_id: target_id,
          separation: target_separation,
          alignment: alignment
        )
      end.freeze
    end

    def unobstructed_between?(level:, world:, source_id:, target_id:)
      source = position(world: world, entity_id: source_id)
      target = position(world: world, entity_id: target_id)
      return false unless source && target

      trace = trace_segment(
        level: level,
        world: world,
        start_x: source.x,
        start_z: source.z,
        end_x: target.x,
        end_z: target.z,
        ground_y: source.y,
        ignore_entity_id: source_id,
        entity_filter: lambda do |entity_id|
          next true if entity_id == target_id

          collision = world.component(entity_id, :collision)
          collision&.blocks_movement || false
        end
      )

      trace.clear? || trace.entity_id == target_id
    end

    def trace_segment(
      level:,
      world:,
      start_x:,
      start_z:,
      end_x:,
      end_z:,
      ground_y: 0.0,
      ignore_entity_id: nil,
      entity_filter: nil
    )
      trace(
        level: level,
        world: world,
        start_x: start_x,
        start_z: start_z,
        end_x: end_x,
        end_z: end_z,
        radius: 0.0,
        ground_y: ground_y,
        ignore_entity_id: ignore_entity_id,
        entity_filter: entity_filter
      )
    end

    def sweep_circle(
      level:,
      world:,
      start_x:,
      start_z:,
      end_x:,
      end_z:,
      radius:,
      ground_y: 0.0,
      ignore_entity_id: nil,
      entity_filter: nil
    )
      radius = Float(radius)
      raise ArgumentError, "radius must be positive" unless radius.positive?

      trace(
        level: level,
        world: world,
        start_x: start_x,
        start_z: start_z,
        end_x: end_x,
        end_z: end_z,
        radius: radius,
        ground_y: ground_y,
        ignore_entity_id: ignore_entity_id,
        entity_filter: entity_filter
      )
    end

    private

    Hit = Data.define(:fraction, :normal_x, :normal_z, :entity_id, :world_hit, :start_blocked)

    def trace(
      level:,
      world:,
      start_x:,
      start_z:,
      end_x:,
      end_z:,
      radius:,
      ground_y:,
      ignore_entity_id:,
      entity_filter:
    )
      start_x = Float(start_x)
      start_z = Float(start_z)
      end_x = Float(end_x)
      end_z = Float(end_z)
      radius = Float(radius)
      ground_y = Float(ground_y)
      dx = end_x - start_x
      dz = end_z - start_z

      hit = earliest_hit(
        terrain_hit(
          level: level,
          start_x: start_x,
          start_z: start_z,
          dx: dx,
          dz: dz,
          radius: radius,
          ground_y: ground_y
        ),
        entity_hit(
          world: world,
          start_x: start_x,
          start_z: start_z,
          dx: dx,
          dz: dz,
          radius: radius,
          ignore_entity_id: ignore_entity_id,
          entity_filter: entity_filter
        )
      )

      return clear_trace(end_x, end_z) unless hit

      fraction = [[hit.fraction, 0.0].max, 1.0].min
      contact_x = start_x + (dx * fraction)
      contact_z = start_z + (dz * fraction)

      GroundTrace.new(
        fraction: fraction,
        end_x: contact_x,
        end_z: contact_z,
        normal_x: hit.normal_x,
        normal_z: hit.normal_z,
        entity_id: hit.entity_id,
        world_hit: hit.world_hit,
        start_blocked: hit.start_blocked
      )
    end

    def clear_trace(end_x, end_z)
      GroundTrace.new(
        fraction: 1.0,
        end_x: end_x,
        end_z: end_z,
        normal_x: 0.0,
        normal_z: 0.0,
        entity_id: nil,
        world_hit: false,
        start_blocked: false
      )
    end

    def earliest_hit(*hits)
      hits.compact.min_by do |hit|
        [hit.fraction, hit.world_hit ? 0 : 1, hit.entity_id || -1]
      end
    end

    def terrain_hit(level:, start_x:, start_z:, dx:, dz:, radius:, ground_y:)
      if @bsp29_point_hull && radius.zero?
        return bsp29_point_hit(
          start_x: start_x,
          start_z: start_z,
          dx: dx,
          dz: dz,
          ground_y: ground_y
        )
      end

      if @bsp29_ground_hull && radius.positive?
        return bsp29_ground_hit(
          start_x: start_x,
          start_z: start_z,
          dx: dx,
          dz: dz,
          radius: radius,
          ground_y: ground_y
        )
      end

      grid_terrain_hit(
        level: level,
        start_x: start_x,
        start_z: start_z,
        dx: dx,
        dz: dz,
        radius: radius
      )
    end

    def bsp29_point_hit(start_x:, start_z:, dx:, dz:, ground_y:)
      trace_y = ground_y + BSP29_OBSTRUCTION_HEIGHT
      trace = @bsp29_point_hull.trace(
        start_position: BSP29::Vec3.new(
          x: start_x,
          y: trace_y,
          z: start_z
        ),
        end_position: BSP29::Vec3.new(
          x: start_x + dx,
          y: trace_y,
          z: start_z + dz
        )
      )
      return unless trace.hit?

      normal = trace.plane_normal
      Hit.new(
        fraction: trace.start_solid ? 0.0 : trace.fraction,
        normal_x: normal ? normal.x : 0.0,
        normal_z: normal ? normal.z : 0.0,
        entity_id: nil,
        world_hit: true,
        start_blocked: trace.start_solid
      )
    end

    def bsp29_ground_hit(start_x:, start_z:, dx:, dz:, radius:, ground_y:)
      trace = @bsp29_ground_hull.trace(
        start_x: start_x,
        start_z: start_z,
        end_x: start_x + dx,
        end_z: start_z + dz,
        feet_y: ground_y,
        ground_body_radius: radius
      )
      return unless trace.hit?

      normal = trace.plane_normal
      Hit.new(
        fraction: trace.start_solid ? 0.0 : trace.fraction,
        normal_x: normal ? normal.x : 0.0,
        normal_z: normal ? normal.z : 0.0,
        entity_id: nil,
        world_hit: true,
        start_blocked: trace.start_solid
      )
    end

    def grid_terrain_hit(level:, start_x:, start_z:, dx:, dz:, radius:)
      min_grid_x, min_grid_z = level.cell_for_world(
        [start_x, start_x + dx].min - radius,
        [start_z, start_z + dz].min - radius
      )
      max_grid_x, max_grid_z = level.cell_for_world(
        [start_x, start_x + dx].max + radius,
        [start_z, start_z + dz].max + radius
      )

      best = nil
      (min_grid_z..max_grid_z).each do |grid_z|
        (min_grid_x..max_grid_x).each do |grid_x|
          next if level.passable?(grid_x, grid_z)

          cell_min_x, cell_min_z, cell_max_x, cell_max_z =
            level.cell_bounds(grid_x, grid_z)

          hit = if radius.zero?
            segment_aabb_hit(
              start_x: start_x,
              start_z: start_z,
              dx: dx,
              dz: dz,
              min_x: cell_min_x,
              min_z: cell_min_z,
              max_x: cell_max_x,
              max_z: cell_max_z
            )
          else
            swept_circle_cell_hit(
              start_x: start_x,
              start_z: start_z,
              dx: dx,
              dz: dz,
              radius: radius,
              min_x: cell_min_x,
              min_z: cell_min_z,
              max_x: cell_max_x,
              max_z: cell_max_z
            )
          end
          next unless hit

          world_hit = Hit.new(
            fraction: hit.fraction,
            normal_x: hit.normal_x,
            normal_z: hit.normal_z,
            entity_id: nil,
            world_hit: true,
            start_blocked: hit.start_blocked
          )
          best = earliest_hit(best, world_hit)
        end
      end
      best
    end

    def entity_hit(
      world:,
      start_x:,
      start_z:,
      dx:,
      dz:,
      radius:,
      ignore_entity_id:,
      entity_filter:
    )
      best = nil
      world.entity_ids.each do |entity_id|
        next if entity_id == ignore_entity_id
        next if retired_entity?(world, entity_id)
        next if entity_filter && !entity_filter.call(entity_id)

        other_position = position(world: world, entity_id: entity_id)
        next unless other_position

        other_radius = self.radius(world: world, entity_id: entity_id)
        next unless other_radius.positive?

        hit = segment_circle_hit(
          start_x: start_x,
          start_z: start_z,
          dx: dx,
          dz: dz,
          center_x: other_position.x,
          center_z: other_position.z,
          radius: radius + other_radius
        )
        next unless hit

        dynamic_hit = Hit.new(
          fraction: hit.fraction,
          normal_x: hit.normal_x,
          normal_z: hit.normal_z,
          entity_id: entity_id,
          world_hit: false,
          start_blocked: hit.start_blocked
        )
        best = earliest_hit(best, dynamic_hit)
      end
      best
    end

    def retired_entity?(world, entity_id)
      world.respond_to?(:retired?) && world.retired?(entity_id)
    end

    def segment_aabb_hit(start_x:, start_z:, dx:, dz:, min_x:, min_z:, max_x:, max_z:)
      if point_inside_aabb?(start_x, start_z, min_x, min_z, max_x, max_z)
        return local_hit(0.0, 0.0, 0.0, true)
      end

      x = slab(start_x, dx, min_x, max_x, -1.0, 0.0, 1.0, 0.0)
      z = slab(start_z, dz, min_z, max_z, 0.0, -1.0, 0.0, 1.0)
      return unless x && z

      enter = [x[:enter], z[:enter], 0.0].max
      exit = [x[:exit], z[:exit], 1.0].min
      return if enter - exit > EPSILON
      return if exit < -EPSILON || enter > 1.0 + EPSILON

      normal_x, normal_z = if x[:enter] > z[:enter] + EPSILON
        x[:normal]
      elsif z[:enter] > x[:enter] + EPSILON
        z[:normal]
      else
        normalize_or_zero(x[:normal][0] + z[:normal][0], x[:normal][1] + z[:normal][1])
      end

      local_hit([[enter, 0.0].max, 1.0].min, normal_x, normal_z, false)
    end

    def slab(start, delta, minimum, maximum, min_normal_x, min_normal_z, max_normal_x, max_normal_z)
      if delta.abs <= EPSILON
        return if start < minimum - EPSILON || start > maximum + EPSILON

        return { enter: -Float::INFINITY, exit: Float::INFINITY, normal: [0.0, 0.0] }
      end

      first = (minimum - start) / delta
      second = (maximum - start) / delta
      if first <= second
        { enter: first, exit: second, normal: [min_normal_x, min_normal_z] }
      else
        { enter: second, exit: first, normal: [max_normal_x, max_normal_z] }
      end
    end

    def swept_circle_cell_hit(
      start_x:,
      start_z:,
      dx:,
      dz:,
      radius:,
      min_x:,
      min_z:,
      max_x:,
      max_z:
    )
      if circle_overlaps_aabb?(start_x, start_z, radius, min_x, min_z, max_x, max_z)
        return local_hit(0.0, 0.0, 0.0, true)
      end

      hits = []

      if dx > EPSILON
        t = ((min_x - radius) - start_x) / dx
        z = start_z + (dz * t)
        hits << local_hit(t, -1.0, 0.0, false) if valid_fraction?(t) && z.between?(min_z - EPSILON, max_z + EPSILON)
      elsif dx < -EPSILON
        t = ((max_x + radius) - start_x) / dx
        z = start_z + (dz * t)
        hits << local_hit(t, 1.0, 0.0, false) if valid_fraction?(t) && z.between?(min_z - EPSILON, max_z + EPSILON)
      end

      if dz > EPSILON
        t = ((min_z - radius) - start_z) / dz
        x = start_x + (dx * t)
        hits << local_hit(t, 0.0, -1.0, false) if valid_fraction?(t) && x.between?(min_x - EPSILON, max_x + EPSILON)
      elsif dz < -EPSILON
        t = ((max_z + radius) - start_z) / dz
        x = start_x + (dx * t)
        hits << local_hit(t, 0.0, 1.0, false) if valid_fraction?(t) && x.between?(min_x - EPSILON, max_x + EPSILON)
      end

      corners = [
        [min_x, min_z, -1, -1],
        [max_x, min_z, 1, -1],
        [min_x, max_z, -1, 1],
        [max_x, max_z, 1, 1]
      ]
      corners.each do |corner_x, corner_z, side_x, side_z|
        hit = segment_circle_hit(
          start_x: start_x,
          start_z: start_z,
          dx: dx,
          dz: dz,
          center_x: corner_x,
          center_z: corner_z,
          radius: radius
        )
        next unless hit

        hit_x = start_x + (dx * hit.fraction)
        hit_z = start_z + (dz * hit.fraction)
        next unless ((hit_x - corner_x) * side_x) >= -EPSILON
        next unless ((hit_z - corner_z) * side_z) >= -EPSILON

        hits << hit
      end

      hits.compact.min_by(&:fraction)
    end

    def segment_circle_hit(start_x:, start_z:, dx:, dz:, center_x:, center_z:, radius:)
      mx = start_x - center_x
      mz = start_z - center_z
      radius_squared = radius * radius
      distance_squared = (mx * mx) + (mz * mz)

      if distance_squared < radius_squared - EPSILON
        normal_x, normal_z = normalize_or_zero(mx, mz)
        return local_hit(0.0, normal_x, normal_z, true)
      end

      a = (dx * dx) + (dz * dz)
      return if a <= EPSILON

      b = (mx * dx) + (mz * dz)
      c = distance_squared - radius_squared

      if c.abs <= EPSILON && b >= -EPSILON
        return
      end

      discriminant = (b * b) - (a * c)
      return if discriminant < -EPSILON

      discriminant = [discriminant, 0.0].max
      t = (-b - Math.sqrt(discriminant)) / a
      return unless valid_fraction?(t)

      hit_x = start_x + (dx * t)
      hit_z = start_z + (dz * t)
      normal_x, normal_z = normalize_or_zero(hit_x - center_x, hit_z - center_z)
      local_hit(t, normal_x, normal_z, false)
    end

    def point_inside_aabb?(x, z, min_x, min_z, max_x, max_z)
      x > min_x + EPSILON && x < max_x - EPSILON &&
        z > min_z + EPSILON && z < max_z - EPSILON
    end

    def circle_overlaps_aabb?(x, z, radius, min_x, min_z, max_x, max_z)
      nearest_x = [[x, min_x].max, max_x].min
      nearest_z = [[z, min_z].max, max_z].min
      dx = x - nearest_x
      dz = z - nearest_z
      ((dx * dx) + (dz * dz)) < ((radius * radius) - EPSILON)
    end

    def valid_fraction?(fraction)
      fraction >= -EPSILON && fraction <= 1.0 + EPSILON
    end

    def local_hit(fraction, normal_x, normal_z, start_blocked)
      Hit.new(
        fraction: [[fraction, 0.0].max, 1.0].min,
        normal_x: normal_x,
        normal_z: normal_z,
        entity_id: nil,
        world_hit: false,
        start_blocked: start_blocked
      )
    end

    def normalize_or_zero(x, z)
      length = Math.hypot(x, z)
      return [0.0, 0.0] if length <= EPSILON

      [x / length, z / length]
    end

    def normalize(x, z)
      length = Math.hypot(x, z)
      raise ArgumentError, "forward vector must not be zero" if length.zero?

      [x / length, z / length]
    end
  end
end
