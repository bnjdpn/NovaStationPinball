#!/usr/bin/env ruby
# frozen_string_literal: true

require "bigdecimal"
require "digest"
require "json"
require "pathname"
require "yaml"
require_relative "pages_workflow_contract"

module NovaStationPinballReleaseContract
  ROOT = File.expand_path("..", __dir__)

  # The shipped drill identifiers, read from the core catalog so the contract
  # can never drift away from the code that defines them.
  module ShotDrillIdentifiers
    SOURCE = File.join(ROOT, "NovaStationCore/Sources/NovaStationCore/ShotDrillCatalog.swift")

    def self.all
      body = File.read(SOURCE, encoding: "UTF-8")[/public static let drills: \[ShotDrill\] = \[(.*?)\n    \]/m, 1].to_s
      body.scan(/drill\("([a-z0-9-]+)"/).flatten
    end
  end
  # Strings that print a count. Each one must vary by grammatical number, on
  # the named argument, in every shipped locale: "1 attempts" on the screen
  # that sells the Workshop is slop, and it is a regression that comes back.
  COUNT_STRINGS = {
    "workshop.rewind.remaining" => 1,
    "workshop.drills.record" => 2,
    "drill.hud.remaining" => 1
  }.freeze
  BUNDLE_ID = "com.bnjdpn.NovaStationPinball"
  REQUIRED_LOCALES = %w[en-US fr-FR].freeze
  REQUIRED_LANES = %w[
    setup_asc release_contract asc_status metadata recover_metadata_pretransport screenshots app_previews adopt_media media_contract upload_screenshots
    upload_previews build_release upload_release submit_review release_quick pricing
    iap_status iap_sync paywall_review_screenshot
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
      validate_release_pipeline_products
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
        NovaStationPinball/App/RootView.swift
        NovaStationPinball/Services/StoreService.swift
        NovaStationPinballTests/BootstrapTests.swift
        NovaStationPinballUITests/BootstrapUITests.swift
        NovaStationPinballUITests/StoreScreenshotUITests.swift
        NovaStationPinballUITests/AppPreviewUITests.swift
        NovaStationPinballUITests/PaywallReviewUITests.swift
        NovaStationPinball/App/MediaScenario.swift
        NovaStationPinball/App/MediaPreviewHandshake.swift
        NovaStationCore/Sources/NovaStationCore/NovaStationCore.swift
        NovaStationCore/Tests/NovaStationCoreTests/NovaStationCoreTests.swift
        fastlane/Fastfile fastlane/Appfile fastlane/release_config.json
        fastlane/pro_products.json
        fastlane/media_adoption_contract.json
        fastlane/metadata_preflight.rb
        fastlane/metadata_pretransport_recovery.json
        fastlane/metadata/en-US/support_url.txt
        fastlane/metadata/fr-FR/support_url.txt
        scripts/app_store/media_contract.rb
        scripts/app_store/media_contract_test.rb
        scripts/app_store/adopt_media.rb
        scripts/app_store/adopt_media_test.rb
        scripts/app_store/client_test.rb
        scripts/app_store/metadata_pretransport_recovery.rb
        scripts/app_store/metadata_pretransport_recovery_test.rb
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
      config_version = JSON.parse(File.read(path("fastlane/release_config.json"), encoding: "UTF-8")).fetch("version")
      error("marketing version must match the release configuration") unless
        settings["MARKETING_VERSION"] == config_version &&
          info["CFBundleShortVersionString"] == "$(MARKETING_VERSION)"
      error("build number must be controlled by Xcode build settings") unless
        settings["CURRENT_PROJECT_VERSION"].to_s.match?(/\A[1-9][0-9]*\z/) &&
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
      # The second entry is a resource, not code: SKTestSession loads the
      # catalogue from the UI test bundle, which is the only way the review
      # capture can price the offer from this repository instead of from the
      # live App Store.
      error("UI test sources are incomplete") unless
        source_paths(project.fetch("targets").fetch("NovaStationPinballUITests")) ==
          ["NovaStationPinballUITests", "NovaStationPinball/StoreKit/NovaStationPinball.storekit"]
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
      pricing = config.fetch("pricing")
      error("configured price must be non-negative") if BigDecimal(pricing.fetch("price").to_s).negative?
      error("pricing territory must be configured") if pricing.fetch("territory", "").strip.empty?
      error("pricing currency must be configured") if pricing.fetch("currency", "").strip.empty?
      error("the tip jar catalogue must be gone from the release configuration") if config.key?("tip_products")
      products = config.fetch("iap_products")
      error("configured monetization products must be an array") unless products.is_a?(Array)
      product_ids = products.map { |product| product.fetch("product_id") }
      error("configured monetization product ids must be unique") unless product_ids.uniq.length == product_ids.length
      products.each do |product|
        error("configured monetization product id is missing") if product.fetch("product_id", "").strip.empty?
        error("configured monetization product type is invalid") unless product.fetch("type", "").match?(/\A[A-Z][A-Z0-9_]*\z/)
        error("a tip product must not be sold alongside a paid unlock") if product.fetch("product_id", "").include?(".tip.")
      end
      error("iap list must mirror configured monetization products") unless config.fetch("iap").sort == product_ids.sort
      validate_monetization_strategy(config, product_ids)
      validate_products_manifest(config)
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

    def validate_monetization_strategy(config, product_ids)
      strategy = config.fetch("monetization_strategy")
      error("monetization model must be the decided one-time unlock") unless strategy["model"] == "one_time_unlock"
      error("monetization strategy must name the sold product") unless product_ids.include?(strategy["product_id"])
      price = BigDecimal(strategy.fetch("base_price").to_s)
      error("monetization base price must be inside the studio 3.99-9.99 band") unless
        price >= BigDecimal("3.99") && price <= BigDecimal("9.99")
      error("monetization base currency must be configured") unless strategy["base_currency"] == "EUR"
      error("monetization base territory must be configured") unless strategy["base_territory"] == "FRA"
      error("monetization strategy must point at the products manifest") unless
        strategy["products_manifest"] == "fastlane/pro_products.json"
      %w[free_forever unlocks].each do |key|
        value = strategy[key]
        error("monetization strategy #{key} must list what it means") unless value.is_a?(Array) && !value.empty?
      end
      error("removing the tip jar must be recorded with its ASC action") unless
        strategy["tips_removed_on"].to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/) &&
          strategy["tips_asc_action"].to_s.include?("DEVELOPER_REMOVED_FROM_SALE")
      error("leaderboard integrity must be stated with the paid assistance") unless
        strategy["leaderboard_integrity"].to_s.match?(/Game Center/)
      error("grandfathering must be described as device-local and never revoked") unless
        strategy["grandfathering"].to_s.match?(/device-local/i) &&
          strategy["grandfathering"].to_s.match?(/never revoked/i)
    rescue StandardError => exception
      error("invalid monetization strategy: #{exception.message}")
    end

    def validate_products_manifest(config)
      manifest = JSON.parse(File.read(path("fastlane/pro_products.json"), encoding: "UTF-8"))
      error("products manifest bundle mismatch") unless manifest["bundle_id"] == BUNDLE_ID
      error("products manifest must sell no subscription group") unless manifest["subscription_group"].nil?
      products = manifest.fetch("products")
      error("products manifest must mirror the configured IAP list") unless
        products.map { |product| product.fetch("product_id") }.sort == config.fetch("iap").sort
      products.each do |product|
        error("products manifest must sell a non-consumable unlock") unless product.fetch("type") == "NON_CONSUMABLE"
        error("a one-time unlock must carry no introductory offer") unless product.fetch("introductory_offer").nil?
        localizations = product.fetch("localizations")
        error("products manifest must localize every store locale") unless
          localizations.keys.sort == REQUIRED_LOCALES
        localizations.each do |locale, localization|
          name = localization.fetch("name")
          description = localization.fetch("description")
          error("IAP display name exceeds 30 characters for #{locale}") if name.length > 30
          error("IAP description exceeds 45 characters for #{locale}") if description.length > 45
          error("IAP display name is empty for #{locale}") if name.strip.empty?
          error("IAP description is empty for #{locale}") if description.strip.empty?
        end
        notes = product.fetch("review_notes")
        error("IAP review notes must enumerate what is unlocked") unless notes.match?(/rewind/i) && notes.match?(/drill/i)
        error("IAP review notes must state what stays free") unless notes.match?(/free/i)
        error("IAP review notes must tell App Review how to reach the paywall") unless
          notes.include?("-paywall-screenshot")
      end
      removed = manifest.fetch("removed_from_sale")
      error("the three 1.0 tips must be scheduled for removal from sale") unless
        removed.map { |product| product.fetch("product_id") }.sort == [
          "com.bnjdpn.NovaStationPinball.tip.cafe",
          "com.bnjdpn.NovaStationPinball.tip.merci",
          "com.bnjdpn.NovaStationPinball.tip.soutien"
        ]
      error("tips must be targeted at DEVELOPER_REMOVED_FROM_SALE") unless
        removed.all? { |product| product.fetch("target_state") == "DEVELOPER_REMOVED_FROM_SALE" }
    rescue StandardError => exception
      error("invalid products manifest: #{exception.message}")
    end

    # The release pipeline must sell whatever the release configuration
    # declares. A pipeline that hard-codes a purchase type or the removed tip
    # jar is a dead pipeline: it fails closed on the very release that changes
    # the catalogue, and it does so after the contract has already said OK.
    PRODUCT_AWARE_PIPELINE_SCRIPTS = %w[
      scripts/app_store/iap_status.rb
      scripts/app_store/iap_sync.rb
      scripts/app_store/review_submission.rb
    ].freeze
    PRODUCT_AWARE_LANES = %w[submit_review iap_status iap_sync].freeze
    PURCHASE_TYPES = /(?:NON_)?CONSUMABLE/.freeze
    RETIRED_JAR = /\btips?\b/i.freeze

    def validate_release_pipeline_products
      config = JSON.parse(File.read(path("fastlane/release_config.json"), encoding: "UTF-8"))
      declared_ids = config.fetch("iap_products").map { |product| product.fetch("product_id") }
      retired = config.fetch("retired_iap_products")
      error("retired products must be declared as a list") unless retired.is_a?(Array)
      retired_ids = retired.map { |product| product.fetch("product_id") }
      error("a retired product must not also be sold") unless (retired_ids & declared_ids).empty?
      error("every retired product must name its target state") unless
        retired.all? { |product| product.fetch("target_state") == "DEVELOPER_REMOVED_FROM_SALE" }
      manifest = JSON.parse(File.read(path("fastlane/pro_products.json"), encoding: "UTF-8"))
      error("retired products must mirror the products manifest") unless
        retired_ids.sort == manifest.fetch("removed_from_sale").map { |product| product.fetch("product_id") }.sort

      PRODUCT_AWARE_PIPELINE_SCRIPTS.each do |relative|
        source = File.read(path(relative), encoding: "UTF-8")
        error("the release pipeline still hard-codes a purchase type in #{relative}") if
          source.match?(PURCHASE_TYPES)
        error("the release pipeline still names the removed jar in #{relative}") if
          source.match?(RETIRED_JAR)
      end
      %w[
        scripts/app_store/iap_status.rb
        scripts/app_store/review_submission.rb
      ].each do |relative|
        source = File.read(path(relative), encoding: "UTF-8")
        error("#{relative} must validate products against the release configuration") unless
          source.include?("iap_products")
      end
      sync = File.read(path("scripts/app_store/iap_sync.rb"), encoding: "UTF-8")
      error("iap_sync must delegate the readback to iap_status") unless
        sync.include?("NovaStationPinballIapStatus.run!")

      submit = File.read(path("scripts/app_store/review_submission.rb"), encoding: "UTF-8")
      error("a never-shipped product must be submitted with the app version") unless
        submit.include?("must_bundle") &&
          submit.include?("IAP version must be submitted with the app version")

      status = File.read(path("scripts/app_store/status.rb"), encoding: "UTF-8")
      error("the IAP readback must report retired products on their own line") unless
        status.include?('"retired_product_ids"')

      fastfile = File.read(path("fastlane/Fastfile"), encoding: "UTF-8")
      PRODUCT_AWARE_LANES.each do |lane|
        description = fastfile[/^\s*desc "([^"]*)"\n\s*lane :#{Regexp.escape(lane)}\b/, 1].to_s
        error("missing description for lane #{lane}") if description.empty?
        error("the #{lane} lane description still describes the removed jar") if
          description.match?(RETIRED_JAR)
      end
    rescue StandardError => exception
      error("invalid release pipeline product contract: #{exception.message}")
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
      release_config = JSON.parse(File.read(path("fastlane/release_config.json"), encoding: "UTF-8"))
      configured_products = release_config.fetch("iap_products")
      expected_product_ids = configured_products.map { |product| product.fetch("product_id") }.sort
      error("StoreKit configuration must mirror configured monetization products") unless products.map { |product| product.fetch("productID") }.sort == expected_product_ids
      error("StoreKit configuration must ship no subscription") unless
        storekit.fetch("subscriptionGroups").empty? && storekit.fetch("nonRenewingSubscriptions").empty?
      type_map = {
        "CONSUMABLE" => "Consumable",
        "NON_CONSUMABLE" => "NonConsumable",
        "NON_RENEWING_SUBSCRIPTION" => "NonRenewingSubscription",
        "AUTO_RENEWABLE_SUBSCRIPTION" => "AutoRenewableSubscription"
      }
      configured_types = configured_products.to_h do |product|
        asc_type = product.fetch("type")
        [product.fetch("product_id"), type_map.fetch(asc_type) { asc_type.split("_").map(&:capitalize).join }]
      end
      error("StoreKit product types must mirror the release configuration") unless products.all? do |product|
        product.fetch("type") == configured_types.fetch(product.fetch("productID"))
      end
      manifest_prices = JSON.parse(File.read(path("fastlane/pro_products.json"), encoding: "UTF-8"))
        .fetch("products").to_h { |product| [product.fetch("product_id"), product.fetch("base_price")] }
      error("StoreKit display prices must mirror the products manifest") unless products.all? do |product|
        product.fetch("displayPrice") == manifest_prices[product.fetch("productID")]
      end

      project = YAML.safe_load(File.read(path("project.yml"), encoding: "UTF-8"), aliases: false)
      app_sources = project.fetch("targets").fetch("NovaStationPinball").fetch("sources")
      excluded = app_sources.flat_map { |source| source.fetch("excludes", []) }
      error("StoreKit development configuration must be excluded from the app bundle") unless excluded.include?("StoreKit")
      run_configuration = project.fetch("schemes").fetch("NovaStationPinball").fetch("run", {})
      unless run_configuration["storeKitConfiguration"] == "NovaStationPinball/StoreKit/NovaStationPinball.storekit"
        error("StoreKit development configuration must be attached to the run scheme")
      end

      %w[AudioEngine.swift HapticsService.swift GameCenterClient.swift StoreService.swift].each do |filename|
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

      validate_tip_jar_removal
      validate_store_service
      validate_plural_strings
      validate_workshop_ui(root_view)
      validate_paywall_ui(root_view)
      validate_leaderboard_integrity(app_model)

      entitlements = File.read(path("NovaStationPinball/NovaStationPinball.entitlements"), encoding: "UTF-8")
      unless entitlements.match?(/<key>com\.apple\.developer\.game-center<\/key>\s*<true\/>/)
        error("Game Center entitlement must be enabled for the optional GameKit adapter")
      end
    rescue StandardError => exception
      error("invalid optional services configuration: #{exception.message}")
    end

    # An app that sells a product no longer asks for tips: no tip source, no
    # tip string, no tip identifier anywhere in the shipped surface.
    def validate_tip_jar_removal
      %w[
        NovaStationPinball/Services/TipJarSupport.swift
        NovaStationPinballTests/TipJarSupportTests.swift
        NovaStationPinballUITests/TipJarReviewUITests.swift
      ].each do |relative|
        error("#{relative} must be deleted, not merely unused") if File.file?(path(relative))
      end

      shipped_sources = Dir.glob(path("NovaStationPinball/**/*.swift")) +
        Dir.glob(path("NovaStationCore/**/*.swift"))
      test_sources = Dir.glob(path("NovaStationPinballTests/**/*.swift")) +
        Dir.glob(path("NovaStationPinballUITests/**/*.swift"))
      (shipped_sources + test_sources).each do |absolute|
        relative = Pathname.new(absolute).relative_path_from(Pathname.new(@root)).to_s
        contents = File.read(absolute, encoding: "UTF-8")
        error("tip jar reference survives in #{relative}") if contents.match?(/TipJar|tipJar|NOVA_TIP_JAR_FIXTURE/)
        # Tests are allowed to name the removed copy in order to assert its
        # absence; shipped sources are not.
        next unless shipped_sources.include?(absolute)
        error("tip copy survives in #{relative}") if contents.match?(/pourboire/i)
      end

      catalog = JSON.parse(File.read(path("NovaStationPinball/Resources/Localizable.xcstrings"), encoding: "UTF-8"))
      strings = catalog.fetch("strings")
      error("tip strings still ship") if strings.keys.any? { |key| key.start_with?("tips.") }
      strings.each do |key, entry|
        entry.fetch("localizations", {}).each do |locale, localization|
          value = localization.dig("stringUnit", "value").to_s
          if value.match?(/pourboire/i) || value.match?(/tip jar/i)
            error("tip copy survives in string #{key} [#{locale}]")
          end
          # The 1.0 disclaimer only made sense while tips existed.
          if value.match?(/ne débloque aucune fonctionnalité|unlocks no features/i)
            error("obsolete tip disclaimer survives in string #{key} [#{locale}]")
          end
        end
      end

      %w[en-US fr-FR].each do |locale|
        %w[description.txt promotional_text.txt release_notes.txt].each do |filename|
          value = File.read(path("fastlane/metadata/#{locale}/#{filename}"), encoding: "UTF-8")
          if value.match?(/pourboire|tip[s]?\b/i)
            error("tip copy survives in fastlane/metadata/#{locale}/#{filename}")
          end
        end
      end
    end

    # StoreKit 2 plumbing, plus the grandfathering rule that costs the most
    # when it is wrong: the legacy signal must never be a key this version
    # writes itself, and it must be read before any service writes anything.
    def validate_store_service
      store = File.read(path("NovaStationPinball/Services/StoreService.swift"), encoding: "UTF-8")
      unless store.include?("Transaction.currentEntitlements") &&
             store.include?("Transaction.updates") &&
             store.include?("AppStore.sync()") &&
             store.include?("Product.products(") &&
             store.include?("displayName: product.displayName") &&
             store.include?("displayPrice: product.displayPrice") &&
             store.include?("transaction.revocationDate == nil")
        error("the shipped store must use StoreKit 2 entitlements, updates, sync and Product metadata")
      end
      error("the sold product must be the decided one-time unlock") unless
        store.include?('static let workshopProductID = "com.bnjdpn.NovaStationPinball.workshop"')
      error("entitlement identifiers must never be dropped") unless
        store.include?("static let entitlementProductIDs: Set<String>")
      unless store.match?(/#if DEBUG.*?NOVA_STORE_FIXTURE.*?#endif/m) &&
             store.match?(/#if DEBUG.*?struct UITestingWorkshopStoreBackend.*?#endif/m) &&
             store.include?('arguments.contains("-ui-testing")') &&
             store.include?('environment["NOVA_STORE_FIXTURE"] == "available"') &&
             store.include?("return StoreKitWorkshopStoreBackend()")
        error("the store fixture must be DEBUG-only, double-gated, and default to StoreKit")
      end
      unless store.include?('arguments.contains("-paywall-screenshot")') &&
             store.match?(/guard !arguments\.contains\("-paywall-screenshot"\) else \{ return false \}/)
        error("the paywall capture must never run with the store bypass enabled")
      end

      keys = store[/static let usageSignalKeys: \[String\] = \[(.*?)\]/m, 1].to_s
      error("the grandfathering signal must read real 1.0 usage keys") unless
        keys.include?("nova-station.high-scores") && keys.include?("nova-station.settings")
      %w[NovaStation.founder NovaStation.founderMigrationCompleted].each do |own_key|
        error("the legacy signal must never include a key this version writes (#{own_key})") if keys.include?(own_key)
      end
      unless store.include?("guard !userDefaults.bool(forKey: Keys.migrationCompleted) else { return }") &&
             store.include?("userDefaults.set(true, forKey: Keys.migrationCompleted)")
        error("grandfathering migration must run exactly once per install")
      end
      if store.match?(/userDefaults\.set\(false, forKey: Keys\.founder\)|removeObject\(forKey: Keys\.founder\)/)
        error("a granted founder entitlement must never be revoked")
      end

      app_entry = File.read(path("NovaStationPinball/App/NovaStationPinballApp.swift"), encoding: "UTF-8")
      migrate = app_entry.index("LegacyEntitlement.migrateIfNeeded()")
      build_model = app_entry.index("State(initialValue: AppModel())")
      unless migrate && build_model && migrate < build_model
        error("grandfathering must be resolved in the app initializer, before any service is built")
      end
      if app_entry.match?(/@State\s+private\s+var\s+model\s*=\s*AppModel\(\)/)
        error("a stored-property default would build AppModel before the grandfathering check")
      end

      tests = File.read(path("NovaStationPinballTests/StoreServiceTests.swift"), encoding: "UTF-8")
      %w[
        testAFreshInstallIsNotAFounderAfterEveryServiceHasStarted
        testAnInstallWithEarlierUsageDataIsAFounder
        testMigrationIsIdempotent
        testGrantedAccessIsNeverRevoked
      ].each do |name|
        error("mandatory grandfathering test #{name} is missing") unless tests.include?("func #{name}")
      end
    end

    # Grammatical number, in every locale, for every string that prints a
    # count — checked structurally so a future edit cannot silently drop the
    # variations and ship "1 attempts" again.
    def validate_plural_strings
      catalog = JSON.parse(File.read(path("NovaStationPinball/Resources/Localizable.xcstrings"), encoding: "UTF-8"))
      strings = catalog.fetch("strings")

      COUNT_STRINGS.each do |key, argument_number|
        entry = strings[key]
        unless entry
          error("missing localized string #{key}")
          next
        end
        %w[en fr].each do |locale|
          localization = entry.dig("localizations", locale)
          unless localization
            error("count string #{key} is missing the #{locale} localization")
            next
          end
          substitutions = localization["substitutions"] || {}
          name, substitution = substitutions.find do |_, value|
            value["argNum"] == argument_number
          end
          unless substitution
            error("count string #{key} [#{locale}] must vary by plural on argument #{argument_number}")
            next
          end
          value = localization.dig("stringUnit", "value").to_s
          error("count string #{key} [#{locale}] never substitutes %#@#{name}@") unless value.include?("%\#@#{name}@")
          plural = substitution.dig("variations", "plural") || {}
          one = plural.dig("one", "stringUnit", "value").to_s
          other = plural.dig("other", "stringUnit", "value").to_s
          if one.strip.empty? || other.strip.empty?
            error("count string #{key} [#{locale}] is missing a one or other plural category")
          elsif one == other
            error("count string #{key} [#{locale}] has an identical singular and plural form")
          end
        end
      end

      # A number immediately followed by a word is a count in a sentence: it
      # belongs to the registry above, whatever locale spells it out.
      strings.each do |key, entry|
        next if COUNT_STRINGS.key?(key)
        entry.fetch("localizations", {}).each do |locale, localization|
          value = localization.dig("stringUnit", "value").to_s
          next unless value.match?(/%(?:\d+\$)?lld\s+[[:alpha:]]+s\b/)
          error("string #{key} [#{locale}] prints a count without plural variations")
        end
      end

      localization_tests = File.read(
        path("NovaStationPinballTests/LocalizationContractTests.swift"),
        encoding: "UTF-8"
      )
      unless localization_tests.include?("stringsdict") &&
             localization_tests.include?("testCountStringsAreGrammaticalAtOneAndAtManyInEveryLocale")
        error("plural forms must be asserted against the compiled catalog by a test")
      end
    end

    def validate_workshop_ui(root_view)
      %w[workshopOpen workshop workshopClose workshopUnlock workshopStatus
         workshopDrillHUD workshopDrillStatus workshopDrillRecord
         workshopDrillRetry workshopDrillExit].each do |identifier|
        error("Workshop UI is missing stable identifier #{identifier}") unless
          root_view.include?(%Q{"#{identifier}"})
      end
      unless root_view.include?('"workshopRewind.\(target.identifier)"') &&
             root_view.include?('"workshopDrill.\(drill.id)"')
        error("Workshop UI must derive stable identifiers from the exact rewind and drill catalogs")
      end
      unless root_view.include?("ShotDrillCatalog.drills") &&
             root_view.include?("model.canRewind(to: target)") &&
             root_view.include?("model.drillEntry(for: drill)")
        error("Workshop UI must render the real drill catalog and the real rewind availability")
      end
      unless root_view.include?("workshop.message.no_keyframe")
        error("Workshop UI must design the empty state where nothing has been recorded yet")
      end

      # A drill the player paid for has to be a loop, not a one-way door: the
      # attempt shows its own budget and verdict, and both ways out are on
      # screen while it runs.
      unless root_view.include?("model.activeDrill") &&
             root_view.include?("model.activeDrillOutcome") &&
             root_view.include?("model.activeDrillRemainingSeconds")
        error("Workshop UI must render the live attempt state of the running drill")
      end
      unless root_view.include?("model.restartActiveDrill()") && root_view.include?("model.endDrill()")
        error("a running drill must expose an explicit retry and an explicit exit")
      end
      %w[drill.hud.remaining drill.hud.succeeded drill.hud.failed drill.hud.retry drill.hud.exit].each do |key|
        error("drill attempt UI is missing localized string #{key}") unless root_view.include?(key)
      end

      ui_tests = File.read(path("NovaStationPinballUITests/LayoutUITests.swift"), encoding: "UTF-8")
      %w[workshopOpen workshopClose workshopRewind. workshopDrill. paywallPurchase paywallRestore
         workshopDrillHUD workshopDrillStatus workshopDrillRetry workshopDrillExit].each do |identifier|
        error("Workshop UI test is missing #{identifier}") unless ui_tests.include?(identifier)
      end
      unless ui_tests.match?(/workshopDrillRetry.*?\n.*?wait\(for:/m) &&
             ui_tests.include?("exists == false")
        error("a UI test must drive one drill attempt to its verdict, retry it and leave it")
      end
      audit_tests = File.read(
        path("NovaStationPinballUITests/AccessibilityAuditUITests.swift"),
        encoding: "UTF-8"
      )
      unless audit_tests.include?("workshopDrillHUD") &&
             audit_tests.include?("UICTContentSizeCategoryAccessibilityXXXL") &&
             audit_tests.include?("performStrictAccessibilityAudit")
        error("the drill panel must be audited and checked at the largest accessibility text size")
      end
      integration_tests = File.read(
        path("NovaStationPinballTests/AppModelRuntimeIntegrationTests.swift"),
        encoding: "UTF-8"
      )
      unless integration_tests.include?("restartActiveDrill()") &&
             integration_tests.include?("activeDrillRemainingSeconds") &&
             integration_tests.include?("endDrill()")
        error("the drill loop must be covered start to exit by a runtime integration test")
      end
      unless ui_tests.include?('app.buttons["workshopClose"].frame.width') &&
             ui_tests.include?('app.otherElements["art.frame.4x3"].exists')
        error("Workshop modal must hide background accessibility and expose a tested 44pt close target")
      end
    end

    # The App Store Connect review capture is the one artefact of this release
    # that states a price in pixels, and the only one App Review looks at
    # before deciding the in-app purchase exists at all. Three ways of getting
    # it wrong are already documented across the portfolio:
    #
    #   * a capture of an empty paywall — spinner, "unavailable", "Try Again" —
    #     earns the rejection "we were unable to locate the in-app purchase";
    #   * a capture whose price comes from the live App Store catalogue states
    #     whatever App Store Connect happens to carry, not what this repository
    #     sells (a BrewMeter capture shipped "$29.99" against a 6,99 € spec);
    #   * a capture sitting in a gitignored folder proves nothing: it vanishes
    #     at the first clone.
    #
    # So the contract checks the route AND the artefact: the UI test drives
    # StoreKit through SKTestSession pinned to the base territory, and the PNG
    # committed next to its sidecar must actually show the price the products
    # manifest promises.
    PAYWALL_CAPTURE_TEST = "NovaStationPinballUITests/PaywallReviewUITests.swift"
    CURRENCY_SYMBOLS = { "€" => "EUR", "$" => "USD", "£" => "GBP", "¥" => "JPY" }.freeze

    def validate_paywall_review_capture
      review_test = File.read(path(PAYWALL_CAPTURE_TEST), encoding: "UTF-8")
      xcode_project = File.read(path("NovaStationPinball.xcodeproj/project.pbxproj"), encoding: "UTF-8")
      unless review_test.include?('"-paywall-screenshot"') &&
             review_test.include?("XCUIScreen.main.screenshot()") &&
             review_test.include?("screenshot.image.cgImage") &&
             review_test.include?("[2064, 2752]") &&
             !review_test.include?("purchaseButton.tap()") &&
             xcode_project.include?("PaywallReviewUITests.swift in Sources")
        error("IAP review capture must be compiled, full-screen, pixel-validated at 2752x2064, and non-purchasing")
      end

      # The price has to be a function of this repository, not of the store the
      # simulator happens to talk to.
      unless review_test.include?("import StoreKitTest") &&
             review_test.include?('SKTestSession(configurationFileNamed: "NovaStationPinball")') &&
             review_test.include?("session.storefront = Self.baseTerritory")
        error("IAP review capture must price the offer from the .storekit catalogue, pinned to the base territory")
      end
      if review_test.include?("NOVA_STORE_FIXTURE")
        error("IAP review capture must not photograph a fixture: a hard-coded price cannot disagree with the spec")
      end
      # An empty paywall is the documented rejection. The test must refuse both
      # of its states rather than screenshot whatever is on screen.
      unless review_test.include?("paywallOfferLoading") && review_test.include?("paywallOfferUnavailable")
        error("IAP review capture must fail on the loading and unavailable paywall states")
      end
      unless review_test.include?('XCTAssertFalse(app.staticTexts["paywallStatus"].exists)')
        error("IAP review capture must prove the offer is not already owned")
      end

      project = YAML.safe_load(File.read(path("project.yml"), encoding: "UTF-8"), aliases: false)
      ui_sources = project.fetch("targets").fetch("NovaStationPinballUITests").fetch("sources")
      ships_catalogue = ui_sources.any? do |source|
        source.is_a?(Hash) &&
          source["path"] == "NovaStationPinball/StoreKit/NovaStationPinball.storekit" &&
          source["buildPhase"] == "resources"
      end
      unless ships_catalogue
        error("the UI test bundle must ship the .storekit catalogue: SKTestSession loads it from there, " \
              "and the scheme's storeKitConfiguration only covers the Run action")
      end

      error("missing scripts/capture_paywall_review_screenshot.rb") unless
        File.file?(path("scripts/capture_paywall_review_screenshot.rb"))

      validate_paywall_review_asset
    end

    def validate_paywall_review_asset
      manifest = JSON.parse(File.read(path("fastlane/pro_products.json"), encoding: "UTF-8"))
      product = manifest.fetch("products").first
      declared = product["review_screenshot"].to_s
      if declared.empty?
        error("pro_products.json must declare review_screenshot: App Store Connect refuses a new " \
              "in-app purchase without a capture of the purchase screen")
        return
      end

      png = path(declared)
      unless File.file?(png)
        error("declared review screenshot is missing: #{declared}; run `bundle exec fastlane paywall_review_screenshot`")
        return
      end
      error("review screenshot is not a PNG: #{declared}") unless File.binread(png, 8) == "\x89PNG\r\n\x1a\n".b

      sidecar = png.sub(/\.png\z/, ".json")
      unless File.file?(sidecar)
        error("missing review capture sidecar next to #{declared}; run `bundle exec fastlane paywall_review_screenshot`")
        return
      end

      payload = JSON.parse(File.read(sidecar, encoding: "UTF-8"))
      actual = Digest::SHA256.hexdigest(File.binread(png))
      unless payload["screenshot_sha256"] == actual
        error("the review capture sidecar describes a different image than the one committed " \
              "(#{payload['screenshot_sha256']} vs #{actual}); recapture instead of editing the sidecar")
        return
      end
      error("the review capture sidecar names another product") unless
        payload["product_id"] == product.fetch("product_id")
      error("the review capture must be pinned to the base territory") unless
        payload["storefront"] == manifest.fetch("base_territory")

      displayed = payload["displayed_price"].to_s
      amount, currency = parse_displayed_price(displayed)
      expected_amount = format("%.2f", Float(product.fetch("base_price")))
      expected_currency = manifest.fetch("base_currency")
      if amount.nil?
        error("cannot read a price out of the review capture sidecar: #{displayed.inspect}")
      elsif amount != expected_amount || currency != expected_currency
        error("the review capture shows #{displayed.inspect} (#{amount} #{currency}) but pro_products.json " \
              "sells at #{expected_amount} #{expected_currency}: App Review would be shown a price the " \
              "App Store does not have")
      end
    end

    # "€4.99", "4,99 €", "EUR 4.99" -> ["4.99", "EUR"].
    def parse_displayed_price(text)
      symbol = CURRENCY_SYMBOLS.keys.find { |candidate| text.include?(candidate) }
      currency = symbol ? CURRENCY_SYMBOLS.fetch(symbol) : text[/\b(EUR|USD|GBP|JPY)\b/, 1]
      digits = text[/\d+(?:[.,]\d{1,2})?/]
      return [nil, currency] if digits.nil?

      [format("%.2f", Float(digits.tr(",", "."))), currency]
    end

    # Guideline 3.1.2(a) for a one-time unlock: price read from the product,
    # explicit non-subscription wording, restore, terms and privacy.
    def validate_paywall_ui(root_view)
      %w[paywall paywallTitle paywallClose paywallPurchase paywallRestore paywallTerms
         paywallTermsLink paywallPrivacyLink paywallStatus].each do |identifier|
        error("paywall is missing stable identifier #{identifier}") unless
          root_view.include?(%Q{"#{identifier}"})
      end
      unless root_view.include?("offer.displayPrice") && root_view.include?("offer.displayName")
        error("paywall must read its name and price from StoreKit.Product")
      end
      if root_view.match?(/(?:USD|EUR|\$\s*\d|\d+[.,]\d{2}\s*€)/)
        error("paywall must not hard-code prices or currencies")
      end
      unless root_view.include?("WorkshopCatalog.termsOfUseURL") &&
             root_view.include?("WorkshopCatalog.privacyURL")
        error("paywall must link the terms of use and the privacy policy")
      end
      store = File.read(path("NovaStationPinball/Services/StoreService.swift"), encoding: "UTF-8")
      unless store.include?('static let termsOfUseURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"') &&
             store.include?('static let privacyURL = "https://bnjdpn.github.io/NovaStationPinball/privacy.html"')
        error("paywall legal links must be the Apple standard EULA and the app privacy page")
      end
      unless root_view.include?("paywall.loading") && root_view.include?("paywall.unavailable")
        error("paywall must design its loading and no-product states")
      end

      catalog = JSON.parse(File.read(path("NovaStationPinball/Resources/Localizable.xcstrings"), encoding: "UTF-8"))
      strings = catalog.fetch("strings")
      required_keys = %w[
        paywall.title paywall.body paywall.one_time paywall.restore paywall.link.terms
        paywall.link.privacy paywall.loading paywall.unavailable paywall.free_forever
        workshop.title workshop.unlock workshop.rewind.remaining workshop.message.no_keyframe
      ] + ShotDrillIdentifiers.all.map { |id| "drill.#{id}" }
      required_keys.each do |key|
        entry = strings[key]
        unless entry
          error("missing localized string #{key}")
          next
        end
        %w[en fr].each do |locale|
          value = entry.dig("localizations", locale, "stringUnit", "value").to_s
          error("string #{key} is not translated in #{locale}") if value.strip.empty?
        end
      end
      disclosure_en = strings.dig("paywall.one_time", "localizations", "en", "stringUnit", "value").to_s
      disclosure_fr = strings.dig("paywall.one_time", "localizations", "fr", "stringUnit", "value").to_s
      unless disclosure_en.match?(/one-time purchase/i) && disclosure_en.match?(/not a subscription/i)
        error("the English paywall must state that the purchase is one-time and not a subscription")
      end
      unless disclosure_fr.match?(/achat unique/i) && disclosure_fr.match?(/pas un abonnement/i)
        error("the French paywall must state that the purchase is one-time and not a subscription")
      end

      validate_paywall_review_capture

      media = File.read(path("NovaStationPinball/App/MediaScenario.swift"), encoding: "UTF-8")
      unless media.include?('opensPaywall = arguments.contains("-paywall-screenshot")') &&
             root_view.include?("openLaunchPaywallIfRequested()")
        error("-paywall-screenshot must open the paywall at launch for the capture pipelines")
      end

      background_is_conditional = root_view.match?(
        /if activeOverlay == nil \{\s+Rectangle\(\)\.fill\(\.clear\).*?"art\.frame\.4x3".*?HStack\(spacing: 0\).*?"art\.table".*?"art\.console"/m
      )
      unless background_is_conditional &&
             root_view.scan(".accessibilityAddTraits(.isModal)").length >= 3 &&
             root_view.include?(".frame(width: 44, height: 44)")
        error("every modal must hide background accessibility and expose a 44pt close target")
      end
    end

    # Rewinding is assistance: a run that used it never reaches the ranked
    # board or Game Center.
    def validate_leaderboard_integrity(app_model)
      unless app_model.include?("guard !isAssistedRun, !scene.isAssisted else {") &&
             app_model.include?("localGameStore.saveTrainingScores(trainingScores)")
        error("assisted runs must be routed to the separate training board")
      end
      assisted_guard = app_model.index("guard !isAssistedRun, !scene.isAssisted else {")
      submit = app_model.index("gameCenterClient.submit")
      unless assisted_guard && submit && assisted_guard < submit
        error("the assisted guard must precede any Game Center submission")
      end
      session = File.read(path("NovaStationCore/Sources/NovaStationCore/GameSession.swift"), encoding: "UTF-8")
      unless session.include?("public private(set) var isAssisted = false") &&
             session.include?("session.isAssisted = true") &&
             session.include?("isAssisted = false")
        error("the assisted flag must be owned by the core session and cleared only by a new game")
      end
      store = File.read(path("NovaStationPinball/Services/LocalGameStore.swift"), encoding: "UTF-8")
      unless store.include?('static let trainingScores = "nova-station.training-scores"') &&
             store.include?('static let drillProgress = "nova-station.drill-progress"') &&
             store.include?('static let assistedSession = "nova-station.assisted-session"')
        error("the Workshop stores must live under their own new keys")
      end
      unless store.include?("private func quarantineCheckpoint()") &&
             store.include?("active-checkpoint.bak")
        error("an unreadable saved game must be quarantined, never destroyed")
      end
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
      PagesWorkflowContract.errors(@root, source_dir: "site").each do |message|
        error("Pages workflow contract: #{message}")
      end
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

if $PROGRAM_NAME == __FILE__
  errors = NovaStationPinballReleaseContract::Verifier.new.verify
  if errors.empty?
    puts "release_contract: OK"
  else
    errors.each { |error| warn "release_contract: #{error}" }
    exit 1
  end
end
