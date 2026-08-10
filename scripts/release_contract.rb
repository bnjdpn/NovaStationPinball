#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require "yaml"

module NovaStationPinballReleaseContract
  ROOT = File.expand_path("..", __dir__)
  BUNDLE_ID = "com.bnjdpn.NovaStationPinball"
  REQUIRED_LOCALES = %w[en-US fr-FR].freeze
  REQUIRED_TIPS = %w[tip.cafe tip.merci tip.soutien].freeze
  REQUIRED_LANES = %w[
    setup_asc release_contract asc_status metadata screenshots app_previews adopt_media media_contract upload_screenshots
    upload_previews build_release upload_release submit_review release_quick pricing
    iap_status iap_sync
  ].freeze
  FORMSPREE_ENDPOINT = "https://formspree.io/f/mykqbyyw"

  class Verifier
    def initialize(root = ROOT)
      @root = root
      @errors = []
    end

    def verify
      validate_required_files
      validate_project
      validate_package
      validate_bootstrap_sources
      validate_release_config
      validate_metadata
      validate_privacy_manifest
      validate_media_pipeline
      validate_optional_services
      validate_fastlane
      validate_support_page
      validate_ci
      @errors
    end

    private

    def validate_required_files
      %w[
        AGENTS.md .gitignore README.md project.yml Package.swift Gemfile
        NovaStationPinball/Resources/PrivacyInfo.xcprivacy
        NovaStationPinball/NovaStationPinball.entitlements
        NovaStationPinball/App/NovaStationPinballApp.swift
        NovaStationPinball/App/AppModel.swift
        NovaStationPinballTests/BootstrapTests.swift
        NovaStationPinballUITests/BootstrapUITests.swift
        NovaStationPinballUITests/StoreScreenshotUITests.swift
        NovaStationPinballUITests/AppPreviewUITests.swift
        NovaStationPinballUITests/TipJarReviewUITests.swift
        NovaStationPinball/App/MediaScenario.swift
        NovaStationPinball/App/MediaPreviewHandshake.swift
        NovaStationCore/Sources/NovaStationCore/NovaStationCore.swift
        NovaStationCore/Tests/NovaStationCoreTests/NovaStationCoreTests.swift
        fastlane/Fastfile fastlane/Appfile fastlane/release_config.json
        fastlane/media_adoption_contract.json
        fastlane/metadata/en-US/support_url.txt
        fastlane/metadata/fr-FR/support_url.txt
        scripts/app_store/media_contract.rb
        scripts/app_store/media_contract_test.rb
        scripts/app_store/adopt_media.rb
        scripts/app_store/adopt_media_test.rb
        scripts/app_store/setup_asc_test.rb
        scripts/app_store/media_generation.rb
        scripts/app_store/generate_screenshots.rb
        scripts/app_store/generate_app_previews.rb
        docs/index.html docs/privacy.html
      ].each { |path| error("missing #{path}") unless File.file?(path(path)) }
    end

    def validate_project
      project = YAML.safe_load(File.read(path("project.yml"), encoding: "UTF-8"), aliases: false)
      target = project.fetch("targets").fetch("NovaStationPinball")
      settings = target.fetch("settings").fetch("base")
      info = target.fetch("info").fetch("properties")
      error("bundle ID mismatch") unless settings["PRODUCT_BUNDLE_IDENTIFIER"] == BUNDLE_ID
      error("iOS deployment target must be 17.0") unless target["deploymentTarget"] == "17.0"
      error("Swift version must be 6.0") unless settings["SWIFT_VERSION"] == "6.0"
      error("device families must be iPhone and iPad") unless settings["TARGETED_DEVICE_FAMILY"] == "1,2"
      error("marketing version must be controlled by Xcode build settings") unless
        settings["MARKETING_VERSION"] == "1.0" &&
          info["CFBundleShortVersionString"] == "$(MARKETING_VERSION)"
      error("build number must be controlled by Xcode build settings") unless
        settings["CURRENT_PROJECT_VERSION"] == "1" &&
          info["CFBundleVersion"] == "$(CURRENT_PROJECT_VERSION)"
      error("export compliance declaration must be explicit") unless
        info["ITSAppUsesNonExemptEncryption"] == false
      landscapes = %w[UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight]
      error("iPhone orientation must be landscape") unless info["UISupportedInterfaceOrientations"] == landscapes
      error("iPad orientation must be landscape") unless info["UISupportedInterfaceOrientations~ipad"] == landscapes
      expected_targets = %w[NovaStationPinball NovaStationPinballTests NovaStationPinballUITests]
      error("XcodeGen targets are incomplete") unless project.fetch("targets").keys.sort == expected_targets
      error("app sources are incomplete") unless source_paths(target) == ["NovaStationPinball"]
      error("unit test sources are incomplete") unless source_paths(project.fetch("targets").fetch("NovaStationPinballTests")) == ["NovaStationPinballTests"]
      error("UI test sources are incomplete") unless source_paths(project.fetch("targets").fetch("NovaStationPinballUITests")) == ["NovaStationPinballUITests"]
    rescue StandardError => exception
      error("invalid project.yml: #{exception.message}")
    end

    def validate_package
      package = File.read(path("Package.swift"), encoding: "UTF-8")
      error("NovaStationCore product is missing") unless package.include?('.library(name: "NovaStationCore", targets: ["NovaStationCore"])')
      error("NovaStationCore source target is missing") unless package.include?('.target(name: "NovaStationCore", path: "NovaStationCore/Sources/NovaStationCore")')
      error("NovaStationCore test target is missing") unless package.include?('.testTarget(name: "NovaStationCoreTests", dependencies: ["NovaStationCore"], path: "NovaStationCore/Tests/NovaStationCoreTests")')
    rescue Errno::ENOENT
      error("missing Package.swift")
    end

    def validate_bootstrap_sources
      app_source = File.read(path("NovaStationPinball/App/NovaStationPinballApp.swift"), encoding: "UTF-8")
      error("app entry point is missing @main") unless app_source.include?("@main") && app_source.include?("struct NovaStationPinballApp: App")
      unit_test = File.read(path("NovaStationPinballTests/BootstrapTests.swift"), encoding: "UTF-8")
      error("unit test bootstrap is missing") unless unit_test.include?("XCTestCase")
      ui_test = File.read(path("NovaStationPinballUITests/BootstrapUITests.swift"), encoding: "UTF-8")
      error("UI test bootstrap is missing") unless ui_test.include?("XCUIApplication")
      core_source = File.read(path("NovaStationCore/Sources/NovaStationCore/NovaStationCore.swift"), encoding: "UTF-8")
      error("SwiftPM core source is missing") unless core_source.include?("public enum NovaStationCore")
      core_test = File.read(path("NovaStationCore/Tests/NovaStationCoreTests/NovaStationCoreTests.swift"), encoding: "UTF-8")
      error("SwiftPM core test is missing") unless core_test.include?("@testable import NovaStationCore")
    rescue Errno::ENOENT => exception
      error("missing bootstrap source: #{exception.message}")
    end

    def validate_release_config
      config = JSON.parse(File.read(path("fastlane/release_config.json"), encoding: "UTF-8"))
      error("release locales must be French and English") unless config["locales"].sort == REQUIRED_LOCALES
      tips = config.fetch("tip_products").map { |tip| tip.fetch("id") }.sort
      error("only the three optional tips are allowed") unless tips == REQUIRED_TIPS
      error("support URL mismatch") unless config["support_url"] == "https://bnjdpn.github.io/NovaStationPinball/#contact"
      expected_scenarios = %w[launch mission promotion multiball tilt game-over]
      expected_preview_policy = {
        "applicable" => true,
        "review_each_release" => true,
        "generator" => "scripts/app_store/generate_app_previews.rb",
        "parallel_locales" => 2,
        "scenarios" => expected_scenarios
      }
      error("App Preview policy mismatch") unless config["app_preview_policy"] == expected_preview_policy
      media = config.fetch("media_contract")
      error("media generator mismatch") unless media["generator"] == "scripts/app_store/generate_screenshots.rb"
      error("media validator mismatch") unless media["validator"] == "scripts/app_store/media_contract.rb"
      error("media generation must limit parallel locales to two") unless media["parallel_locales"] == 2
      error("media devices mismatch") unless media["devices"] == %w[iphone-17-pro-max iphone-se-3 ipad-pro-13-m5]
      error("media scenarios mismatch") unless media["scenarios"] == expected_scenarios
    rescue StandardError => exception
      error("invalid release config: #{exception.message}")
    end

    def validate_metadata
      required = %w[
        name.txt subtitle.txt description.txt keywords.txt promotional_text.txt
        release_notes.txt support_url.txt privacy_url.txt marketing_url.txt
      ]
      REQUIRED_LOCALES.each do |locale|
        required.each do |filename|
          relative = "fastlane/metadata/#{locale}/#{filename}"
          unless File.file?(path(relative))
            error("missing #{relative}")
            next
          end
          value = File.read(path(relative), encoding: "UTF-8").strip
          error("empty #{relative}") if value.empty?
          error("public identity reference in #{relative}") if value.match?(/Space Cadet|Windows|Microsoft/i)
        end
        validate_metadata_limit(locale, "name.txt", 30)
        validate_metadata_limit(locale, "subtitle.txt", 30)
        validate_metadata_limit(locale, "promotional_text.txt", 170)
        keywords = File.read(path("fastlane/metadata/#{locale}/keywords.txt"), encoding: "UTF-8").strip
        error("keywords exceed 100 bytes for #{locale}") if keywords.bytesize > 100
        support = File.read(path("fastlane/metadata/#{locale}/support_url.txt"), encoding: "UTF-8").strip
        privacy = File.read(path("fastlane/metadata/#{locale}/privacy_url.txt"), encoding: "UTF-8").strip
        error("support URL mismatch for #{locale}") unless support == "https://bnjdpn.github.io/NovaStationPinball/#contact"
        error("privacy URL mismatch for #{locale}") unless privacy == "https://bnjdpn.github.io/NovaStationPinball/privacy.html"
      end
      en_promo = File.read(path("fastlane/metadata/en-US/promotional_text.txt"), encoding: "UTF-8")
      fr_promo = File.read(path("fastlane/metadata/fr-FR/promotional_text.txt"), encoding: "UTF-8")
      error("English promotional text must truthfully advertise 17 original missions") unless en_promo.match?(/17 (?:original )?missions/i)
      error("French promotional text must truthfully advertise 17 missions") unless fr_promo.match?(/17 missions/i)
      error("promotional text must not claim six mission states") if "#{en_promo}\n#{fr_promo}".match?(/six mission states|six états de mission/i)
    rescue Errno::ENOENT => exception
      error("metadata validation failed: #{exception.message}")
    end

    def validate_privacy_manifest
      privacy = File.read(path("NovaStationPinball/Resources/PrivacyInfo.xcprivacy"), encoding: "UTF-8")
      unless privacy.match?(/<key>NSPrivacyAccessedAPIType<\/key>\s*<string>NSPrivacyAccessedAPICategoryUserDefaults<\/string>/)
        error("privacy manifest must declare UserDefaults required-reason API category")
      end
      unless privacy.match?(/<key>NSPrivacyAccessedAPITypeReasons<\/key>\s*<array>\s*<string>CA92\.1<\/string>\s*<\/array>/)
        error("privacy manifest must declare UserDefaults reason CA92.1")
      end
    rescue Errno::ENOENT
      error("missing PrivacyInfo.xcprivacy")
    end

    def validate_metadata_limit(locale, filename, maximum)
      value = File.read(path("fastlane/metadata/#{locale}/#{filename}"), encoding: "UTF-8").strip
      error("#{filename} exceeds #{maximum} characters for #{locale}") if value.length > maximum
    end

    def validate_media_pipeline
      scenario_source = File.read(path("NovaStationPinball/App/MediaScenario.swift"), encoding: "UTF-8")
      app_model_source = File.read(path("NovaStationPinball/App/AppModel.swift"), encoding: "UTF-8")
      scenarios = %w[launch mission promotion multiball tilt game-over]
      scenarios.each { |scenario| error("missing media scenario #{scenario}") unless scenario_source.include?(%Q{"#{scenario}"}) }
      error("media scenarios must not reference vector assets") if scenario_source.match?(/\.svg\b|\.pdf\b/i)
      unless scenario_source.include?("static func preparePreviewSessions()") &&
             scenario_source.include?("allCases.map { scenario in")
        error("App Preview sessions must be prepared as the exact scenario catalog")
      end
      prepare_marker = "let preparedSessions = try MediaScenario.preparePreviewSessions()"
      ready_marker = "try handshake.prepareAndSignalReady()"
      prepare_index = app_model_source.index(prepare_marker)
      ready_index = app_model_source.index(ready_marker)
      unless prepare_index && ready_index && prepare_index < ready_index
        error("App Preview sessions must be prepared before the ready handshake")
      end
      loop_start = app_model_source.index("for (offset, scenario) in MediaScenario.allCases.dropFirst().enumerated()")
      loop_end = app_model_source.index("try await clock.sleep(until: timelineStart.advanced(by: .seconds(24)))")
      loop_source = loop_start && loop_end && loop_start < loop_end ? app_model_source[loop_start...loop_end] : ""
      unless loop_source.include?("preparedSessions[scenario]") &&
             loop_source.include?("applyMediaScenario(scenario, preparedSession: preparedSession)") &&
             !loop_source.include?("makeSession()")
        error("the timed App Preview loop must only swap prepared sessions")
      end

      screenshot_tests = File.read(path("NovaStationPinballUITests/StoreScreenshotUITests.swift"), encoding: "UTF-8")
      preview_tests = File.read(path("NovaStationPinballUITests/AppPreviewUITests.swift"), encoding: "UTF-8")
      scenarios.each do |scenario|
        error("screenshot scenario missing #{scenario}") unless screenshot_tests.include?(%Q{"#{scenario}"})
        error("preview scenario missing #{scenario}") unless preview_tests.include?(%Q{"#{scenario}"})
      end
      error("screenshot tests must retain real XCTest attachments") unless screenshot_tests.include?("XCTAttachment(screenshot:")
      unless screenshot_tests.include?("assertGuideCopyFitsAboveNavigation(in: app)") &&
             screenshot_tests.include?("body.frame.maxY") &&
             screenshot_tests.include?("next.frame.minY - 8") &&
             preview_tests.include?("assertGuideCopyFitsAboveNavigation(in: app)") &&
             preview_tests.include?("app.descendants(matching: .any)") &&
             preview_tests.include?(%Q{matching(identifier: "tableGuideNavigation")}) &&
             preview_tests.include?("XCTAssertTrue(title.exists)") &&
             preview_tests.include?("XCTAssertTrue(body.exists)") &&
             preview_tests.include?("XCTAssertTrue(navigation.exists)") &&
             !preview_tests.include?("title.waitForExistence") &&
             !preview_tests.include?("body.waitForExistence") &&
             !preview_tests.include?("navigation.waitForExistence") &&
             preview_tests.include?("body.frame.maxY") &&
             preview_tests.include?("navigation.frame.minY - 8")
        error("mission screenshot and preview tests must fail closed when localized guide copy reaches the fixed navigation")
      end

      generation = File.read(path("scripts/app_store/media_generation.rb"), encoding: "UTF-8")
      error("media generation must cap locale batches at two") unless generation.include?("locales.each_slice(2)")
      error("media generation must target exact simulator UDIDs") unless generation.include?("platform=iOS Simulator,id=")
      error("media generation must require fixed-pool ownership locks") unless
        generation.include?("simulator lease ownership changed") && generation.include?("lease path is not the fixed-pool lock")
      error("media generation must require iOS 26.2 exact model descriptors") unless
        generation.include?("com.apple.CoreSimulator.SimRuntime.iOS-26-2") &&
          generation.include?("com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max") &&
          generation.include?("com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation") &&
          generation.include?("com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5")
      if generation.match?(/simctl.*(?:create|delete)|shutdown all|erase all|\bbooted\b/i)
        error("media generation must never select or mutate unowned simulators")
      end
      unless generation.include?("build-for-testing") && generation.include?("test-without-building") &&
             generation.include?("XCTestRunConfigurator") &&
             generation.include?("EnvironmentVariablesEnabled") &&
             generation.include?("EnvironmentVariables") &&
             generation.include?("NOVA_MEDIA_HANDSHAKE_TOKEN")
        error("App Preview handshake token must be injected into an isolated xctestrun")
      end
      preview_generator = File.read(path("scripts/app_store/generate_app_previews.rb"), encoding: "UTF-8")
      ready = preview_generator.index('wait_for!("ready")')
      recording = preview_generator.index("recordVideo")
      recorder_ready = preview_generator.rindex("wait_until_writing!")
      recording_marker = preview_generator.index('write!("recording")')
      started = preview_generator.index('wait_for!("started")')
      complete = preview_generator.index('wait_for!("complete")')
      raw_tail_wait = preview_generator.rindex("recorder.wait_until_elapsed!")
      stop = preview_generator.index('stop_owned_process!(record_pid, "INT")')
      unless ready && recording && recorder_ready && recording_marker && started && complete && raw_tail_wait && stop &&
             ready < recording && recording < recorder_ready && recorder_ready < recording_marker &&
             recording_marker < started && complete < raw_tail_wait && raw_tail_wait < stop
        error("App Preview recording must be bounded by the ready/complete app handshake and full raw capture window")
      end
      device_loop = preview_generator.index("configuration.udids.each_key")
      canonical_call = preview_generator.index("prepare_canonical_test_artifacts!(device)", device_loop || 0)
      locale_loop = preview_generator.index("configuration.locales.each", canonical_call || 0)
      build = preview_generator.index("build_for_testing_arguments")
      run_build = preview_generator.index("run_xcodebuild!(arguments)", build || 0)
      find = preview_generator.index("XCTestRunConfigurator.new.find!", run_build || 0)
      inject = preview_generator.index("inject_environment!", find || 0)
      test = preview_generator.index("test_without_building_arguments", inject || 0)
      canonical_pipeline = [build, run_build, find, inject, test]
      unless device_loop && canonical_call && locale_loop && device_loop < canonical_call && canonical_call < locale_loop &&
             canonical_pipeline.all? && canonical_pipeline.each_cons(2).all? { |left, right| left < right } &&
             preview_generator.scan("build_for_testing_arguments").length == 1 &&
             preview_generator.scan("test_without_building_arguments").length == 1 &&
             preview_generator.include?("source: canonical.xctestrun") &&
             !preview_generator.match?(/simctl.*(?:install|uninstall)/)
        error("App Preview XCTest must build once per device, then run locale xctestrun copies sequentially from the canonical products")
      end
      if preview_generator.match?(/Process\.spawn\(\s*\{\s*"NOVA_MEDIA_HANDSHAKE_TOKEN"/m)
        error("App Preview handshake token must not rely on a shell export around xcodebuild")
      end
      media_contract = File.read(path("scripts/app_store/media_contract.rb"), encoding: "UTF-8")
      preview_test = File.read(path("NovaStationPinballUITests/AppPreviewUITests.swift"), encoding: "UTF-8")
      settle = preview_test.index("guard waitForSpringBoardToSettle()")
      launch = preview_test.index("let app = XCUIApplication()", settle || 0)
      unless settle && launch && settle < launch &&
             preview_test.include?('XCUIApplication(bundleIdentifier: "com.apple.springboard")') &&
             preview_test.include?('notificationIdentifier = "NotificationShortLookView"') &&
             preview_test.include?("initialDelaySeconds: TimeInterval = 30") &&
             preview_test.include?("requiredContinuousAbsenceSeconds: TimeInterval = 5") &&
             preview_test.include?("maximumObservationSeconds: TimeInterval = 30") &&
             preview_generator.include?("timeout: 90.0")
        error("App Preview capture must wait after boot and require a bounded continuous absence of SpringBoard notifications before launch/recording")
      end
      unless preview_generator.include?("CaptureTiming.trim_offset") &&
             preview_generator.include?("capture_trim_offset: trim_offset") &&
             media_contract.include?('"capture_trim_offset_seconds" => nil') &&
             media_contract.include?("invalid capture trim offset")
        error("App Preview measured trim offset must be persisted and validated")
      end
      unless preview_generator.include?("RAW_TAIL_MARGIN_SECONDS = 1.0") &&
             preview_generator.include?("MAX_FINAL_PADDING_SECONDS = 1.0 / FRAME_RATE") &&
             preview_generator.include?("RawTimeline.end_time") &&
             preview_generator.include?("CaptureWindow.residual_padding") &&
             preview_generator.include?("EncodedMedia.validate!")
        error("App Preview recorder must retain a deterministic raw tail and fail closed beyond one frame of residual padding")
      end
      %w[-profile:v -level:v -pix_fmt -b:v -minrate -maxrate -profile:a -b:a -ar -ac].each do |flag|
        error("App Preview encoder missing #{flag}") unless preview_generator.include?(%Q{"#{flag}"})
      end
      unless preview_generator.include?("tpad=stop_mode=clone") &&
             preview_generator.include?("TARGET_FRAME_COUNT = 720") &&
             preview_generator.include?('trim=end_frame=#{CaptureWindow::TARGET_FRAME_COUNT}') &&
             preview_generator.include?('"-frames:v"') &&
             preview_generator.include?("atrim=duration=24") &&
             preview_generator.include?("fps=30") &&
             preview_generator.include?("setfield=prog") &&
             preview_generator.include?("nal-hrd=cbr") &&
             !preview_generator.include?('"-shortest"')
        error("App Preview encoder must produce exact 24-second, 720-frame progressive H.264 CBR media without shortest truncation")
      end
      unless media_contract.include?("preview video track must be exactly 24 seconds") &&
             media_contract.include?("preview audio track must be exactly 24 seconds") &&
             media_contract.include?("preview must contain exactly 720 video frames")
        error("App Preview media contract must validate exact audio/video durations and frame count")
      end
      overlay = preview_generator.index("validate_system_overlay!(destination, locale, device)")
      mark = preview_generator.index("mark_artifact!", overlay || 0)
      reencoder = File.read(path("scripts/app_store/reencode_app_previews.rb"), encoding: "UTF-8")
      reencode_overlay = reencoder.index("SystemOverlayGuard.new")
      reencode_mark = reencoder.index("mark_artifact!", reencode_overlay || 0)
      unless overlay && mark && overlay < mark && reencode_overlay && reencode_mark && reencode_overlay < reencode_mark &&
             media_contract.include?("class SystemOverlayGuard") &&
             media_contract.include?("EXPECTED_FRAME_COUNT = 720") &&
             media_contract.include?("MAX_TOP_BAND_YAVG = 64.0") &&
             media_contract.include?("lavfi.signalstats.YAVG") &&
             media_contract.include?("system UI top-band guard rejected") &&
             media_contract.include?("violation_spans") &&
             media_contract.include?("@overlay_guard.validate!")
        error("App Preview generation, reuse, and strict contract must exhaustively reject system overlays across all 720 top-band frames with timestamped reports")
      end
      clean_fixture = JSON.parse(File.read(path("scripts/app_store/fixtures/system_overlay_clean.json"), encoding: "UTF-8"))
      polluted_fixture = JSON.parse(File.read(path("scripts/app_store/fixtures/system_overlay_polluted_en_se.json"), encoding: "UTF-8"))
      polluted_span = polluted_fixture.fetch("spans", []).first
      unless clean_fixture["frame_count"] == 720 && clean_fixture["spans"] == [] &&
             polluted_fixture["frame_count"] == 720 &&
             polluted_span&.values_at("identifier", "first_frame", "last_frame", "first_pts_seconds", "last_pts_seconds") ==
               ["NotificationShortLookView", 374, 597, 12.466667, 19.9]
        error("system-overlay fixtures must retain the clean 720-frame control and the observed EN SE 12.466667-19.900000 regression")
      end
      error("App Preview UI test must receive the app-local handshake token") unless preview_test.include?("NOVA_MEDIA_HANDSHAKE_TOKEN")
      fastfile = File.read(path("fastlane/Fastfile"), encoding: "UTF-8")
      %w[generate_screenshots.rb generate_app_previews.rb media_contract.rb adopt_media.rb].each do |script|
        error("Fastlane media hook missing #{script}") unless fastfile.include?("scripts/app_store/#{script}")
      end
      %w[upload_screenshots upload_previews release_quick].each do |lane|
        body = fastfile[/lane :#{lane}\b do\n(.*?)\n\s*end/m, 1]
        error("#{lane} must gate media through media_contract") unless body&.include?("media_contract")
      end
    rescue Errno::ENOENT, JSON::ParserError => exception
      error("media pipeline validation failed: #{exception.message}")
    end

    def validate_fastlane
      fastfile = File.read(path("fastlane/Fastfile"), encoding: "UTF-8")
      REQUIRED_LANES.each { |lane| error("missing Fastlane lane #{lane}") unless fastfile.match?(/^\s*lane :#{Regexp.escape(lane)}\b/) }
      error("Fastlane lane must invoke standalone contract") unless fastfile.include?("scripts/release_contract.rb")
    rescue Errno::ENOENT
      error("missing fastlane/Fastfile")
    end

    def validate_optional_services
      storekit = JSON.parse(File.read(path("NovaStationPinball/StoreKit/NovaStationPinball.storekit"), encoding: "UTF-8"))
      products = storekit.fetch("products")
      expected_product_ids = REQUIRED_TIPS.map { |tip| "#{BUNDLE_ID}.#{tip}" }.sort
      error("StoreKit configuration must contain exactly the three tips") unless products.map { |product| product.fetch("productID") }.sort == expected_product_ids
      error("all tip products must be consumable") unless products.all? { |product| product["type"] == "Consumable" }
      error("tip products must unlock no features") unless products.all? do |product|
        product.fetch("localizations").all? do |localization|
          localization.fetch("description").match?(/(?:Unlocks no features|ne débloque aucune fonctionnalité)/i)
        end
      end

      project = YAML.safe_load(File.read(path("project.yml"), encoding: "UTF-8"), aliases: false)
      app_sources = project.fetch("targets").fetch("NovaStationPinball").fetch("sources")
      excluded = app_sources.flat_map { |source| source.fetch("excludes", []) }
      error("StoreKit development configuration must be excluded from the app bundle") unless excluded.include?("StoreKit")
      run_configuration = project.fetch("schemes").fetch("NovaStationPinball").fetch("run", {})
      unless run_configuration["storeKitConfiguration"] == "NovaStationPinball/StoreKit/NovaStationPinball.storekit"
        error("StoreKit development configuration must be attached to the run scheme")
      end

      %w[AudioEngine.swift HapticsService.swift GameCenterClient.swift TipJarSupport.swift].each do |filename|
        source = File.read(path("NovaStationPinball/Services/#{filename}"), encoding: "UTF-8")
        error("required network client in #{filename}") if source.match?(/\b(?:URLSession|NWConnection)\b/)
      end
      game_center = File.read(path("NovaStationPinball/Services/GameCenterClient.swift"), encoding: "UTF-8")
      error("Game Center must provide a foreground-scene authentication presenter") unless
        game_center.include?("presentAuthenticationController") && game_center.include?(".foregroundActive")
      error("Game Center authentication presenter must not default to nil") if
        game_center.match?(/presenter:\s*AuthenticationPresenter\?\s*=\s*nil/)

      app_model = File.read(path("NovaStationPinball/App/AppModel.swift"), encoding: "UTF-8")
      local_save = app_model.index("localGameStore.saveHighScores")
      remote_submit = app_model.index("gameCenterClient.submit")
      unless local_save && remote_submit && local_save < remote_submit
        error("completed games must be saved locally before best-effort Game Center submission")
      end
      root_view = File.read(path("NovaStationPinball/App/RootView.swift"), encoding: "UTF-8")
      error("optional services must start from the non-blocking app lifecycle") unless
        root_view.include?(".task") && root_view.include?("model.start()") &&
          app_model.include?("func start()") && app_model.include?("startOptionalServices()") &&
          app_model.include?("lifecycleCoordinator.start()")

      tip_identifiers = %w[tipJarOpen tipJar tipJarClose tipJarStatus]
      tip_identifiers.each do |identifier|
        error("tip UI is missing stable identifier #{identifier}") unless
          root_view.include?(%Q{"#{identifier}"})
      end
      unless root_view.include?('"tipJarPurchase.\(tip.definition.id)"')
        error("tip UI must derive stable purchase identifiers from the exact tip catalog")
      end
      unless root_view.include?("model.availableTips()") &&
             root_view.match?(/model\.purchaseTip\(\s*productIdentifier:/m) &&
             root_view.include?("tip.displayName") &&
             root_view.include?("tip.displayPrice")
        error("tip UI must load StoreKit names and prices only after explicit access")
      end
      if root_view.match?(/(?:USD|EUR|\$\s*\d|\d+[.,]\d{2}\s*€)/)
        error("tip UI must not hard-code prices or currencies")
      end
      tip_support = File.read(path("NovaStationPinball/Services/TipJarSupport.swift"), encoding: "UTF-8")
      unless tip_support.include?("displayName: product.displayName") &&
             tip_support.include?("displayPrice: product.displayPrice") &&
             app_model.include?("TipJarSupportFactory.applicationDefault()")
        error("shipping tip names and prices must come from StoreKit.Product")
      end
      unless tip_support.match?(/#if DEBUG.*?NOVA_TIP_JAR_FIXTURE.*?#endif/m) &&
             tip_support.match?(/#if DEBUG.*?actor UITestingTipJarSupport.*?#endif/m) &&
             tip_support.include?('arguments.contains("-ui-testing")') &&
             tip_support.include?('environment["NOVA_TIP_JAR_FIXTURE"] == "available"') &&
             tip_support.include?("return StoreKitTipJarSupport()")
        error("tip UI fixture must be DEBUG-only, double-gated, and default to StoreKit")
      end
      unless tip_support.include?("Transaction.unfinished") &&
             tip_support.include?("Transaction.updates") &&
             tip_support.include?("knownProductIdentifiers.contains(transaction.productIdentifier)") &&
             tip_support.include?("await transaction.finish()")
        error("shipping tip support must finish verified catalog transactions delivered after a pending purchase")
      end
      products.each do |product|
        localizations = product.fetch("localizations")
        english_name = localizations.find { |entry| entry["locale"] == "en_US" }.fetch("displayName")
        french_name = localizations.find { |entry| entry["locale"] == "fr_FR" }.fetch("displayName")
        price = product.fetch("displayPrice")
        french_price = price.tr(".", ",")
        unless tip_support.include?(%Q{displayName: french ? "#{french_name}" : "#{english_name}"}) &&
               tip_support.include?(%Q{displayPrice: french ? "#{french_price} €" : "$#{price}"})
          error("tip UI fixture must mirror the StoreKit name and price for #{product.fetch("productID")}")
        end
      end
      ui_tests = File.read(path("NovaStationPinballUITests/LayoutUITests.swift"), encoding: "UTF-8")
      tip_identifiers.each do |identifier|
        error("tip UI test is missing #{identifier}") unless ui_tests.include?(identifier)
      end
      %w[tip.cafe tip.merci tip.soutien].each do |tip_id|
        error("tip UI test is missing resolved purchase identifier #{tip_id}") unless
          ui_tests.include?(%Q{"#{tip_id}"})
      end
      unless ui_tests.include?('app.buttons["tipJarPurchase.\(identifier)"]')
        error("tip UI test must resolve each exact tip through the dynamic purchase identifier")
      end
      unless ui_tests.include?('launchEnvironment["NOVA_TIP_JAR_FIXTURE"] = "available"') &&
             ui_tests.include?("-ui-testing")
        error("tip UI test must explicitly activate both fixture gates")
      end
      screenshot_tests = File.read(path("NovaStationPinballUITests/StoreScreenshotUITests.swift"), encoding: "UTF-8")
      preview_tests = File.read(path("NovaStationPinballUITests/AppPreviewUITests.swift"), encoding: "UTF-8")
      unless screenshot_tests.include?("tipJarOpen") && preview_tests.include?("tipJarOpen")
        error("shipping media tests must prove visible tip access")
      end
      if screenshot_tests.include?("NOVA_TIP_JAR_FIXTURE") || preview_tests.include?("NOVA_TIP_JAR_FIXTURE")
        error("shipping media must never use the UI-test tip fixture")
      end
      review_test = File.read(path("NovaStationPinballUITests/TipJarReviewUITests.swift"), encoding: "UTF-8")
      xcode_project = File.read(path("NovaStationPinball.xcodeproj/project.pbxproj"), encoding: "UTF-8")
      unless review_test.include?('launchEnvironment["NOVA_TIP_JAR_FIXTURE"] = "available"') &&
             review_test.include?("XCUIScreen.main.screenshot()") &&
             review_test.include?("screenshot.image.cgImage") &&
             review_test.include?("[2064, 2752]") &&
             review_test.include?("fixture DEBUG") &&
             !review_test.include?("purchaseButton.tap()") &&
             xcode_project.include?("TipJarReviewUITests.swift in Sources")
        error("IAP review capture must be compiled, fixture-labelled, full-screen, pixel-validated at 2752x2064, and non-purchasing")
      end
      background_is_conditional = root_view.match?(
        /if activeOverlay == nil \{\s+Rectangle\(\)\.fill\(\.clear\).*?"art\.frame\.4x3".*?HStack\(spacing: 0\).*?"art\.table".*?"art\.console"/m
      )
      unless background_is_conditional &&
             root_view.scan(".accessibilityAddTraits(.isModal)").length >= 2 &&
             root_view.include?(".frame(width: 44, height: 44)") &&
             ui_tests.include?('app.otherElements["art.frame.4x3"].exists') &&
             ui_tests.include?('app.buttons["tipJarClose"].frame.width')
        error("tip modal must hide background accessibility and expose a tested 44pt close target")
      end

      entitlements = File.read(path("NovaStationPinball/NovaStationPinball.entitlements"), encoding: "UTF-8")
      unless entitlements.match?(/<key>com\.apple\.developer\.game-center<\/key>\s*<true\/>/)
        error("Game Center entitlement must be enabled for the optional GameKit adapter")
      end
    rescue StandardError => exception
      error("invalid optional services configuration: #{exception.message}")
    end

    def validate_support_page
      page = File.read(path("docs/index.html"), encoding: "UTF-8")
      error("support Formspree endpoint mismatch") unless page.include?(FORMSPREE_ENDPOINT)
      error("support page must expose #contact") unless page.include?("id=\"contact\"")
      public_contact_paths.each do |relative|
        contents = File.read(path(relative), encoding: "UTF-8")
        error("public mailto link in #{relative}") if contents.match?(/mailto:/i)
        error("public email address in #{relative}") if contents.match?(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i)
      end
    rescue Errno::ENOENT
      error("missing docs/index.html")
    end

    def validate_ci
      error("GitHub workflows are forbidden") if Dir.exist?(path(".github/workflows"))
    end

    def error(message)
      @errors << message
    end

    def path(relative)
      File.join(@root, relative)
    end

    def source_paths(target)
      target.fetch("sources").map { |source| source.fetch("path") }
    end

    def public_contact_paths
      %w[docs/index.html docs/privacy.html] + Dir.glob(path("fastlane/metadata/{en-US,fr-FR}/*")).map do |absolute|
        Pathname.new(absolute).relative_path_from(Pathname.new(@root)).to_s
      end
    end
  end
end

errors = NovaStationPinballReleaseContract::Verifier.new.verify
if errors.empty?
  puts "release_contract: OK"
else
  errors.each { |error| warn "release_contract: #{error}" }
  exit 1
end
