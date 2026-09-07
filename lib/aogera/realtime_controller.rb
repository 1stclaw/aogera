# frozen_string_literal: true

module Aogera
  class RealtimeController
    BEHAVIOR_HANDLERS = {
      idle: :idle_behavior,
      wander: :wander_behavior,
      chase: :chase
    }.freeze

    DEFAULT_PLAYER_MOVE_INTERVAL = Realtime::PLAYER_MOVE_INTERVAL
    DEFAULT_NPC_INTERVAL = Realtime::NPC_ACTION_INTERVAL

    def initialize(
      pathfinder: Simulation::Pathfinder.new,
      player_move_interval: DEFAULT_PLAYER_MOVE_INTERVAL,
      npc_interval: DEFAULT_NPC_INTERVAL
    )
      @pathfinder = pathfinder
      @player_move_interval = validate_interval(
        player_move_interval,
        :player_move_interval
      )
      @npc_interval = validate_interval(npc_interval, :npc_interval)
      @next_player_move_tick = nil
    end

    def build(input:, level:, world:, controlled_id:, tick_number:, view: nil)
      commands = []

      controlled_command = controlled_move(
        input,
        controlled_id,
        tick_number,
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

    def controlled_move(input, entity_id, tick_number, view)
      movement_pressed = movement_kinds.any? { |kind| input.pressed?(kind) }
      movement_held = movement_kinds.any? { |kind| input.held?(kind) }

      unless movement_held
        @next_player_move_tick = nil
        return
      end

      due = movement_pressed ||
        @next_player_move_tick.nil? ||
        tick_number >= @next_player_move_tick
      return unless due

      forward = 0
      strafe = 0
      forward += 1 if input.held?(:move_forward)
      forward -= 1 if input.held?(:move_backward)
      strafe -= 1 if input.held?(:strafe_left)
      strafe += 1 if input.held?(:strafe_right)
      return if forward.zero? && strafe.zero?

      dx, dy = view.grid_movement_delta(
        forward: forward,
        strafe: strafe
      )
      return if dx.zero? && dy.zero?

      @next_player_move_tick = tick_number + @player_move_interval

      Simulation::Commands::Move.new(
        entity_id: entity_id,
        dx: dx,
        dy: dy
      )
    end


    def default_view(world, entity_id)
      facing = world.component(entity_id, :facing)
      direction = facing&.direction || :north
      FirstPersonView.for_direction(direction)
    end

    def movement_kinds
      @movement_kinds ||= %i[
        move_forward
        move_backward
        strafe_left
        strafe_right
      ].freeze
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
  end
end
