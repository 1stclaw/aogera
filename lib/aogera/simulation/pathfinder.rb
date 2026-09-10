# frozen_string_literal: true

module Aogera
  class Simulation
    class Pathfinder
      DIRECTIONS = Direction::VECTORS

      def initialize(ground_clearance: nil)
        @ground_clearance = ground_clearance
      end

      def next_step(level:, world:, source_id:, target_id:)
        source = world.component(source_id, :position)
        target = world.component(target_id, :position)
        return unless source && target

        start = cell_for(level, source)
        target_cell = cell_for(level, target)
        goals = adjacent_goals(
          level: level,
          world: world,
          source_id: source_id,
          target_cell: target_cell
        )
        return if goals.empty?
        return [0, 0] if goals.key?(start)

        first_step = search(
          level: level,
          world: world,
          source_id: source_id,
          source: source,
          start: start,
          target_cell: target_cell,
          goals: goals
        )
        return unless first_step

        [
          first_step[0] - start[0],
          first_step[1] - start[1]
        ]
      end

      private

      def cell_for(level, position)
        level.cell_for_world(position.x, position.z)
      end

      def adjacent_goals(level:, world:, source_id:, target_cell:)
        DIRECTIONS.each_with_object({}) do |(dx, dz), goals|
          x = target_cell[0] + dx
          z = target_cell[1] + dz

          next unless cell_traversable?(
            level: level,
            world: world,
            x: x,
            z: z,
            except_id: source_id
          )

          goals[[x, z].freeze] = true
        end
      end

      def search(level:, world:, source_id:, source:, start:, target_cell:, goals:)
        queue = [start]
        head = 0
        parents = { start => nil }
        ground_body = world.component(source_id, :ground_body)

        while head < queue.length
          current = queue[head]
          head += 1

          return first_step(parents, current, start) if goals.key?(current)

          ordered_directions(current, target_cell).each do |dx, dz|
            neighbor = [current[0] + dx, current[1] + dz].freeze

            next if parents.key?(neighbor)
            next unless cell_traversable?(
              level: level,
              world: world,
              x: neighbor[0],
              z: neighbor[1],
              except_id: source_id
            )
            next unless transition_clear?(
              level: level,
              from: current,
              to: neighbor,
              feet_y: source.y,
              ground_body: ground_body
            )

            parents[neighbor] = current
            queue << neighbor
          end
        end

        nil
      end

      def ordered_directions(position, target_cell)
        DIRECTIONS.sort_by.with_index do |(dx, dz), index|
          x = position[0] + dx
          z = position[1] + dz
          distance = (target_cell[0] - x).abs + (target_cell[1] - z).abs

          [distance, index]
        end
      end

      def cell_traversable?(level:, world:, x:, z:, except_id: nil)
        return false unless level.passable?(x, z)

        world.entity_ids.none? do |entity_id|
          next false if entity_id == except_id
          next false if world.respond_to?(:retired?) && world.retired?(entity_id)

          collision = world.component(entity_id, :collision)
          next false unless collision&.blocks_movement

          position = world.component(entity_id, :position)
          next false unless position

          cell_x, cell_z = level.cell_for_world(position.x, position.z)
          cell_x == x && cell_z == z
        end
      end

      def transition_clear?(level:, from:, to:, feet_y:, ground_body:)
        return true unless @ground_clearance
        return false unless ground_body&.radius&.positive?

        start_x, start_z = level.cell_center(from[0], from[1])
        end_x, end_z = level.cell_center(to[0], to[1])
        @ground_clearance.clear?(
          start_x: start_x,
          start_z: start_z,
          end_x: end_x,
          end_z: end_z,
          feet_y: feet_y,
          ground_body_radius: ground_body.radius
        )
      end

      def first_step(parents, goal, start)
        step = goal

        while parents[step] && parents[step] != start
          step = parents[step]
        end

        step == start ? nil : step
      end
    end
  end
end
