# frozen_string_literal: true

module Aogera
  class Simulation
    StepResult = Data.define(:number, :effects)

    attr_reader :level, :step_number

    def initialize(level:, prototypes:)
      @level = level
      @prototypes = prototypes
      @world = World.new
      @bindings = Bindings.new
      @step_number = 0
      @executor = Executor.new
      @reference_ids = {}

      instantiate_spawns
      resolve_relations
    end

    def step(commands:)
      effects = @executor.execute(
        level: level,
        world: @world,
        commands: commands,
        bindings: @bindings
      )

      @step_number += 1
      StepResult.new(number: @step_number, effects: effects)
    end

    def spawn_character(character_key:, prototype:, entry: level.default_entry)
      key = character_key.to_sym
      if @bindings.bound_character?(key)
        raise ArgumentError, "character already spawned: #{key.inspect}"
      end

      entry_definition = level.entry(entry)
      prototype_definition = @prototypes.fetch(prototype)

      if prototype_definition.components.key?(:health)
        raise ArgumentError,
          "persistent character prototype must not define local Health"
      end

      if @reference_ids.key?(entry_definition.key)
        raise ArgumentError,
          "level entry already occupied: #{entry_definition.key.inspect}"
      end

      extra = {
        ground_position: Component::GroundPosition.new(
          x: entry_definition.x + 0.5,
          z: entry_definition.y + 0.5
        )
      }
      if entry_definition.facing
        extra[:facing] = Component::Facing.new(direction: entry_definition.facing)
      end

      entity_id = instantiate(
        prototype_definition,
        x: entry_definition.x,
        y: entry_definition.y,
        extra_components: extra
      )

      @bindings.bind(character_key: key, entity_id: entity_id)
      @reference_ids[entry_definition.key] = entity_id
      resolve_relations
      entity_id
    end

    def entity_id_for_character(character_key)
      @bindings.entity_for(character_key)
    end

    def character_key_for_entity(entity_id)
      @bindings.character_for(entity_id)
    end

    def entity_id_for_spawn(spawn_key)
      @reference_ids.fetch(spawn_key)
    end

    def world_view
      @world.view
    end

    private

    def instantiate_spawns
      level.spawns.each do |spawn|
        prototype = @prototypes.fetch(spawn.prototype)
        @reference_ids[spawn.key] = instantiate(
          prototype,
          x: spawn.x,
          y: spawn.y
        )
      end
    end

    def instantiate(prototype, x:, y:, extra_components: {})
      components = prototype.components.merge(
        prototype_ref: Component::PrototypeRef.new(name: prototype.name),
        position: Component::Position.new(x: x, y: y)
      ).merge(extra_components)

      @world.spawn(**components)
    end

    def resolve_relations
      level.relations.each do |relation|
        source_id = @reference_ids[relation.source]
        target_id = @reference_ids[relation.target]
        next unless source_id && target_id

        @world.add_relation(
          kind: relation.kind,
          source_id: source_id,
          target_id: target_id
        )
      end
    end
  end
end
