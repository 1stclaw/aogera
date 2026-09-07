# frozen_string_literal: true

module Aogera
  class RealtimeController
    BEHAVIOR_HANDLERS = {
      idle: :idle_behavior,
      wander: :wander_behavior,
      chase: :chase
    }.freeze

    DEFAULT_PLAYER_SPEED = Realtime::PLAYER_SPEED
    DEFAULT_NPC_INTERVAL = Realtime::NPC_ACTION_INTERVAL

    def initialize(
      pathfinder: Simulation::Pathfinder.new,
      player_speed: DEFAULT_PLAYER_SPEED,
      npc_interval: DEFAULT_NPC_INTERVAL
    )
      @pathfinder = pathfinder
      @player_step = validate_positive_number(player_speed, :player_speed) /
        Realtime::TICK_HZ
      @npc_interval = validate_interval(npc_interval, :npc_interval)
    end

    def build(input:, level:, world:, controlled_id:, tick_number:, view: nil)
      commands = []

      controlled_command = controlled_move(
        input,
        controlled_id,
        view || default_view(world, controlled_id)
      )
      commands << controlled_command if controlled_command

      if cadence_due?(tick_number, @npc_interval)
        world.entity_ids.each do |entity_id|
          next if entity_id == controlled_id

          command = behavior_command(level, world, entity_id)
          commands << command if command
        end
      end

      Simulation::Commands::Buffer.new(commands)
    end

    private

    def controlled_move(input, entity_id, view)
      forward = 0
      strafe = 0
      forward += 1 if input.held?(:move_forward)
      forward -= 1 if input.held?(:move_backward)
      strafe -= 1 if input.held?(:strafe_left)
      strafe += 1 if input.held?(:strafe_right)
      return if forward.zero? && strafe.zero?

      dx, dz = view.ground_movement_delta(
        forward: forward,
        strafe: strafe,
        distance: @player_step
      )

      Simulation::Commands::GroundMove.new(
        entity_id: entity_id,
        dx: dx,
        dz: dz
      )
    end

    def default_view(world, entity_id)
      facing = world.component(entity_id, :facing)
      direction = facing&.direction || :north
      FirstPersonView.for_direction(direction)
    end

    def cadence_due?(tick_number, interval)
      (tick_number % interval).zero?
    end

    def behavior_command(level, world, entity_id)
      behavior = world.component(entity_id, :behavior)
      return unless behavior

      handler = BEHAVIOR_HANDLERS.fetch(behavior.kind) do
        raise ArgumentError,
          "unknown behavior: #{behavior.kind.inspect}"
      end

      __send__(handler, level, world, entity_id)
    end

    def idle_behavior(_level, _world, _entity_id)
      nil
    end

    def wander_behavior(_level, _world, entity_id)
      dx, dy = Direction::VECTORS.sample
      Simulation::Commands::Move.new(
        entity_id: entity_id,
        dx: dx,
        dy: dy
      )
    end

    def chase(level, world, entity_id)
      target_id = world.relation_targets(
        kind: :targets,
        source_id: entity_id
      ).first
      return unless target_id

      if adjacent?(world, entity_id, target_id)
        combatant = world.component(entity_id, :combatant)
        return unless combatant&.attack&.positive?

        return Simulation::Commands::Attack.new(
          attacker_id: entity_id,
          target_id: target_id,
          damage: combatant.attack
        )
      end

      step = @pathfinder.next_step(
        level: level,
        world: world,
        source_id: entity_id,
        target_id: target_id
      )
      return unless step

      dx, dy = step
      Simulation::Commands::Move.new(
        entity_id: entity_id,
        dx: dx,
        dy: dy
      )
    end

    def adjacent?(world, source_id, target_id)
      source = world.component(source_id, :position)
      target = world.component(target_id, :position)
      return false unless source && target

      (source.x - target.x).abs +
        (source.y - target.y).abs == 1
    end

    def validate_interval(value, name)
      return value if value.is_a?(Integer) && value.positive?

      raise ArgumentError,
        "#{name} must be a positive Integer"
    end

    def validate_positive_number(value, name)
      number = Float(value)
      return number if number.positive?

      raise ArgumentError, "#{name} must be positive"
    rescue ArgumentError, TypeError
      raise ArgumentError, "#{name} must be positive"
    end
  end
end
