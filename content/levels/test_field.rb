# frozen_string_literal: true

module Aogera
  class Level
    module Definitions
      TestField = Definition.new(
        name: :test_field,
        tiles: {
          " " => Tile.new(
            render_key: :ground,
            glyph: " ",
            passable: true
          ),
          '"' => Tile.new(
            render_key: :grass,
            glyph: '"',
            passable: true
          ),
          "~" => Tile.new(
            render_key: :water,
            glyph: "~",
            passable: false
          ),
          "|" => Tile.new(
            render_key: :wall,
            glyph: "|",
            passable: false
          ),
          "_" => Tile.new(
            render_key: :wall,
            glyph: "_",
            passable: false
          )
        }.freeze,
        rows: [
          "____________________________________________",
          '|      """"                ~~~~~           |',
          '|   """""""              ~~~~~~~           |',
          '|                         ~~~~~            |',
          '|            """""                         |',
          '|       """"""""              ~~~~         |',
          '|                            ~~~~~~        |',
          '|     ~~~~~                  ~~~~~         |',
          '|    ~~~~~~~        """""                  |',
          '|     ~~~~~       """"""""                 |',
          '|                  """"             """"   |',
          '|        """"                        ""    |',
          '|                                          |',
          "____________________________________________"
        ].map!(&:freeze).freeze,
        spawns: [
          Spawn.new(
            key: :villager,
            prototype: :villager,
            x: 5,
            y: 3
          ),
          Spawn.new(
            key: :goblin_a,
            prototype: :goblin,
            x: 35,
            y: 3
          ),
          Spawn.new(
            key: :goblin_b,
            prototype: :goblin,
            x: 14,
            y: 10
          ),
          Spawn.new(
            key: :goblin_c,
            prototype: :goblin,
            x: 32,
            y: 11
          )
        ].freeze,
        entries: [
          Entry.new(
            key: :start,
            x: 3,
            y: 3,
            facing: :south
          )
        ].freeze,
        relations: [
          Relation.new(
            kind: :targets,
            source: :goblin_a,
            target: :start
          ),
          Relation.new(
            kind: :targets,
            source: :goblin_b,
            target: :start
          ),
          Relation.new(
            kind: :targets,
            source: :goblin_c,
            target: :start
          )
        ].freeze,
        default_entry: :start
      )
    end
  end
end
