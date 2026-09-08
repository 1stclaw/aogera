# frozen_string_literal: true

require_relative "test_helper"

class GroundMovementTest < Minitest::Test
  def test_wall_blocks_one_axis_while_allowing_slide_on_the_other
    tiles = {
      " " => Aogera::Level::Tile.new(render_key: :ground, glyph: " ", passable: true),
      "|" => Aogera::Level::Tile.new(render_key: :wall, glyph: "|", passable: false)
    }.freeze
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0,
        rows: ["     ", "   | ", "     "],
        tiles: tiles
      ),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )

    resolved = Aogera::Simulation::GroundMovement.new.resolve(
      level: level,
      world: world.view,
      entity_id: hero_id,
      position: world.component(hero_id, :position),
      dx: 0.4,
      dz: 0.2
    )

    assert_operator resolved.x, :>, 2.5
    assert_operator resolved.x, :<, 3.0
    assert_in_delta 1.7, resolved.z
  end

  def test_blocking_entity_ground_body_is_solid_to_continuous_player_motion
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 5, height: 5),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28)
    )

    resolved = Aogera::Simulation::GroundMovement.new.resolve(
      level: level,
      world: world.view,
      entity_id: hero_id,
      position: world.component(hero_id, :position),
      dx: 0.4,
      dz: 0.0
    )

    assert_operator resolved.x, :>, 2.5
    assert_operator resolved.x, :<, 3.0
    assert_in_delta 2.5, resolved.z
  end
end

class GroundMovementSweepTest < Minitest::Test
  def test_large_motion_cannot_tunnel_through_a_wall_cell
    tiles = {
      " " => Aogera::Level::Tile.new(render_key: :ground, glyph: " ", passable: true),
      "|" => Aogera::Level::Tile.new(render_key: :wall, glyph: "|", passable: false)
    }.freeze
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0,
        rows: ["     ", "   | ", "     "],
        tiles: tiles
      ),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 1.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )

    resolved = Aogera::Simulation::GroundMovement.new.resolve(
      level: level,
      world: world.view,
      entity_id: hero_id,
      position: world.component(hero_id, :position),
      dx: 2.0,
      dz: 0.0
    )

    assert_operator resolved.x, :<, 3.0
  end
end

class GroundMovementCornerTest < Minitest::Test
  def test_inside_corner_stops_diagonal_motion_without_axis_preference
    tiles = {
      " " => Aogera::Level::Tile.new(render_key: :ground, glyph: " ", passable: true),
      "|" => Aogera::Level::Tile.new(render_key: :wall, glyph: "|", passable: false)
    }.freeze
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0,
        rows: ["     ", "     ", "   | ", "  || ", "     "],
        tiles: tiles
      ),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )

    resolved = Aogera::Simulation::GroundMovement.new.resolve(
      level: level,
      world: world.view,
      entity_id: hero_id,
      position: world.component(hero_id, :position),
      dx: 0.8,
      dz: 0.8
    )

    assert_operator resolved.x, :<, 2.79
    assert_operator resolved.z, :<, 2.79
    assert_in_delta resolved.x, resolved.z, 1e-5
  end
end

class GroundMovementBodyShapeTest < Minitest::Test
  def test_blocking_actor_uses_ground_body_circle_instead_of_whole_grid_cell
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 6, height: 6),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.1),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28)
    )

    resolved = Aogera::Simulation::GroundMovement.new.resolve(
      level: level,
      world: world.view,
      entity_id: hero_id,
      position: world.component(hero_id, :position),
      dx: 0.6,
      dz: 0.0
    )

    assert_operator resolved.x, :>, 3.0
    assert_in_delta 2.1, resolved.z
  end

  def test_nonblocking_ground_body_does_not_stop_movement
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 6, height: 6),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    world.spawn(
      position: Aogera::Component::Position.new(x: 3.0, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: false),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28)
    )

    resolved = Aogera::Simulation::GroundMovement.new.resolve(
      level: level,
      world: world.view,
      entity_id: hero_id,
      position: world.component(hero_id, :position),
      dx: 0.8,
      dz: 0.0
    )

    assert_in_delta 3.3, resolved.x
    assert_in_delta 2.5, resolved.z
  end

  def test_moving_entity_radius_comes_from_ground_body
    level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0, width: 5, height: 5),
      spawns: [],
      relations: []
    )
    world = Aogera::World.new
    hero_id = world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.4)
    )
    world.spawn(
      position: Aogera::Component::Position.new(x: 3.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.4)
    )

    resolved = Aogera::Simulation::GroundMovement.new.resolve(
      level: level,
      world: world.view,
      entity_id: hero_id,
      position: world.component(hero_id, :position),
      dx: 0.4,
      dz: 0.0
    )

    assert_operator resolved.x, :<, 2.9
  end
end

class GroundMovementMultiContactTest < Minitest::Test
  def setup
    tiles = {
      " " => Aogera::Level::Tile.new(render_key: :ground, glyph: " ", passable: true),
      "|" => Aogera::Level::Tile.new(render_key: :wall, glyph: "|", passable: false)
    }.freeze
    @level = Aogera::Level.new(
      name: :test,
      terrain: Aogera::Level::Terrain.new(cell_size: 1.0,
        rows: Array.new(5, "   |  "),
        tiles: tiles
      ),
      spawns: [],
      relations: []
    )
    @world = Aogera::World.new
    @hero_id = @world.spawn(
      position: Aogera::Component::Position.new(x: 2.7799998, y: 0.0, z: 1.8),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.22)
    )
    @goblin_id = @world.spawn(
      position: Aogera::Component::Position.new(x: 2.5, y: 0.0, z: 2.5),
      collision: Aogera::Component::Collision.new(blocks_movement: true),
      ground_body: Aogera::Component::GroundBody.new(radius: 0.28)
    )
    @space = Aogera::GroundSpace.new
    @movement = Aogera::Simulation::GroundMovement.new(ground_space: @space)
  end

  def test_wall_and_actor_contact_never_returns_position_inside_wall
    resolved = move(dx: 0.0, dz: 0.5)

    assert_operator resolved.x, :<=, 2.78

    validation = @space.sweep_circle(
      level: @level,
      world: @world.view,
      start_x: resolved.x,
      start_z: resolved.z,
      end_x: resolved.x,
      end_z: resolved.z,
      radius: 0.22,
      ignore_entity_id: @hero_id,
      entity_filter: movement_blocker
    )

    refute validation.start_blocked
  end

  def test_player_can_move_away_after_wall_actor_wedge
    wedged = move(dx: 0.0, dz: 0.5)

    escaped = @movement.resolve(
      level: @level,
      world: @world.view,
      entity_id: @hero_id,
      position: wedged,
      dx: 0.0,
      dz: -0.2
    )

    assert_in_delta wedged.x, escaped.x
    assert_operator escaped.z, :<, wedged.z
  end

  private

  def move(dx:, dz:)
    @movement.resolve(
      level: @level,
      world: @world.view,
      entity_id: @hero_id,
      position: @world.component(@hero_id, :position),
      dx: dx,
      dz: dz
    )
  end

  def movement_blocker
    lambda do |entity_id|
      collision = @world.component(entity_id, :collision)
      collision&.blocks_movement || false
    end
  end
end
