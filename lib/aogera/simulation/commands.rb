# frozen_string_literal: true

module Aogera
  class Simulation
    module Commands
      GroundMove = Data.define(:entity_id, :dx, :dz)
      SetSteeringTarget = Data.define(:entity_id, :x, :z, :goal_entity_id) do
        def initialize(entity_id:, x:, z:, goal_entity_id: nil)
          super(
            entity_id: entity_id,
            x: Float(x),
            z: Float(z),
            goal_entity_id: goal_entity_id
          )
        end
      end
      ClearSteeringTarget = Data.define(:entity_id)
      SetGroundHeading = Data.define(:entity_id, :dx, :dz)
      ClearGroundHeading = Data.define(:entity_id)
      Attack = Data.define(:attacker_id, :target_id, :damage)
      Defeat = Data.define(:entity_id)
      Despawn = Data.define(:entity_id)

      class Buffer
        include Enumerable

        def initialize(commands)
          @commands = commands.dup.freeze
        end

        def each(&block)
          @commands.each(&block)
        end

        def empty?
          @commands.empty?
        end

        def size
          @commands.size
        end
      end
    end
  end
end
