# frozen_string_literal: true

module Aogera
  class RealtimeController
    BEHAVIOR_HANDLERS = {
      idle: :idle_behavior,
      wander: :wander_behavior,
      chase: :chase
    }.freeze

    DEFAULT_PLAYER_SPEED = Realtime::PLAYER_SPEED
    DEFAULT_NPC_SPEED = Realtime::NPC_SPEED
    DEFAULT_NPC_INTERVAL = Realtime::NPC_ACTION_INTERVAL

    def initialize(
      pathfinder: Simulation::Pathfinder.new,
      ground_space: GroundSpace.new,
      player_speed: DEFAULT_PLAYER_SPEED,
      npc_speed: DEFAULT_NPC_SPEED,
      npc_interval: DEFAULT_NPC_INTERVAL
    )
      @pathfinder = pathfinder
      @ground_space = ground_space
      @player_step = validate_positive_number(player_speed, :player_speed) /
        Realtime::TICK_HZ
      @npc_interval = validate_interval(npc_interval, :npc_interval)
      @npc_step = validate_positive_number(npc_speed, :npc_speed) *
        (@npc_interval.to_f / Realtime::TICK_HZ)
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
          next if world.respond_to?(:retired?) && world.retired?(entity_id)

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

      ground_move(entity_id, dx, dz)
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
      dx, dz = Direction::VECTORS.sample
      ground_move(entity_id, dx * @npc_step, dz * @npc_step)
    end

    def chase(level, world, entity_id)
      target_id = world.relation_targets(
        kind: :targets,
        source_id: entity_id
      ).first
      return unless target_id
      return if world.respond_to?(:retired?) && world.retired?(target_id)

      combatant = world.component(entity_id, :combatant)
      melee = world.component(entity_id, :melee_attack)
      if combatant&.attack&.positive? && melee &&
          melee_reachable?(level, world, entity_id, target_id, melee)
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

      source = world.component(entity_id, :position)
      return unless source

      cell_x = source.x.floor + step[0]
      cell_z = source.z.floor + step[1]
      target_x = cell_x + 0.5
      target_z = cell_z + 0.5
      dx = target_x - source.x
      dz = target_z - source.z
      distance = Math.hypot(dx, dz)
      return if distance.zero?

      scale = [@npc_step / distance, 1.0].min
      ground_move(entity_id, dx * scale, dz * scale)
    end

    def melee_reachable?(level, world, source_id, target_id, profile)
      separation = @ground_space.separation(
        world: world,
        source_id: source_id,
        target_id: target_id
      )
      return false unless separation && separation <= Float(profile.reach)

      source = @ground_space.position(world: world, entity_id: source_id)
      target = @ground_space.position(world: world, entity_id: target_id)
      return false unless source && target

      trace = @ground_space.trace_segment(
        level: level,
        world: world,
        start_x: source.x,
        start_z: source.z,
        end_x: target.x,
        end_z: target.z,
        ignore_entity_id: source_id,
        entity_filter: lambda do |entity_id|
          next true if entity_id == target_id

          collision = world.component(entity_id, :collision)
          collision&.blocks_movement || false
        end
      )

      trace.clear? || trace.entity_id == target_id
    end

    def ground_move(entity_id, dx, dz)
      Simulation::Commands::GroundMove.new(
        entity_id: entity_id,
        dx: dx,
        dz: dz
      )
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
