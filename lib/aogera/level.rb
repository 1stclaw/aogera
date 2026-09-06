# frozen_string_literal: true

module Aogera
  class Level
    Tile = Data.define(:render_key, :glyph, :passable)
    Spawn = Data.define(:key, :prototype, :x, :y)
    Entry = Data.define(:key, :x, :y, :facing)
    Relation = Data.define(:kind, :source, :target)

    Definition = Data.define(
      :name,
      :tiles,
      :rows,
      :spawns,
      :entries,
      :relations,
      :default_entry
    )

    module Definitions
    end

    attr_reader :name, :terrain, :spawns, :entries, :relations, :default_entry

    def initialize(name:, terrain:, spawns:, relations:, entries: [], default_entry: nil)
      @name = name
      @terrain = terrain
      @spawns = spawns.dup.freeze
      @entries = entries.dup.freeze
      @relations = relations.dup.freeze
      @default_entry = default_entry
    end

    def entry(key = default_entry)
      entries.find { |entry| entry.key == key } ||
        raise(KeyError, "unknown level entry: #{key.inspect}")
    end

    def width = terrain.width
    def height = terrain.height
    def inside?(x, y) = terrain.inside?(x, y)
    def glyph_at(x, y) = terrain.glyph_at(x, y)
    def render_key_at(x, y) = terrain.render_key_at(x, y)
    def passable?(x, y) = terrain.passable?(x, y)
  end
end
