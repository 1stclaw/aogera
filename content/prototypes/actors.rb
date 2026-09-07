# frozen_string_literal: true

module Aogera
  class Prototype
    module Definitions
      Actors = [
        Prototype.new(
          name: :player,
          components: {
            renderable: Component::Renderable.new(
              render_key: :player, glyph: "P", layer: 10
            ),
            collision: Component::Collision.new(blocks_movement: true),
            ground_body: Component::GroundBody.new(radius: 0.22),
            melee_attack: Component::MeleeAttack.new(
              reach: 0.65, arc_degrees: 110.0
            ),
            interactor: Component::Interactor.new(
              reach: 0.65, arc_degrees: 110.0
            )
          }.freeze
        ),
        Prototype.new(
          name: :goblin,
          components: {
            health: Component::Health.new(current: 4, max: 4),
            renderable: Component::Renderable.new(
              render_key: :goblin, glyph: "G", layer: 10
            ),
            behavior: Component::Behavior.new(kind: :chase),
            collision: Component::Collision.new(blocks_movement: true),
            ground_body: Component::GroundBody.new(radius: 0.28),
            melee_attack: Component::MeleeAttack.new(
              reach: 0.65, arc_degrees: 110.0
            ),
            combatant: Component::Combatant.new(attack: 1)
          }.freeze
        ),
        Prototype.new(
          name: :villager,
          components: {
            renderable: Component::Renderable.new(
              render_key: :villager, glyph: "V", layer: 10
            ),
            collision: Component::Collision.new(blocks_movement: true),
            ground_body: Component::GroundBody.new(radius: 0.28),
            interactable: Component::Interactable.new(
              dialogue_key: :village_greeting
            )
          }.freeze
        )
      ].freeze
    end
  end
end
