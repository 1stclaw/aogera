# frozen_string_literal: true

module Aogera
  module Mode
    class Play
      attr_reader :simulation, :session, :player_key, :dialogues, :controller, :view

      def initialize(
        simulation:,
        session:,
        player_key:,
        dialogues:,
        controller: RealtimeController.new,
        view: nil
      )
        @simulation = simulation
        @session = session
        @player_key = player_key.to_sym
        @dialogues = dialogues
        @controller = controller

        validate_player!
        @view = view || FirstPersonView.for_direction(player_facing.direction)
      end

      def advance(input:)
        return :quit if input.pressed?(:quit)
        return :quit if input.pressed?(:cancel)

        if input.pressed?(:interact)
          transition = interaction_transition
          return transition if transition
        end

        commands = commands_for(input)
        result = simulation.step(commands: commands)
        session.apply_effects(result.effects)

        return :quit if player_defeated?

        :advanced
      end

      def level = simulation.level
      def world_view = simulation.world_view
      def step_number = simulation.step_number
      def camera_entity_id = controlled_entity_id

      def controlled_entity_id
        simulation.entity_id_for_character(player_key)
      end

      def status_text
        player = player_character
        "#{player_key.to_s.capitalize} " \
          "HP #{player.hp}/#{player.max_hp} " \
          "MP #{player.mp}/#{player.max_mp} | " \
          "Mouse look. WASD/arrows move. Space attack. Enter interact. " \
          "Q or Esc quit. Tick #{step_number}"
      end

      private

      def commands_for(input)
        planned = controller.build(
          input: input,
          level: level,
          world: world_view,
          controlled_id: controlled_entity_id,
          tick_number: simulation.step_number + 1,
          view: view
        )

        return planned unless input.pressed?(:attack)

        Simulation::Commands::Buffer.new(
          player_attack_commands + planned.to_a
        )
      end

      def player_attack_commands
        target_id = adjacent_target_id
        return [] unless target_id

        health = world_view.component(target_id, :health)
        combatant = world_view.component(target_id, :combatant)
        return [] unless health && combatant

        [
          Simulation::Commands::Attack.new(
            attacker_id: controlled_entity_id,
            target_id: target_id,
            damage: player_character.attack
          )
        ]
      end

      def interaction_transition
        target_id = adjacent_target_id
        return unless target_id

        interactable = world_view.component(target_id, :interactable)
        return unless interactable

        Push.new(
          mode: Dialogue.new(
            simulation: simulation,
            lines: dialogues.fetch(interactable.dialogue_key),
            camera_entity_id: controlled_entity_id
          )
        )
      end

      def adjacent_target_id
        origin = world_view.component(controlled_entity_id, :position)
        return unless origin

        offset = Direction.delta(view.cardinal_direction)
        target_x = origin.x + offset[0]
        target_y = origin.y + offset[1]

        world_view.entity_ids.find do |entity_id|
          next if entity_id == controlled_entity_id
          position = world_view.component(entity_id, :position)
          position && position.x == target_x && position.y == target_y
        end
      end

      def player_facing
        world_view.component(controlled_entity_id, :facing) ||
          Component::Facing.new(direction: :south)
      end

      def player_character
        session.character(player_key)
      end

      def player_defeated?
        player_character.hp.zero?
      end

      def validate_player!
        player_character
        controlled_entity_id
      rescue KeyError
        raise ArgumentError,
          "unbound persistent character: #{player_key.inspect}"
      end
    end
  end
end
