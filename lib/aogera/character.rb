# frozen_string_literal: true

module Aogera
  class Character
    attr_reader :hp, :max_hp, :mp, :max_mp, :attack

    def initialize(hp:, max_hp:, mp:, max_mp:, attack:)
      @hp = hp
      @max_hp = max_hp
      @mp = mp
      @max_mp = max_mp
      @attack = attack

      validate!
      freeze
    end

    def replace(**changes)
      self.class.new(
        hp: changes.fetch(:hp, hp),
        max_hp: changes.fetch(:max_hp, max_hp),
        mp: changes.fetch(:mp, mp),
        max_mp: changes.fetch(:max_mp, max_mp),
        attack: changes.fetch(:attack, attack)
      )
    end

    private

    def validate!
      values = [hp, max_hp, mp, max_mp, attack]
      unless values.all? { |value| value.is_a?(Integer) }
        raise ArgumentError, "character values must be Integers"
      end

      raise ArgumentError, "max_hp must be positive" unless max_hp.positive?
      raise ArgumentError, "max_mp must not be negative" if max_mp.negative?
      raise ArgumentError, "attack must not be negative" if attack.negative?
      raise ArgumentError, "hp is outside 0..max_hp" unless hp.between?(0, max_hp)
      raise ArgumentError, "mp is outside 0..max_mp" unless mp.between?(0, max_mp)
    end
  end
end
