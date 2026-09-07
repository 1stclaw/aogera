# frozen_string_literal: true

module Aogera
  GroundTrace = Data.define(
    :fraction,
    :end_x,
    :end_z,
    :normal_x,
    :normal_z,
    :entity_id,
    :world_hit,
    :start_blocked
  ) do
    def hit?
      start_blocked || world_hit || !entity_id.nil?
    end

    def clear?
      !hit?
    end
  end
end
