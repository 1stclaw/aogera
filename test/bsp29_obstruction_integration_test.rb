# frozen_string_literal: true

require_relative "test_helper"

class BSP29ObstructionIntegrationTest < Minitest::Test
  include AogeraTestSupport

  FakePointHull = Struct.new(:result, :calls) do
    def trace(**arguments)
      calls << arguments
      result
    end
  end

  def test_executor_attack_validation_uses_bsp_point_obstruction
    space = blocked_space
    level = combat_level
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog(melee_reach: 2.0),
      ground_space: space.fetch(:space)
    )
    player_id = simulation.spawn_character(character_key: :hero, prototype: :player)
    goblin_id = simulation.entity_id_for_spawn(:goblin)

    simulation.step(
      commands: Aogera::Simulation::Commands::Buffer.new(
        [
          Aogera::Simulation::Commands::Attack.new(
            attacker_id: player_id,
            target_id: goblin_id,
            damage: 2
          )
        ]
      )
    )

    assert_equal(4, simulation.world_view.component(goblin_id, :health).current)
    assert_equal(1, space.fetch(:hull).calls.length)
  end

  def test_play_player_targeting_uses_bsp_point_obstruction
    space = blocked_space
    level = combat_level
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog(melee_reach: 2.0)
    )
    simulation.spawn_character(character_key: :hero, prototype: :player)
    goblin_id = simulation.entity_id_for_spawn(:goblin)
    mode = Aogera::Mode::Play.new(
      simulation: simulation,
      session: test_session,
      player_key: :hero,
      dialogues: dialogue_catalog,
      view: Aogera::FirstPersonView.for_direction(:east),
      ground_space: space.fetch(:space)
    )

    mode.advance(input: action_input(:attack))

    assert_equal(4, simulation.world_view.component(goblin_id, :health).current)
    assert_equal(1, space.fetch(:hull).calls.length)
  end

  def test_play_interaction_uses_bsp_point_obstruction
    space = blocked_space
    level = level_with(
      width: 6,
      height: 4,
      spawns: [
        Aogera::Level::Spawn.new(
          key: :villager,
          prototype: :villager,
          x: 3,
          y: 1
        )
      ],
      entries: [default_entry(x: 1, y: 1, facing: :east)],
      default_entry: :start
    )
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog(interaction_reach: 2.0)
    )
    simulation.spawn_character(character_key: :hero, prototype: :player)
    mode = Aogera::Mode::Play.new(
      simulation: simulation,
      session: test_session,
      player_key: :hero,
      dialogues: dialogue_catalog,
      view: Aogera::FirstPersonView.for_direction(:east),
      ground_space: space.fetch(:space)
    )

    result = mode.advance(input: action_input(:interact))

    assert_equal(:advanced, result)
    assert_equal(1, space.fetch(:hull).calls.length)
  end

  def test_npc_melee_planning_uses_bsp_point_obstruction
    space = blocked_space
    world = Aogera::World.new
    goblin_id = world.spawn(
      position: Aogera::Component::Position.new(x: 1.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28),
      melee_attack: Aogera::Component::MeleeAttack.new(reach: 0.65, arc_degrees: 110.0),
      behavior: Aogera::Component::Behavior.new(kind: :chase),
      combatant: Aogera::Component::Combatant.new(attack: 1)
    )
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    world.add_relation(kind: :targets, source_id: goblin_id, target_id: hero_id)
    controller = Aogera::RealtimeController.new(
      ground_space: space.fetch(:space),
      npc_interval: 1
    )

    commands = controller.build(
      input: Aogera::Input::Snapshot.empty,
      level: level_with(spawns: []),
      world: world.view,
      controlled_id: hero_id,
      tick_number: 1
    ).to_a

    refute(commands.any? { |command| command.is_a?(Aogera::Simulation::Commands::Attack) })
    assert_equal(1, space.fetch(:hull).calls.length)
  end

  def test_bsp_runtime_retains_shared_point_obstruction_space_under_spectator
    app = Aogera::App.new(
      clock: -> { 0.0 },
      raylib_api: Object.new,
      bsp29_map: minimal_bsp_map,
      bsp29_mode: :spectator
    )
    mode = app.instance_variable_get(:@modes).current
    simulation = mode.simulation
    executor = simulation.instance_variable_get(:@executor)
    executor_space = executor.instance_variable_get(:@ground_space)
    steering = simulation.instance_variable_get(:@ground_steering)
    navigation = steering.instance_variable_get(:@ground_navigation)
    navigation_space = navigation.instance_variable_get(:@ground_space)
    point_hull = executor_space.instance_variable_get(:@bsp29_point_hull)

    assert_instance_of Aogera::Mode::Spectator, mode
    assert_same executor_space, navigation_space
    assert_instance_of Aogera::GroundSpace, executor_space
    assert_instance_of Aogera::BSP29::PointHull, point_hull
  end

  private

  def minimal_bsp_map
    model = Aogera::BSP29::Model.new(
      bounds: nil,
      origin: vec(0, 0, 0),
      headnodes: [0, 0, -1, -1].freeze,
      visible_leaf_count: 0,
      first_face: 0,
      face_count: 0
    )
    node = Aogera::BSP29::Node.new(
      plane_index: 0,
      children: [-2, -1].freeze,
      bounds: nil,
      first_face: 0,
      face_count: 0
    )
    solid_leaf = Aogera::BSP29::Leaf.new(
      contents: -2,
      visibility_offset: -1,
      bounds: nil,
      first_marksurface: 0,
      marksurface_count: 0,
      ambient_levels: [0, 0, 0, 0].freeze
    )
    empty_leaf = solid_leaf.with(contents: -1)
    plane = Aogera::BSP29::Plane.new(
      normal: vec(1, 0, 0),
      distance: 0.0,
      type: 0
    )
    clipnode = Aogera::BSP29::ClipNode.new(
      plane_index: 0,
      children: [-1, -2].freeze
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
      clipnodes: [clipnode].freeze,
      leaves: [solid_leaf, empty_leaf].freeze,
      marksurfaces: [].freeze,
      edges: [].freeze,
      surfedges: [].freeze,
      models: [model].freeze
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

  def blocked_space
    hull = FakePointHull.new(
      Aogera::BSP29::PointHull::Trace.new(
        fraction: 0.5,
        end_position: vec(2.5, 16.0, 1.5),
        plane_normal: vec(-1.0, 0.0, 0.0),
        start_solid: false,
        all_solid: false
      ),
      []
    )
    {
      hull: hull,
      space: Aogera::GroundSpace.new(bsp29_point_hull: hull)
    }
  end

  def combat_level
    level_with(
      width: 6,
      height: 4,
      spawns: [
        Aogera::Level::Spawn.new(
          key: :goblin,
          prototype: :goblin,
          x: 3,
          y: 1
        )
      ],
      entries: [default_entry(x: 1, y: 1, facing: :east)],
      default_entry: :start
    )
  end

  def vec(x, y, z)
    Aogera::BSP29::Vec3.new(x: Float(x), y: Float(y), z: Float(z))
  end
end
