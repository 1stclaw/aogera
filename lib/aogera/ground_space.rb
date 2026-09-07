# frozen_string_literal: true

module Aogera
  class GroundSpace
    ArcHit = Data.define(:entity_id, :separation, :alignment)

    def position(world:, entity_id:)
      ground = world.component(entity_id, :ground_position)
      return ground if ground

      grid = world.component(entity_id, :position)
      return unless grid

      Component::GroundPosition.new(
        x: grid.x + 0.5,
        z: grid.y + 0.5
      )
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

    private

    def normalize(x, z)
      length = Math.hypot(x, z)
      raise ArgumentError, "forward vector must not be zero" if length.zero?

      [x / length, z / length]
    end
  end
end
