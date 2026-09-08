# frozen_string_literal: true

module Aogera
  module WorldUnits
    GRID_CELL_SIZE = 32.0

    module_function

    def grid_center(index, cell_size: GRID_CELL_SIZE)
      (Integer(index) * Float(cell_size)) + (Float(cell_size) / 2.0)
    end

    def grid_cell(value, cell_size: GRID_CELL_SIZE)
      (Float(value) / Float(cell_size)).floor
    end
  end
end
