# frozen_string_literal: true

require "stringio"
require "tempfile"
require "tmpdir"
require_relative "test_helper"

class BSP29CLITest < Minitest::Test
  FakeApp = Struct.new(:runs) do
    def run
      self.runs += 1
    end
  end

  FakeMap = Struct.new(
    :entities,
    :planes,
    :textures,
    :texinfo,
    :vertices,
    :visibility,
    :nodes,
    :faces,
    :clipnodes,
    :leaves,
    :edges,
    :surfedges,
    :models,
    :lighting,
    keyword_init: true
  ) do
    def world_model
      models.first
    end

    def entities_named(classname)
      entities.select { |entity| entity.classname == classname }.freeze
    end
  end

  FakeFace = Struct.new(:texinfo_index)
  FakeTexInfo = Struct.new(:texture_index)
  FakeTexture = Struct.new(:name, :width, :height)

  def test_bare_map_requires_an_explicit_launch_mode
    app = FakeApp.new(0)
    reader_paths = []
    stderr = StringIO.new
    cli = build_cli(
      map: fake_map,
      app: app,
      reader_paths: reader_paths,
      stderr: stderr
    )

    status = cli.run(["map.bsp"])

    assert_equal 64, status
    assert_empty reader_paths
    assert_equal 0, app.runs
    assert_includes stderr.string, "launch mode required; use --spectator"
  end

  def test_explicit_spectator_is_supported
    app = FakeApp.new(0)
    modes = []
    cli = build_cli(map: fake_map, app: app, modes: modes)

    status = cli.run(["--spectator", "map.bsp"])

    assert_equal 0, status
    assert_equal [:spectator], modes
    assert_equal 1, app.runs
  end

  def test_default_app_factory_builds_the_bsp_app
    map = fake_map
    app = FakeApp.new(0)
    built_args = []
    cli = Aogera::CLI::BSP29.new(
      reader: ->(_path) { map },
      stdout: StringIO.new,
      stderr: StringIO.new
    )

    factory = lambda do |bsp29_map:, bsp29_mode:, bsp29_palette:|
      built_args << [bsp29_map, bsp29_mode, bsp29_palette]
      app
    end

    Aogera::App.stub(:new, factory) do
      status = cli.run(["--spectator", "map.bsp"])

      assert_equal 0, status
    end

    assert_equal [[map, :spectator, nil]], built_args
    assert_equal 1, app.runs
  end

  def test_bsp_info_prints_structure_without_launching_app
    app = FakeApp.new(0)
    stdout = StringIO.new
    cli = build_cli(map: fake_map, app: app, stdout: stdout)

    status = cli.run(["maps/e1m3.bsp", "--bsp-info"])

    assert_equal 0, status
    assert_equal 0, app.runs
    assert_includes stdout.string, "BSP29: maps/e1m3.bsp"
    assert_includes stdout.string, "entities:     2"
    assert_includes stdout.string, "planes:       3"
    assert_includes stdout.string, "world bounds:  (-64.0, -24.0, -32.0) -> (64.0, 96.0, 128.0)"
    assert_includes stdout.string, "player starts: 1"
    assert_includes stdout.string, "0: (12.0, 24.0, 36.0)"
  end

  def test_dump_entities_prints_source_properties_and_normalized_origin
    app = FakeApp.new(0)
    stdout = StringIO.new
    cli = build_cli(map: fake_map, app: app, stdout: stdout)

    status = cli.run(["--dump-entities", "map.bsp"])

    assert_equal 0, status
    assert_equal 0, app.runs
    assert_includes stdout.string, "[0] worldspawn"
    assert_includes stdout.string, 'message="CLI fixture"'
    assert_includes stdout.string, "[1] info_player_start"
    assert_includes stdout.string, 'origin="12 -36 24"'
    assert_includes stdout.string, "normalized_origin=(12.0, 24.0, 36.0)"
  end

  def test_dump_textures_prints_world_usage_missing_slots_and_unused_embedded_textures
    app = FakeApp.new(0)
    stdout = StringIO.new
    cli = build_cli(map: texture_map, app: app, stdout: stdout)

    status = cli.run(["map.bsp", "--dump-textures"])

    assert_equal 0, status
    assert_equal 0, app.runs
    assert_includes stdout.string, "texture slots:       4"
    assert_includes stdout.string, "embedded textures:   3"
    assert_includes stdout.string, "world face refs:      4"
    assert_includes stdout.string, "unique used textures: 2"
    assert_includes stdout.string, "BRICKA2_4"
    assert_includes stdout.string, "64x64"
    assert_includes stdout.string, "faces=2"
    assert_includes stdout.string, "METAL1_3"
    assert_includes stdout.string, "128x64"
    assert_includes stdout.string, "Missing texture slots referenced by world faces:"
    assert_includes stdout.string, "index=2 faces=1"
    assert_includes stdout.string, "Embedded but unused by world model:"
    assert_includes stdout.string, "UNUSED"
  end

  def test_help_does_not_require_a_path_or_read_a_map
    reader_calls = []
    stdout = StringIO.new
    cli = build_cli(
      map: fake_map,
      reader_paths: reader_calls,
      stdout: stdout
    )

    status = cli.run(["--help"])

    assert_equal 0, status
    assert_empty reader_calls
    assert_includes stdout.string, "Usage: bundle exec ruby bin/aogera-bsp29"
    assert_includes stdout.string, "--bsp-info"
    assert_includes stdout.string, "--dump-entities"
    assert_includes stdout.string, "--dump-textures"
    assert_includes stdout.string, "--pak PATH"
  end

  def test_missing_path_is_a_usage_error
    stderr = StringIO.new
    cli = build_cli(map: fake_map, stderr: stderr)

    status = cli.run([])

    assert_equal 64, status
    assert_includes stderr.string, "missing argument: BSP"
    assert_includes stderr.string, "--help"
  end

  def test_conflicting_exit_commands_are_a_usage_error
    stderr = StringIO.new
    cli = build_cli(map: fake_map, stderr: stderr)

    status = cli.run(["map.bsp", "--bsp-info", "--dump-entities"])

    assert_equal 64, status
    assert_includes stderr.string, "conflicts with another exit command"
  end

  def test_reader_format_error_is_reported_as_data_error
    stderr = StringIO.new
    cli = Aogera::CLI::BSP29.new(
      reader: ->(_path) { raise Aogera::BSP29::FormatError, "bad BSP" },
      app_factory: ->(_map, mode:) { raise "should not launch #{mode}" },
      stdout: StringIO.new,
      stderr: stderr
    )

    status = cli.run(["--spectator", "broken.bsp"])

    assert_equal 65, status
    assert_includes stderr.string, "aogera-bsp29: bad BSP"
  end

  def test_missing_input_is_reported_as_an_input_error
    stderr = StringIO.new
    cli = Aogera::CLI::BSP29.new(
      reader: ->(_path) { raise Errno::ENOENT, "missing.bsp" },
      app_factory: ->(_map, mode:) { raise "should not launch #{mode}" },
      stdout: StringIO.new,
      stderr: stderr
    )

    status = cli.run(["--spectator", "missing.bsp"])

    assert_equal 66, status
    assert_includes stderr.string, "aogera-bsp29: input not available:"
    assert_includes stderr.string, "missing.bsp"
  end

  def test_pak_spectator_reads_virtual_bsp_bytes_and_launches
    app = FakeApp.new(0)
    modes = []

    with_pak(
      "maps/test.bsp" => minimal_bsp,
      Aogera::Quake::PALETTE_PATH => minimal_palette
    ) do |pak_path|
      palettes = []
      cli = Aogera::CLI::BSP29.new(
        app_factory: lambda do |_map, mode:, palette:|
          modes << mode
          palettes << palette
          app
        end,
        stdout: StringIO.new,
        stderr: StringIO.new
      )

      status = cli.run(["--spectator", "--pak", pak_path, "maps/test.bsp"])

      assert_equal 0, status
      assert_equal [:spectator], modes
      assert_equal 1, palettes.length
      assert_equal 256, palettes.first.size
      assert_equal 1, app.runs
    end
  end

  def test_pak_spectator_requires_palette_member
    stderr = StringIO.new

    with_pak("maps/test.bsp" => minimal_bsp) do |pak_path|
      cli = Aogera::CLI::BSP29.new(stdout: StringIO.new, stderr: stderr)

      status = cli.run(["--spectator", "--pak", pak_path, "maps/test.bsp"])

      assert_equal 66, status
      assert_includes stderr.string, "gfx/palette.lmp"
    end
  end

  def test_pak_spectator_rejects_malformed_palette
    stderr = StringIO.new

    with_pak(
      "maps/test.bsp" => minimal_bsp,
      Aogera::Quake::PALETTE_PATH => "bad".b
    ) do |pak_path|
      cli = Aogera::CLI::BSP29.new(stdout: StringIO.new, stderr: stderr)

      status = cli.run(["--spectator", "--pak", pak_path, "maps/test.bsp"])

      assert_equal 65, status
      assert_includes stderr.string, "Quake palette must be exactly 768 bytes"
    end
  end

  def test_pak_inspection_actions_read_the_same_virtual_bsp
    with_pak("maps/test.bsp" => minimal_bsp) do |pak_path|
      {
        "--bsp-info" => "BSP29: #{pak_path}:maps/test.bsp",
        "--dump-entities" => "BSP29 entities: #{pak_path}:maps/test.bsp",
        "--dump-textures" => "BSP29 textures: #{pak_path}:maps/test.bsp"
      }.each do |option, heading|
        stdout = StringIO.new
        cli = Aogera::CLI::BSP29.new(stdout: stdout, stderr: StringIO.new)

        status = cli.run(["--pak", pak_path, "maps\\test.bsp", option])

        assert_equal 0, status, option
        assert_includes stdout.string, heading, option
      end
    end
  end

  def test_pak_missing_member_is_reported_as_input_error
    stderr = StringIO.new

    with_pak("maps/other.bsp" => minimal_bsp) do |pak_path|
      cli = Aogera::CLI::BSP29.new(stdout: StringIO.new, stderr: stderr)

      status = cli.run(["--bsp-info", "--pak", pak_path, "maps/missing.bsp"])

      assert_equal 66, status
      assert_includes stderr.string, "aogera-bsp29: input not available:"
      assert_includes stderr.string, "maps/missing.bsp"
    end
  end

  def test_pak_invalid_virtual_path_is_a_usage_error
    stderr = StringIO.new

    with_pak("maps/test.bsp" => minimal_bsp) do |pak_path|
      cli = Aogera::CLI::BSP29.new(stdout: StringIO.new, stderr: stderr)

      status = cli.run(["--bsp-info", "--pak", pak_path, "../maps/test.bsp"])

      assert_equal 64, status
      assert_includes stderr.string, "aogera-bsp29: invalid content path:"
    end
  end

  def test_malformed_pak_is_reported_as_data_error
    stderr = StringIO.new

    Tempfile.create(["aogera-bsp29-cli", ".pak"]) do |file|
      file.binmode
      file.write("NOPE".b + [12, 0].pack("V2"))
      file.flush

      cli = Aogera::CLI::BSP29.new(stdout: StringIO.new, stderr: stderr)
      status = cli.run(["--bsp-info", "--pak", file.path, "maps/test.bsp"])

      assert_equal 65, status
      assert_includes stderr.string, "invalid PAK magic"
    end
  end

  def test_malformed_bsp_inside_pak_is_reported_as_data_error
    stderr = StringIO.new

    with_pak("maps/broken.bsp" => "not a bsp".b) do |pak_path|
      cli = Aogera::CLI::BSP29.new(stdout: StringIO.new, stderr: stderr)

      status = cli.run(["--bsp-info", "--pak", pak_path, "maps/broken.bsp"])

      assert_equal 65, status
      assert_includes stderr.string, "BSP29 header is truncated"
    end
  end

  def test_missing_physical_pak_is_reported_as_input_error
    stderr = StringIO.new
    missing = File.join(Dir.tmpdir, "aogera-missing-#{Process.pid}-#{object_id}.pak")
    File.unlink(missing) if File.exist?(missing)
    cli = Aogera::CLI::BSP29.new(stdout: StringIO.new, stderr: stderr)

    status = cli.run(["--bsp-info", "--pak", missing, "maps/test.bsp"])

    assert_equal 66, status
    assert_includes stderr.string, "aogera-bsp29: input not available:"
    assert_includes stderr.string, missing
  end

  private

  def with_pak(entries)
    payload = +"".b
    records = entries.map do |name, bytes|
      bytes = bytes.b
      offset = Aogera::Content::Pak::HEADER_SIZE + payload.bytesize
      payload << bytes
      pak_directory_entry(name, offset, bytes.bytesize)
    end
    directory = records.join.b
    directory_offset = Aogera::Content::Pak::HEADER_SIZE + payload.bytesize
    archive = "PACK".b +
      [directory_offset, directory.bytesize].pack("V2") +
      payload + directory

    Tempfile.create(["aogera-bsp29-cli", ".pak"]) do |file|
      file.binmode
      file.write(archive)
      file.flush
      yield file.path
    end
  end

  def pak_directory_entry(name, offset, length)
    name = name.b
    raise "test PAK name too long" if name.bytesize > Aogera::Content::Pak::NAME_SIZE

    name.ljust(Aogera::Content::Pak::NAME_SIZE, "\0") +
      [offset, length].pack("V2")
  end

  def minimal_bsp
    directory = Array.new(Aogera::BSP29::HEADER_LUMP_COUNT) do
      [Aogera::BSP29::HEADER_SIZE, 0]
    end

    [Aogera::BSP29::VERSION].pack("l<") + directory.flatten.pack(
      "l<#{Aogera::BSP29::HEADER_LUMP_COUNT * 2}"
    )
  end

  def minimal_palette
    bytes = String.new(capacity: Aogera::Quake::PaletteReader::BYTE_SIZE, encoding: Encoding::BINARY)
    256.times do |index|
      bytes << index
      bytes << index
      bytes << index
    end
    bytes
  end

  def build_cli(
    map:,
    app: FakeApp.new(0),
    reader_paths: [],
    modes: [],
    stdout: StringIO.new,
    stderr: StringIO.new
  )
    Aogera::CLI::BSP29.new(
      reader: lambda do |path|
        reader_paths << path
        map
      end,
      app_factory: lambda do |_map, mode:, palette:|
        modes << mode
        raise "unexpected palette for direct BSP" if palette
        app
      end,
      stdout: stdout,
      stderr: stderr
    )
  end

  def fake_map
    world = Aogera::BSP29::Model.new(
      bounds: Aogera::BSP29::Bounds.new(
        mins: vec(-64, -24, -32),
        maxs: vec(64, 96, 128)
      ),
      origin: vec(0, 0, 0),
      headnodes: [0, 1, 2, 3].freeze,
      visible_leaf_count: 4,
      first_face: 0,
      face_count: 5
    )

    FakeMap.new(
      entities: [
        entity("worldspawn", {"message" => "CLI fixture"}),
        entity(
          "info_player_start",
          {"origin" => "12 -36 24"},
          origin: vec(12, 24, 36)
        )
      ].freeze,
      planes: Array.new(3),
      textures: Array.new(4),
      texinfo: Array.new(2),
      vertices: Array.new(5),
      visibility: "vis".b.freeze,
      nodes: Array.new(6),
      faces: Array.new(7),
      clipnodes: Array.new(8),
      leaves: Array.new(9),
      edges: Array.new(10),
      surfedges: Array.new(11),
      models: [world].freeze,
      lighting: "light".b.freeze
    )
  end

  def texture_map
    map = fake_map
    world = Aogera::BSP29::Model.new(
      bounds: map.world_model.bounds,
      origin: map.world_model.origin,
      headnodes: map.world_model.headnodes,
      visible_leaf_count: map.world_model.visible_leaf_count,
      first_face: 0,
      face_count: 4
    )

    FakeMap.new(
      **map.to_h.merge(
        textures: [
          FakeTexture.new("BRICKA2_4", 64, 64),
          FakeTexture.new("METAL1_3", 128, 64),
          nil,
          FakeTexture.new("UNUSED", 32, 32)
        ].freeze,
        texinfo: [
          FakeTexInfo.new(0),
          FakeTexInfo.new(1),
          FakeTexInfo.new(2)
        ].freeze,
        faces: [
          FakeFace.new(0),
          FakeFace.new(1),
          FakeFace.new(0),
          FakeFace.new(2),
          FakeFace.new(3)
        ].freeze,
        models: [world].freeze
      )
    )
  end

  def entity(classname, properties = {}, origin: nil)
    Aogera::BSP29::Entity.new(
      properties: {"classname" => classname}.merge(properties).freeze,
      origin: origin
    )
  end

  def vec(x, y, z)
    Aogera::BSP29::Vec3.new(x: x.to_f, y: y.to_f, z: z.to_f)
  end
end
