# frozen_string_literal: true

require "digest"
require "cfpropertylist"
require "fileutils"
require "json"
require "minitest/autorun"
require "rbconfig"
require "tmpdir"
require "zlib"

IMPLEMENTATION = File.expand_path("media_contract.rb", __dir__)
require IMPLEMENTATION if File.file?(IMPLEMENTATION)
GENERATION_IMPLEMENTATION = File.expand_path("media_generation.rb", __dir__)
require GENERATION_IMPLEMENTATION if File.file?(GENERATION_IMPLEMENTATION)
PREVIEW_IMPLEMENTATION = File.expand_path("generate_app_previews.rb", __dir__)
require PREVIEW_IMPLEMENTATION if File.file?(PREVIEW_IMPLEMENTATION)
SCREENSHOT_IMPLEMENTATION = File.expand_path("generate_screenshots.rb", __dir__)
require SCREENSHOT_IMPLEMENTATION if File.file?(SCREENSHOT_IMPLEMENTATION)
REENCODE_IMPLEMENTATION = File.expand_path("reencode_app_previews.rb", __dir__)
require REENCODE_IMPLEMENTATION if File.file?(REENCODE_IMPLEMENTATION)

class NovaStationMediaContractTest < Minitest::Test
  SOURCE_REVISION = "7f9f56f2d5cb2c4c16f95d95781357c52b7715e07d87ac35d8e7be8d7da86373"
  OVERLAY_FIXTURE_ROOT = File.expand_path("fixtures", __dir__)

  FakeProbe = Struct.new(:calls, :overrides) do
    def probe(path)
      calls << path
      device = NovaStationPinballMediaContract::DEVICES.find do |candidate|
        File.basename(path).include?(candidate.fetch(:id))
      end
      raise "unknown preview device: #{path}" unless device
      {
        "width" => device.fetch(:preview_width),
        "height" => device.fetch(:preview_height),
        "duration" => 24.0,
        "video_duration" => 24.0,
        "audio_duration" => 24.0,
        "video_frames" => 720,
        "frame_rate" => 30.0,
        "video_codec" => "h264",
        "video_profile" => "High",
        "video_level" => 40,
        "pixel_format" => "yuv420p",
        "field_order" => "progressive",
        "rotation" => 0.0,
        "video_bit_rate" => 11_000_000,
        "audio_codec" => "aac",
        "audio_profile" => "LC",
        "audio_bit_rate" => 256_000,
        "audio_channels" => 2,
        "audio_sample_rate" => 48_000,
        "video_streams" => 1,
        "audio_streams" => 1
      }.merge(overrides || {})
    end
  end

  FakeVisualProbe = Struct.new(:overrides) do
    def probe(_path)
      { "width_ratio" => 1.0, "height_ratio" => 1.0 }.merge(overrides || {})
    end
  end

  FakeOverlayGuard = Struct.new(:calls) do
    def validate!(path:, report_path:)
      calls << { path: path, report_path: report_path }
      { "status" => "pass", "scanned_frame_count" => 720 }
    end
  end

  RejectingOverlayGuard = Struct.new(:message) do
    def validate!(path:, report_path:)
      raise NovaStationPinballMediaContract::ContractError,
            "#{message}: #{File.basename(path)} -> #{File.basename(report_path)}"
    end
  end


  FakeCommandStatus = Struct.new(:success?)

  OverlayScanRunner = Struct.new(:stdout, :stderr, :status, :calls) do
    def capture3(*arguments)
      calls << arguments
      [stdout, stderr, status]
    end
  end

  def test_implementation_exists
    assert File.file?(IMPLEMENTATION), "missing scripts/app_store/media_contract.rb"
  end

  def test_system_runner_capture_without_chdir_omits_the_nil_spawn_option
    runner = NovaStationPinballMediaGeneration::SystemRunner.new

    stdout, stderr, status = runner.capture(RbConfig.ruby, "-e", 'print "ready"')

    assert status.success?, stderr
    assert_equal "ready", stdout
  end

  def test_store_screenshot_frame_extraction_uses_stable_preview_offsets_and_strips_metadata
    arguments = NovaStationPinballScreenshotGeneration::PreviewFrameExtraction.arguments(
      source: "/run/preview.mov", destination: "/run/mission.png",
      width: 2_868, height: 1_320, scenario_index: 1
    )

    assert_equal "/opt/homebrew/bin/ffmpeg", arguments.first
    assert_equal "4.500", arguments.fetch(arguments.index("-ss") + 1)
    assert_includes arguments, "scale=2868:1320:flags=lanczos"
    assert_includes arguments, "-map_metadata"
    assert_includes arguments, "-1"
    assert_equal "/run/mission.png", arguments.last
  end

  def test_generation_configuration_requires_three_exact_owned_pool_leases_and_at_most_two_locales
    assert File.file?(GENERATION_IMPLEMENTATION), "missing scripts/app_store/media_generation.rb"
    skip unless defined?(NovaStationPinballMediaGeneration)

    with_owned_pool do |pool_path, lease_paths, execution_id|
      valid = NovaStationPinballMediaGeneration::Configuration.new(
        locales: %w[en-US fr-FR], execution_id: execution_id,
        pool_config_path: pool_path, lease_paths: lease_paths
      )
      assert_equal [%w[en-US fr-FR]], valid.locale_batches
      assert_equal "11111111-1111-1111-1111-111111111111", valid.udids.fetch("iphone-17-pro-max")
      assert_match(%r{\A/private/tmp/apps-factory/NovaStationPinball/#{execution_id}/}, valid.scratch_root("ignored", "en-US", "iphone-se-3", :screenshots))

      assert_raises(NovaStationPinballMediaContract::ContractError) do
        NovaStationPinballMediaGeneration::Configuration.new(
          locales: %w[en-US fr-FR de-DE], execution_id: execution_id,
          pool_config_path: pool_path, lease_paths: lease_paths
        )
      end
      lease = JSON.parse(File.read(lease_paths.fetch("iphone-se-3")))
      lease["execution_id"] = "foreign-execution"
      File.write(lease_paths.fetch("iphone-se-3"), JSON.generate(lease))
      assert_raises(NovaStationPinballMediaContract::ContractError) do
        NovaStationPinballMediaGeneration::Configuration.new(
          locales: ["en-US"], execution_id: execution_id,
          pool_config_path: pool_path, lease_paths: lease_paths
        )
      end
    end
  end

  def test_generation_commands_target_only_exact_udids_and_compile_ready_ui_suites
    assert File.file?(GENERATION_IMPLEMENTATION), "missing scripts/app_store/media_generation.rb"
    skip unless defined?(NovaStationPinballMediaGeneration)

    with_owned_pool do |pool_path, lease_paths, execution_id|
      configuration = NovaStationPinballMediaGeneration::Configuration.new(
        locales: %w[en-US fr-FR], execution_id: execution_id,
        pool_config_path: pool_path, lease_paths: lease_paths
      )
      screenshot = configuration.xcodebuild_arguments(
        kind: :screenshots, locale: "fr-FR", device: "iphone-se-3", run_root: "/ignored"
      )
      assert_includes screenshot, "platform=iOS Simulator,id=22222222-2222-2222-2222-222222222222"
      assert_includes screenshot, "-only-testing:NovaStationPinballUITests/StoreScreenshotUITests"
      refute screenshot.any? { |argument| %w[booted iphone].include?(argument.downcase) }

      assert_respond_to configuration, :build_for_testing_arguments
      assert_respond_to configuration, :test_without_building_arguments
      return unless configuration.respond_to?(:build_for_testing_arguments) &&
                    configuration.respond_to?(:test_without_building_arguments)

      preview_build = configuration.build_for_testing_arguments(
        kind: :app_previews, device: "ipad-pro-13-m5", run_root: "/ignored"
      )
      assert_includes preview_build, "generic/platform=iOS Simulator"
      assert_includes preview_build, "build-for-testing"
      preview_build_derived_data = preview_build.fetch(preview_build.index("-derivedDataPath") + 1)
      assert_equal File.join(
        "/private/tmp/apps-factory/NovaStationPinball", execution_id,
        "app_previews", "canonical", "ipad-pro-13-m5", "DerivedData"
      ), preview_build_derived_data
      refute preview_build.any? { |argument| argument.include?("33333333-3333-3333-3333-333333333333") }

      preview_test = configuration.test_without_building_arguments(
        kind: :app_previews, locale: "fr-FR", device: "ipad-pro-13-m5", run_root: "/ignored",
        xctestrun: "/isolated/NovaStationPinball.xctestrun"
      )
      assert_includes preview_test, "test-without-building"
      assert_includes preview_test, "-xctestrun"
      assert_includes preview_test, "/isolated/NovaStationPinball.xctestrun"
      assert_includes preview_test, "platform=iOS Simulator,id=33333333-3333-3333-3333-333333333333"
      assert_includes preview_test, "-only-testing:NovaStationPinballUITests/AppPreviewUITests"
      assert_equal preview_build_derived_data,
                   preview_test.fetch(preview_test.index("-derivedDataPath") + 1)

      english_test = configuration.test_without_building_arguments(
        kind: :app_previews, locale: "en-US", device: "ipad-pro-13-m5", run_root: "/ignored",
        xctestrun: "/isolated/en/NovaStationPinball.xctestrun"
      )
      assert_equal preview_build_derived_data,
                   english_test.fetch(english_test.index("-derivedDataPath") + 1)
      refute_equal preview_test.fetch(preview_test.index("-resultBundlePath") + 1),
                   english_test.fetch(english_test.index("-resultBundlePath") + 1)
    end
  end

  def test_app_preview_injects_handshake_token_into_isolated_xctestrun_ui_target
    assert defined?(NovaStationPinballMediaGeneration::XCTestRunConfigurator),
           "missing isolated xctestrun configurator"
    return unless defined?(NovaStationPinballMediaGeneration::XCTestRunConfigurator)

    Dir.mktmpdir("nova-xctestrun", "/private/tmp") do |root|
      products = File.join(root, "DerivedData", "Build", "Products")
      FileUtils.mkdir_p(products)
      source = File.join(products, "NovaStationPinball.xctestrun")
      destination = File.join(root, "worker", "xctestrun", "NovaStationPinball.xctestrun")
      payload = {
        "TestConfigurations" => [{
          "Name" => "Test Scheme Action",
          "TestTargets" => [
            { "BlueprintName" => "NovaStationPinballTests",
              "TestBundlePath" => "__TESTROOT__/Debug-iphonesimulator/NovaStationPinballTests.xctest" },
            { "BlueprintName" => "NovaStationPinballUITests",
              "TestBundlePath" => "__TESTROOT__/Debug-iphonesimulator/NovaStationPinballUITests-Runner.app/PlugIns/NovaStationPinballUITests.xctest",
              "EnvironmentVariables" => { "EXISTING" => "preserved" },
              "EnvironmentVariablesEnabled" => { "EXISTING" => true } }
          ]
        }],
        "__xctestrun_metadata__" => { "FormatVersion" => 2 }
      }
      write_plist(source, payload)

      token = "d" * 32
      configured = NovaStationPinballMediaGeneration::XCTestRunConfigurator.new.inject_environment!(
        source: source, destination: destination,
        isolation_root: File.join(root, "worker"),
        target_name: "NovaStationPinballUITests",
        environment: { "NOVA_MEDIA_HANDSHAKE_TOKEN" => token, "NOVA_MEDIA_LOCALE" => "en-US" }
      )

      assert_equal destination, configured
      result = read_plist(destination)
      targets = result.fetch("TestConfigurations").first.fetch("TestTargets")
      unit = targets.find { |target| target["BlueprintName"] == "NovaStationPinballTests" }
      ui = targets.find { |target| target["BlueprintName"] == "NovaStationPinballUITests" }
      refute unit.key?("EnvironmentVariables")
      assert_equal "preserved", ui.fetch("EnvironmentVariables").fetch("EXISTING")
      assert_equal token, ui.fetch("EnvironmentVariables").fetch("NOVA_MEDIA_HANDSHAKE_TOKEN")
      assert_equal "en-US", ui.fetch("EnvironmentVariables").fetch("NOVA_MEDIA_LOCALE")
      assert_equal token, ui.fetch("TestingEnvironmentVariables").fetch("NOVA_MEDIA_HANDSHAKE_TOKEN")
      assert_equal "en-US", ui.fetch("TestingEnvironmentVariables").fetch("NOVA_MEDIA_LOCALE")
      assert_equal true, ui.fetch("EnvironmentVariablesEnabled").fetch("NOVA_MEDIA_HANDSHAKE_TOKEN")
      assert_includes ui.fetch("TestBundlePath"), products
      refute_includes ui.fetch("TestBundlePath"), "__TESTROOT__"
      refute_equal File.binread(source), File.binread(destination)
      assert_equal 0o600, File.stat(destination).mode & 0o777
    end
  end

  def test_app_preview_xctestrun_copy_cannot_escape_its_execution_scratch
    assert defined?(NovaStationPinballMediaGeneration::XCTestRunConfigurator)
    return unless defined?(NovaStationPinballMediaGeneration::XCTestRunConfigurator)

    Dir.mktmpdir("nova-xctestrun-escape", "/private/tmp") do |root|
      source = File.join(root, "source.xctestrun")
      write_plist(source, {
        "NovaStationPinballUITests" => {
          "BlueprintName" => "NovaStationPinballUITests",
          "TestBundlePath" => "__TESTROOT__/NovaStationPinballUITests.xctest"
        }
      })
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        NovaStationPinballMediaGeneration::XCTestRunConfigurator.new.inject_environment!(
          source: source, destination: File.join(root, "..", "escaped.xctestrun"),
          isolation_root: File.join(root, "execution"),
          target_name: "NovaStationPinballUITests",
          environment: { "NOVA_MEDIA_HANDSHAKE_TOKEN" => "e" * 32, "NOVA_MEDIA_LOCALE" => "fr-FR" }
        )
      end
      assert_includes error.message, "execution scratch"
      refute File.exist?(File.expand_path(File.join(root, "..", "escaped.xctestrun")))
    end
  end

  def test_app_preview_xctestrun_rejects_unknown_or_missing_media_locale
    configurator = NovaStationPinballMediaGeneration::XCTestRunConfigurator.new
    token = "e" * 32
    assert_raises(NovaStationPinballMediaContract::ContractError) do
      configurator.send(:validate_environment!, "NOVA_MEDIA_HANDSHAKE_TOKEN" => token)
    end
    assert_raises(NovaStationPinballMediaContract::ContractError) do
      configurator.send(
        :validate_environment!,
        "NOVA_MEDIA_HANDSHAKE_TOKEN" => token, "NOVA_MEDIA_LOCALE" => "de-DE"
      )
    end
  end

  def test_app_preview_generator_builds_once_per_device_then_runs_en_and_fr_from_the_same_artifacts
    devices = {
      "iphone-17-pro-max" => "11111111-1111-1111-1111-111111111111",
      "iphone-se-3" => "22222222-2222-2222-2222-222222222222",
      "ipad-pro-13-m5" => "33333333-3333-3333-3333-333333333333"
    }
    configuration = Object.new
    configuration.define_singleton_method(:udids) { devices }
    configuration.define_singleton_method(:locales) { %w[en-US fr-FR] }
    configuration.define_singleton_method(:assert_owned!) { true }

    generator_class = Class.new(NovaStationPinballPreviewGeneration::Generator) do
      attr_reader :events

      def seed(configuration)
        @configuration = configuration
        @run_root = "/private/tmp/nova-preview-orchestration"
        @events = []
        self
      end

      def prepare_only!
        events << :prepare_manifest
      end

      def prepare_canonical_test_artifacts!(device)
        events << [:build, device]
        "canonical-#{device}"
      end

      def boot_owned_simulator!(udid)
        events << [:boot, udid]
      end

      def generate_locale!(locale, device, canonical)
        events << [:test, locale, device, canonical]
      end

      def shutdown_owned_simulator!(udid)
        events << [:shutdown, udid]
      end
    end
    generator = generator_class.allocate.seed(configuration)

    assert_equal "/private/tmp/nova-preview-orchestration", generator.generate!
    devices.each do |device, udid|
      assert_equal 1, generator.events.count { |event| event == [:build, device] }
      build_index = generator.events.index([:build, device])
      english_index = generator.events.index([:test, "en-US", device, "canonical-#{device}"])
      french_index = generator.events.index([:test, "fr-FR", device, "canonical-#{device}"])
      shutdown_index = generator.events.index([:shutdown, udid])
      assert_operator build_index, :<, english_index
      assert_operator english_index, :<, french_index
      assert_operator french_index, :<, shutdown_index
    end
    source = File.read(PREVIEW_IMPLEMENTATION, encoding: "UTF-8")
    refute_match(/runner\.capture\(\s*"xcrun",\s*"simctl",\s*"(?:install|uninstall)"/m, source)
  end

  def test_app_preview_generator_stops_on_first_locale_failure_and_still_shuts_down_owned_device
    devices = {
      "iphone-17-pro-max" => "11111111-1111-1111-1111-111111111111",
      "iphone-se-3" => "22222222-2222-2222-2222-222222222222"
    }
    configuration = Object.new
    configuration.define_singleton_method(:udids) { devices }
    configuration.define_singleton_method(:locales) { %w[en-US fr-FR] }
    configuration.define_singleton_method(:assert_owned!) { true }

    generator_class = Class.new(NovaStationPinballPreviewGeneration::Generator) do
      attr_reader :events

      def seed(configuration)
        @configuration = configuration
        @run_root = "/private/tmp/nova-preview-fail-fast"
        @events = []
        self
      end

      def prepare_only!
        events << :prepare_manifest
      end

      def prepare_canonical_test_artifacts!(device)
        events << [:build, device]
        "canonical-#{device}"
      end

      def boot_owned_simulator!(udid)
        events << [:boot, udid]
      end

      def generate_locale!(locale, device, _canonical)
        events << [:test, locale, device]
        raise NovaStationPinballMediaContract::ContractError, "first red" if locale == "fr-FR"
      end

      def shutdown_owned_simulator!(udid)
        events << [:shutdown, udid]
      end
    end
    generator = generator_class.allocate.seed(configuration)

    error = assert_raises(NovaStationPinballMediaContract::ContractError) { generator.generate! }
    assert_equal "first red", error.message
    assert_includes generator.events, [:test, "en-US", "iphone-17-pro-max"]
    assert_includes generator.events, [:test, "fr-FR", "iphone-17-pro-max"]
    assert_includes generator.events, [:shutdown, devices.fetch("iphone-17-pro-max")]
    refute_includes generator.events, [:build, "iphone-se-3"]
  end

  def test_app_preview_locale_copies_share_canonical_products_but_have_distinct_exact_tokens
    Dir.mktmpdir("nova-canonical-xctestrun", "/private/tmp") do |root|
      canonical_products = File.join(root, "canonical", "DerivedData", "Build", "Products")
      FileUtils.mkdir_p(canonical_products)
      source = File.join(canonical_products, "NovaStationPinball.xctestrun")
      write_plist(source, {
        "NovaStationPinballUITests" => {
          "BlueprintName" => "NovaStationPinballUITests",
          "TestBundlePath" => "__TESTROOT__/Debug-iphonesimulator/NovaStationPinballUITests-Runner.app/PlugIns/NovaStationPinballUITests.xctest"
        }
      })
      configurator = NovaStationPinballMediaGeneration::XCTestRunConfigurator.new
      configured = {
        "en-US" => ["a" * 32, File.join(root, "en-US", "xctestrun", "Nova.xctestrun")],
        "fr-FR" => ["b" * 32, File.join(root, "fr-FR", "xctestrun", "Nova.xctestrun")]
      }
      payloads = configured.to_h do |locale, (token, destination)|
        configurator.inject_environment!(
          source: source, destination: destination, isolation_root: File.join(root, locale),
          target_name: "NovaStationPinballUITests",
          environment: { "NOVA_MEDIA_HANDSHAKE_TOKEN" => token, "NOVA_MEDIA_LOCALE" => locale }
        )
        assert_equal 0o600, File.stat(destination).mode & 0o777
        [locale, read_plist(destination).fetch("NovaStationPinballUITests")]
      end

      english = payloads.fetch("en-US")
      french = payloads.fetch("fr-FR")
      assert_equal english.fetch("TestBundlePath"), french.fetch("TestBundlePath")
      assert_includes english.fetch("TestBundlePath"), canonical_products
      assert_equal "a" * 32, english.fetch("EnvironmentVariables").fetch("NOVA_MEDIA_HANDSHAKE_TOKEN")
      assert_equal "b" * 32, french.fetch("EnvironmentVariables").fetch("NOVA_MEDIA_HANDSHAKE_TOKEN")
      refute_equal english.fetch("EnvironmentVariables").fetch("NOVA_MEDIA_HANDSHAKE_TOKEN"),
                   french.fetch("EnvironmentVariables").fetch("NOVA_MEDIA_HANDSHAKE_TOKEN")
      configured.each do |locale, (token, _destination)|
        payload = payloads.fetch(locale)
        assert_equal token, payload.fetch("TestingEnvironmentVariables").fetch("NOVA_MEDIA_HANDSHAKE_TOKEN")
        assert_equal locale, payload.fetch("TestingEnvironmentVariables").fetch("NOVA_MEDIA_LOCALE")
        assert_equal true, payload.fetch("EnvironmentVariablesEnabled").fetch("NOVA_MEDIA_HANDSHAKE_TOKEN")
        assert_equal true, payload.fetch("EnvironmentVariablesEnabled").fetch("NOVA_MEDIA_LOCALE")
      end
    end
  end

  def test_app_preview_generator_allocates_a_distinct_handshake_token_per_locale_capture
    generator = NovaStationPinballPreviewGeneration::Generator.allocate
    generator.instance_variable_set(:@runner, Object.new)
    tokens = 6.times.map do
      generator.send(:handshake_for, "11111111-1111-1111-1111-111111111111").token
    end
    assert_equal 6, tokens.uniq.length
    assert tokens.all? { |token| token.match?(/\A[0-9a-f]{32}\z/) }
  end

  def test_generation_rejects_wrong_pool_model_runtime_udid_and_symlinked_lock
    mutations = [
      ->(pool) { pool.fetch("devices").first["runtime"] = "com.apple.CoreSimulator.SimRuntime.iOS-26-1" },
      ->(pool) { pool.fetch("devices").first["device_type"] = "com.apple.CoreSimulator.SimDeviceType.iPhone-17" },
      ->(pool) { pool.fetch("devices").first["udid"] = pool.fetch("devices")[1].fetch("udid") }
    ]
    mutations.each do |mutation|
      with_owned_pool do |pool_path, lease_paths, execution_id|
        pool = JSON.parse(File.read(pool_path))
        mutation.call(pool)
        File.write(pool_path, JSON.generate(pool))
        assert_raises(NovaStationPinballMediaContract::ContractError) do
          NovaStationPinballMediaGeneration::Configuration.new(
            locales: ["en-US"], execution_id: execution_id,
            pool_config_path: pool_path, lease_paths: lease_paths
          )
        end
      end
    end

    with_owned_pool do |pool_path, lease_paths, execution_id|
      lock = lease_paths.fetch("ipad-pro-13-m5")
      payload = File.binread(lock)
      File.unlink(lock)
      foreign = File.join(File.dirname(lock), "foreign.lock")
      File.binwrite(foreign, payload)
      File.symlink(foreign, lock)
      assert_raises(NovaStationPinballMediaContract::ContractError) do
        NovaStationPinballMediaGeneration::Configuration.new(
          locales: ["en-US"], execution_id: execution_id,
          pool_config_path: pool_path, lease_paths: lease_paths
        )
      end
    end
  end

  def test_app_preview_encoding_arguments_match_apple_h264_requirements
    arguments = NovaStationPinballPreviewGeneration::Encoding.arguments(
      source: "/tmp/raw.mov", destination: "/tmp/final.mov", width: 1_920, height: 886, trim_offset: 0.25
    )
    %w[-ss 0.250 -t 24 -profile:v high -level:v 4.0 -pix_fmt yuv420p -b:v 11M -minrate 11M -maxrate 11M -b:a 256k -ar 48000 -ac 2].each_slice(2) do |flag, value|
      index = arguments.index(flag)
      refute_nil index, "missing ffmpeg flag #{flag}"
      assert_equal value, arguments[index + 1]
    end
    assert_includes arguments.fetch(arguments.index("-vf") + 1), "fps=30"
    assert_includes arguments.fetch(arguments.index("-vf") + 1), "tpad=stop_mode=clone:stop_duration=0.000000"
    assert_includes arguments.fetch(arguments.index("-vf") + 1), "trim=end_frame=720"
    assert_includes arguments.fetch(arguments.index("-vf") + 1), "setpts=N/(30*TB)"
    assert_includes arguments.fetch(arguments.index("-vf") + 1), "setfield=prog"
    assert_equal "720", arguments.fetch(arguments.index("-frames:v") + 1)
    assert_equal "atrim=duration=24,asetpts=N/SR/TB", arguments.fetch(arguments.index("-af") + 1)
    refute_includes arguments, "-shortest"
    assert_match(/\Atranspose=clock,scale=1920:886:/, arguments.fetch(arguments.index("-vf") + 1))
    se_arguments = NovaStationPinballPreviewGeneration::Encoding.arguments(
      source: "/tmp/raw.mov", destination: "/tmp/se.mov", width: 1_334, height: 750,
      trim_offset: 0.25, transform: "transpose=clock"
    )
    assert_match(/\Atranspose=clock,scale=1334:750:/,
                 se_arguments.fetch(se_arguments.index("-vf") + 1))
    assert NovaStationPinballMediaContract::DEVICES.all? { |device| device.fetch(:raw_transform) == "transpose=clock" }
  end

  def test_system_overlay_guard_accepts_the_clean_720_frame_fixture_and_writes_a_0600_report
    fixture = overlay_fixture("system_overlay_clean.json")
    runner = OverlayScanRunner.new(
      overlay_metadata_output(fixture), "", FakeCommandStatus.new(true), []
    )
    Dir.mktmpdir("nova-overlay-clean", "/private/tmp") do |root|
      video = File.join(root, "clean.mov")
      report_path = File.join(root, "logs", "clean.json")
      File.binwrite(video, "clean-fixture-video")
      report = NovaStationPinballMediaContract::SystemOverlayGuard.new(
        runner: runner, captured_at: -> { Time.utc(2026, 8, 10, 6, 0, 0) }
      ).validate!(path: video, report_path: report_path)

      assert_equal "pass", report.fetch("status")
      assert_equal 720, report.fetch("scanned_frame_count")
      assert_equal 0, report.fetch("violation_count")
      assert_equal 0o600, File.stat(report_path).mode & 0o777
      persisted = JSON.parse(File.read(report_path, encoding: "UTF-8"))
      assert_equal Digest::SHA256.file(video).hexdigest, persisted.fetch("video_sha256")
      arguments = runner.calls.fetch(0)
      assert_includes arguments, NovaStationPinballMediaContract::SystemOverlayGuard::TOP_BAND_FILTER
      assert_equal "/dev/null", arguments.last
    end
  end

  def test_system_overlay_guard_rejects_the_en_se_notification_from_12_466667_through_19_900000
    fixture = overlay_fixture("system_overlay_polluted_en_se.json")
    runner = OverlayScanRunner.new(
      overlay_metadata_output(fixture), "", FakeCommandStatus.new(true), []
    )
    Dir.mktmpdir("nova-overlay-polluted", "/private/tmp") do |root|
      video = File.join(root, "en-se.mov")
      report_path = File.join(root, "logs", "en-se.json")
      File.binwrite(video, "polluted-en-se-fixture-video")
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        NovaStationPinballMediaContract::SystemOverlayGuard.new(
          runner: runner, captured_at: -> { Time.utc(2026, 8, 10, 6, 0, 0) }
        ).validate!(path: video, report_path: report_path)
      end

      assert_includes error.message, "rejected 224 frame(s)"
      assert_includes error.message, "PTS 12.466667-19.900000"
      report = JSON.parse(File.read(report_path, encoding: "UTF-8"))
      assert_equal "fail", report.fetch("status")
      assert_equal 720, report.fetch("scanned_frame_count")
      assert_equal 224, report.fetch("violation_count")
      span = report.fetch("violation_spans").fetch(0)
      assert_equal 374, span.fetch("first_frame")
      assert_equal 597, span.fetch("last_frame")
      assert_equal 12.466667, span.fetch("first_pts_seconds")
      assert_equal 19.9, span.fetch("last_pts_seconds")
      assert_equal 19.933333, span.fetch("end_pts_exclusive_seconds")
      assert_equal 224, report.fetch("violating_frames").length
      assert_equal 0o600, File.stat(report_path).mode & 0o777
    end
  end

  def test_system_overlay_guard_fails_closed_when_the_scan_is_not_exhaustive
    fixture = overlay_fixture("system_overlay_clean.json").merge("frame_count" => 719)
    runner = OverlayScanRunner.new(
      overlay_metadata_output(fixture), "", FakeCommandStatus.new(true), []
    )
    Dir.mktmpdir("nova-overlay-short", "/private/tmp") do |root|
      video = File.join(root, "short.mov")
      report_path = File.join(root, "logs", "short.json")
      File.binwrite(video, "short-fixture-video")
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        NovaStationPinballMediaContract::SystemOverlayGuard.new(runner: runner).validate!(
          path: video, report_path: report_path
        )
      end

      assert_includes error.message, "exactly 720 sequential frames"
      report = JSON.parse(File.read(report_path, encoding: "UTF-8"))
      assert_equal "error", report.fetch("status")
      assert_includes report.fetch("error"), "exactly 720 sequential frames"
    end
  end

  def test_app_preview_raw_geometry_must_be_portrait_inverse_of_store_device
    device = NovaStationPinballMediaContract::DEVICES.first

    assert NovaStationPinballPreviewGeneration::RawGeometry.validate!(
      width: device.fetch(:height), height: device.fetch(:width), device: device
    )
    error = assert_raises(NovaStationPinballMediaContract::ContractError) do
      NovaStationPinballPreviewGeneration::RawGeometry.validate!(
        width: device.fetch(:width), height: device.fetch(:height), device: device
      )
    end
    assert_includes error.message, "raw App Preview geometry"
  end

  def test_app_entry_hides_system_status_chrome_for_immersive_gameplay
    source = File.read(
      File.expand_path("../../NovaStationPinball/App/NovaStationPinballApp.swift", __dir__),
      encoding: "UTF-8"
    )
    assert_includes source, ".statusBarHidden(true)"
  end

  def test_raw_preview_reuse_extracts_and_hashes_the_verified_handshake_token
    assert File.file?(REENCODE_IMPLEMENTATION), "missing raw preview reuse implementation"
    return unless defined?(NovaStationPinballPreviewReencoding)

    reencoder = File.read(REENCODE_IMPLEMENTATION, encoding: "UTF-8")
    overlay_index = reencoder.index("SystemOverlayGuard.new")
    mark_index = reencoder.index("mark_artifact!", overlay_index || 0)
    refute_nil overlay_index
    refute_nil mark_index
    assert_operator overlay_index, :<, mark_index

    Dir.mktmpdir do |root|
      xctestrun = File.join(root, "source.xctestrun")
      File.write(xctestrun, <<~XML)
        <key>NOVA_MEDIA_HANDSHAKE_TOKEN</key>
        <string>0123456789abcdef0123456789abcdef</string>
      XML
      assert_equal Digest::SHA256.hexdigest("0123456789abcdef0123456789abcdef"),
                   NovaStationPinballPreviewReencoding::Source.handshake_sha256(xctestrun)
    end
  end

  def test_app_preview_trim_offset_tracks_variable_monotonic_handshake_latency
    assert defined?(NovaStationPinballPreviewGeneration::CaptureTiming),
           "missing monotonic App Preview capture timing"
    return unless defined?(NovaStationPinballPreviewGeneration::CaptureTiming)

    short = NovaStationPinballPreviewGeneration::CaptureTiming.trim_offset(
      recording_origin: 100.0, timeline_started: 100.2374
    )
    long = NovaStationPinballPreviewGeneration::CaptureTiming.trim_offset(
      recording_origin: 200.0, timeline_started: 202.8146
    )
    assert_in_delta 0.237, short, 0.0001
    assert_in_delta 2.815, long, 0.0001
    refute_equal short, long
    short_arguments = NovaStationPinballPreviewGeneration::Encoding.arguments(
      source: "/tmp/raw.mov", destination: "/tmp/short.mov",
      width: 1_334, height: 750, trim_offset: short
    )
    long_arguments = NovaStationPinballPreviewGeneration::Encoding.arguments(
      source: "/tmp/raw.mov", destination: "/tmp/long.mov",
      width: 1_334, height: 750, trim_offset: long
    )
    assert_equal "0.237", short_arguments.fetch(short_arguments.index("-ss") + 1)
    assert_equal "2.815", long_arguments.fetch(long_arguments.index("-ss") + 1)
  end

  def test_capture_window_wait_targets_cover_the_short_en_se_and_ipad_regression
    window = NovaStationPinballPreviewGeneration::CaptureWindow

    assert_in_delta 25.792, window.minimum_raw_elapsed(0.792), 0.000_001
    assert_in_delta 26.009, window.minimum_raw_elapsed(1.009), 0.000_001
    assert_equal 24.0, window::TIMELINE_SECONDS
    assert_equal 1.0, window::RAW_TAIL_MARGIN_SECONDS
  end

  def test_capture_window_refuses_the_observed_short_en_se_and_ipad_raw_segments
    window = NovaStationPinballPreviewGeneration::CaptureWindow
    failures = [
      { raw_end: 24.641667, trim_offset: 0.792, deficit: "0.150" },
      { raw_end: 24.700000, trim_offset: 1.009, deficit: "0.309" }
    ]

    failures.each do |sample|
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        window.residual_padding(raw_end: sample.fetch(:raw_end), trim_offset: sample.fetch(:trim_offset))
      end
      assert_includes error.message, "residual padding is limited"
      assert_includes error.message, sample.fetch(:deficit)
    end
  end

  def test_capture_window_allows_only_one_frame_of_residual_padding
    window = NovaStationPinballPreviewGeneration::CaptureWindow

    padding = window.residual_padding(raw_end: 24.985, trim_offset: 1.0)
    assert_in_delta 1.0 / 30.0, padding, 0.000_001
    assert_equal 0.0, window.residual_padding(raw_end: 25.2, trim_offset: 1.0)
    assert_raises(NovaStationPinballMediaContract::ContractError) do
      window.residual_padding(raw_end: 24.96, trim_offset: 1.0)
    end

    arguments = NovaStationPinballPreviewGeneration::Encoding.arguments(
      source: "/tmp/raw.mov", destination: "/tmp/final.mov",
      width: 1_334, height: 750, trim_offset: 1.0, padding_duration: padding
    )
    assert_includes arguments.fetch(arguments.index("-vf") + 1),
                    "tpad=stop_mode=clone:stop_duration=0.033333"
  end

  def test_app_preview_source_requires_ready_recording_started_and_complete_handshake
    source = File.read(PREVIEW_IMPLEMENTATION, encoding: "UTF-8")
    generation = File.read(GENERATION_IMPLEMENTATION, encoding: "UTF-8")
    ui_source = File.read(File.expand_path("../../NovaStationPinballUITests/AppPreviewUITests.swift", __dir__), encoding: "UTF-8")
    %w[ready recording started complete].each { |marker| assert_includes source, %Q{"#{marker}"} }
    assert_operator source.index('wait_for!("ready"'), :<, source.index("recordVideo")
    readiness = source.rindex("wait_until_writing!")
    refute_nil readiness, "recorder readiness must precede the app recording marker"
    assert_operator readiness, :<, source.index('write!("recording"')
    assert_operator source.index('write!("recording"'), :<, source.index('wait_for!("started"')
    raw_tail_wait = source.rindex("recorder.wait_until_elapsed!")
    assert_operator source.index('wait_for!("complete"'), :<, raw_tail_wait
    assert_operator raw_tail_wait, :<, source.index("Process.kill")
    assert_includes source, "NOVA_MEDIA_HANDSHAKE_TOKEN"
    assert_includes source, "NOVA_MEDIA_LOCALE"
    assert_includes ui_source, '"-AppleLanguages"'
    assert_includes ui_source, '"-AppleLocale"'
    assert_includes ui_source, 'XCUIApplication(bundleIdentifier: "com.apple.springboard")'
    assert_includes ui_source, 'notificationIdentifier = "NotificationShortLookView"'
    assert_includes ui_source, "initialDelaySeconds: TimeInterval = 30"
    assert_includes ui_source, "requiredContinuousAbsenceSeconds: TimeInterval = 5"
    assert_includes ui_source, "maximumObservationSeconds: TimeInterval = 30"
    assert_operator ui_source.index("guard waitForSpringBoardToSettle()"), :<,
                    ui_source.index("let app = XCUIApplication()")
    assert_includes generation, "build-for-testing"
    assert_includes generation, "test-without-building"
    refute_match(/Process\.spawn\(\s*\{\s*"NOVA_MEDIA_HANDSHAKE_TOKEN"/m, source)
    refute_includes source, '"booted"'
    guard_index = source.index("validate_system_overlay!(destination, locale, device)")
    mark_index = source.index("mark_artifact!", guard_index || 0)
    refute_nil guard_index
    refute_nil mark_index
    assert_operator guard_index, :<, mark_index
    assert_includes source, "timeout: 90.0"
  end

  def test_recorder_readiness_requires_the_exact_live_pid_and_growing_nonempty_file
    assert defined?(NovaStationPinballPreviewGeneration::RecorderReadiness),
           "missing recorder readiness probe"
    return unless defined?(NovaStationPinballPreviewGeneration::RecorderReadiness)

    Dir.mktmpdir("nova-recorder-ready") do |root|
      output = File.join(root, "raw.mov")
      pid = Process.spawn(
        RbConfig.ruby, "-e",
        "path=ARGV.fetch(0); File.open(path, 'wb') { |f| f.write('header'); f.flush; sleep 0.08; f.write('frame'); f.flush; sleep 1 }",
        output, out: File::NULL, err: File::NULL
      )
      readiness = NovaStationPinballPreviewGeneration::RecorderReadiness.new(
        path: output, pid: pid, timeout: 0.8, poll_interval: 0.02
      )
      assert readiness.wait_until_writing!
      assert_operator File.size(output), :>, 6
    ensure
      terminate_test_process(pid)
    end
  end

  def test_recorder_readiness_timeout_is_fail_closed_and_cleanup_targets_only_owned_pid
    Dir.mktmpdir("nova-recorder-timeout") do |root|
      output = File.join(root, "raw.mov")
      pid = Process.spawn(
        RbConfig.ruby, "-e",
        "File.open(ARGV.fetch(0), 'wb') { |f| f.write('header'); f.flush; sleep 5 }",
        output, out: File::NULL, err: File::NULL
      )
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        NovaStationPinballPreviewGeneration::RecorderReadiness.new(
          path: output, pid: pid, timeout: 0.15, poll_interval: 0.02
        ).wait_until_writing!
      end
      assert_includes error.message, "growing non-empty file"

      NovaStationPinballPreviewGeneration::Generator.allocate.send(
        :stop_owned_process!, pid, "TERM", timeout: 0.1
      )
      assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
      pid = nil
    ensure
      terminate_test_process(pid)
    end
  end

  def test_recorder_waits_for_the_full_raw_capture_deadline_while_its_exact_pid_is_live
    pid = Process.spawn(RbConfig.ruby, "-e", "sleep 5", out: File::NULL, err: File::NULL)
    readings = [100.0, 100.4, 101.0]
    sleeps = []
    readiness = NovaStationPinballPreviewGeneration::RecorderReadiness.new(
      path: "/private/tmp/unused-recorder.mov", pid: pid, poll_interval: 0.5,
      clock: -> { readings.shift || 101.0 }, sleeper: ->(duration) { sleeps << duration }
    )

    reached = readiness.wait_until_elapsed!(recording_origin: 100.0, minimum_duration: 1.0)

    assert_equal 101.0, reached
    assert_equal [0.5, 0.5], sleeps
  ensure
    terminate_test_process(pid)
  end

  def test_app_preview_handshake_waits_for_exact_app_container_until_ready
    Dir.mktmpdir("nova-handshake") do |container|
      token = "b" * 32
      marker = File.join(container, "Library", "Caches", "NovaStationMediaHandshake", token, "ready")
      FileUtils.mkdir_p(File.dirname(marker))
      File.binwrite(marker, token)
      status = Struct.new(:success?)
      runner = Struct.new(:responses, :calls) do
        def capture(*arguments)
          calls << arguments
          responses.shift
        end
      end.new([
        ["", "not installed", status.new(false)],
        ["", "not launched", status.new(false)],
        ["#{container}\n", "", status.new(true)]
      ], [])
      handshake = NovaStationPinballPreviewGeneration::Handshake.new(
        udid: "11111111-1111-1111-1111-111111111111", runner: runner,
        token: token, timeout: 0.2
      )
      assert handshake.wait_for!("ready")
      assert_equal 3, runner.calls.length
      assert runner.calls.all? { |arguments| arguments.include?("11111111-1111-1111-1111-111111111111") }
      refute runner.calls.flatten.include?("booted")
    end
  end

  def test_app_preview_boot_waits_for_the_exact_owned_udid_to_be_ready
    status = Struct.new(:success?)
    runner = Struct.new(:calls, :status) do
      def capture(*arguments)
        calls << arguments
        ["", "", status.new(true)]
      end
    end.new([], status)
    generator = NovaStationPinballPreviewGeneration::Generator.allocate
    generator.instance_variable_set(:@runner, runner)
    udid = "11111111-1111-1111-1111-111111111111"

    generator.send(:boot_owned_simulator!, udid)

    assert_equal [
      ["xcrun", "simctl", "boot", udid],
      ["xcrun", "simctl", "bootstatus", udid, "-b"]
    ], runner.calls
    refute runner.calls.flatten.include?("booted")
  end

  def test_app_preview_boot_fails_closed_when_the_fresh_owned_device_cannot_boot
    status = Struct.new(:success?).new(false)
    runner = Struct.new(:calls, :status) do
      def capture(*arguments)
        calls << arguments
        ["", "device was not in the expected fresh state", status]
      end
    end.new([], status)
    generator = NovaStationPinballPreviewGeneration::Generator.allocate
    generator.instance_variable_set(:@runner, runner)
    udid = "11111111-1111-1111-1111-111111111111"

    error = assert_raises(NovaStationPinballMediaContract::ContractError) do
      generator.send(:boot_owned_simulator!, udid)
    end

    assert_includes error.message, "could not boot owned App Preview simulator"
    assert_equal [["xcrun", "simctl", "boot", udid]], runner.calls
  end

  def test_app_preview_shutdown_targets_only_the_owned_udid
    status = Struct.new(:success?).new(true)
    runner = Struct.new(:calls, :status) do
      def capture(*arguments)
        calls << arguments
        ["", "", status]
      end
    end.new([], status)
    generator = NovaStationPinballPreviewGeneration::Generator.allocate
    generator.instance_variable_set(:@runner, runner)
    udid = "11111111-1111-1111-1111-111111111111"

    generator.send(:shutdown_owned_simulator!, udid)

    assert_equal [["xcrun", "simctl", "shutdown", udid]], runner.calls
  end

  def test_app_preview_shutdown_accepts_an_already_stopped_owned_device
    status = Struct.new(:success?).new(false)
    runner = Struct.new(:status) do
      def capture(*_arguments)
        ["", "Unable to shutdown device in current state: Shutdown", status]
      end
    end.new(status)
    generator = NovaStationPinballPreviewGeneration::Generator.allocate
    generator.instance_variable_set(:@runner, runner)

    assert_nil generator.send(:shutdown_owned_simulator!, "11111111-1111-1111-1111-111111111111")
  end

  def test_app_preview_shutdown_fails_closed_on_ambiguous_cleanup
    status = Struct.new(:success?).new(false)
    runner = Struct.new(:status) do
      def capture(*_arguments)
        ["", "CoreSimulator service unavailable", status]
      end
    end.new(status)
    generator = NovaStationPinballPreviewGeneration::Generator.allocate
    generator.instance_variable_set(:@runner, runner)

    error = assert_raises(NovaStationPinballMediaContract::ContractError) do
      generator.send(:shutdown_owned_simulator!, "11111111-1111-1111-1111-111111111111")
    end
    assert_includes error.message, "could not shut down owned App Preview simulator"
  end

  def test_app_preview_handshake_refreshes_the_container_after_xcode_reinstalls_the_app
    Dir.mktmpdir("nova-handshake-old") do |old_container|
      Dir.mktmpdir("nova-handshake-current") do |current_container|
        token = "d" * 32
        marker = File.join(
          current_container, "Library", "Caches", "NovaStationMediaHandshake", token, "ready"
        )
        FileUtils.mkdir_p(File.dirname(marker))
        File.binwrite(marker, token)
        status = Struct.new(:success?)
        runner = Struct.new(:containers, :calls, :status) do
          def capture(*arguments)
            calls << arguments
            container = containers.shift || containers.last
            ["#{container}\n", "", status.new(true)]
          end
        end.new([old_container, current_container], [], status)
        handshake = NovaStationPinballPreviewGeneration::Handshake.new(
          udid: "11111111-1111-1111-1111-111111111111", runner: runner,
          token: token, timeout: 0.2
        )

        assert handshake.wait_for!("ready")
        assert_operator runner.calls.length, :>=, 2
      end
    end
  end

  def test_app_preview_handshake_rejects_symlinked_protocol_directory
    Dir.mktmpdir("nova-handshake-symlink") do |container|
      token = "c" * 32
      protocol_root = File.join(container, "Library", "Caches", "NovaStationMediaHandshake")
      foreign = File.join(container, "foreign")
      FileUtils.mkdir_p([protocol_root, foreign])
      File.binwrite(File.join(foreign, "ready"), token)
      File.symlink(foreign, File.join(protocol_root, token))
      status = Struct.new(:success?)
      runner = Struct.new(:container, :status) do
        def capture(*_arguments)
          ["#{container}\n", "", status.new(true)]
        end
      end.new(container, status)
      handshake = NovaStationPinballPreviewGeneration::Handshake.new(
        udid: "11111111-1111-1111-1111-111111111111", runner: runner,
        token: token, timeout: 0.05
      )
      error = assert_raises(NovaStationPinballMediaContract::ContractError) { handshake.wait_for!("ready") }
      assert_includes error.message, "unsafe App Preview handshake path"
    end
  end

  def test_locale_batches_never_use_the_same_owned_udid_concurrently
    %w[generate_screenshots.rb generate_app_previews.rb].each do |filename|
      source = File.read(File.join(__dir__, filename), encoding: "UTF-8")
      refute_includes source, "Thread.new", "#{filename} must serialize locales over the single exact UDID per device"
    end
    screenshots = File.read(File.join(__dir__, "generate_screenshots.rb"), encoding: "UTF-8")
    previews = File.read(PREVIEW_IMPLEMENTATION, encoding: "UTF-8")
    assert_includes screenshots, "batch.each"
    assert_includes previews, "configuration.udids.each_key"
    assert_includes previews, "configuration.locales.each"
  end

  def test_preparation_manifest_has_the_exact_locale_device_scenario_matrix
    require_implementation!
    with_run do |run_root|
      manifest = builder(run_root).prepare!
      cells = manifest.fetch("cells")

      assert_equal 36, cells.length
      assert_equal %w[en-US fr-FR], manifest.fetch("locales")
      assert_equal %w[iphone-17-pro-max iphone-se-3 ipad-pro-13-m5], manifest.fetch("devices")
      assert_equal %w[launch mission promotion multiball tilt game-over], manifest.fetch("scenarios")
      assert_equal 36, cells.map { |cell| cell.values_at("locale", "device", "scenario") }.uniq.length
      assert cells.all? { |cell| cell.fetch("status") == "pending" }
      assert cells.all? { |cell| cell.fetch("source_revision") == SOURCE_REVISION }
      assert cells.all? { |cell| cell.fetch("screenshot_sha256").nil? }
      assert cells.all? { |cell| cell.fetch("preview_sha256").nil? }
      assert cells.all? { |cell| cell.key?("capture_trim_offset_seconds") && cell["capture_trim_offset_seconds"].nil? }
      assert_equal((0..5).map { |index| index * 4.0 }.uniq,
                   cells.select { |cell| cell.fetch("locale") == "en-US" && cell.fetch("device") == "iphone-17-pro-max" }
                        .map { |cell| cell.fetch("preview_offset_seconds") })
    end
  end

  def test_strict_contract_accepts_only_a_complete_captured_matrix_and_hashes
    require_implementation!
    with_complete_run do |run_root, probe|
      overlay_guard = FakeOverlayGuard.new([])
      report = contract(run_root, probe: probe, overlay_guard: overlay_guard).validate!

      assert_equal 36, report.fetch("cells").length
      assert_equal 36, report.fetch("screenshots").length
      assert_equal 6, report.fetch("app_previews").length
      assert_equal SOURCE_REVISION, report.fetch("source_revision")
      assert File.file?(File.join(run_root, "logs", "media-contract.json"))
      assert_equal 6, probe.calls.length
      assert_equal 6, overlay_guard.calls.length
      assert overlay_guard.calls.all? { |call| call.fetch(:report_path).include?("/logs/system-overlay/") }
    end
  end

  def test_strict_contract_rejects_tiny_visible_screenshot_content
    with_complete_run do |run_root, probe|
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        contract(run_root, probe: probe,
                 visual_probe: FakeVisualProbe.new({ "width_ratio" => 0.40 })).validate!
      end

      assert_includes error.message, "screenshot content coverage is too small"
    end
  end

  def test_strict_contract_rejects_a_preview_rejected_by_the_system_overlay_guard
    with_complete_run do |run_root, probe|
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        contract(
          run_root, probe: probe,
          overlay_guard: RejectingOverlayGuard.new("system UI top-band guard rejected")
        ).validate!
      end

      assert_includes error.message, "system UI top-band guard rejected"
      refute File.exist?(File.join(run_root, "logs", "media-contract.json"))
    end
  end

  def test_strict_contract_requires_valid_screenshot_capture_timestamp
    with_complete_run do |run_root, probe|
      manifest = read_manifest(run_root)
      manifest.fetch("cells").first["screenshot_captured_at"] = "not-a-timestamp"
      write_manifest(run_root, manifest)

      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        contract(run_root, probe: probe).validate!
      end
      assert_includes error.message, "invalid screenshot capture timestamp"
    end
  end

  def test_strict_contract_requires_clockwise_raw_preview_provenance
    with_complete_run do |run_root, probe|
      manifest = read_manifest(run_root)
      manifest.fetch("cells").first["preview_raw_transform"] = "scale-only"
      write_manifest(run_root, manifest)

      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        contract(run_root, probe: probe).validate!
      end
      assert_includes error.message, "invalid raw App Preview provenance"
    end
  end

  def test_strict_contract_rejects_pending_cells_but_preparation_mode_reports_them
    require_implementation!
    with_run do |run_root|
      builder(run_root).prepare!
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        contract(run_root).validate!
      end
      assert_includes error.message, "pending media cell"

      report = contract(run_root, allow_pending: true).validate!
      assert_equal 36, report.fetch("pending_cells")
      refute File.exist?(File.join(run_root, "logs", "media-contract.json"))
    end
  end

  def test_rejects_missing_duplicate_foreign_and_stale_cells
    require_implementation!
    mutations = {
      "missing media cell" => ->(manifest) { manifest.fetch("cells").pop },
      "duplicate media cell" => ->(manifest) { manifest.fetch("cells") << manifest.fetch("cells").first.dup },
      "foreign media cell" => ->(manifest) { manifest.fetch("cells").first["locale"] = "de-DE" },
      "stale media manifest" => ->(manifest) { manifest["source_revision"] = "0" * 64 }
    }

    mutations.each do |message, mutation|
      with_run do |run_root|
        manifest = builder(run_root).prepare!
        mutation.call(manifest)
        write_manifest(run_root, manifest)

        error = assert_raises(NovaStationPinballMediaContract::ContractError) do
          contract(run_root, allow_pending: true).validate!
        end
        assert_includes error.message, message
      end
    end
  end

  def test_rejects_missing_foreign_or_tampered_artifacts
    require_implementation!
    with_complete_run do |run_root, probe|
      manifest = read_manifest(run_root)
      first = manifest.fetch("cells").first
      FileUtils.rm(File.join(run_root, first.fetch("screenshot_path")))
      File.binwrite(File.join(run_root, "screenshots", "en-US", "foreign.png"), "foreign")

      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        contract(run_root, probe: probe).validate!
      end
      assert_includes error.message, "missing screenshot artifact"
      assert_includes error.message, "foreign media artifact"
    end

    with_complete_run do |run_root, probe|
      manifest = read_manifest(run_root)
      first = manifest.fetch("cells").first
      File.binwrite(File.join(run_root, first.fetch("screenshot_path")), "tampered")
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        contract(run_root, probe: probe).validate!
      end
      assert_includes error.message, "screenshot checksum mismatch"
    end

    with_complete_run do |run_root, probe|
      manifest = read_manifest(run_root)
      preview = File.join(run_root, manifest.fetch("cells").first.fetch("preview_path"))
      File.binwrite(preview, "forged-preview")
      error = assert_raises(NovaStationPinballMediaContract::ContractError) { contract(run_root, probe: probe).validate! }
      assert_includes error.message, "preview checksum mismatch"
    end
  end

  def test_rejects_rotated_png_metadata_and_normalizer_preserves_pixel_chunks
    with_complete_run do |run_root, probe|
      manifest = read_manifest(run_root)
      cell = manifest.fetch("cells").first
      screenshot = File.join(run_root, cell.fetch("screenshot_path"))
      add_exif_orientation(screenshot, 6)
      cell["screenshot_sha256"] = Digest::SHA256.file(screenshot).hexdigest
      write_manifest(run_root, manifest)

      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        contract(run_root, probe: probe).validate!
      end
      assert_includes error.message, "screenshot orientation metadata must be absent or 1"

      before = png_chunks(screenshot).select { |type, _data| type == "IDAT" }
      NovaStationPinballMediaContract::PNGMetadata.strip_orientation!(screenshot)
      after = png_chunks(screenshot).select { |type, _data| type == "IDAT" }
      assert_nil NovaStationPinballMediaContract::PNGMetadata.orientation(screenshot)
      assert_equal before, after
    end
  end

  def test_rejects_every_noncompliant_app_preview_property
    cases = {
      "preview dimensions mismatch" => { "width" => 1 },
      "preview duration must be exactly 24 seconds" => { "duration" => 23.7 },
      "preview video track must be exactly 24 seconds" => { "video_duration" => 23.9 },
      "preview audio track must be exactly 24 seconds" => { "audio_duration" => 23.9 },
      "preview must contain exactly 720 video frames" => { "video_frames" => 719 },
      "preview frame rate must be exactly 30 fps" => { "frame_rate" => 29.0 },
      "preview video codec must be H.264" => { "video_codec" => "hevc" },
      "preview H.264 profile must be High" => { "video_profile" => "Main" },
      "preview H.264 level must be 4.0 or lower" => { "video_level" => 41 },
      "preview pixel format must be yuv420p" => { "pixel_format" => "yuv444p" },
      "preview must be progressive" => { "field_order" => "tt" },
      "preview rotation metadata must be zero" => { "rotation" => 90.0 },
      "preview video bit rate must be 10-12 Mbps" => { "video_bit_rate" => 9_999_999 },
      "preview audio codec must be AAC" => { "audio_codec" => "mp3" },
      "preview audio profile must be AAC-LC" => { "audio_profile" => "HE-AAC" },
      "preview audio bit rate must be 256 kbps" => { "audio_bit_rate" => 128_000 },
      "preview audio must be stereo" => { "audio_channels" => 1 },
      "preview audio sample rate" => { "audio_sample_rate" => 32_000 },
      "preview must contain exactly one video stream" => { "video_streams" => 2 },
      "preview must contain exactly one stereo audio stream" => { "audio_streams" => 2 },
      "preview tracks must be enabled" => { "audio_enabled" => false }
    }
    cases.each do |message, overrides|
      with_complete_run do |run_root, _probe|
        probe = FakeProbe.new([], overrides)
        error = assert_raises(NovaStationPinballMediaContract::ContractError) { contract(run_root, probe: probe).validate! }
        assert_includes error.message, message
      end
    end
  end

  def test_rejects_missing_invalid_or_inconsistent_measured_capture_trim_offset
    [nil, "0.250", -0.1, 46.0, 0.5].each do |invalid|
      with_complete_run do |run_root, probe|
        manifest = read_manifest(run_root)
        manifest.fetch("cells").first["capture_trim_offset_seconds"] = invalid
        write_manifest(run_root, manifest)
        error = assert_raises(NovaStationPinballMediaContract::ContractError) do
          contract(run_root, probe: probe).validate!
        end
        assert_includes error.message, "capture trim offset"
      end
    end
  end

  def test_preview_artifact_persists_the_exact_measured_trim_offset_for_all_six_segments
    with_run do |run_root|
      builder(run_root).prepare!
      preview = File.join(run_root, "app_previews", "en-US", "NovaStationPinball-iphone-se-3.mov")
      FileUtils.mkdir_p(File.dirname(preview))
      File.binwrite(preview, "preview")
      generator = NovaStationPinballMediaGeneration::GeneratorBase.allocate
      generator.instance_variable_set(:@run_root, run_root)
      generator.instance_variable_set(
        :@store,
        NovaStationPinballMediaGeneration::ManifestStore.new(
          run_root: run_root, source_revision: SOURCE_REVISION
        )
      )
      generator.send(
        :mark_artifact!, locale: "en-US", device: "iphone-se-3", kind: :preview,
        path: preview, capture_trim_offset: 2.815
      )
      cells = read_manifest(run_root).fetch("cells").select do |cell|
        cell.values_at("locale", "device") == ["en-US", "iphone-se-3"]
      end
      assert_equal 6, cells.length
      assert_equal [2.815], cells.map { |cell| cell["capture_trim_offset_seconds"] }.uniq
      assert cells.all? { |cell| cell["preview_sha256"] == Digest::SHA256.file(preview).hexdigest }
    end
  end

  def test_ffprobe_rejects_malformed_or_forged_stream_metadata
    valid_json = JSON.generate({
      "streams" => [
        { "codec_type" => "video", "codec_name" => "h264", "profile" => "High", "level" => 40,
          "width" => 1920, "height" => 886, "pix_fmt" => "yuv420p", "field_order" => "progressive",
          "avg_frame_rate" => "30/1", "duration" => "24.000000", "nb_read_frames" => "720",
          "bit_rate" => "11000000", "disposition" => { "default" => 1 } },
        { "codec_type" => "audio", "codec_name" => "aac", "profile" => "LC", "channels" => 2,
          "sample_rate" => "48000", "duration" => "24.000000", "bit_rate" => "256000",
          "disposition" => { "default" => 1 } }
      ], "format" => { "duration" => "24.000000" }
    })
    runner = Struct.new(:stdout) do
      def capture3(*_arguments)
        [stdout, "", Struct.new(:success?).new(true)]
      end
    end
    info = NovaStationPinballMediaContract::FFProbe.new(runner: runner.new(valid_json)).probe("preview.mov")
    assert_equal 11_000_000, info.fetch("video_bit_rate")
    assert_equal 256_000, info.fetch("audio_bit_rate")
    assert_equal 720, info.fetch("video_frames")
    assert_equal 24.0, info.fetch("video_duration")
    assert_equal 24.0, info.fetch("audio_duration")

    ["not-json", valid_json.sub('"30/1"', '"oops"'), valid_json.sub('"streams":[', '"streams":[]')].each do |payload|
      assert_raises(NovaStationPinballMediaContract::ContractError) do
        NovaStationPinballMediaContract::FFProbe.new(runner: runner.new(payload)).probe("forged.mov")
      end
    end
  end

  def test_source_fingerprint_tracks_semantic_source_and_rejects_symlinks
    Dir.mktmpdir("nova-source") do |root|
      FileUtils.mkdir_p(File.join(root, "NovaStationPinball"))
      source = File.join(root, "NovaStationPinball", "Game.swift")
      File.write(source, "let score = 1\n")
      first = NovaStationPinballMediaContract::SourceFingerprint.new(root).value
      FileUtils.mkdir_p(File.join(root, "Builds"))
      File.write(File.join(root, "Builds", "noise"), "ignored")
      assert_equal first, NovaStationPinballMediaContract::SourceFingerprint.new(root).value
      File.write(source, "let score = 2\n")
      refute_equal first, NovaStationPinballMediaContract::SourceFingerprint.new(root).value
      File.write(source, "let score = 1\n")
      File.chmod(0o755, source)
      refute_equal first, NovaStationPinballMediaContract::SourceFingerprint.new(root).value
      File.unlink(source)
      File.symlink("/tmp/foreign.swift", source)
      assert_raises(NovaStationPinballMediaContract::ContractError) do
        NovaStationPinballMediaContract::SourceFingerprint.new(root).value
      end
    end
  end

  def test_source_fingerprint_ignores_only_the_generated_validation_report
    Dir.mktmpdir("nova-validation-report") do |root|
      FileUtils.mkdir_p(File.join(root, "NovaStationPinball"))
      FileUtils.mkdir_p(File.join(root, "docs"))
      File.write(File.join(root, "NovaStationPinball", "Game.swift"), "let score = 1\n")
      fingerprint = NovaStationPinballMediaContract::SourceFingerprint.new(root).value

      File.write(File.join(root, "docs", "validation-report.md"), "first proof\n")
      assert_equal fingerprint, NovaStationPinballMediaContract::SourceFingerprint.new(root).value
      File.write(File.join(root, "docs", "validation-report.md"), "final proof\n")
      assert_equal fingerprint, NovaStationPinballMediaContract::SourceFingerprint.new(root).value

      File.write(File.join(root, "docs", "aso-strategy.md"), "semantic change\n")
      refute_equal fingerprint, NovaStationPinballMediaContract::SourceFingerprint.new(root).value
    end
  end

  def test_rejects_symlinked_media_artifact
    with_complete_run do |run_root, probe|
      manifest = read_manifest(run_root)
      preview = File.join(run_root, manifest.fetch("cells").first.fetch("preview_path"))
      File.unlink(preview)
      File.symlink("/tmp/forged.mov", preview)
      error = assert_raises(NovaStationPinballMediaContract::ContractError) { contract(run_root, probe: probe).validate! }
      assert_includes error.message, "symbolic link is forbidden"
    end
  end

  def test_rejects_manifest_paths_that_escape_the_run_root
    require_implementation!
    with_run do |run_root|
      manifest = builder(run_root).prepare!
      manifest.fetch("cells").first["screenshot_path"] = "../../outside.png"
      write_manifest(run_root, manifest)
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        contract(run_root, allow_pending: true).validate!
      end
      assert_includes error.message, "media path escapes run root"
    end
  end

  def test_rejects_duplicate_or_misnamed_artifact_paths_inside_the_run
    require_implementation!
    with_run do |run_root|
      manifest = builder(run_root).prepare!
      manifest.fetch("cells")[1]["screenshot_path"] = manifest.fetch("cells")[0].fetch("screenshot_path")
      write_manifest(run_root, manifest)
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        contract(run_root, allow_pending: true).validate!
      end
      assert_includes error.message, "duplicate screenshot artifact path"
      assert_includes error.message, "screenshot path mismatch"
    end

    with_run do |run_root|
      manifest = builder(run_root).prepare!
      manifest.fetch("cells").last["preview_path"] = "app_previews/fr-FR/foreign.mov"
      write_manifest(run_root, manifest)
      error = assert_raises(NovaStationPinballMediaContract::ContractError) do
        contract(run_root, allow_pending: true).validate!
      end
      assert_includes error.message, "preview path mismatch"
    end
  end

  private

  def write_plist(path, value)
    list = CFPropertyList::List.new
    list.value = CFPropertyList.guess(value)
    list.save(path, CFPropertyList::List::FORMAT_XML)
  end

  def read_plist(path)
    CFPropertyList.native_types(CFPropertyList::List.new(file: path).value)
  end

  def overlay_fixture(filename)
    JSON.parse(File.read(File.join(OVERLAY_FIXTURE_ROOT, filename), encoding: "UTF-8"))
  end

  def overlay_metadata_output(fixture)
    spans = fixture.fetch("spans")
    frame_rate = Float(fixture.fetch("frame_rate"))
    (0...Integer(fixture.fetch("frame_count"))).map do |frame|
      span = spans.find do |candidate|
        frame.between?(candidate.fetch("first_frame"), candidate.fetch("last_frame"))
      end
      yavg = span ? span.fetch("top_band_yavg") : fixture.fetch("default_top_band_yavg")
      format(
        "frame:%d    pts:%d       pts_time:%.6f\nlavfi.signalstats.YAVG=%.6f\n",
        frame, frame * 512, frame / frame_rate, yavg
      )
    end.join
  end

  def terminate_test_process(pid)
    return unless pid
    Process.kill("TERM", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def require_implementation!
    skip "implementation not created yet" unless defined?(NovaStationPinballMediaContract)
  end

  def builder(run_root)
    NovaStationPinballMediaContract::ManifestBuilder.new(
      run_root: run_root,
      source_revision: SOURCE_REVISION,
      captured_at: Time.utc(2026, 7, 22, 10, 30, 0)
    )
  end

  def contract(run_root, probe: nil, visual_probe: nil, overlay_guard: nil, allow_pending: false)
    NovaStationPinballMediaContract::Contract.new(
      run_root: run_root,
      source_revision: SOURCE_REVISION,
      probe: probe || FakeProbe.new([]),
      visual_probe: visual_probe || FakeVisualProbe.new,
      overlay_guard: overlay_guard || FakeOverlayGuard.new([]),
      allow_pending: allow_pending
    )
  end

  def with_run
    Dir.mktmpdir("nova-station-media") do |root|
      run_root = File.join(root, "Builds", "AppStore", "NovaStationPinball", "test-run")
      yield run_root
    end
  end

  def with_complete_run
    with_run do |run_root|
      manifest = builder(run_root).prepare!
      screenshot_hashes = {}
      preview_hashes = {}

      manifest.fetch("cells").each do |cell|
        screenshot = File.join(run_root, cell.fetch("screenshot_path"))
        unless screenshot_hashes.key?(screenshot)
          write_png(screenshot, cell.fetch("width"), cell.fetch("height"))
          screenshot_hashes[screenshot] = Digest::SHA256.file(screenshot).hexdigest
        end
        preview = File.join(run_root, cell.fetch("preview_path"))
        unless preview_hashes.key?(preview)
          FileUtils.mkdir_p(File.dirname(preview))
          File.binwrite(preview, "deterministic-preview-#{cell.fetch('locale')}-#{cell.fetch('device')}")
          preview_hashes[preview] = Digest::SHA256.file(preview).hexdigest
        end
        cell["status"] = "captured"
        cell["capture_trim_offset_seconds"] = 0.375
        cell["screenshot_source_preview_path"] = cell.fetch("preview_path")
        cell["screenshot_source_offset_seconds"] =
          NovaStationPinballMediaContract::SCENARIOS.index(cell.fetch("scenario")) * 4.0 + 0.5
        cell["screenshot_captured_at"] = "2026-07-22T10:30:01.000000Z"
        cell["screenshot_sha256"] = screenshot_hashes.fetch(screenshot)
        cell["preview_sha256"] = preview_hashes.fetch(preview)
        cell["preview_raw_source_sha256"] = "a" * 64
        cell["preview_raw_source_run_id"] = "source-run"
        cell["preview_raw_width"] = cell.fetch("height")
        cell["preview_raw_height"] = cell.fetch("width")
        device = NovaStationPinballMediaContract::DEVICES.find { |candidate| candidate.fetch(:id) == cell.fetch("device") }
        cell["preview_raw_transform"] = device.fetch(:raw_transform)
        cell["preview_raw_udid"] = "11111111-1111-1111-1111-111111111111"
        cell["preview_raw_locale"] = cell.fetch("locale")
        cell["preview_raw_handshake_sha256"] = "b" * 64
      end
      write_manifest(run_root, manifest)
      probe = FakeProbe.new([], {})
      yield run_root, probe
    end
  end

  def read_manifest(run_root)
    JSON.parse(File.read(File.join(run_root, "logs", "media-manifest.json"), encoding: "UTF-8"))
  end

  def write_manifest(run_root, manifest)
    FileUtils.mkdir_p(File.join(run_root, "logs"))
    File.write(File.join(run_root, "logs", "media-manifest.json"), "#{JSON.pretty_generate(manifest)}\n")
  end

  def write_png(path, width, height)
    FileUtils.mkdir_p(File.dirname(path))
    signature = "\x89PNG\r\n\x1A\n".b
    ihdr = [width, height, 8, 2, 0, 0, 0].pack("NNCCCCC")
    row = "\x00".b + ("\x00\x00\x00".b * width)
    idat = Zlib::Deflate.deflate(row * height)
    File.binwrite(path, signature + png_chunk("IHDR", ihdr) + png_chunk("IDAT", idat) + png_chunk("IEND", "".b))
  end

  def add_exif_orientation(path, orientation)
    data = File.binread(path)
    entry = [0x0112, 3].pack("nn") + [1].pack("N") + [orientation, 0].pack("nn")
    exif = "MM\x00*".b + [8].pack("N") + [1].pack("n") + entry + [0].pack("N")
    insert_at = 8 + 12 + 13
    File.binwrite(path, data.byteslice(0, insert_at) + png_chunk("eXIf", exif) + data.byteslice(insert_at..-1))
  end

  def png_chunks(path)
    data = File.binread(path)
    offset = 8
    result = []
    while offset < data.bytesize
      length = data.byteslice(offset, 4).unpack1("N")
      type = data.byteslice(offset + 4, 4)
      result << [type, data.byteslice(offset + 8, length)]
      offset += length + 12
    end
    result
  end

  def png_chunk(type, data)
    payload = type.b + data
    [data.bytesize].pack("N") + payload + [Zlib.crc32(payload)].pack("N")
  end

  def with_owned_pool
    Dir.mktmpdir("nova-owned-pool") do |root|
      execution_id = "task11-media-0001"
      lock_root = File.join(root, "locks")
      FileUtils.mkdir_p(lock_root)
      definitions = [
        ["iphone-17-pro-max", "iphone-1", "iphone", "11111111-1111-1111-1111-111111111111", "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"],
        ["iphone-se-3", "iphone-2", "iphone", "22222222-2222-2222-2222-222222222222", "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"],
        ["ipad-pro-13-m5", "ipad", "ipad", "33333333-3333-3333-3333-333333333333", "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"]
      ]
      pool = {
        "schema_version" => 1, "lock_root" => lock_root,
        "devices" => definitions.map do |media_id, id, role, udid, type|
          { "id" => id, "media_id" => media_id, "role" => role, "udid" => udid,
            "device_type" => type, "runtime" => "com.apple.CoreSimulator.SimRuntime.iOS-26-2" }
        end
      }
      pool_path = File.join(root, "pool.json")
      File.write(pool_path, JSON.generate(pool))
      leases = definitions.to_h do |media_id, id, _role, udid, _type|
        path = File.join(lock_root, "#{id}.lock")
        File.write(path, JSON.generate({
          "schema_version" => 1, "device_id" => id, "udid" => udid,
          "app" => "nova-station-pinball", "pid" => Process.pid,
          "started_at" => Time.now.utc.iso8601(6), "execution_id" => execution_id,
          "token" => "a" * 32
        }), perm: 0o600)
        [media_id, path]
      end
      yield pool_path, leases, execution_id
    end
  end
end
