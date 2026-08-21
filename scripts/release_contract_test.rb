#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "fileutils"
require "tmpdir"
require "yaml"
require_relative "pages_workflow_contract"
require_relative "release_contract"

class ReleaseContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REQUIRED_LANES = %w[
    setup_asc release_contract asc_status metadata screenshots app_previews adopt_media media_contract upload_screenshots
    upload_previews build_release upload_release submit_review release_quick pricing
    iap_status iap_sync paywall_review_screenshot
  ].freeze

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
    release_config_version = JSON.parse(
      File.read(File.join(ROOT, "fastlane/release_config.json"), encoding: "UTF-8")
    ).fetch("version")
    assert_equal release_config_version, settings.fetch("MARKETING_VERSION")
    assert_match(/\A[1-9][0-9]*\z/, settings.fetch("CURRENT_PROJECT_VERSION"))
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
    # The `.storekit` entry is a resource of the UI test bundle: SKTestSession
    # loads its catalogue from there, and the scheme's storeKitConfiguration
    # only ever applies to the Run action.
    assert_equal ["NovaStationPinballUITests", "NovaStationPinball/StoreKit/NovaStationPinball.storekit"],
                 project.fetch("targets").fetch("NovaStationPinballUITests").fetch("sources").map { |source| source.fetch("path") }
    assert_equal "resources",
                 project.fetch("targets").fetch("NovaStationPinballUITests").fetch("sources").last.fetch("buildPhase")

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
    refute release_config.key?("tip_products"), "the tip jar catalogue must be gone"
    configured_products = release_config.fetch("iap_products")
    assert_equal configured_products.map { |product| product.fetch("product_id") }.sort,
                 release_config.fetch("iap").sort
    assert configured_products.all? { |product| product.fetch("type").match?(/\A[A-Z][A-Z0-9_]*\z/) }
    assert_equal "one_time_unlock", release_config.fetch("monetization_strategy").fetch("model")
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
    pages_errors = PagesWorkflowContract.errors(ROOT, source_dir: "site", required: true)
    assert_empty pages_errors, pages_errors.join("\n")

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

  def test_configured_monetization_is_mirrored_by_the_development_storekit_file
    release_config = JSON.parse(
      File.read(File.join(ROOT, "fastlane/release_config.json"), encoding: "UTF-8")
    )
    configured_products = release_config.fetch("iap_products")
    storekit = JSON.parse(
      File.read(File.join(ROOT, "NovaStationPinball/StoreKit/NovaStationPinball.storekit"), encoding: "UTF-8")
    )
    products = storekit.fetch("products")

    assert_equal configured_products.map { |product| product.fetch("product_id") }.sort,
                 products.map { |product| product.fetch("productID") }.sort
    type_map = {
      "CONSUMABLE" => "Consumable",
      "NON_CONSUMABLE" => "NonConsumable",
      "NON_RENEWING_SUBSCRIPTION" => "NonRenewingSubscription",
      "AUTO_RENEWABLE_SUBSCRIPTION" => "AutoRenewableSubscription"
    }
    configured_types = configured_products.to_h do |product|
      [product.fetch("product_id"), type_map.fetch(product.fetch("type"))]
    end
    assert products.all? { |product| product.fetch("type") == configured_types.fetch(product.fetch("productID")) }
    assert_empty storekit.fetch("subscriptionGroups")
    assert_empty storekit.fetch("nonRenewingSubscriptions")

    manifest = JSON.parse(File.read(File.join(ROOT, "fastlane/pro_products.json"), encoding: "UTF-8"))
    assert_nil manifest.fetch("subscription_group")
    assert_equal release_config.fetch("iap").sort,
                 manifest.fetch("products").map { |product| product.fetch("product_id") }.sort
    manifest.fetch("products").each do |product|
      assert_equal "NON_CONSUMABLE", product.fetch("type")
      assert_nil product.fetch("introductory_offer")
      assert_equal %w[en-US fr-FR], product.fetch("localizations").keys.sort
      product.fetch("localizations").each_value do |localization|
        assert_operator localization.fetch("name").length, :<=, 30
        assert_operator localization.fetch("description").length, :<=, 45
      end
    end
    manifest_prices = manifest.fetch("products").to_h { |product| [product.fetch("product_id"), product.fetch("base_price")] }
    assert products.all? { |product| product.fetch("displayPrice") == manifest_prices.fetch(product.fetch("productID")) }
    assert_equal %w[
      com.bnjdpn.NovaStationPinball.tip.cafe
      com.bnjdpn.NovaStationPinball.tip.merci
      com.bnjdpn.NovaStationPinball.tip.soutien
    ], manifest.fetch("removed_from_sale").map { |product| product.fetch("product_id") }.sort
    assert manifest.fetch("removed_from_sale").all? { |product| product.fetch("target_state") == "DEVELOPER_REMOVED_FROM_SALE" }

    project = YAML.safe_load(File.read(File.join(ROOT, "project.yml"), encoding: "UTF-8"), aliases: false)
    app_sources = project.fetch("targets").fetch("NovaStationPinball").fetch("sources")
    assert_includes app_sources.flat_map { |source| source.fetch("excludes", []) }, "StoreKit"
    assert_equal "NovaStationPinball/StoreKit/NovaStationPinball.storekit",
                 project.fetch("schemes").fetch("NovaStationPinball").fetch("run").fetch("storeKitConfiguration")

    %w[AudioEngine.swift HapticsService.swift GameCenterClient.swift StoreService.swift].each do |filename|
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

  # The pipeline that submits the release must sell whatever the release
  # configuration declares. Tour 2 shipped a non-consumable unlock behind a
  # pipeline that still demanded three consumable tips: the contract said OK
  # while submit_review and iap_status could only raise.
  PIPELINE_FIXTURE_FILES = %w[
    fastlane/release_config.json
    fastlane/pro_products.json
    fastlane/Fastfile
    scripts/app_store/iap_status.rb
    scripts/app_store/iap_sync.rb
    scripts/app_store/review_submission.rb
    scripts/app_store/status.rb
  ].freeze

  def test_the_release_pipeline_sells_the_configured_products_not_hard_coded_ones
    release_config = JSON.parse(
      File.read(File.join(ROOT, "fastlane/release_config.json"), encoding: "UTF-8")
    )
    retired = release_config.fetch("retired_iap_products")
    assert_equal %w[
      com.bnjdpn.NovaStationPinball.tip.cafe
      com.bnjdpn.NovaStationPinball.tip.merci
      com.bnjdpn.NovaStationPinball.tip.soutien
    ], retired.map { |product| product.fetch("product_id") }.sort
    assert retired.all? { |product| product.fetch("target_state") == "DEVELOPER_REMOVED_FROM_SALE" }
    assert_empty retired.map { |product| product.fetch("product_id") } &
                 release_config.fetch("iap")

    %w[
      scripts/app_store/iap_status.rb
      scripts/app_store/iap_sync.rb
      scripts/app_store/review_submission.rb
    ].each do |relative|
      source = File.read(File.join(ROOT, relative), encoding: "UTF-8")
      refute_match(/(?:NON_)?CONSUMABLE/, source, relative)
      refute_match(/\btips?\b/i, source, relative)
    end

    fastfile = File.read(File.join(ROOT, "fastlane/Fastfile"), encoding: "UTF-8")
    %w[submit_review iap_status iap_sync].each do |lane|
      description = fastfile[/^\s*desc "([^"]*)"\n\s*lane :#{lane}\b/, 1].to_s
      refute_empty description, lane
      refute_match(/\btips?\b/i, description, lane)
    end

    with_pipeline_fixture do |root|
      assert_empty pipeline_errors(root)
    end

    with_pipeline_fixture do |root|
      path = File.join(root, "scripts/app_store/review_submission.rb")
      File.write(path, File.read(path, encoding: "UTF-8").sub(
        "REVIEWABLE_PRODUCT_STATES", "CONSUMABLE_ONLY_STATES"
      ))
      refute_empty pipeline_errors(root),
                   "a pipeline that hard-codes a purchase type must fail the contract"
    end

    with_pipeline_fixture do |root|
      path = File.join(root, "scripts/app_store/iap_status.rb")
      File.write(path, File.read(path, encoding: "UTF-8").sub(
        "sold products are missing", "optional tips are missing"
      ))
      refute_empty pipeline_errors(root),
                   "a pipeline that still names the removed jar must fail the contract"
    end

    with_pipeline_fixture do |root|
      path = File.join(root, "fastlane/Fastfile")
      File.write(path, File.read(path, encoding: "UTF-8").sub(
        /desc "[^"]*"\n(\s*lane :iap_status\b)/,
        %Q{desc "Read and enforce exactly the three optional consumable tips"\n\\1}
      ))
      refute_empty pipeline_errors(root),
                   "a lane description that still sells the removed jar must fail the contract"
    end
  end

  def test_the_tip_jar_is_gone_from_the_binary_the_catalogue_and_the_copy
    %w[
      NovaStationPinball/Services/TipJarSupport.swift
      NovaStationPinballTests/TipJarSupportTests.swift
      NovaStationPinballUITests/TipJarReviewUITests.swift
    ].each do |relative|
      refute File.file?(File.join(ROOT, relative)), "#{relative} must be deleted"
    end

    shipped = Dir.glob(File.join(ROOT, "NovaStationPinball/**/*.swift")) +
              Dir.glob(File.join(ROOT, "NovaStationCore/**/*.swift"))
    shipped.each do |absolute|
      contents = File.read(absolute, encoding: "UTF-8")
      refute_match(/TipJar|tipJar|NOVA_TIP_JAR_FIXTURE/, contents, absolute)
      refute_match(/pourboire/i, contents, absolute)
    end

    catalog = JSON.parse(
      File.read(File.join(ROOT, "NovaStationPinball/Resources/Localizable.xcstrings"), encoding: "UTF-8")
    ).fetch("strings")
    assert catalog.keys.none? { |key| key.start_with?("tips.") }
    catalog.each_value do |entry|
      entry.fetch("localizations", {}).each_value do |localization|
        value = localization.dig("stringUnit", "value").to_s
        refute_match(/pourboire/i, value)
        refute_match(/ne débloque aucune fonctionnalité|unlocks no features/i, value)
      end
    end

    %w[en-US fr-FR].each do |locale|
      %w[description.txt promotional_text.txt release_notes.txt].each do |filename|
        value = File.read(File.join(ROOT, "fastlane/metadata", locale, filename), encoding: "UTF-8")
        refute_match(/pourboire|tip[s]?\b/i, value, "#{locale}/#{filename}")
      end
    end
  end

  def test_workshop_paywall_is_storekit_driven_disclosed_and_statically_owned
    root_view = File.read(
      File.join(ROOT, "NovaStationPinball/App/RootView.swift"),
      encoding: "UTF-8"
    )
    %w[workshopOpen workshop workshopClose workshopUnlock workshopStatus
       paywall paywallTitle paywallClose paywallPurchase paywallRestore
       paywallTerms paywallTermsLink paywallPrivacyLink paywallStatus].each do |identifier|
      assert_includes root_view, %Q{"#{identifier}"}
    end
    assert_includes root_view, '"workshopRewind.\(target.identifier)"'
    assert_includes root_view, '"workshopDrill.\(drill.id)"'
    assert_includes root_view, "offer.displayName"
    assert_includes root_view, "offer.displayPrice"
    assert_includes root_view, "WorkshopCatalog.termsOfUseURL"
    assert_includes root_view, "WorkshopCatalog.privacyURL"
    refute_match(/(?:USD|EUR|\$\s*\d|\d+[.,]\d{2}\s*€)/, root_view)
    assert_includes root_view, "paywall.loading"
    assert_includes root_view, "paywall.unavailable"
    assert_includes root_view, "workshop.message.no_keyframe"

    store = File.read(
      File.join(ROOT, "NovaStationPinball/Services/StoreService.swift"),
      encoding: "UTF-8"
    )
    assert_includes store, "Transaction.currentEntitlements"
    assert_includes store, "Transaction.updates"
    assert_includes store, "AppStore.sync()"
    assert_includes store, "displayName: product.displayName"
    assert_includes store, "displayPrice: product.displayPrice"
    assert_match(/#if DEBUG.*?NOVA_STORE_FIXTURE.*?#endif/m, store)
    assert_match(/#if DEBUG.*?struct UITestingWorkshopStoreBackend.*?#endif/m, store)
    assert_includes store, 'arguments.contains("-ui-testing")'
    assert_includes store, 'environment["NOVA_STORE_FIXTURE"] == "available"'
    assert_includes store, "return StoreKitWorkshopStoreBackend()"
    assert_includes store, 'arguments.contains("-paywall-screenshot")'

    # Grandfathering: the legacy signal is never a key this version writes.
    usage_keys = store[/static let usageSignalKeys: \[String\] = \[(.*?)\]/m, 1].to_s
    assert_includes usage_keys, "nova-station.high-scores"
    assert_includes usage_keys, "nova-station.settings"
    refute_includes usage_keys, "NovaStation.founder"
    refute_match(/userDefaults\.set\(false, forKey: Keys\.founder\)|removeObject\(forKey: Keys\.founder\)/, store)

    app_entry = File.read(
      File.join(ROOT, "NovaStationPinball/App/NovaStationPinballApp.swift"),
      encoding: "UTF-8"
    )
    assert_operator app_entry.index("LegacyEntitlement.migrateIfNeeded()"), :<,
                    app_entry.index("State(initialValue: AppModel())")
    refute_match(/@State\s+private\s+var\s+model\s*=\s*AppModel\(\)/, app_entry)

    store_tests = File.read(
      File.join(ROOT, "NovaStationPinballTests/StoreServiceTests.swift"),
      encoding: "UTF-8"
    )
    %w[
      testAFreshInstallIsNotAFounderAfterEveryServiceHasStarted
      testAnInstallWithEarlierUsageDataIsAFounder
      testMigrationIsIdempotent
      testGrantedAccessIsNeverRevoked
    ].each { |name| assert_includes store_tests, "func #{name}" }

    layout_test = File.read(
      File.join(ROOT, "NovaStationPinballUITests/LayoutUITests.swift"),
      encoding: "UTF-8"
    )
    %w[workshopOpen workshopClose paywallPurchase paywallRestore].each do |identifier|
      assert_includes layout_test, identifier
    end
    assert_includes layout_test, 'launchEnvironment["NOVA_STORE_FIXTURE"] = "available"'
    assert_includes layout_test, "-ui-testing"
    assert_includes layout_test, 'app.otherElements["art.frame.4x3"].exists'
    assert_includes layout_test, 'app.buttons["workshopClose"].frame.width'

    storekit = JSON.parse(
      File.read(
        File.join(ROOT, "NovaStationPinball/StoreKit/NovaStationPinball.storekit"),
        encoding: "UTF-8"
      )
    )
    storekit.fetch("products").each do |product|
      localizations = product.fetch("localizations")
      english_name = localizations.find { |entry| entry.fetch("locale") == "en_US" }.fetch("displayName")
      french_name = localizations.find { |entry| entry.fetch("locale") == "fr_FR" }.fetch("displayName")
      price = product.fetch("displayPrice")
      assert_includes store, %Q{displayName: french ? "#{french_name}" : "#{english_name}"}
      assert_includes store, %Q{displayPrice: french ? "#{price.tr(".", ",")} €" : "$#{price}"}
    end

    screenshot_tests = File.read(
      File.join(ROOT, "NovaStationPinballUITests/StoreScreenshotUITests.swift"),
      encoding: "UTF-8"
    )
    preview_tests = File.read(
      File.join(ROOT, "NovaStationPinballUITests/AppPreviewUITests.swift"),
      encoding: "UTF-8"
    )
    [screenshot_tests, preview_tests].each do |media_test|
      assert_includes media_test, "workshopOpen"
      refute_includes media_test, "NOVA_STORE_FIXTURE"
    end

    review_test = File.read(
      File.join(ROOT, "NovaStationPinballUITests/PaywallReviewUITests.swift"),
      encoding: "UTF-8"
    )
    xcode_project = File.read(
      File.join(ROOT, "NovaStationPinball.xcodeproj/project.pbxproj"),
      encoding: "UTF-8"
    )
    assert_includes review_test, '"-paywall-screenshot"'
    assert_includes review_test, "XCUIScreen.main.screenshot()"
    assert_includes review_test, "[2064, 2752]"
    assert_includes review_test, "screenshot.image.cgImage"
    refute_includes review_test, "purchaseButton.tap()"
    assert_includes xcode_project, "PaywallReviewUITests.swift in Sources"

    # The capture prices the offer from the repository's own catalogue. A
    # fixture with a hard-coded price cannot disagree with the spec, so it
    # cannot detect that it disagrees; the live catalogue prices it from
    # whatever App Store Connect happens to carry.
    assert_includes review_test, "import StoreKitTest"
    assert_includes review_test, 'SKTestSession(configurationFileNamed: "NovaStationPinball")'
    assert_includes review_test, "session.storefront = Self.baseTerritory"
    refute_includes review_test, "NOVA_STORE_FIXTURE"
    assert_includes review_test, "paywallOfferLoading"
    assert_includes review_test, "paywallOfferUnavailable"
    assert_includes review_test, 'XCTAssertFalse(app.staticTexts["paywallStatus"].exists)'

    assert File.file?(File.join(ROOT, "scripts/capture_paywall_review_screenshot.rb"))
    assert_review_capture_asset_matches_the_products_manifest

    assert_match(
      /if activeOverlay == nil \{\s+Rectangle\(\)\.fill\(\.clear\).*?"art\.frame\.4x3".*?HStack\(spacing: 0\).*?"art\.table".*?"art\.console"/m,
      root_view
    )
    assert_operator root_view.scan(".accessibilityAddTraits(.isModal)").length, :>=, 3
    assert_includes root_view, ".frame(width: 44, height: 44)"

    catalog = JSON.parse(
      File.read(
        File.join(ROOT, "NovaStationPinball/Resources/Localizable.xcstrings"),
        encoding: "UTF-8"
      )
    ).fetch("strings")
    %w[
      paywall.title paywall.body paywall.one_time paywall.restore paywall.free_forever
      paywall.link.terms paywall.link.privacy paywall.loading paywall.unavailable
      workshop.title workshop.unlock workshop.rewind.remaining workshop.message.no_keyframe
    ].each do |key|
      assert_equal %w[en fr], catalog.fetch(key).fetch("localizations").keys.sort
    end
    disclosure = catalog.fetch("paywall.one_time").fetch("localizations")
    assert_match(/one-time purchase/i, disclosure.dig("en", "stringUnit", "value"))
    assert_match(/not a subscription/i, disclosure.dig("en", "stringUnit", "value"))
    assert_match(/achat unique/i, disclosure.dig("fr", "stringUnit", "value"))
    assert_match(/pas un abonnement/i, disclosure.dig("fr", "stringUnit", "value"))

    drill_catalog = File.read(
      File.join(ROOT, "NovaStationCore/Sources/NovaStationCore/ShotDrillCatalog.swift"),
      encoding: "UTF-8"
    )
    drill_ids = drill_catalog[/public static let drills: \[ShotDrill\] = \[(.*?)\n    \]/m, 1]
                  .to_s.scan(/drill\("([a-z0-9-]+)"/).flatten
    assert_equal 14, drill_ids.length
    drill_ids.each do |drill_id|
      assert_equal %w[en fr], catalog.fetch("drill.#{drill_id}").fetch("localizations").keys.sort
    end
  end

  # The Workshop sells a loop: an attempt that shows its own budget and
  # verdict, a retry, and a way out — and copy that is grammatical at one.
  def test_drill_attempt_loop_and_count_strings_are_contract_owned
    root_view = File.read(
      File.join(ROOT, "NovaStationPinball/App/RootView.swift"),
      encoding: "UTF-8"
    )
    %w[workshopDrillHUD workshopDrillStatus workshopDrillRecord
       workshopDrillRetry workshopDrillExit].each do |identifier|
      assert_includes root_view, %Q{"#{identifier}"}
    end
    assert_includes root_view, "model.activeDrillOutcome"
    assert_includes root_view, "model.activeDrillRemainingSeconds"
    assert_includes root_view, "model.restartActiveDrill()"
    assert_includes root_view, "model.endDrill()"

    app_model = File.read(
      File.join(ROOT, "NovaStationPinball/App/AppModel.swift"),
      encoding: "UTF-8"
    )
    assert_includes app_model, "func restartActiveDrill()"
    assert_includes app_model, "func endDrill()"
    assert_includes app_model, "private(set) var activeDrillRemainingSeconds"

    layout_test = File.read(
      File.join(ROOT, "NovaStationPinballUITests/LayoutUITests.swift"),
      encoding: "UTF-8"
    )
    %w[workshopDrillHUD workshopDrillStatus workshopDrillRetry workshopDrillExit].each do |identifier|
      assert_includes layout_test, identifier
    end
    assert_includes layout_test, "exists == false"

    audit_test = File.read(
      File.join(ROOT, "NovaStationPinballUITests/AccessibilityAuditUITests.swift"),
      encoding: "UTF-8"
    )
    assert_includes audit_test, "workshopDrillHUD"
    assert_includes audit_test, "UICTContentSizeCategoryAccessibilityXXXL"

    integration_test = File.read(
      File.join(ROOT, "NovaStationPinballTests/AppModelRuntimeIntegrationTests.swift"),
      encoding: "UTF-8"
    )
    assert_includes integration_test, "restartActiveDrill()"
    assert_includes integration_test, "activeDrillRemainingSeconds"

    catalog = JSON.parse(
      File.read(
        File.join(ROOT, "NovaStationPinball/Resources/Localizable.xcstrings"),
        encoding: "UTF-8"
      )
    ).fetch("strings")
    %w[drill.hud.title drill.hud.remaining drill.hud.succeeded drill.hud.failed
       drill.hud.retry drill.hud.exit].each do |key|
      assert_equal %w[en fr], catalog.fetch(key).fetch("localizations").keys.sort
    end

    {
      "workshop.rewind.remaining" => 1,
      "workshop.drills.record" => 2,
      "drill.hud.remaining" => 1
    }.each do |key, argument_number|
      %w[en fr].each do |locale|
        localization = catalog.fetch(key).fetch("localizations").fetch(locale)
        substitution = localization
                       .fetch("substitutions")
                       .values
                       .find { |value| value.fetch("argNum") == argument_number }
        refute_nil substitution, "#{key} [#{locale}] must vary by plural on argument #{argument_number}"
        plural = substitution.fetch("variations").fetch("plural")
        one = plural.fetch("one").fetch("stringUnit").fetch("value")
        other = plural.fetch("other").fetch("stringUnit").fetch("value")
        refute_empty one
        refute_equal one, other, "#{key} [#{locale}] must not repeat the singular as the plural"
      end
    end
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
      NovaStationPinball/App/AppModel.swift
      NovaStationPinballUITests/StoreScreenshotUITests.swift
      NovaStationPinballUITests/AppPreviewUITests.swift
    ]
    required.each { |relative| assert File.file?(File.join(ROOT, relative)), "missing #{relative}" }

    scenario_source = File.read(File.join(ROOT, "NovaStationPinball/App/MediaScenario.swift"), encoding: "UTF-8")
    app_model_source = File.read(File.join(ROOT, "NovaStationPinball/App/AppModel.swift"), encoding: "UTF-8")
    %w[launch mission promotion multiball tilt game-over].each do |scenario|
      assert_includes scenario_source, "\"#{scenario}\""
    end
    refute_match(/\.svg\b|\.pdf\b/i, scenario_source)
    assert_includes scenario_source, "static func preparePreviewSessions()"
    assert_includes scenario_source, "allCases.map { scenario in"
    prepare_marker = "let preparedSessions = try MediaScenario.preparePreviewSessions()"
    ready_marker = "try handshake.prepareAndSignalReady()"
    assert_operator app_model_source.index(prepare_marker), :<, app_model_source.index(ready_marker)
    loop_start = app_model_source.index("for (offset, scenario) in MediaScenario.allCases.dropFirst().enumerated()")
    loop_end = app_model_source.index("try await clock.sleep(until: timelineStart.advanced(by: .seconds(24)))")
    loop_source = app_model_source[loop_start...loop_end]
    assert_includes loop_source, "preparedSessions[scenario]"
    assert_includes loop_source, "applyMediaScenario(scenario, preparedSession: preparedSession)"
    refute_includes loop_source, "makeSession()"
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
    assert_includes screenshot_tests, "assertGuideCopyFitsAboveNavigation(in: app)"
    assert_includes screenshot_tests, "body.frame.maxY"
    assert_includes screenshot_tests, "next.frame.minY - 8"
    assert_includes preview_tests, "assertGuideCopyFitsAboveNavigation(in: app)"
    assert_includes preview_tests, "app.descendants(matching: .any)"
    assert_includes preview_tests, 'matching(identifier: "tableGuideNavigation")'
    assert_includes preview_tests, "XCTAssertTrue(title.exists)"
    assert_includes preview_tests, "XCTAssertTrue(body.exists)"
    assert_includes preview_tests, "XCTAssertTrue(navigation.exists)"
    refute_includes preview_tests, "title.waitForExistence"
    refute_includes preview_tests, "body.waitForExistence"
    refute_includes preview_tests, "navigation.waitForExistence"
    assert_includes preview_tests, "body.frame.maxY"
    assert_includes preview_tests, "navigation.frame.minY - 8"

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

  def with_pipeline_fixture
    Dir.mktmpdir("nova-pipeline-contract") do |root|
      PIPELINE_FIXTURE_FILES.each do |relative|
        destination = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(File.join(ROOT, relative), destination)
      end
      yield root
    end
  end

  def pipeline_errors(root)
    verifier = NovaStationPinballReleaseContract::Verifier.new(root)
    verifier.send(:validate_release_pipeline_products)
    verifier.instance_variable_get(:@errors)
  end

  # The capture is the only artefact of the release that states a price in
  # pixels. Checking that the file exists is what let a sibling app ship a
  # "$29.99" capture against a 6,99 € spec, so the sidecar written by the
  # capture script is checked against the manifest and against the PNG itself.
  def assert_review_capture_asset_matches_the_products_manifest
    manifest = JSON.parse(
      File.read(File.join(ROOT, "fastlane/pro_products.json"), encoding: "UTF-8")
    )
    product = manifest.fetch("products").first
    declared = product.fetch("review_screenshot")
    png = File.join(ROOT, declared)
    assert File.file?(png), "missing review capture: #{declared}"
    assert_equal "\x89PNG\r\n\x1a\n".b, File.binread(png, 8)

    sidecar = png.sub(/\.png\z/, ".json")
    assert File.file?(sidecar), "missing review capture sidecar: #{sidecar}"
    payload = JSON.parse(File.read(sidecar, encoding: "UTF-8"))
    assert_equal Digest::SHA256.hexdigest(File.binread(png)), payload.fetch("screenshot_sha256"),
                 "the sidecar describes another image; recapture instead of editing it"
    assert_equal product.fetch("product_id"), payload.fetch("product_id")
    assert_equal manifest.fetch("base_territory"), payload.fetch("storefront")

    displayed = payload.fetch("displayed_price")
    digits = displayed[/\d+(?:[.,]\d{1,2})?/]
    refute_nil digits, "cannot read a price out of #{displayed.inspect}"
    assert_equal format("%.2f", Float(product.fetch("base_price"))),
                 format("%.2f", Float(digits.tr(",", "."))),
                 "the review capture states a price the App Store does not have: #{displayed.inspect}"
    assert_includes displayed, "€", "the base currency is EUR: #{displayed.inspect}"
  end

  def required_files
    %w[
      AGENTS.md .gitignore README.md project.yml Package.swift Gemfile
      NovaStationPinball/Resources/PrivacyInfo.xcprivacy
      NovaStationPinball/NovaStationPinball.entitlements
      NovaStationPinball/App/NovaStationPinballApp.swift
      NovaStationPinball/App/MediaPreviewHandshake.swift
      NovaStationPinballTests/BootstrapTests.swift
      NovaStationPinballUITests/BootstrapUITests.swift
      NovaStationPinballUITests/PaywallReviewUITests.swift
      NovaStationPinball/Services/StoreService.swift
      NovaStationCore/Sources/NovaStationCore/NovaStationCore.swift
      NovaStationCore/Tests/NovaStationCoreTests/NovaStationCoreTests.swift
      scripts/release_contract.rb scripts/release_contract_test.rb
      fastlane/Fastfile fastlane/Appfile fastlane/release_config.json
      fastlane/pro_products.json
      fastlane/media_adoption_contract.json
      fastlane/metadata_preflight.rb
      fastlane/metadata_pretransport_recovery.json
      scripts/app_store/adopt_media.rb scripts/app_store/adopt_media_test.rb
      scripts/app_store/metadata_pretransport_recovery.rb
      scripts/app_store/metadata_pretransport_recovery_test.rb
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
