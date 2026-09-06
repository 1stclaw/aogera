# frozen_string_literal: true

module Aogera
  class Simulation
    class Pathfinder
      DIRECTIONS = Direction::VECTORS


      def initialize(movement: Movement.new)
        @movement = movement
      end

      def next_step(level:, world:, source_id:, target_id:)
        source = world.component(source_id, :position)
        target = world.component(target_id, :position)
        return unless source && target

        start = [source.x, source.y].freeze
        goals = adjacent_goals(
          level: level,
          world: world,
          source_id: source_id,
          target: target
        )
        return if goals.empty? || goals.key?(start)

        first_step = search(
          level: level,
          world: world,
          source_id: source_id,
          start: start,
          target: target,
          goals: goals
        )
        return unless first_step

        [
          first_step[0] - source.x,
          first_step[1] - source.y
        ]
      end

      private

      def adjacent_goals(level:, world:, source_id:, target:)
        DIRECTIONS.each_with_object({}) do |(dx, dy), goals|
          x = target.x + dx
          y = target.y + dy

          next unless @movement.traversable?(
            level: level,
            world: world,
            x: x,
            y: y,
            except_id: source_id
          )

          goals[[x, y].freeze] = true
        end
      end

      def search(level:, world:, source_id:, start:, target:, goals:)
        queue = [start]
        head = 0
        parents = { start => nil }

        while head < queue.length
          current = queue[head]
          head += 1

          return first_step(parents, current, start) if goals.key?(current)

          ordered_directions(current, target).each do |dx, dy|
            neighbor = [current[0] + dx, current[1] + dy].freeze

            next if parents.key?(neighbor)
            next unless @movement.traversable?(
              level: level,
              world: world,
              x: neighbor[0],
              y: neighbor[1],
              except_id: source_id
            )

            parents[neighbor] = current
            queue << neighbor
          end
        end

        nil
      end

      def ordered_directions(position, target)
        DIRECTIONS.sort_by.with_index do |(dx, dy), index|
          x = position[0] + dx
          y = position[1] + dy
          distance = (target.x - x).abs + (target.y - y).abs

          [distance, index]
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
