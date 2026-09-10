# frozen_string_literal: true

require_relative "test_helper"

class BSP29NavigationClearanceTest < Minitest::Test
  include AogeraTestSupport
  def test_bsp_clearance_routes_grid_bfs_around_compiled_hull_blocker
    level = open_level
    world = Aogera::World.new
    source = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28)
    )
    target = world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true)
    )
    pathfinder = Aogera::Simulation::Pathfinder.new(
      ground_clearance: Aogera::BSP29::GroundClearance.for_world(
        map_data: bsp_map_with_solid_box
      )
    )

    waypoint = pathfinder.next_waypoint(
      level: level,
      world: world.view,
      source_id: source,
      target_id: target
    )

    assert_instance_of Aogera::Simulation::Pathfinder::Waypoint, waypoint
    assert_in_delta 1.5, waypoint.x
    assert_includes [1.5, 3.5], waypoint.z
  end

  def test_bsp_aware_bfs_reroute_executes_with_same_bsp_clearance_backend
    level = level_with(
      width: 5,
      height: 5,
      spawns: [
        Aogera::Level::Spawn.new(
          key: :hunter,
          prototype: :goblin,
          x: 1,
          y: 2
        )
      ],
      entries: [default_entry(x: 3, y: 2)],
      default_entry: :start,
      relations: [
        Aogera::Level::Relation.new(
          kind: :targets,
          source: :hunter,
          target: :start
        )
      ]
    )
    clearance = Aogera::BSP29::GroundClearance.for_world(
      map_data: bsp_map_with_solid_box
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      ground_space: Aogera::GroundSpace.new(
        bsp29_ground_hull: clearance
      )
    )
    hero_id = simulation.spawn_character(
      character_key: :hero,
      prototype: :player
    )
    hunter_id = simulation.entity_id_for_spawn(:hunter)
    controller = Aogera::RealtimeController.new(
      pathfinder: Aogera::Simulation::Pathfinder.new(
        ground_clearance: clearance
      ),
      npc_interval: 1,
      npc_speed: 2.0
    )

    commands = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: level,
      world: simulation.world_view,
      controlled_id: hero_id,
      tick_number: 1
    )
    simulation.step(commands: commands)

    position = simulation.world_view.component(hunter_id, :position)
    assert_in_delta(1.5, position.x)
    assert_operator((position.z - 2.5).abs, :>, 0.0)
    assert_in_delta(
      2.0 / Aogera::Realtime::TICK_HZ,
      (position.z - 2.5).abs
    )
  end

  def test_app_shares_bsp_ground_clearance_between_navigation_and_actor_movement
    app = Aogera::App.new(
      clock: -> { 0.0 },
      raylib_api: Object.new,
      bsp29_map: app_bsp_map
    )
    mode = app.instance_variable_get(:@modes).current
    controller = mode.controller
    pathfinder = controller.instance_variable_get(:@pathfinder)
    clearance = pathfinder.instance_variable_get(:@ground_clearance)
    simulation = mode.simulation
    executor = simulation.instance_variable_get(:@executor)
    movement = executor.instance_variable_get(:@ground_movement)
    movement_space = movement.instance_variable_get(:@ground_space)
    movement_clearance = movement_space.instance_variable_get(:@bsp29_ground_hull)

    assert_instance_of(Aogera::BSP29::GroundClearance, clearance)
    assert_same(clearance, movement_clearance)
    assert_same(mode.instance_variable_get(:@ground_space), movement_space)
    refute executor.instance_variable_defined?(:@character_ground_movement)
  end

  private

  def open_level
    Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 5, height: 5),
      spawns: [],
      entries: [],
      relations: []
    )
  end

  def bsp_map_with_solid_box
    planes = [
      plane(1, 0, 0, 2),
      plane(-1, 0, 0, -3),
      plane(0, 0, 1, 2),
      plane(0, 0, -1, -3)
    ].freeze
    clipnodes = [
      clipnode(0, 1, -1),
      clipnode(1, 2, -1),
      clipnode(2, 3, -1),
      clipnode(3, -2, -1)
    ].freeze
    model = model_with_headnodes([99, 0, -1, -1])

    Struct.new(:planes, :clipnodes, :world_model).new(
      planes,
      clipnodes,
      model
    )
  end

  def app_bsp_map
    solid_leaf = Aogera::BSP29::Leaf.new(
      contents: -2,
      visibility_offset: -1,
      bounds: nil,
      first_marksurface: 0,
      marksurface_count: 0,
      ambient_levels: [0, 0, 0, 0].freeze
    )
    empty_leaf = solid_leaf.with(contents: -1)
    plane = plane(1, 0, 0, 0)
    node = Aogera::BSP29::Node.new(
      plane_index: 0,
      children: [-2, -1].freeze,
      bounds: nil,
      first_face: 0,
      face_count: 0
    )

    Aogera::BSP29::MapData.new(
      entities: [].freeze,
      planes: [plane].freeze,
      textures: [].freeze,
      vertices: [].freeze,
      visibility: "".b.freeze,
      nodes: [node].freeze,
      texinfo: [].freeze,
      faces: [].freeze,
      lighting: "".b.freeze,
      clipnodes: [clipnode(0, -1, -2)].freeze,
      leaves: [solid_leaf, empty_leaf].freeze,
      marksurfaces: [].freeze,
      edges: [].freeze,
      surfedges: [].freeze,
      models: [model_with_headnodes([0, 0, -1, -1])].freeze
    )
  end

  def model_with_headnodes(headnodes)
    Aogera::BSP29::Model.new(
      bounds: nil,
      origin: vec(0, 0, 0),
      headnodes: headnodes.freeze,
      visible_leaf_count: 0,
      first_face: 0,
      face_count: 0
    )
  end

  def plane(x, y, z, distance)
    Aogera::BSP29::Plane.new(
      normal: vec(x, y, z),
      distance: Float(distance),
      type: 0
    )
  end

  def clipnode(plane_index, front, back)
    Aogera::BSP29::ClipNode.new(
      plane_index: plane_index,
      children: [front, back].freeze
    )
  end

  def vec(x, y, z)
    Aogera::BSP29::Vec3.new(x: Float(x), y: Float(y), z: Float(z))
  end
end
