# frozen_string_literal: true

require_relative "test_helper"

class WalkthroughModeTest < Minitest::Test
  include AogeraTestSupport

  def test_walkthrough_moves_bound_camera_entity_through_bsp_ground_collision
    map_data = bsp_map_with_solid_behind_x_plane(3.0)
    clearance = Aogera::BSP29::GroundClearance.for_world(map_data: map_data)
    ground_space = Aogera::GroundSpace.new(bsp29_ground_hull: clearance)
    level = open_level
    simulation = Aogera::Simulation.new(
      level: level,
      prototypes: prototype_catalog,
      ground_space: ground_space
    )
    player_id = simulation.spawn_character(
      character_key: :hero,
      prototype: :player
    )
    mode = Aogera::Mode::Walkthrough.new(
      simulation: simulation,
      view: Aogera::FirstPersonView.for_direction(:west),
      controlled_entity_id: player_id,
      controller: Aogera::RealtimeController.new(ground_space: ground_space)
    )

    result = mode.advance(input: move_input(:move_forward))

    position = mode.world_view.component(player_id, :position)
    assert_equal :advanced, result
    assert_equal 1, mode.step_number
    assert_equal player_id, mode.camera_entity_id
    assert_in_delta 3.0, position.x
    assert_in_delta 5.0, position.y
    assert_in_delta 4.0, position.z
  end

  def test_walkthrough_quit_does_not_advance_simulation
    simulation, player_id, ground_space = open_simulation
    mode = Aogera::Mode::Walkthrough.new(
      simulation: simulation,
      view: Aogera::FirstPersonView.for_direction(:north),
      controlled_entity_id: player_id,
      controller: Aogera::RealtimeController.new(ground_space: ground_space)
    )

    assert_equal :quit, mode.advance(input: action_input(:quit))
    assert_equal 0, mode.step_number
  end

  def test_walkthrough_status_describes_horizontal_collision_mode
    simulation, player_id, ground_space = open_simulation
    mode = Aogera::Mode::Walkthrough.new(
      simulation: simulation,
      view: Aogera::FirstPersonView.for_direction(:north),
      controlled_entity_id: player_id,
      controller: Aogera::RealtimeController.new(ground_space: ground_space)
    )

    assert_match "BSP walkthrough", mode.status_text
    assert_match "BSP collision", mode.status_text
    assert_match "Horizontal-only", mode.status_text
  end

  private

  def open_simulation
    ground_space = Aogera::GroundSpace.new
    simulation = Aogera::Simulation.new(
      level: open_level,
      prototypes: prototype_catalog,
      ground_space: ground_space
    )
    player_id = simulation.spawn_character(
      character_key: :hero,
      prototype: :player
    )
    [simulation, player_id, ground_space]
  end

  def open_level
    Aogera::Level.new(
      name: :walkthrough,
      terrain: Aogera::Level::Terrain.new(width: 16, height: 16, cell_size: 1.0),
      spawns: [],
      entries: [
        Aogera::Level::AuthoredEntry.new(
          key: :start,
          x: 4.0,
          y: 5.0,
          z: 4.0,
          facing: nil
        )
      ],
      relations: [],
      default_entry: :start
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
