# frozen_string_literal: true

module Aogera
  module Component
    PrototypeRef = Data.define(:name)
    Position = Data.define(:x, :y)
    GroundPosition = Data.define(:x, :z)
    GroundBody = Data.define(:radius)
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
