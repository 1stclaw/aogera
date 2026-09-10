# frozen_string_literal: true

module Aogera
  Character = Data.define(:hp, :max_hp, :mp, :max_mp, :attack) do
    def initialize(hp:, max_hp:, mp:, max_mp:, attack:)
      values = [hp, max_hp, mp, max_mp, attack]
      unless values.all? { |value| value.is_a?(Integer) }
        raise ArgumentError, "character values must be Integers"
      end

      raise ArgumentError, "max_hp must be positive" unless max_hp.positive?
      raise ArgumentError, "max_mp must not be negative" if max_mp.negative?
      raise ArgumentError, "attack must not be negative" if attack.negative?
      raise ArgumentError, "hp is outside 0..max_hp" unless hp.between?(0, max_hp)
      raise ArgumentError, "mp is outside 0..max_mp" unless mp.between?(0, max_mp)

      super
    end
  end
end
