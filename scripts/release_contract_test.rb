#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "yaml"

class ReleaseContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REQUIRED_LANES = %w[
    setup_asc release_contract asc_status metadata screenshots app_previews media_contract upload_screenshots
    upload_previews build_release upload_release submit_review release_quick pricing
    iap_status iap_sync
  ].freeze
  EXPECTED_TIPS = %w[tip.cafe tip.merci tip.soutien].freeze

  def test_repository_contract_is_complete
    required_files.each do |path|
      assert File.exist?(path), "missing required file: #{path}"
    end

    project = YAML.safe_load(File.read(File.join(ROOT, "project.yml"), encoding: "UTF-8"), aliases: false)
    app_target = project.fetch("targets").fetch("NovaStationPinball")
    settings = app_target.fetch("settings").fetch("base")

    assert_equal "com.bnjdpn.NovaStationPinball", settings.fetch("PRODUCT_BUNDLE_IDENTIFIER")
    assert_equal "6.0", settings.fetch("SWIFT_VERSION")
    assert_equal "1,2", settings.fetch("TARGETED_DEVICE_FAMILY")
    assert_equal "17.0", app_target.fetch("deploymentTarget")
    info = app_target.fetch("info").fetch("properties")
    assert_equal "1.0", settings.fetch("MARKETING_VERSION")
    assert_equal "1", settings.fetch("CURRENT_PROJECT_VERSION")
    assert_equal "$(MARKETING_VERSION)", info.fetch("CFBundleShortVersionString")
    assert_equal "$(CURRENT_PROJECT_VERSION)", info.fetch("CFBundleVersion")
    assert_equal false, info.fetch("ITSAppUsesNonExemptEncryption")
    expected_orientations = %w[UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight]
    assert_equal expected_orientations,
                 info.fetch("UISupportedInterfaceOrientations")
    assert_equal expected_orientations,
                 info.fetch("UISupportedInterfaceOrientations~ipad")
    assert_equal %w[NovaStationPinballTests NovaStationPinballUITests],
                 project.fetch("targets").keys.grep(/Tests?$/).sort
    assert_equal ["NovaStationPinball"], app_target.fetch("sources").map { |source| source.fetch("path") }
    assert_equal ["NovaStationPinballTests"],
                 project.fetch("targets").fetch("NovaStationPinballTests").fetch("sources").map { |source| source.fetch("path") }
    assert_equal ["NovaStationPinballUITests"],
                 project.fetch("targets").fetch("NovaStationPinballUITests").fetch("sources").map { |source| source.fetch("path") }

    package = File.read(File.join(ROOT, "Package.swift"), encoding: "UTF-8")
    assert_includes package, '.library(name: "NovaStationCore", targets: ["NovaStationCore"])'
    assert_includes package, '.target(name: "NovaStationCore", path: "NovaStationCore/Sources/NovaStationCore")'
    assert_includes package, '.testTarget(name: "NovaStationCoreTests", dependencies: ["NovaStationCore"], path: "NovaStationCore/Tests/NovaStationCoreTests")'
    assert_includes File.read(File.join(ROOT, "NovaStationCore/Sources/NovaStationCore/NovaStationCore.swift"), encoding: "UTF-8"),
                    "public enum NovaStationCore"
    assert_includes File.read(File.join(ROOT, "NovaStationCore/Tests/NovaStationCoreTests/NovaStationCoreTests.swift"), encoding: "UTF-8"),
                    "@testable import NovaStationCore"

    app_source = File.read(File.join(ROOT, "NovaStationPinball/App/NovaStationPinballApp.swift"), encoding: "UTF-8")
    assert_includes app_source, "@main"
    assert_includes app_source, "struct NovaStationPinballApp: App"
    assert_includes File.read(File.join(ROOT, "NovaStationPinballTests/BootstrapTests.swift"), encoding: "UTF-8"), "XCTestCase"
    assert_includes File.read(File.join(ROOT, "NovaStationPinballUITests/BootstrapUITests.swift"), encoding: "UTF-8"), "XCUIApplication"

    release_config = JSON.parse(File.read(File.join(ROOT, "fastlane/release_config.json"), encoding: "UTF-8"))
    assert_equal %w[en-US fr-FR], release_config.fetch("locales").sort
    assert_equal EXPECTED_TIPS, release_config.fetch("tip_products").map { |tip| tip.fetch("id") }.sort
    assert_equal "https://bnjdpn.github.io/NovaStationPinball/#contact", release_config.fetch("support_url")

    fastfile = File.read(File.join(ROOT, "fastlane/Fastfile"), encoding: "UTF-8")
    REQUIRED_LANES.each { |lane| assert_match(/^\s*lane :#{lane}\b/, fastfile) }
    assert_includes fastfile, "scripts/release_contract.rb"

    public_contact_files.each do |path|
      contents = File.read(path, encoding: "UTF-8")
      refute_match(/mailto:/i, contents, "public mailto link in #{path}")
      refute_match(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i, contents, "public email address in #{path}")
    end
    assert_includes File.read(File.join(ROOT, "docs/index.html"), encoding: "UTF-8"), "formspree.io"
    refute File.exist?(File.join(ROOT, ".github", "workflows")), "GitHub workflows are forbidden"

    stdout, stderr, status = Open3.capture3("ruby", File.join(ROOT, "scripts/release_contract.rb"))
    assert status.success?, "release contract failed:\n#{stdout}\n#{stderr}"
  end

  def test_fastlane_release_contract_resolves_app_script_independently_of_lane_cwd
    stdout, stderr, status = Open3.capture3(
      {
        "FASTLANE_SKIP_UPDATE_CHECK" => "1",
        "FASTLANE_OPT_OUT_USAGE" => "YES",
        "BUNDLE_DISABLE_CHECKSUM_VALIDATION" => "true"
      },
      "/opt/homebrew/bin/ruby", "-S", "bundle", "exec", "fastlane", "release_contract",
      chdir: ROOT
    )

    assert status.success?, "Fastlane release_contract failed from app root:\n#{stdout}\n#{stderr}"
    assert_includes stdout, "release_contract: OK"
  end

  def test_optional_tip_configuration_is_exact_and_development_only
    storekit = JSON.parse(
      File.read(File.join(ROOT, "NovaStationPinball/StoreKit/NovaStationPinball.storekit"), encoding: "UTF-8")
    )
    products = storekit.fetch("products")

    assert_equal EXPECTED_TIPS.map { |tip| "com.bnjdpn.NovaStationPinball.#{tip}" }.sort,
                 products.map { |product| product.fetch("productID") }.sort
    assert products.all? { |product| product.fetch("type") == "Consumable" }
    assert products.flat_map { |product| product.fetch("localizations") }
                   .all? { |localization| localization.fetch("description").match?(/(?:Unlocks no features|ne débloque aucune fonctionnalité)/i) }

    project = YAML.safe_load(File.read(File.join(ROOT, "project.yml"), encoding: "UTF-8"), aliases: false)
    app_sources = project.fetch("targets").fetch("NovaStationPinball").fetch("sources")
    assert_includes app_sources.flat_map { |source| source.fetch("excludes", []) }, "StoreKit"
    assert_equal "NovaStationPinball/StoreKit/NovaStationPinball.storekit",
                 project.fetch("schemes").fetch("NovaStationPinball").fetch("run").fetch("storeKitConfiguration")

    %w[AudioEngine.swift HapticsService.swift GameCenterClient.swift TipJarSupport.swift].each do |filename|
      source = File.read(File.join(ROOT, "NovaStationPinball/Services", filename), encoding: "UTF-8")
      refute_match(/\b(?:URLSession|NWConnection)\b/, source)
    end

    game_center = File.read(File.join(ROOT, "NovaStationPinball/Services/GameCenterClient.swift"), encoding: "UTF-8")
    assert_includes game_center, "presentAuthenticationController"
    assert_includes game_center, ".foregroundActive"
    refute_match(/presenter:\s*AuthenticationPresenter\?\s*=\s*nil/, game_center)

    app_model = File.read(File.join(ROOT, "NovaStationPinball/App/AppModel.swift"), encoding: "UTF-8")
    assert_operator app_model.index("localGameStore.saveHighScores"), :<, app_model.index("gameCenterClient.submit")
    root_view = File.read(File.join(ROOT, "NovaStationPinball/App/RootView.swift"), encoding: "UTF-8")
    assert_includes root_view, ".task"
    assert_includes root_view, "model.start()"
    refute_includes root_view, "model.startOptionalServices()"
    assert_includes app_model, "func start()"
    assert_includes app_model, "startOptionalServices()"
    assert_includes app_model, "lifecycleCoordinator.start()"

    entitlements = File.read(File.join(ROOT, "NovaStationPinball/NovaStationPinball.entitlements"), encoding: "UTF-8")
    assert_includes entitlements, "<key>com.apple.developer.game-center</key>"
    assert_match(/<key>com\.apple\.developer\.game-center<\/key>\s*<true\/>/, entitlements)
  end

  def test_task_11_aso_support_media_and_ui_scenario_contract
    metadata_files = %w[
      name.txt subtitle.txt description.txt keywords.txt promotional_text.txt
      release_notes.txt support_url.txt privacy_url.txt
    ]
    %w[en-US fr-FR].each do |locale|
      root = File.join(ROOT, "fastlane", "metadata", locale)
      metadata_files.each do |filename|
        path = File.join(root, filename)
        assert File.file?(path), "missing #{path}"
        value = File.read(path, encoding: "UTF-8").strip
        refute_empty value, "empty #{path}"
        refute_match(/mailto:|\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i, value)
        refute_match(/Space Cadet|Windows|Microsoft/i, value)
      end
      assert_operator File.read(File.join(root, "name.txt"), encoding: "UTF-8").strip.length, :<=, 30
      assert_operator File.read(File.join(root, "subtitle.txt"), encoding: "UTF-8").strip.length, :<=, 30
      assert_operator File.read(File.join(root, "keywords.txt"), encoding: "UTF-8").strip.bytesize, :<=, 100
      assert_operator File.read(File.join(root, "promotional_text.txt"), encoding: "UTF-8").strip.length, :<=, 170
      assert_equal "https://bnjdpn.github.io/NovaStationPinball/#contact",
                   File.read(File.join(root, "support_url.txt"), encoding: "UTF-8").strip
      assert_equal "https://bnjdpn.github.io/NovaStationPinball/privacy.html",
                   File.read(File.join(root, "privacy_url.txt"), encoding: "UTF-8").strip
    end

    required = %w[
      scripts/app_store/media_contract.rb
      scripts/app_store/media_contract_test.rb
      scripts/app_store/generate_screenshots.rb
      scripts/app_store/generate_app_previews.rb
      NovaStationPinball/App/MediaScenario.swift
      NovaStationPinballUITests/StoreScreenshotUITests.swift
      NovaStationPinballUITests/AppPreviewUITests.swift
    ]
    required.each { |relative| assert File.file?(File.join(ROOT, relative)), "missing #{relative}" }

    scenario_source = File.read(File.join(ROOT, "NovaStationPinball/App/MediaScenario.swift"), encoding: "UTF-8")
    %w[launch mission promotion multiball tilt game-over].each do |scenario|
      assert_includes scenario_source, "\"#{scenario}\""
    end
    refute_match(/\.svg\b|\.pdf\b/i, scenario_source)
    scene_source = File.read(File.join(ROOT, "NovaStationPinball/Game/PinballScene.swift"), encoding: "UTF-8")
    assert_includes scene_source, "private var didBuildRasterTable = false"
    refute_includes scene_source, "guard children.isEmpty else { return }"

    screenshot_tests = File.read(File.join(ROOT, "NovaStationPinballUITests/StoreScreenshotUITests.swift"), encoding: "UTF-8")
    preview_tests = File.read(File.join(ROOT, "NovaStationPinballUITests/AppPreviewUITests.swift"), encoding: "UTF-8")
    %w[launch mission promotion multiball tilt game-over].each do |scenario|
      assert_includes screenshot_tests, "\"#{scenario}\""
      assert_includes preview_tests, "\"#{scenario}\""
    end
    assert_includes screenshot_tests, "XCTAttachment(screenshot:"

    config = JSON.parse(File.read(File.join(ROOT, "fastlane/release_config.json"), encoding: "UTF-8"))
    assert_equal(
      {
        "applicable" => true,
        "review_each_release" => true,
        "generator" => "scripts/app_store/generate_app_previews.rb",
        "parallel_locales" => 2,
        "scenarios" => %w[launch mission promotion multiball tilt game-over]
      },
      config.fetch("app_preview_policy")
    )

    fastfile = File.read(File.join(ROOT, "fastlane/Fastfile"), encoding: "UTF-8")
    assert_match(/^\s*lane :app_previews\b/, fastfile)
    assert_match(/^\s*lane :media_contract\b/, fastfile)
    assert_includes fastfile, "scripts/app_store/generate_screenshots.rb"
    assert_includes fastfile, "scripts/app_store/generate_app_previews.rb"
    assert_includes fastfile, "scripts/app_store/media_contract.rb"

    %w[docs/index.html docs/privacy.html].each do |relative|
      text = File.read(File.join(ROOT, relative), encoding: "UTF-8")
      refute_match(/mailto:|\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i, text)
      refute_match(/<svg\b|\.svg\b|\.pdf\b/i, text)
    end
    assert_includes File.read(File.join(ROOT, "docs/index.html"), encoding: "UTF-8"),
                    "https://formspree.io/f/mykqbyyw"
  end

  def test_task_11_privacy_metadata_handshake_and_media_spec_are_fail_closed
    privacy = File.read(File.join(ROOT, "NovaStationPinball/Resources/PrivacyInfo.xcprivacy"), encoding: "UTF-8")
    assert_match(/<key>NSPrivacyAccessedAPIType<\/key>\s*<string>NSPrivacyAccessedAPICategoryUserDefaults<\/string>/, privacy)
    assert_match(/<key>NSPrivacyAccessedAPITypeReasons<\/key>\s*<array>\s*<string>CA92\.1<\/string>\s*<\/array>/, privacy)

    en = File.read(File.join(ROOT, "fastlane/metadata/en-US/promotional_text.txt"), encoding: "UTF-8")
    fr = File.read(File.join(ROOT, "fastlane/metadata/fr-FR/promotional_text.txt"), encoding: "UTF-8")
    assert_match(/17 (?:original )?missions/i, en)
    assert_match(/17 missions/i, fr)
    refute_match(/six mission states|six états de mission/i, "#{en}\n#{fr}")
    refute_match(/Space Cadet|Windows|Microsoft/i, "#{en}\n#{fr}")

    handshake = File.read(File.join(ROOT, "NovaStationPinball/App/MediaPreviewHandshake.swift"), encoding: "UTF-8")
    preview_test = File.read(File.join(ROOT, "NovaStationPinballUITests/AppPreviewUITests.swift"), encoding: "UTF-8")
    preview_generator = File.read(File.join(ROOT, "scripts/app_store/generate_app_previews.rb"), encoding: "UTF-8")
    %w[ready recording started complete].each { |marker| assert_includes preview_generator, %Q{"#{marker}"} }
    assert_includes handshake, "prepareAndSignalReady"
    assert_includes preview_test, "NOVA_MEDIA_HANDSHAKE_TOKEN"
    assert_includes preview_test, 'XCUIApplication(bundleIdentifier: "com.apple.springboard")'
    assert_includes preview_test, 'notificationIdentifier = "NotificationShortLookView"'
    assert_includes preview_test, "initialDelaySeconds: TimeInterval = 30"
    assert_includes preview_test, "requiredContinuousAbsenceSeconds: TimeInterval = 5"
    assert_includes preview_test, "maximumObservationSeconds: TimeInterval = 30"
    assert_operator preview_test.index("guard waitForSpringBoardToSettle()"), :<,
                    preview_test.index("let app = XCUIApplication()")
    assert_includes preview_generator, 'wait_for!("ready")'
    assert_includes preview_generator, 'wait_for!("complete")'
    assert_includes preview_generator, "wait_until_writing!"
    assert_includes preview_generator, "recorder.wait_until_elapsed!"
    assert_includes preview_generator, "CaptureTiming.trim_offset"
    assert_includes preview_generator, "capture_trim_offset: trim_offset"
    assert_includes preview_generator, "RAW_TAIL_MARGIN_SECONDS = 1.0"
    assert_includes preview_generator, "MAX_FINAL_PADDING_SECONDS = 1.0 / FRAME_RATE"
    assert_includes preview_generator, "RawTimeline.end_time"
    assert_includes preview_generator, "CaptureWindow.residual_padding"
    assert_includes preview_generator, "EncodedMedia.validate!"
    assert_includes preview_generator, "timeout: 90.0"
    overlay_index = preview_generator.index("validate_system_overlay!(destination, locale, device)")
    mark_index = preview_generator.index("mark_artifact!", overlay_index || 0)
    refute_nil overlay_index
    refute_nil mark_index
    assert_operator overlay_index, :<, mark_index
    assert_includes preview_generator, 'runner.capture("xcrun", "simctl", "shutdown", udid)'
    assert_includes preview_generator, "configuration.udids.each_key"
    assert_includes preview_generator, "prepare_canonical_test_artifacts!(device)"
    assert_includes preview_generator, "configuration.locales.each"
    assert_includes preview_generator, "XCTestRunConfigurator.new.find!"
    assert_includes preview_generator, "source: canonical.xctestrun"
    assert_equal 1, preview_generator.scan("build_for_testing_arguments").length
    assert_equal 1, preview_generator.scan("test_without_building_arguments").length
    assert_operator preview_generator.index("configuration.udids.each_key"), :<,
                    preview_generator.index("prepare_canonical_test_artifacts!(device)")
    assert_operator preview_generator.index("prepare_canonical_test_artifacts!(device)"), :<,
                    preview_generator.index("configuration.locales.each")
    refute_match(/simctl.*(?:install|uninstall)/, preview_generator)
    refute_match(/shutdown all|erase all|\bbooted\b/i, preview_generator)
    refute_match(/Process\.spawn\(\s*\{\s*"NOVA_MEDIA_HANDSHAKE_TOKEN"/m, preview_generator)
    %w[-profile:v -level:v -b:v -minrate -maxrate -profile:a -b:a -ar -ac].each do |flag|
      assert_includes preview_generator, %Q{"#{flag}"}
    end
    assert_includes preview_generator, "tpad=stop_mode=clone"
    assert_includes preview_generator, "TARGET_FRAME_COUNT = 720"
    assert_includes preview_generator, 'trim=end_frame=#{CaptureWindow::TARGET_FRAME_COUNT}'
    assert_includes preview_generator, '"-frames:v"'
    assert_includes preview_generator, "atrim=duration=24"
    assert_includes preview_generator, "fps=30"
    assert_includes preview_generator, "setfield=prog"
    assert_includes preview_generator, "nal-hrd=cbr"
    refute_includes preview_generator, '"-shortest"'

    generation = File.read(File.join(ROOT, "scripts/app_store/media_generation.rb"), encoding: "UTF-8")
    assert_includes generation, "REQUIRED_RUNTIME"
    assert_includes generation, "iOS-26-2"
    assert_includes generation, "simulator lease ownership changed"
    assert_includes generation, "/private/tmp/apps-factory/NovaStationPinball"
    assert_includes generation, "EnvironmentVariablesEnabled"
    assert_includes generation, "EnvironmentVariables"
    assert_includes generation, "NOVA_MEDIA_HANDSHAKE_TOKEN"
    assert_includes generation, "build-for-testing"
    assert_includes generation, "test-without-building"
    media_contract = File.read(File.join(ROOT, "scripts/app_store/media_contract.rb"), encoding: "UTF-8")
    assert_includes media_contract, '"capture_trim_offset_seconds" => nil'
    assert_includes media_contract, "invalid capture trim offset"
    assert_includes media_contract, "preview video track must be exactly 24 seconds"
    assert_includes media_contract, "preview audio track must be exactly 24 seconds"
    assert_includes media_contract, "preview must contain exactly 720 video frames"
    assert_includes media_contract, "class SystemOverlayGuard"
    assert_includes media_contract, "EXPECTED_FRAME_COUNT = 720"
    assert_includes media_contract, "MAX_TOP_BAND_YAVG = 64.0"
    assert_includes media_contract, "lavfi.signalstats.YAVG"
    assert_includes media_contract, "system UI top-band guard rejected"
    assert_includes media_contract, "violation_spans"
    assert_includes media_contract, "@overlay_guard.validate!"
    reencoder = File.read(File.join(ROOT, "scripts/app_store/reencode_app_previews.rb"), encoding: "UTF-8")
    reencode_overlay = reencoder.index("SystemOverlayGuard.new")
    reencode_mark = reencoder.index("mark_artifact!", reencode_overlay || 0)
    refute_nil reencode_overlay
    refute_nil reencode_mark
    assert_operator reencode_overlay, :<, reencode_mark
    clean_fixture = JSON.parse(File.read(File.join(ROOT, "scripts/app_store/fixtures/system_overlay_clean.json")))
    polluted_fixture = JSON.parse(File.read(File.join(ROOT, "scripts/app_store/fixtures/system_overlay_polluted_en_se.json")))
    assert_equal 720, clean_fixture.fetch("frame_count")
    assert_empty clean_fixture.fetch("spans")
    polluted_span = polluted_fixture.fetch("spans").fetch(0)
    assert_equal "NotificationShortLookView", polluted_span.fetch("identifier")
    assert_equal 374, polluted_span.fetch("first_frame")
    assert_equal 597, polluted_span.fetch("last_frame")
    assert_equal 12.466667, polluted_span.fetch("first_pts_seconds")
    assert_equal 19.9, polluted_span.fetch("last_pts_seconds")
    refute_match(/simctl.*(?:create|delete)|shutdown all|erase all|\bbooted\b/i, generation)
  end

  private

  def required_files
    %w[
      AGENTS.md .gitignore README.md project.yml Package.swift Gemfile
      NovaStationPinball/Resources/PrivacyInfo.xcprivacy
      NovaStationPinball/NovaStationPinball.entitlements
      NovaStationPinball/App/NovaStationPinballApp.swift
      NovaStationPinball/App/MediaPreviewHandshake.swift
      NovaStationPinballTests/BootstrapTests.swift
      NovaStationPinballUITests/BootstrapUITests.swift
      NovaStationCore/Sources/NovaStationCore/NovaStationCore.swift
      NovaStationCore/Tests/NovaStationCoreTests/NovaStationCoreTests.swift
      scripts/release_contract.rb scripts/release_contract_test.rb
      fastlane/Fastfile fastlane/Appfile fastlane/release_config.json
      fastlane/metadata/en-US/support_url.txt
      fastlane/metadata/fr-FR/support_url.txt
      docs/index.html docs/privacy.html
    ].map { |path| File.join(ROOT, path) }
  end

  def public_contact_files
    %w[
      docs/index.html docs/privacy.html
      fastlane/metadata/en-US/support_url.txt
      fastlane/metadata/fr-FR/support_url.txt
    ].map { |path| File.join(ROOT, path) }
  end
end
