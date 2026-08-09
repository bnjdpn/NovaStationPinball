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
    assert_includes preview_generator, 'wait_for!("ready")'
    assert_includes preview_generator, 'wait_for!("complete")'
    assert_includes preview_generator, "wait_until_writing!"
    assert_includes preview_generator, "CaptureTiming.trim_offset"
    assert_includes preview_generator, "capture_trim_offset: trim_offset"
    refute_match(/Process\.spawn\(\s*\{\s*"NOVA_MEDIA_HANDSHAKE_TOKEN"/m, preview_generator)
    %w[-profile:v -level:v -b:v -minrate -maxrate -profile:a -b:a -ar -ac].each do |flag|
      assert_includes preview_generator, %Q{"#{flag}"}
    end
    assert_includes preview_generator, "nal-hrd=cbr"

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
