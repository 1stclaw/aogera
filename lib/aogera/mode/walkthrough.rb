# frozen_string_literal: true

module Aogera
  module Mode
    # Minimal collision-aware BSP development mode.
    #
    # The camera remains bound to the controlled runtime entity and horizontal
    # movement is expressed through the same RealtimeController -> GroundMove
    # -> GroundMovement -> GroundSpace stack as ordinary gameplay. Vertical
    # physics are intentionally absent: Position.y stays fixed at the BSP
    # bootstrap height until floor following, gravity, steps, and jumping are
    # introduced explicitly.
    class Walkthrough
      attr_reader :simulation, :view, :controller, :controlled_entity_id

      def initialize(simulation:, view:, controlled_entity_id:, controller:)
        @simulation = simulation
        @view = view
        @controlled_entity_id = Integer(controlled_entity_id)
        @controller = controller

        validate_controlled_entity!
      end

      def advance(input:)
        return :quit if input.pressed?(:quit)
        return :quit if input.pressed?(:cancel)

        commands = controller.build(
          input: input,
          level: level,
          world: world_view,
          controlled_id: controlled_entity_id,
          tick_number: simulation.step_number + 1,
          view: view
        )
        simulation.step(commands: commands)
        :advanced
      end

      def level = simulation.level
      def world_view = simulation.world_view
      def step_number = simulation.step_number
      def camera_entity_id = controlled_entity_id

      def status_text
        "BSP walkthrough | Mouse look. WASD/arrows move with BSP collision. " \
          "Q or Esc quit. Horizontal-only. Tick #{step_number}"
      end

      private

      def validate_controlled_entity!
        position = world_view.component(controlled_entity_id, :position)
        body = world_view.component(controlled_entity_id, :ground_body)

        raise ArgumentError, "walkthrough entity has no position" unless position
        return if body&.radius&.positive?

        raise ArgumentError, "walkthrough entity has no positive GroundBody radius"
      end
    end
  end
end
