# frozen_string_literal: true

module Aogera
  class Simulation
    class Executor
      RETIRED_COMPONENTS = %i[
        behavior collision renderable combatant interactable
      ].freeze

      def initialize(movement: Movement.new)
        @movement = movement
      end

      def execute(level:, world:, commands:, bindings:)
        effects = []

        commands.each do |command|
          effect = case command
          in Commands::Move
            execute_move(world, level, command)
          in Commands::Attack
            execute_attack(world, command, bindings)
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

      def execute_move(world, level, command)
        return unless world.entity?(command.entity_id)

        position = world.component(command.entity_id, :position)
        return unless position

        update_facing(world, command)
        next_x = position.x + command.dx
        next_y = position.y + command.dy

        return unless @movement.traversable?(
          level: level,
          world: world,
          x: next_x,
          y: next_y,
          except_id: command.entity_id
        )

        world.set_component(
          command.entity_id,
          :position,
          Component::Position.new(x: next_x, y: next_y)
        )
        nil
      end

      def update_facing(world, command)
        current = world.component(command.entity_id, :facing)
        return unless current

        direction = direction_for(command.dx, command.dy)
        return unless direction

        world.set_component(
          command.entity_id,
          :facing,
          Component::Facing.new(direction: direction)
        )
      end

      def direction_for(dx, dy)
        Direction.for_delta(dx, dy)
      end

      def execute_attack(world, command, bindings)
        return unless valid_attack?(world, command)

        health = world.component(command.target_id, :health)
        if health
          current = [health.current - command.damage, 0].max
          world.set_component(
            command.target_id,
            :health,
            Component::Health.new(current: current, max: health.max)
          )
          return nil
        end

        character_key = bindings.character_for(command.target_id)
        return unless character_key

        Effect::DamageCharacter.new(
          character_key: character_key,
          amount: command.damage
        )
      end

      def valid_attack?(world, command)
        return false unless command.damage.positive?
        return false unless world.entity?(command.attacker_id)
        return false unless world.entity?(command.target_id)

        attacker_health = world.component(command.attacker_id, :health)
        return false if attacker_health&.current&.zero?

        attacker = world.component(command.attacker_id, :position)
        target = world.component(command.target_id, :position)
        return false unless attacker && target

        (attacker.x - target.x).abs + (attacker.y - target.y).abs == 1
      end

      def execute_defeat(world, command)
        return unless world.entity?(command.entity_id)

        health = world.component(command.entity_id, :health)
        return unless health&.current&.zero?

        RETIRED_COMPONENTS.each do |name|
          world.remove_component(command.entity_id, name)
        end
        nil
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
