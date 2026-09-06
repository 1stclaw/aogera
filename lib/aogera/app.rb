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
      env: ENV,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
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
      @host = Host::Terminal.new(env: env)
      @renderer = Render::Selector.build(
        capabilities: @host.capabilities
      )
      @clock = clock
      @fixed_step = FixedStep.new(hz: TICK_HZ)
    end

    def run
      @host.enter_application
      @fixed_step.start(@clock.call)
      draw

      loop do
        poll_input
        now = @clock.call
        due = @fixed_step.due_steps(now)

        if due.zero?
          @host.wait_for_input(
            timeout: @fixed_step.wait_time(now)
          )
          next
        end

        should_quit = false

        due.times do
          snapshot = take_input_snapshot
          result = @modes.current.advance(input: snapshot)

          if result == :quit
            should_quit = true
            break
          end

          apply_mode_result(result)
        end

        break if should_quit
        draw
      end
    ensure
      finish_renderer
      @host.leave_application
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
      synchronized = @renderer.synchronized_updates?
      @host.begin_synchronized_update if synchronized
      begin
        @host.clear if @renderer.clear_before_render?
        @host.write(@renderer.render(scene))
        @host.write_status(
          row: @renderer.status_row(scene),
          text: status_text(mode)
        )
      ensure
        @host.end_synchronized_update if synchronized
      end
    end

    def status_text(mode)
      return mode.status_text if mode.respond_to?(:status_text)
      "Q or Esc to quit. Tick #{mode.step_number}"
    end

    def finish_renderer
      return unless @renderer.respond_to?(:finish)
      output = @renderer.finish
      @host.write(output) unless output.empty?
    end
  end
end
