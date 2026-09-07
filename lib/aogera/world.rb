# frozen_string_literal: true

module Aogera
  class World
    def initialize
      @next_entity_id = 0
      @active_entities = []
      @entity_ids = [].freeze
      @entity_ids_dirty = false
      @component_tables = {}
      @relations = Relations.new
      @view = View.new(self)
    end

    def spawn(**components)
      entity_id = @next_entity_id
      @next_entity_id += 1
      @active_entities[entity_id] = true
      @entity_ids_dirty = true

      components.each do |name, component|
        set_component(entity_id, name, component)
      end

      entity_id
    end

    def despawn(entity_id)
      validate_entity!(entity_id)

      @component_tables.each_value do |table|
        table.delete(entity_id)
      end
      @relations.remove_entity(entity_id)
      @active_entities[entity_id] = false
      @entity_ids_dirty = true

      entity_id
    end

    def entity?(entity_id)
      entity_id.is_a?(Integer) &&
        entity_id >= 0 &&
        entity_id < @next_entity_id &&
        @active_entities[entity_id] == true
    end

    def entity_ids
      return @entity_ids unless @entity_ids_dirty

      @entity_ids = @active_entities.each_index.select do |entity_id|
        @active_entities[entity_id]
      end.freeze
      @entity_ids_dirty = false
      @entity_ids
    end

    def component(entity_id, name)
      validate_entity!(entity_id)
      @component_tables[name]&.[](entity_id)
    end

    def set_component(entity_id, name, component)
      validate_entity!(entity_id)
      table_for(name)[entity_id] = component
    end

    def remove_component(entity_id, name)
      validate_entity!(entity_id)
      @component_tables[name]&.delete(entity_id)
    end

    def add_relation(kind:, source_id:, target_id:)
      validate_entity!(source_id)
      validate_entity!(target_id)

      @relations.add(kind: kind, source_id: source_id, target_id: target_id)
    end

    def relation_targets(kind:, source_id:)
      validate_entity!(source_id)
      @relations.targets(kind: kind, source_id: source_id)
    end

    def view
      @view
    end

    private

    def table_for(name)
      @component_tables[name] ||= ComponentTable.new
    end

    def validate_entity!(entity_id)
      return if entity?(entity_id)

      raise ArgumentError, "unknown entity_id: #{entity_id.inspect}"
    end
  end
end
