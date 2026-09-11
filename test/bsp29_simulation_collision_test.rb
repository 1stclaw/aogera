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
      ground_space: bsp_ground_space(map_data)
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

  def test_spawned_npc_ground_move_uses_bsp_static_collision_backend
    map_data = bsp_map_with_solid_behind_x_plane(3.0)
    level = open_level(
      spawns: [spawn(key: :goblin, prototype: :goblin, x: 4.0, z: 2.0)],
      entries: [entry(key: :start, x: 8.0, z: 8.0)]
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      ground_space: bsp_ground_space(map_data)
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
    assert_in_delta(3.0, position.x)
    assert_in_delta(2.0, position.z)
  end

  def test_one_bsp_ground_space_handles_player_and_npc_authored_radii
    map_data = bsp_map_with_solid_behind_x_plane(3.0)
    level = open_level(
      spawns: [spawn(key: :goblin, prototype: :goblin, x: 4.0, z: 2.0)],
      entries: [entry(key: :start, x: 4.0, z: 4.0, facing: :west)]
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      ground_space: bsp_ground_space(map_data)
    )
    player_id = simulation.spawn_character(
      character_key: :hero,
      prototype: :player
    )
    goblin_id = simulation.entity_id_for_spawn(:goblin)

    simulation.step(
      commands: ground_moves(
        Aogera::Simulation::Commands::GroundMove.new(
          entity_id: player_id,
          dx: -2.0,
          dz: 0.0
        ),
        Aogera::Simulation::Commands::GroundMove.new(
          entity_id: goblin_id,
          dx: -2.0,
          dz: 0.0
        )
      )
    )

    player_position = simulation.world_view.component(player_id, :position)
    goblin_position = simulation.world_view.component(goblin_id, :position)
    assert_in_delta(3.0, player_position.x)
    assert_in_delta(4.0, player_position.z)
    assert_in_delta(3.0, goblin_position.x)
    assert_in_delta(2.0, goblin_position.z)
  end

  def test_spawned_npc_slides_along_bsp_wall_with_existing_ground_movement_solver
    map_data = bsp_map_with_solid_behind_x_plane(3.0)
    level = open_level(
      spawns: [spawn(key: :goblin, prototype: :goblin, x: 4.0, z: 2.0)],
      entries: [entry(key: :start, x: 8.0, z: 8.0)]
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      ground_space: bsp_ground_space(map_data)
    )
    simulation.spawn_character(character_key: :hero, prototype: :player)
    goblin_id = simulation.entity_id_for_spawn(:goblin)

    simulation.step(
      commands: ground_moves(
        Aogera::Simulation::Commands::GroundMove.new(
          entity_id: goblin_id,
          dx: -2.0,
          dz: 2.0
        )
      )
    )

    position = simulation.world_view.component(goblin_id, :position)
    assert_in_delta(3.0, position.x)
    assert_in_delta(4.0, position.z)
  end

  def test_dynamic_ground_body_still_blocks_npc_before_empty_bsp_world
    map_data = empty_bsp_map
    level = open_level(
      spawns: [
        spawn(key: :mover, prototype: :goblin, x: 4.0, z: 2.0),
        spawn(key: :blocker, prototype: :goblin, x: 3.0, z: 2.0)
      ],
      entries: [entry(key: :start, x: 8.0, z: 8.0)]
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      ground_space: bsp_ground_space(map_data)
    )
    simulation.spawn_character(character_key: :hero, prototype: :player)
    mover_id = simulation.entity_id_for_spawn(:mover)

    simulation.step(
      commands: ground_moves(
        Aogera::Simulation::Commands::GroundMove.new(
          entity_id: mover_id,
          dx: -2.0,
          dz: 0.0
        )
      )
    )

    position = simulation.world_view.component(mover_id, :position)
    assert_in_delta(3.56, position.x)
    assert_in_delta(2.0, position.z)
  end

  def test_retiring_dynamic_blocker_allows_bsp_backed_npc_to_continue
    map_data = empty_bsp_map
    clearance = Aogera::BSP29::GroundClearance.for_world(map_data: map_data)
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
      ground_space: Aogera::GroundSpace.new(
        bsp29_ground_hull: clearance
      ),
      ground_steering: Aogera::Simulation::GroundSteering.new(
        speed: Aogera::Realtime::TICK_HZ
      )
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
      pathfinder: Aogera::Simulation::Pathfinder.new(
        ground_clearance: clearance
      ),
      npc_interval: 1
    )
    planned = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: level,
      world: simulation.world_view,
      controlled_id: player_id,
      tick_number: simulation.step_number + 1
    )
    hunter_target = planned.to_a.find do |command|
      command.is_a?(Aogera::Simulation::Commands::SetSteeringTarget) &&
        command.entity_id == hunter_id
    end

    refute_nil(hunter_target)
    assert_in_delta(3.5, hunter_target.x)
    assert_in_delta(2.5, hunter_target.z)

    simulation.step(commands: planned)

    position = simulation.world_view.component(hunter_id, :position)
    assert_in_delta(3.5, position.x)
    assert_in_delta(2.5, position.z)
  end

  private

  def bsp_ground_space(map_data)
    Aogera::GroundSpace.new(
      bsp29_ground_hull: Aogera::BSP29::GroundClearance.for_world(
        map_data: map_data
      )
    )
  end

  def empty_bsp_map
    model = Aogera::BSP29::Model.new(
      bounds: nil,
      origin: Aogera::BSP29::Vec3.new(x: 0.0, y: 0.0, z: 0.0),
      headnodes: [99, -1, -1, -1].freeze,
      visible_leaf_count: 0,
      first_face: 0,
      face_count: 0
    )

    Struct.new(:planes, :clipnodes, :world_model).new(
      [].freeze,
      [].freeze,
      model
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
