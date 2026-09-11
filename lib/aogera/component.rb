# frozen_string_literal: true

module Aogera
  module Component
    PrototypeRef = Data.define(:name)
    Retired = Data.define()
    Position = Data.define(:x, :y, :z)
    GroundBody = Data.define(:radius)
    SteeringTarget = Data.define(:x, :z, :goal_entity_id) do
      def initialize(x:, z:, goal_entity_id: nil)
        super(x: Float(x), z: Float(z), goal_entity_id: goal_entity_id)
      end
    end
    Health = Data.define(:current, :max)
    Renderable = Data.define(:render_key, :glyph, :layer)
    Behavior = Data.define(:kind)
    Collision = Data.define(:blocks_movement)
    Facing = Data.define(:direction)
    Interactable = Data.define(:dialogue_key)
    Combatant = Data.define(:attack)
    MeleeAttack = Data.define(:reach, :arc_degrees)
    Interactor = Data.define(:reach, :arc_degrees)
  end
end
