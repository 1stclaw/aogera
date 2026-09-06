# frozen_string_literal: true

module Aogera
  module Realtime
    TICK_HZ = 30
    PLAYER_MOVE_HZ = 5
    NPC_ACTION_HZ = 2

    PLAYER_MOVE_INTERVAL = TICK_HZ / PLAYER_MOVE_HZ
    NPC_ACTION_INTERVAL = TICK_HZ / NPC_ACTION_HZ
  end
end
