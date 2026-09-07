# frozen_string_literal: true

module Aogera
  class App
    PROTOTYPE_PATH = File.expand_path(
      "../../content/prototypes/actors.rb",
      __dir__
    )
    LEVEL_PATH = File.expand_path(
      "../../content/levels/test_field.rb",
      __dir__
    )
    DIALOGUE_PATH = File.expand_path(
      "../../content/dialogue/test_field.rb",
      __dir__
    )
    PLAYER_KEY = :player
    TICK_HZ = Realtime::TICK_HZ

    def initialize(
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      raylib_api: nil
    )
      prototypes = Prototype::Loader.load(PROTOTYPE_PATH)
      level = Level::Loader.load(LEVEL_PATH, prototypes: prototypes)
      dialogues = Dialogue::Loader.load(DIALOGUE_PATH)
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

      simulation = Simulation.new(level: level, prototypes: prototypes)
      simulation.spawn_character(
        character_key: PLAYER_KEY,
        prototype: :player,
        entry: level.default_entry
      )
      @modes = ModeStack.new
      @modes.push(
        Mode::Play.new(
          simulation: simulation,
          session: @session,
          player_key: PLAYER_KEY,
          dialogues: dialogues
        )
      )
      @mapper = Input::Mapper.new
      @handoff = Input::Handoff.new
      @input_tracker = Input::Tracker.new
      @projector = Render::Projector.new

      api = raylib_api || RaylibAPI.new
      @host = Host::Raylib.new(api: api)
      @renderer = Render::Raylib2D.new(api: api)
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

    def poll_input
      @host.poll_events.each do |physical_event|
        action = @mapper.map(physical_event)
        @handoff.push(action) if action
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
      scene = @projector.project(
        level: mode.level,
        world: mode.world_view
      )
      @renderer.draw(
        scene,
        status: status_text(mode)
      )
    end

    def status_text(mode)
      return mode.status_text if mode.respond_to?(:status_text)

      "Q or Esc to quit. Tick #{mode.step_number}"
    end
  end
end
