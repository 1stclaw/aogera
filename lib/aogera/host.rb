# frozen_string_literal: true

module Aogera
  module Host
    KeyEvent = Data.define(
      :key,
      :state
    )

    MouseMotion = Data.define(
      :dx,
      :dy
    )
  end
end
