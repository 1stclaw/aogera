# frozen_string_literal: true

module Aogera
  class Simulation
    class Executor
      RETIRED_COMPONENTS = %i[
        behavior collision renderable combatant interactable
      ].freeze

      def initialize(
        ground_movement: nil,
        ground_space: GroundSpace.new,
        character_ground_movement: nil,
        character_ground_space: nil
      )
        @ground_space = ground_space
        @ground_movement = ground_movement || GroundMovement.new(
          ground_space: ground_space
        )
        @character_ground_movement = character_ground_movement ||
          if character_ground_space
            GroundMovement.new(ground_space: character_ground_space)
          end
      end

      def execute(level:, world:, commands:, bindings:)
        effects = []
        commands.each do |command|
          effect = case command
          in Commands::GroundMove
            execute_ground_move(world, level, command, bindings)
          in Commands::Attack
            execute_attack(world, level, command, bindings)
          in Commands::Defeat
            execute_defeat(world, command)
          in Commands::Despawn
            execute_despawn(world, command, bindings)
          else
            raise ArgumentError, "unsupported command: #{command.inspect}"
          end
          effects << effect if effect
        end

        effects.freeze
      end

      private

      def execute_ground_move(world, level, command, bindings)
        return unless active_entity?(world, command.entity_id)

        position = world.component(command.entity_id, :position)
        return unless position

        movement = ground_movement_for(bindings, command.entity_id)
        resolved = movement.resolve(
          level: level,
          world: world,
          entity_id: command.entity_id,
          position: position,
          dx: command.dx,
          dz: command.dz
        )

        world.set_component(command.entity_id, :position, resolved)
        nil
      end

      def ground_movement_for(bindings, entity_id)
        if @character_ground_movement && bindings.bound_entity?(entity_id)
          @character_ground_movement
        else
          @ground_movement
        end
      end

      def execute_attack(world, level, command, bindings)
        return unless valid_attack?(world, level, command)

        health = world.component(command.target_id, :health)
        if health
          current = [health.current - command.damage, 0].max
          world.set_component(
            command.target_id,
            :health,
            Component::Health.new(current: current, max: health.max)
          )
          retire_entity(world, command.target_id) if current.zero?
          return nil
        end

        character_key = bindings.character_for(command.target_id)
        return unless character_key

        Effect::DamageCharacter.new(
          character_key: character_key,
          amount: command.damage
        )
      end

      def valid_attack?(world, level, command)
        return false unless command.damage.positive?
        return false unless active_entity?(world, command.attacker_id)
        return false unless active_entity?(world, command.target_id)

        attacker_health = world.component(command.attacker_id, :health)
        return false if attacker_health&.current&.zero?

        profile = world.component(command.attacker_id, :melee_attack)
        return false unless profile

        separation = @ground_space.separation(
          world: world,
          source_id: command.attacker_id,
          target_id: command.target_id
        )
        return false unless separation
        return false if separation > Float(profile.reach)

        unobstructed_attack?(
          level: level,
          world: world,
          attacker_id: command.attacker_id,
          target_id: command.target_id
        )
      end

      def unobstructed_attack?(level:, world:, attacker_id:, target_id:)
        source = @ground_space.position(world: world, entity_id: attacker_id)
        target = @ground_space.position(world: world, entity_id: target_id)
        return false unless source && target

        trace = @ground_space.trace_segment(
          level: level,
          world: world,
          start_x: source.x,
          start_z: source.z,
          end_x: target.x,
          end_z: target.z,
          ground_y: source.y,
          ignore_entity_id: attacker_id,
          entity_filter: lambda do |entity_id|
            next true if entity_id == target_id

            collision = world.component(entity_id, :collision)
            collision&.blocks_movement || false
          end
        )

        trace.clear? || trace.entity_id == target_id
      end

      def execute_defeat(world, command)
        return unless world.entity?(command.entity_id)
        return if world.retired?(command.entity_id)

        health = world.component(command.entity_id, :health)
        return unless health&.current&.zero?

        retire_entity(world, command.entity_id)
        nil
      end

      def retire_entity(world, entity_id)
        world.set_component(entity_id, :retired, Component::Retired.new)
        RETIRED_COMPONENTS.each do |name|
          world.remove_component(entity_id, name)
        end
      end

      def active_entity?(world, entity_id)
        world.entity?(entity_id) && !world.retired?(entity_id)
      end

      def execute_despawn(world, command, bindings)
        return unless world.entity?(command.entity_id)

        if bindings.bound_entity?(command.entity_id)
          raise ArgumentError,
            "cannot despawn bound character entity: #{command.entity_id.inspect}"
        end

        world.despawn(command.entity_id)
        nil
      end
    end
  end
end
