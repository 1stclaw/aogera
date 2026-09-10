# frozen_string_literal: true

require_relative "test_helper"

class BSP29SimulationCollisionTest < Minitest::Test
  include AogeraTestSupport

  def test_supplied_bsp_ground_space_controls_bound_character_ground_move
    map_data = bsp_map_with_solid_behind_x_plane(3.0)
    level = open_level(
      entries: [entry(key: :start, x: 4.0, z: 4.0, facing: :west)]
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      character_ground_space: bsp_ground_space(map_data)
    )
    player_id = simulation.spawn_character(
      character_key: :hero,
      prototype: :player
    )

    simulation.step(
      commands: ground_moves(
        Aogera::Simulation::Commands::GroundMove.new(
          entity_id: player_id,
          dx: -2.0,
          dz: 0.0
        )
      )
    )

    position = simulation.world_view.component(player_id, :position)
    assert_in_delta(3.0, position.x)
    assert_in_delta(4.0, position.z)
  end

  def test_spawned_npc_ground_move_stays_on_grid_collision_backend
    map_data = bsp_map_with_solid_behind_x_plane(3.0)
    level = open_level(
      spawns: [spawn(key: :goblin, prototype: :goblin, x: 4.0, z: 2.0)],
      entries: [entry(key: :start, x: 4.0, z: 6.0)]
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      character_ground_space: bsp_ground_space(map_data)
    )
    simulation.spawn_character(character_key: :hero, prototype: :player)
    goblin_id = simulation.entity_id_for_spawn(:goblin)

    simulation.step(
      commands: ground_moves(
        Aogera::Simulation::Commands::GroundMove.new(
          entity_id: goblin_id,
          dx: -2.0,
          dz: 0.0
        )
      )
    )

    position = simulation.world_view.component(goblin_id, :position)
    assert_in_delta(2.0, position.x)
    assert_in_delta(2.0, position.z)
  end

  def test_retiring_grid_blocker_does_not_freeze_other_goblin_against_character_bsp_hull
    map_data = bsp_map_with_solid_behind_x_plane(4.0)
    level = open_level(
      spawns: [
        spawn(key: :hunter, prototype: :goblin, x: 4.5, z: 2.5),
        spawn(key: :blocker, prototype: :dead_blocker, x: 3.5, z: 2.5)
      ],
      entries: [entry(key: :start, x: 1.5, z: 2.5)],
      relations: [
        Aogera::Level::Relation.new(
          kind: :targets,
          source: :hunter,
          target: :start
        )
      ]
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: catalog_with_dead_blocker,
      character_ground_space: bsp_ground_space(map_data)
    )
    player_id = simulation.spawn_character(character_key: :hero, prototype: :player)
    hunter_id = simulation.entity_id_for_spawn(:hunter)
    blocker_id = simulation.entity_id_for_spawn(:blocker)

    simulation.step(
      commands: ground_moves(
        Aogera::Simulation::Commands::Defeat.new(entity_id: blocker_id)
      )
    )
    assert simulation.world_view.retired?(blocker_id)

    controller = Aogera::RealtimeController.new(
      npc_interval: 1,
      npc_speed: Aogera::Realtime::TICK_HZ
    )
    planned = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: level,
      world: simulation.world_view,
      controlled_id: player_id,
      tick_number: simulation.step_number + 1
    )
    hunter_move = planned.to_a.find do |command|
      command.is_a?(Aogera::Simulation::Commands::GroundMove) &&
        command.entity_id == hunter_id
    end

    refute_nil(hunter_move)
    assert_in_delta(-1.0, hunter_move.dx)
    assert_in_delta(0.0, hunter_move.dz)

    simulation.step(commands: planned)

    position = simulation.world_view.component(hunter_id, :position)
    assert_in_delta(3.5, position.x)
    assert_in_delta(2.5, position.z)
  end

  private

  def bsp_ground_space(map_data)
    Aogera::GroundSpace.new(
      bsp29_ground_hull: Aogera::BSP29::GroundHull.for_world(
        map_data: map_data,
        ground_body_radius: 0.22
      )
    )
  end

  def open_level(spawns: [], entries:, relations: [])
    Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(width: 10, height: 10, cell_size: 1.0),
      spawns: spawns,
      entries: entries,
      relations: relations,
      default_entry: :start
    )
  end

  def spawn(key:, prototype:, x:, z:)
    Aogera::Level::AuthoredSpawn.new(
      key: key,
      prototype: prototype,
      x: Float(x),
      y: 0.0,
      z: Float(z)
    )
  end

  def entry(key:, x:, z:, facing: :west)
    Aogera::Level::AuthoredEntry.new(
      key: key,
      x: Float(x),
      y: 0.0,
      z: Float(z),
      facing: facing
    )
  end

  def ground_moves(*commands)
    Aogera::Simulation::Commands::Buffer.new(commands)
  end

  def catalog_with_dead_blocker
    base = prototype_catalog
    dead_blocker = Aogera::Prototype.new(
      name: :dead_blocker,
      components: {
        health: Aogera::Component::Health.new(current: 0, max: 1),
        behavior: Aogera::Component::Behavior.new(kind: :idle),
        collision: Aogera::Component::Collision.new(blocks_movement: true),
        ground_body: Aogera::Component::GroundBody.new(radius: 0.28)
      }.freeze
    )

    Aogera::Prototype::Catalog.new(
      base.names.map { |name| base.fetch(name) } + [dead_blocker]
    )
  end

  def bsp_map_with_solid_behind_x_plane(distance)
    vec = ->(x, y, z) { Aogera::BSP29::Vec3.new(x: x, y: y, z: z) }
    model = Aogera::BSP29::Model.new(
      bounds: nil,
      origin: vec.call(0.0, 0.0, 0.0),
      headnodes: [99, 0, -1, -1].freeze,
      visible_leaf_count: 0,
      first_face: 0,
      face_count: 0
    )

    Struct.new(:planes, :clipnodes, :world_model).new(
      [
        Aogera::BSP29::Plane.new(
          normal: vec.call(1.0, 0.0, 0.0),
          distance: distance,
          type: 0
        )
      ],
      [
        Aogera::BSP29::ClipNode.new(
          plane_index: 0,
          children: [-1, -2].freeze
        )
      ],
      model
    )
  end
end
