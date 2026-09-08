# frozen_string_literal: true

module Aogera
  class Level
    module Loader
      module_function

      def load(authored_data, prototypes:)
        unless authored_data.is_a?(AuthoredData)
          raise ArgumentError, "Level::Loader expects normalized Level::AuthoredData"
        end

        terrain = authored_data.terrain
        validate_spawns!(terrain, authored_data.spawns, prototypes)
        validate_entries!(terrain, authored_data.entries)
        validate_reference_keys!(authored_data.spawns, authored_data.entries)
        validate_default_entry!(authored_data.default_entry, authored_data.entries)
        validate_relations!(authored_data.relations, authored_data.spawns, authored_data.entries)

        Level.new(
          name: authored_data.name,
          terrain: terrain,
          spawns: authored_data.spawns,
          entries: authored_data.entries,
          relations: authored_data.relations,
          default_entry: authored_data.default_entry
        )
      end

      def validate_spawns!(terrain, spawns, prototypes)
        spawns.each do |spawn|
          prototypes.fetch(spawn.prototype)
          validate_position!(terrain, spawn.x, spawn.z, "#{spawn.prototype} spawn")
        end
      end
      private_class_method :validate_spawns!

      def validate_entries!(terrain, entries)
        entries.each do |entry|
          validate_position!(terrain, entry.x, entry.z, "#{entry.key} entry")
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

      def validate_position!(terrain, x, z, label)
        grid_x, grid_z = terrain.cell_for_world(x, z)
        unless terrain.inside?(grid_x, grid_z)
          raise ArgumentError,
            "#{label} is outside the terrain at world position (#{x}, #{z})"
        end
        return if terrain.passable?(grid_x, grid_z)

        raise ArgumentError,
          "#{label} is on blocked terrain at world position (#{x}, #{z})"
      end
      private_class_method :validate_position!
    end
  end
end
