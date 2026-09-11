# frozen_string_literal: true

module Aogera
  class App
    PLAYER_KEY = :player
    TICK_HZ = Realtime::TICK_HZ

    def initialize(
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      raylib_api: nil,
      bsp29_map: nil
    )
      prototypes = Prototype::Loader.load(Content::Paths.prototype(:actors))
      authored_level = Level::Readers::Ruby.read(
        Content::Paths.level(:test_field)
      )
      level = Level::Loader.load(
        authored_level,
        prototypes: prototypes
      )
      dialogues = Dialogue::Loader.load(Content::Paths.dialogue(:test_field))
      @session = Session.new(
        characters: {
          PLAYER_KEY => Character.new(
            hp: 10,
            max_hp: 10,
            mp: 4,
            max_mp: 4,
            attack: 2
          )
        }
      )

      ground_clearance = ground_clearance_for(bsp29_map)
      ground_space = ground_space_for(
        bsp29_map,
        ground_clearance: ground_clearance
      )
      simulation = Simulation.new(
        level: level,
        prototypes: prototypes,
        ground_space: ground_space
      )
      simulation.spawn_character(
        character_key: PLAYER_KEY,
        prototype: :player,
        entry: level.default_entry
      )
      facing = simulation.world_view.component(
        simulation.entity_id_for_character(PLAYER_KEY),
        :facing
      )
      @view = FirstPersonView.for_direction(facing.direction)

      @modes = ModeStack.new
      @modes.push(
        Mode::Play.new(
          simulation: simulation,
          session: @session,
          player_key: PLAYER_KEY,
          dialogues: dialogues,
          controller: RealtimeController.new(
            ground_space: ground_space
          ),
          view: @view,
          ground_space: ground_space
        )
      )
      @mapper = Input::Mapper.new
      @handoff = Input::Handoff.new
      @input_tracker = Input::Tracker.new

      api = raylib_api || RaylibAPI.new
      @host = Host::Raylib.new(api: api)
      @renderer = Render::Raylib3D.new(api: api, bsp29_map: bsp29_map)
      @clock = clock
      @fixed_step = FixedStep.new(hz: TICK_HZ)
    end

    def run
      @host.open
      @fixed_step.start(@clock.call)

      until @host.window_should_close?
        poll_input
        now = @clock.call
        due = @fixed_step.due_steps(now)
        should_quit = advance_simulation(due)
        break if should_quit

        draw
      end
    ensure
      @host.close
    end

    private

    def ground_clearance_for(bsp29_map)
      return unless bsp29_map

      BSP29::GroundClearance.for_world(map_data: bsp29_map)
    end

    def ground_space_for(bsp29_map, ground_clearance:)
      return GroundSpace.new unless bsp29_map

      GroundSpace.new(
        bsp29_ground_hull: ground_clearance,
        bsp29_point_hull: BSP29::PointHull.for_world(map_data: bsp29_map)
      )
    end

    def poll_input
      @host.poll_events.each do |physical_event|
        input = @mapper.map(physical_event)
        next unless input

        case input
        when Input::LookDelta
          @view.rotate(dx: input.dx, dy: input.dy)
        when Input::Action
          @handoff.push(input)
        end
      end
    end

    def take_input_snapshot
      @handoff.flip!
      @input_tracker.snapshot(
        @handoff.take_completed
      )
    end

    def advance_simulation(due)
      due.times do
        snapshot = take_input_snapshot
        result = @modes.current.advance(input: snapshot)
        return true if result == :quit

        apply_mode_result(result)
      end

      false
    end

    def apply_mode_result(result)
      case result
      when Mode::Push
        @modes.push(result.mode)
      when :pop
        @modes.pop
      end
    end

    def draw
      mode = @modes.current
      @renderer.draw(
        level: mode.level,
        world: mode.world_view,
        status: status_text(mode),
        view: @view,
        camera_entity_id: mode.camera_entity_id
      )
    end

    def status_text(mode)
      return mode.status_text if mode.respond_to?(:status_text)

      "Q or Esc to quit. Tick #{mode.step_number}"
    end
  end
end
