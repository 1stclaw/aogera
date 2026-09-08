# frozen_string_literal: true

module Aogera
  class Level
    module Readers
      module Ruby
        module_function

        def read(path)
          absolute_path = Content::RubySource.absolute_path(path, kind: :level)
          require absolute_path

          definition_name = Content::RubySource.constant_name_for(absolute_path)
          definition = Definitions.const_get(definition_name, false)
          terrain = Terrain.new(
            rows: definition.rows,
            tiles: definition.tiles,
            cell_size: WorldUnits::GRID_CELL_SIZE
          )

          AuthoredData.new(
            name: definition.name,
            terrain: terrain,
            spawns: definition.spawns.map { |spawn| normalize_spawn(spawn, terrain) }.freeze,
            entries: definition.entries.map { |entry| normalize_entry(entry, terrain) }.freeze,
            relations: definition.relations,
            default_entry: definition.default_entry
          )
        end

        def normalize_spawn(spawn, terrain)
          x, z = terrain.cell_center(spawn.x, spawn.y)
          AuthoredSpawn.new(
            key: spawn.key,
            prototype: spawn.prototype,
            x: x,
            y: 0.0,
            z: z
          )
        end
        private_class_method :normalize_spawn

        def normalize_entry(entry, terrain)
          x, z = terrain.cell_center(entry.x, entry.y)
          AuthoredEntry.new(
            key: entry.key,
            x: x,
            y: 0.0,
            z: z,
            facing: entry.facing
          )
        end
        private_class_method :normalize_entry
      end
    end
  end
end
