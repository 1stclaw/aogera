# frozen_string_literal: true

module Aogera
  class Level
    module Loader
      module_function

      def load(path, prototypes:)
        absolute_path = Content::RubySource.absolute_path(path, kind: :level)
        require absolute_path

        definition_name = Content::RubySource.constant_name_for(absolute_path)
        definition = Definitions.const_get(definition_name, false)

        terrain = Terrain.new(rows: definition.rows, tiles: definition.tiles)

        validate_spawns!(terrain, definition.spawns, prototypes)
        validate_entries!(terrain, definition.entries)
        validate_reference_keys!(definition.spawns, definition.entries)
        validate_default_entry!(definition.default_entry, definition.entries)
        validate_relations!(definition.relations, definition.spawns, definition.entries)

        Level.new(
          name: definition.name,
          terrain: terrain,
          spawns: definition.spawns,
          entries: definition.entries,
          relations: definition.relations,
          default_entry: definition.default_entry
        )
      end

      def validate_spawns!(terrain, spawns, prototypes)
        spawns.each do |spawn|
          prototypes.fetch(spawn.prototype)
          validate_position!(terrain, spawn.x, spawn.y, "#{spawn.prototype} spawn")
        end
      end
      private_class_method :validate_spawns!

      def validate_entries!(terrain, entries)
        entries.each do |entry|
          validate_position!(terrain, entry.x, entry.y, "#{entry.key} entry")
        end
      end
      private_class_method :validate_entries!

      def validate_reference_keys!(spawns, entries)
        keys = (spawns.map(&:key) + entries.map(&:key))
        duplicate = keys.group_by(&:itself).find { |_key, values| values.length > 1 }&.first
        return unless duplicate

        raise ArgumentError, "duplicate level reference key: #{duplicate.inspect}"
      end
      private_class_method :validate_reference_keys!

      def validate_default_entry!(default_entry, entries)
        return if default_entry.nil?
        return if entries.any? { |entry| entry.key == default_entry }

        raise ArgumentError, "unknown default entry: #{default_entry.inspect}"
      end
      private_class_method :validate_default_entry!

      def validate_relations!(relations, spawns, entries)
        keys = spawns.map(&:key) + entries.map(&:key)
        relations.each do |relation|
          unless keys.include?(relation.source)
            raise ArgumentError, "unknown relation source: #{relation.source.inspect}"
          end
          unless keys.include?(relation.target)
            raise ArgumentError, "unknown relation target: #{relation.target.inspect}"
          end
        end
      end
      private_class_method :validate_relations!

      def validate_position!(terrain, x, y, label)
        unless terrain.inside?(x, y)
          raise ArgumentError, "#{label} is outside the terrain at (#{x}, #{y})"
        end
        return if terrain.passable?(x, y)

        raise ArgumentError, "#{label} is on blocked terrain at (#{x}, #{y})"
      end
      private_class_method :validate_position!
    end
  end
end
