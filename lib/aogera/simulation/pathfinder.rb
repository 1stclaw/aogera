# frozen_string_literal: true

module Aogera
  class Simulation
    class Pathfinder
      DIRECTIONS = Direction::VECTORS

      def next_step(level:, world:, source_id:, target_id:)
        source = world.component(source_id, :position)
        target = world.component(target_id, :position)
        return unless source && target

        start = cell_for(source)
        target_cell = cell_for(target)
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

      def cell_for(position)
        [position.x.floor, position.z.floor].freeze
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

      def search(level:, world:, source_id:, start:, target_cell:, goals:)
        queue = [start]
        head = 0
        parents = { start => nil }

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
          position && position.x.floor == x && position.z.floor == z
        end
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
