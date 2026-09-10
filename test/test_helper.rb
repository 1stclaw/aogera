# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(
  File.expand_path("../lib", __dir__)
)

require "aogera"

module AogeraTestPaths
  PROTOTYPE_PATH = Aogera::Content::Paths.prototype(:actors)
  LEVEL_PATH = Aogera::Content::Paths.level(:test_field)
  DIALOGUE_PATH = Aogera::Content::Paths.dialogue(:test_field)
end

module AogeraTestSupport
  def replace_data(record, **changes)
    values = record.class.members.to_h do |member|
      value = changes.key?(member) ? changes.fetch(member) : record.public_send(member)
      [member, value]
    end

    record.class.new(**values)
  end

  def prototype_catalog(
    goblin_behavior: :chase,
    melee_reach: 0.65,
    interaction_reach: 0.65
  )
    player = Aogera::Prototype.new(
      name: :player,
      components: {
        collision: Aogera::Component::Collision.new(
          blocks_movement: true
        ),
        ground_body: Aogera::Component::GroundBody.new(radius: 0.22),
        melee_attack: Aogera::Component::MeleeAttack.new(
          reach: melee_reach,
          arc_degrees: 110.0
        ),
        interactor: Aogera::Component::Interactor.new(
          reach: interaction_reach,
          arc_degrees: 110.0
        )
      }.freeze
    )

    goblin = Aogera::Prototype.new(
      name: :goblin,
      components: {
        health: Aogera::Component::Health.new(
          current: 4,
          max: 4
        ),
        behavior: Aogera::Component::Behavior.new(
          kind: goblin_behavior
        ),
        collision: Aogera::Component::Collision.new(
          blocks_movement: true
        ),
        ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
        melee_attack: Aogera::Component::MeleeAttack.new(
          reach: 0.65,
          arc_degrees: 110.0
        ),
        combatant: Aogera::Component::Combatant.new(
          attack: 1
        )
      }.freeze
    )

    villager = Aogera::Prototype.new(
      name: :villager,
      components: {
        collision: Aogera::Component::Collision.new(
          blocks_movement: true
        ),
        ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
        interactable: Aogera::Component::Interactable.new(
          dialogue_key: :village_greeting
        )
      }.freeze
    )

    Aogera::Prototype::Catalog.new([player, goblin, villager])
  end

  def dialogue_catalog
    Aogera::Dialogue::Catalog.new(
      village_greeting: [
        "First line.",
        "Second line."
      ]
    )
  end

  def test_session
    Aogera::Session.new(
      characters: {
        hero: Aogera::Character.new(
          hp: 10,
          max_hp: 10,
          mp: 4,
          max_mp: 4,
          attack: 2
        ),
        mage: Aogera::Character.new(
          hp: 8,
          max_hp: 8,
          mp: 8,
          max_mp: 8,
          attack: 1
        )
      }
    )
  end

  def level_with(
    width: 7,
    height: 7,
    spawns:,
    relations: [],
    entries: [],
    default_entry: nil
  )
    terrain = Aogera::Level::Terrain.new(
      width: width,
      height: height,
      cell_size: 1.0
    )
    authored_spawns = spawns.map do |spawn|
      x, z = terrain.cell_center(spawn.x, spawn.y)
      Aogera::Level::AuthoredSpawn.new(
        key: spawn.key, prototype: spawn.prototype, x: x, y: 0.0, z: z
      )
    end
    authored_entries = entries.map do |entry|
      x, z = terrain.cell_center(entry.x, entry.y)
      Aogera::Level::AuthoredEntry.new(
        key: entry.key, x: x, y: 0.0, z: z, facing: entry.facing
      )
    end

    Aogera::Level.new(
      name: :test,
      terrain: terrain,
      spawns: authored_spawns,
      entries: authored_entries,
      relations: relations,
      default_entry: default_entry
    )
  end

  def default_entry(x: 2, y: 2, key: :start, facing: :south)
    Aogera::Level::Entry.new(
      key: key,
      x: x,
      y: y,
      facing: facing
    )
  end

  def authored_spawn(key:, prototype:, x:, y:, cell_size: 1.0)
    Aogera::Level::AuthoredSpawn.new(
      key: key,
      prototype: prototype,
      x: Aogera::WorldUnits.grid_center(x, cell_size: cell_size),
      y: 0.0,
      z: Aogera::WorldUnits.grid_center(y, cell_size: cell_size)
    )
  end

  def authored_entry(x: 2, y: 2, key: :start, facing: :south, cell_size: 1.0)
    Aogera::Level::AuthoredEntry.new(
      key: key,
      x: Aogera::WorldUnits.grid_center(x, cell_size: cell_size),
      y: 0.0,
      z: Aogera::WorldUnits.grid_center(y, cell_size: cell_size),
      facing: facing
    )
  end

  def action_input(kind)
    Aogera::Input::Snapshot.from(
      [
        Aogera::Input::Action.new(
          kind: kind,
          state: :pressed
        )
      ]
    )
  end

  def move_input(kind)
    action_input(kind)
  end

  def spawn_character(
    simulation,
    session,
    character_key: :hero,
    prototype: :player,
    entry: simulation.level.default_entry
  )
    simulation.spawn_character(
      character_key: character_key,
      prototype: prototype,
      entry: entry
    )
  end

  def advance_simulation(
    simulation,
    input,
    controlled_id:,
    controller: Aogera::RealtimeController.new(
      npc_interval: 1
    ),
    tick_number: simulation.step_number + 1
  )
    commands = controller.build(
      input: input,
      level: simulation.level,
      world: simulation.world_view,
      controlled_id: controlled_id,
      tick_number: tick_number
    )
    simulation.step(commands: commands)
  end

  def entity_id_for(simulation, prototype_name)
    simulation.world_view.entity_ids.find do |entity_id|
      ref = simulation.world_view.component(
        entity_id,
        :prototype_ref
      )
      ref&.name == prototype_name
    end
  end
end
