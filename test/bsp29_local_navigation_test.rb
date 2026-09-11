# frozen_string_literal: true

require_relative "test_helper"

class BSP29LocalNavigationTest < Minitest::Test
  include AogeraTestSupport
  def test_bsp_local_navigation_avoids_compiled_hull_blocker
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
    ground_space = Aogera::GroundSpace.new(bsp29_ground_hull: clearance)
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      ground_space: ground_space,
      ground_steering: Aogera::Simulation::GroundSteering.new(
        speed: 2.0,
        ground_space: ground_space
      )
    )
    hero_id = simulation.spawn_character(
      character_key: :hero,
      prototype: :player
    )
    hunter_id = simulation.entity_id_for_spawn(:hunter)
    controller = Aogera::RealtimeController.new(npc_interval: 1)

    decision = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: level,
      world: simulation.world_view,
      controlled_id: hero_id,
      tick_number: 1
    )
    simulation.step(commands: decision)
    14.times do
      simulation.step(commands: Aogera::Simulation::Commands::Buffer.new([]))
    end

    position = simulation.world_view.component(hunter_id, :position)
    assert_operator((position.z - 2.5).abs, :>, 0.1)
    assert_instance_of Aogera::GroundHeading,
      simulation.world_view.component(hunter_id, :ground_heading)
  end
  def test_bsp_app_uses_spectator_while_retaining_bsp_ground_space_for_runtime
    app = Aogera::App.new(
      clock: -> { 0.0 },
      raylib_api: Object.new,
      bsp29_map: app_bsp_map
    )
    mode = app.instance_variable_get(:@modes).current
    simulation = mode.simulation
    steering = simulation.instance_variable_get(:@ground_steering)
    navigation = steering.instance_variable_get(:@ground_navigation)
    navigation_space = navigation.instance_variable_get(:@ground_space)
    executor = simulation.instance_variable_get(:@executor)
    movement = executor.instance_variable_get(:@ground_movement)
    movement_space = movement.instance_variable_get(:@ground_space)
    clearance = movement_space.instance_variable_get(:@bsp29_ground_hull)

    assert_instance_of Aogera::Mode::Spectator, mode
    assert_instance_of Aogera::BSP29::GroundClearance, clearance
    assert_same movement_space, navigation_space
    assert_equal :bsp29, simulation.level.name
    assert_equal 1, simulation.world_view.entity_ids.length

    player_position = simulation.world_view.component(
      mode.camera_entity_id,
      :position
    )
    assert_equal Aogera::Component::Position.new(x: 0.0, y: 0.0, z: 0.0),
      player_position
    assert_equal [0.0, mode.view.eye_height, 0.0], mode.camera_eye

    mapper = app.instance_variable_get(:@mapper)
    action = mapper.map(
      Aogera::Host::KeyEvent.new(key: :space, state: :pressed)
    )
    assert_equal :move_up, action.kind
    refute Aogera::Simulation.const_defined?(:Pathfinder, false)
  end
  private

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
      entities: [player_start_entity].freeze,
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

  def player_start_entity
    Aogera::BSP29::Entity.new(
      properties: {
        "classname" => "info_player_start",
        "origin" => "0 0 0",
        "angle" => "90"
      }.freeze,
      origin: Aogera::BSP29::Vec3.new(x: 0.0, y: 0.0, z: 0.0)
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
