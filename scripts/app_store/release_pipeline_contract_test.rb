# frozen_string_literal: true

require "bigdecimal"
require "digest"
require "json"
require "minitest/autorun"
require_relative "adopt_media"
require_relative "iap_status"
require_relative "metadata_pretransport_recovery"
require_relative "review_submission"

class NovaStationPinballReleasePipelineContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  CONFIG_PATH = File.join(ROOT, "fastlane", "release_config.json")
  FASTFILE_PATH = File.join(ROOT, "fastlane", "Fastfile")
  LOCALES = %w[en-US fr-FR].freeze
  DEVICES = %w[iphone-17-pro-max iphone-se-3 ipad-pro-13-m5].freeze
  SCENARIOS = %w[launch mission promotion multiball tilt game-over].freeze

  def test_checkpoint_pipeline_configuration_is_exact_and_app_local
    config = JSON.parse(File.binread(CONFIG_PATH))
    assert_match(/\A\d+\.\d+(?:\.\d+)?\z/, config.fetch("version"))
    assert_equal "NovaStationPinball.xcodeproj", config.fetch("project")
    assert_equal "NovaStationPinball", config.fetch("scheme")
    assert_equal "767SX34A7Z", config.fetch("team_id")
    assert_equal "Builds/AppStore/NovaStationPinball", config.fetch("artifact_root")
    assert_equal "/private/tmp/apps-factory/NovaStationPinball", config.fetch("scratch_root")
    configured_products = config.fetch("iap_products")
    assert_equal configured_products.map { |product| product.fetch("product_id") }, config.fetch("iap")
    assert_equal "one_time_unlock", config.fetch("monetization_strategy").fetch("model")
    assert_equal "fastlane/pro_products.json",
                 config.fetch("monetization_strategy").fetch("products_manifest")
    assert_operator BigDecimal(config.fetch("pricing").fetch("price")), :>=, BigDecimal("0")
    assert_equal "FRA", config.fetch("pricing").fetch("territory")
    assert_equal "EUR", config.fetch("pricing").fetch("currency")
    refute_empty config.fetch("pricing").fetch("readback_contract")
    leaderboards = NovaStationPinballReviewSubmission.declared_leaderboards(config)
    assert_equal ["nova-station-high-score"], config.fetch("leaderboard_ids")
    assert_equal ["nova-station-high-score"],
                 leaderboards.map { |definition| definition.fetch("id") }
    assert_equal 999_999_999, leaderboards.first.fetch("score_range_end")

    pipeline = config.fetch("release_pipeline")
    assert_equal 1, pipeline.fetch("schema_version")
    assert_equal "deliver-v1", pipeline.fetch("metadata_readback_contract")
    assert_equal LOCALES, pipeline.fetch("metadata_locales")
    assert_equal ["notes"], pipeline.fetch("metadata_review_information_fields")
    assert_equal "exact-v1", pipeline.fetch("iap_readback_contract")
    %w[
      status_script media_inputs media_expectations select_build_script
    ].each do |key|
      path = File.expand_path(pipeline.fetch(key), ROOT)
      assert path.start_with?("#{ROOT}/"), "#{key} escaped app root"
      assert File.file?(path), "missing #{key}: #{path}"
      refute File.symlink?(path), "#{key} must not be a symlink"
    end
    refute pipeline.key?("simulator_requirements"),
           "Nova owns its fixed-pool leases inside the app-local generator"
    refute pipeline.key?("media_adoption_contract"),
           "a historical adoption contract must not hijack a new release run"
    refute pipeline.key?("media_adoption_lane"),
           "new runs must regenerate from media_inputs when the product changed"

    # This remains an immutable proof of the previously validated 1.0 media. It is
    # deliberately no longer selected by release_config for a fresh build-2 run.
    contract = JSON.parse(
      File.binread(File.join(ROOT, "fastlane", "media_adoption_contract.json"))
    )
    assert_equal 2, contract.fetch("schema_version")
    assert_equal "NovaStationPinball", contract.fetch("app_slug")
    assert_equal "20260810-nova-100-official-545d2d2a-precompute",
                 contract.fetch("release_run_id")
    assert_equal "262f6f213ae808a28871b3723de48838a8046ab6",
                 contract.fetch("baseline_head")
    assert_equal "86b5d42e02a8a96e35227a5a8ede6fe2581fbe947d38d25d5734b449c22dd496",
                 contract.fetch("baseline_contract_sha256")
    assert_equal "545d2d2a4fcd1f0748954c4b7b53a5a4698d261ab97f86a4b9a0153ae9ff98d0",
                 contract.fetch("source_revision")
    assert_equal 36, contract.fetch("screenshot_count")
    assert_equal 6, contract.fetch("preview_count")
    proof = contract.fetch("media_proof")
    assert_equal 36, proof.dig("screenshots", "count")
    assert_equal "84046113af2d7c4024d3ed7b6edadbc8d1945244a6940369609b26b1390567a5",
                 proof.dig("screenshots", "sha256")
    assert_equal 6, proof.dig("previews", "count")
    assert_equal "9e425544407a30cfc283f27d5fe56d8070efea60eafe38baa6315b90e2ac262d",
                 proof.dig("previews", "sha256")
    assert_equal 1, proof.dig("manifest", "count")
    assert_equal "809bfcbe78707052c19f035aee409f16c15b9937ebcfd0005e23bd597f5becb5",
                 proof.dig("manifest", "sha256")
    assert_equal 6, proof.dig("system_overlay", "reports")
    assert_equal 4_320, proof.dig("system_overlay", "scanned_frames")
    assert_equal 0, proof.dig("system_overlay", "violation_count")
    assert_equal "759b80752a7008a9cd053ddbe4d21990c6474ad7f6191b28403c6e84591ac86e",
                 proof.dig("system_overlay", "semantic_sha256")
    assert_equal 19, proof.dig("human_review", "count")
    assert_equal "PASS", proof.dig("human_review", "verdict")
    assert_equal "4a9009d720a2a30cfaed1c2565589dbbe750b88d44c277440ef6a71a29f12f5f",
                 proof.dig("human_review", "sha256")
    assert_equal Digest::SHA256.hexdigest(
      NovaStationPinballMediaAdoption.canonical_bytes(
        contract.reject { |key, _| key == "contract_self_sha256" }
      )
    ), contract.fetch("contract_self_sha256")
    changes = contract.fetch("allowed_source_changes")
    assert_equal %w[
      fastlane/Fastfile
      fastlane/metadata_preflight.rb
      fastlane/metadata_preflight_test.rb
      fastlane/metadata_pretransport_recovery.json
      fastlane/release_support.rb
      fastlane/release_support_test.rb
      scripts/app_store/adopt_media.rb
      scripts/app_store/adopt_media_test.rb
      scripts/app_store/client.rb
      scripts/app_store/client_test.rb
      scripts/app_store/metadata_pretransport_recovery.rb
      scripts/app_store/metadata_pretransport_recovery_test.rb
      scripts/app_store/release_pipeline_contract_test.rb
      scripts/release_contract.rb
      scripts/release_contract_test.rb
    ], changes.map { |change| change.fetch("path") }
    assert changes.all? { |change|
        change.keys.sort == %w[after_sha256 before_sha256 class path] &&
        change.fetch("class") == "release_tooling" &&
        (change["before_sha256"].nil? ||
          change.fetch("before_sha256").match?(/\A[0-9a-f]{64}\z/)) &&
        change.fetch("after_sha256").match?(/\A[0-9a-f]{64}\z/)
    }

    recovery = JSON.parse(
      File.binread(File.join(ROOT, "fastlane", "metadata_pretransport_recovery.json"))
    )
    NovaStationPinballMetadataPretransportRecovery.validate_contract!(recovery)
    assert_equal contract.fetch("release_run_id"),
                 recovery.fetch("release_run_id")
    assert_equal contract.fetch("baseline_head"),
                 recovery.fetch("historical_head")
    assert_equal "ead006d2f2f3d776e65b8bc7cc43be82b062da2635f031b2b08a4c8ea7f65fc6",
                 recovery.fetch("historical_candidate_id")
    assert_equal contract.fetch("baseline_contract_sha256"),
                 recovery.fetch("historical_adoption_contract_sha256")
    assert_equal %w[
      fastlane/Fastfile
      fastlane/metadata_preflight.rb
      fastlane/metadata_preflight_test.rb
      fastlane/release_support.rb
      fastlane/release_support_test.rb
      scripts/app_store/adopt_media.rb
      scripts/app_store/adopt_media_test.rb
      scripts/app_store/client.rb
      scripts/app_store/client_test.rb
      scripts/app_store/metadata_pretransport_recovery.rb
      scripts/app_store/metadata_pretransport_recovery_test.rb
      scripts/app_store/release_pipeline_contract_test.rb
      scripts/release_contract.rb
      scripts/release_contract_test.rb
    ], recovery.fetch("source_changes").map { |change| change.fetch("path") }
  end

  def test_media_snapshot_and_expectation_cover_the_real_nova_matrix
    inputs = JSON.parse(File.binread(File.join(ROOT, "fastlane", "media_inputs.json")))
    assert_equal 1, inputs.fetch("schema_version")
    assert_includes inputs.fetch("ui"), "NovaStationPinball"
    assert_includes inputs.fetch("ui"), "NovaStationCore"
    assert_includes inputs.fetch("assets"), "Art"
    assert_includes inputs.fetch("fixtures"), "NovaStationPinballUITests"
    assert_includes inputs.fetch("framing"), "scripts/app_store/generate_screenshots.rb"
    assert_includes inputs.fetch("framing"), "scripts/app_store/generate_app_previews.rb"
    assert_equal LOCALES, inputs.fetch("localizations").keys

    expectation = JSON.parse(
      File.binread(File.join(ROOT, "fastlane", "media_expectations.json"))
    )
    assert_equal 1, expectation.fetch("schema_version")
    assert_equal "self_provisioning_simulator", expectation.fetch("strategy")
    assert_equal LOCALES, expectation.fetch("locales")
    assert_equal true, expectation.fetch("previews_applicable")

    config = JSON.parse(File.binread(CONFIG_PATH))
    assert_equal DEVICES, config.dig("media_contract", "devices")
    assert_equal SCENARIOS, config.dig("media_contract", "scenarios")
    assert_equal SCENARIOS, config.dig("app_preview_policy", "scenarios")
  end

  def test_fastfile_exposes_real_checkpoint_operations_and_disables_monolith
    source = File.binread(FASTFILE_PATH)
    required_lanes = %w[
      setup_asc release_contract asc_status metadata screenshots app_previews
      adopt_media media_contract upload_screenshots upload_previews build_release upload_release
      submit_review release_quick pricing iap_status iap_sync
      recover_metadata_pretransport
    ]
    required_lanes.each { |name| assert_match(/^\s*lane :#{name}\b/, source) }

    quick = lane_body(source, "release_quick")
    assert_includes quick, "UI.user_error!"
    assert_includes quick, "bin/apple-release release NovaStationPinball"
    %w[metadata screenshots app_previews upload_screenshots upload_previews build_release upload_release submit_review].each do |operation|
      refute_match(/^\s*#{operation}\b/, quick)
    end

    metadata = lane_body(source, "metadata")
    assert_guarded_transport(metadata, kind: "metadata")
    assert_includes metadata, "nova_metadata_paths!"
    assert_includes metadata, "nova_metadata_preflight!"
    assert_includes metadata, "metadata_paths.fetch(:metadata_path)"
    assert_includes metadata, "metadata_paths.fetch(:app_rating_config_path)"
    refute_includes metadata, 'File.join(__dir__, "metadata")'
    recovery = lane_body(source, "recover_metadata_pretransport")
    assert_includes recovery, '"metadata_pretransport_recovery"'
    screenshots = lane_body(source, "upload_screenshots")
    assert_includes screenshots, "media_contract"
    assert_guarded_transport(screenshots, kind: "screenshots")
    previews = lane_body(source, "upload_previews")
    assert_includes previews, "media_contract"
    assert_guarded_transport(previews, kind: "previews")
    binary = lane_body(source, "upload_release")
    assert_guarded_transport(binary, kind: "ipa")
    assert_includes binary, 'ENV.fetch("APPLE_RELEASE_EXPECTED_IPA_SHA256")'

    build = lane_body(source, "build_release")
    assert_includes build, "nova_require_wrapper_signing!"
    assert_includes build, "nova_target_build!"
    assert_equal 1, build.scan("build_app(").length
    assert_includes build, "nova_verify_ipa!"

    adoption = lane_body(source, "adopt_media")
    assert_includes adoption, "nova_adopt_media!"
    assert_includes source, "scripts/app_store/adopt_media.rb"
    assert_includes source, "scripts/app_store/adopt_media_test.rb"
    assert_includes File.binread(File.join(ROOT, "scripts/app_store/adopt_media.rb")),
                    'flags.on("--check-only")'
    assert_includes File.binread(File.join(ROOT, ".gitignore")),
                    "fastlane/asc_api_key.json"

  end

  def test_status_select_and_submission_helpers_are_fail_closed
    helpers = %w[
      client.rb metadata_readback.rb status.rb wait_for_state.rb select_build.rb
      review_submission.rb setup_asc.rb pricing.rb iap_status.rb iap_sync.rb
      metadata_pretransport_recovery.rb rejected_submission_recovery.rb
    ]
    helpers.each do |name|
      path = File.join(ROOT, "scripts", "app_store", name)
      assert File.file?(path), "missing app-local helper #{name}"
      refute File.symlink?(path), "helper #{name} must not be a symlink"
    end

    status = File.binread(File.join(ROOT, "scripts", "app_store", "status.rb"))
    assert_includes status, "assetDeliveryState"
    assert_includes status, "videoDeliveryState"
    assert_includes status, '== "COMPLETE"'
    assert_includes status, "target-build.json"
    assert_includes status, '"screenshots_complete"'
    assert_includes status, '"previews_complete"'
    assert_includes status, '"pricing"'
    assert_includes status, '"iap"'
    assert_includes status, '"game_center"'
    assert_includes status, "gameCenterLeaderboardVersion"
    assert_includes status, "app_version_enabled!"
    assert_includes status, '"app_version" => game_center_app_version'
    assert_includes status, "required_review_resources"

    select = File.binread(File.join(ROOT, "scripts", "app_store", "select_build.rb"))
    assert_includes select, "NovaStationPinballReleaseSupport.transport_once!"
    assert_includes select, "NovaStationPinballReleaseSupport.mark_observed!"
    assert_includes select, "selected_build_matches?"

    submit = File.binread(File.join(ROOT, "scripts", "app_store", "review_submission.rb"))
    assert_includes submit, "NovaStationPinballReleaseSupport.transport_once!"
    assert_includes submit, "NovaStationPinballReleaseSupport.mark_observed!"
    assert_includes submit, "review_submitted?"
    assert_includes submit, "gameCenterLeaderboardVersions"
    assert_includes submit, "gameCenterLeaderboardVersion"
    assert_includes submit, "app_version_enabled!"
    assert_includes submit, "validate_retired_products!"
    assert_includes submit, "RetiredIapReadback.exact!"

    setup = File.binread(File.join(ROOT, "scripts", "app_store", "setup_asc.rb"))
    assert_includes setup, 'kind: "setup_asc"'
    assert_includes setup, "NovaStationPinballReleaseSupport.transport_once!"
    assert_includes setup, "NovaStationPinballReleaseSupport.mark_observed!"
    assert_includes setup, "apply_run_id!"
    assert_includes setup, "formatterOverride: nil"
    assert_includes setup, 'description: localization.fetch("description")'
    assert_includes setup, "app_version_enabled!"
    refute_includes setup, 'client.post("/v2/gameCenterLeaderboardVersions"'
    refute_match(/client\.patch\([^\n]*gameCenter/, setup)

    game_center_contract = File.binread(
      File.join(ROOT, "scripts", "app_store", "game_center_contract.rb")
    )
    assert_includes game_center_contract,
                    '"description" => attributes["description"]'
  end

  # A stub App Store Connect: the only thing the submission path is allowed to
  # know about the purchase catalogue is what the release configuration says.
  class StubClient
    def initialize(purchases:, versions:, availabilities: {})
      @purchases = purchases
      @versions = versions
      @availabilities = availabilities
    end

    def get(path, _query = {}, optional: false)
      case path
      when %r{\A/v2/inAppPurchases/([^/]+)/inAppPurchaseAvailability\z}
        availability = @availabilities[Regexp.last_match(1)]
        return nil if availability.nil? && optional
        raise "missing availability" unless availability

        {
          "data" => {
            "id" => availability.fetch("id"),
            "type" => "inAppPurchaseAvailabilities",
            "attributes" => {
              "availableInNewTerritories" =>
                availability.fetch("available_in_new_territories")
            }
          }
        }
      when %r{\A/v2/inAppPurchases/([^/]+)\z}
        purchase = @purchases.find { |item| item.fetch("id") == Regexp.last_match(1) }
        raise "missing purchase" unless purchase

        { "data" => purchase }
      else
        raise "unexpected request: #{path}"
      end
    end

    def get_all(path, _query = {})
      case path
      when %r{\A/v1/apps/[^/]+/inAppPurchasesV2\z}
        { "data" => @purchases }
      when %r{\A/v2/inAppPurchases/([^/]+)/versions\z}
        { "data" => @versions.fetch(Regexp.last_match(1), []) }
      when %r{\A/v1/inAppPurchaseAvailabilities/([^/]+)/availableTerritories\z}
        availability = @availabilities.values.find do |item|
          item.fetch("id") == Regexp.last_match(1)
        end
        raise "missing availability" unless availability

        { "data" => availability.fetch("territories") }
      else
        raise "unexpected request: #{path}"
      end
    end
  end

  class SubmissionClient
    def initialize(submissions)
      @submissions = submissions
    end

    def get_all(path, _query = {})
      case path
      when "/v1/apps/app-1/reviewSubmissions"
        {
          "data" => @submissions.map do |submission|
            {
              "id" => submission.fetch("id"),
              "type" => "reviewSubmissions",
              "attributes" => { "state" => submission.fetch("state") }
            }
          end
        }
      when %r{\A/v1/reviewSubmissions/([^/]+)/items\z}
        submission = @submissions.find do |candidate|
          candidate.fetch("id") == Regexp.last_match(1)
        end
        raise "missing submission" unless submission

        {
          "data" => submission.fetch("resources").map.with_index do |resource, index|
            type, id = resource
            relationship =
              NovaStationPinballReviewSubmission.review_item_relationship(type)
            {
              "id" => "#{submission.fetch('id')}-item-#{index}",
              "type" => "reviewSubmissionItems",
              "relationships" => {
                relationship => { "data" => { "type" => type, "id" => id } }
              }
            }
          end
        }
      else
        raise "unexpected request: #{path}"
      end
    end
  end

  def purchase(id:, product_id:, type:, state:)
    {
      "id" => id, "type" => "inAppPurchases",
      "attributes" => {
        "productId" => product_id, "inAppPurchaseType" => type, "state" => state
      }
    }
  end

  def purchase_version(id:, version:, state:)
    {
      "id" => id, "type" => "inAppPurchaseVersions",
      "attributes" => { "version" => version, "state" => state }
    }
  end

  def workshop_client(type: "NON_CONSUMABLE", state: "READY_TO_SUBMIT",
                      version_state: "PREPARE_FOR_SUBMISSION")
    StubClient.new(
      purchases: [
        purchase(
          id: "iap-1", product_id: "com.bnjdpn.NovaStationPinball.workshop",
          type: type, state: state
        )
      ],
      versions: {
        "iap-1" => [purchase_version(id: "iapv-1", version: "1", state: version_state)]
      }
    )
  end

  def retired_availabilities(purchases, available: false, territories: [])
    purchases.each_with_object({}) do |item, result|
      result[item.fetch("id")] = {
        "id" => "availability-#{item.fetch('id')}",
        "available_in_new_territories" => available,
        "territories" => territories
      }
    end
  end

  # Regression guarded here: the shipped release sells a non-consumable
  # unlock, and the submission path must carry it instead of raising about the
  # removed jar.
  def test_the_configured_non_consumable_unlock_goes_through_the_submission_path
    config = JSON.parse(File.binread(CONFIG_PATH))
    products = NovaStationPinballReviewSubmission.declared_products(config)
    assert_equal ["com.bnjdpn.NovaStationPinball.workshop"],
                 products.map { |product| product.fetch("product_id") }
    assert_equal ["NON_CONSUMABLE"], products.map { |product| product.fetch("type") }

    records = NovaStationPinballReviewSubmission.product_submission_records(
      workshop_client, "app-1", products
    )
    assert_equal 1, records.length
    record = records.fetch(0)
    assert_equal "iapv-1", record.fetch("version_id")
    assert record.fetch("must_bundle"),
           "a product App Store Connect has never approved must ride with the version"
    assert record.fetch("required")

    required = NovaStationPinballReviewSubmission.required_resources(
      "v-1", records, [{ "version_id" => "gcv-1" }]
    )
    assert_equal [
      ["appStoreVersions", "v-1"],
      ["gameCenterLeaderboardVersions", "gcv-1"],
      ["inAppPurchaseVersions", "iapv-1"]
    ], required
  end

  def test_submission_refuses_until_every_retired_tip_matches_its_target_state
    config = JSON.parse(File.binread(CONFIG_PATH))
    retired = NovaStationPinballReviewSubmission.declared_retired_products(config)
    ready = retired.map.with_index do |product, index|
      purchase(
        id: "retired-#{index}", product_id: product.fetch("product_id"),
        type: product.fetch("type"), state: "READY_TO_SUBMIT"
      )
    end
    client = StubClient.new(purchases: ready, versions: {})

    error = assert_raises(RuntimeError) do
      NovaStationPinballReviewSubmission.validate_retired_products!(
        client, "app-1", retired
      )
    end
    assert_includes error.message, "READY_TO_SUBMIT"
    assert_includes error.message, "DEVELOPER_REMOVED_FROM_SALE"

    removed = ready.map do |item|
      copy = Marshal.load(Marshal.dump(item))
      copy["attributes"]["state"] = "DEVELOPER_REMOVED_FROM_SALE"
      copy
    end
    missing_error = assert_raises(
      NovaStationPinballRejectedSubmissionRecovery::Error
    ) do
      NovaStationPinballReviewSubmission.validate_retired_products!(
        StubClient.new(purchases: removed, versions: {}), "app-1", retired
      )
    end
    assert_includes missing_error.message, "exact type, state, availability"

    exact_availabilities = retired_availabilities(removed)
    NovaStationPinballReviewSubmission.validate_retired_products!(
      StubClient.new(
        purchases: removed, versions: {},
        availabilities: exact_availabilities
      ),
      "app-1", retired
    )

    true_error = assert_raises(
      NovaStationPinballRejectedSubmissionRecovery::Error
    ) do
      NovaStationPinballReviewSubmission.validate_retired_products!(
        StubClient.new(
          purchases: removed, versions: {},
          availabilities: retired_availabilities(removed, available: true)
        ),
        "app-1", retired
      )
    end
    assert_includes true_error.message, "availability and territories"

    territory_error = assert_raises(
      NovaStationPinballRejectedSubmissionRecovery::Error
    ) do
      NovaStationPinballReviewSubmission.validate_retired_products!(
        StubClient.new(
          purchases: removed, versions: {},
          availabilities: retired_availabilities(
            removed, territories: [{ "type" => "territories", "id" => "FRA" }]
          )
        ),
        "app-1", retired
      )
    end
    assert_includes territory_error.message, "availability and territories"
  end

  def test_review_item_readback_accepts_exactly_app_leaderboard_or_iap
    assert_equal "gameCenterLeaderboardVersion",
                 NovaStationPinballReviewSubmission.review_item_relationship(
                   "gameCenterLeaderboardVersions"
                 )
    resources = [
      ["appStoreVersion", "appStoreVersions", "v-1"],
      [
        "gameCenterLeaderboardVersion", "gameCenterLeaderboardVersions", "gcv-1"
      ],
      ["inAppPurchaseVersion", "inAppPurchaseVersions", "iapv-1"]
    ].map.with_index do |(relationship, type, id), index|
      item = {
        "id" => "item-#{index}",
        "relationships" => {
          relationship => { "data" => { "type" => type, "id" => id } }
        }
      }
      NovaStationPinballReviewSubmission.review_item_resource!(item)
    end
    assert_equal [
      ["appStoreVersions", "v-1"],
      ["gameCenterLeaderboardVersions", "gcv-1"],
      ["inAppPurchaseVersions", "iapv-1"]
    ], resources

    ambiguous = {
      "id" => "ambiguous",
      "relationships" => {
        "appStoreVersion" => {
          "data" => { "type" => "appStoreVersions", "id" => "v-1" }
        },
        "gameCenterLeaderboardVersion" => {
          "data" => {
            "type" => "gameCenterLeaderboardVersions", "id" => "gcv-1"
          }
        }
      }
    }
    assert_raises(RuntimeError) do
      NovaStationPinballReviewSubmission.review_item_resource!(ambiguous)
    end
  end

  def test_submission_readback_requires_one_exact_resource_set
    required = [
      ["appStoreVersions", "v-1"],
      ["gameCenterLeaderboardVersions", "gcv-1"],
      ["inAppPurchaseVersions", "iapv-1"]
    ]
    exact = {
      "id" => "review-1", "state" => "WAITING_FOR_REVIEW",
      "resources" => required.reverse
    }
    assert NovaStationPinballReviewSubmission.review_submitted?(
      SubmissionClient.new([exact]), "app-1", required
    )

    subset = Marshal.load(Marshal.dump(exact))
    subset["resources"] = required.first(2)
    refute NovaStationPinballReviewSubmission.review_submitted?(
      SubmissionClient.new([subset]), "app-1", required
    )

    superset = Marshal.load(Marshal.dump(exact))
    superset["resources"] += [["inAppPurchaseVersions", "old-tip-version"]]
    refute NovaStationPinballReviewSubmission.review_submitted?(
      SubmissionClient.new([superset]), "app-1", required
    )
    assert_raises(RuntimeError) do
      NovaStationPinballReviewSubmission.resumable_draft!(
        [{
          "id" => "draft-extra", "state" => "READY_FOR_REVIEW",
          "resources" => superset.fetch("resources")
        }],
        required
      )
    end

    duplicate = Marshal.load(Marshal.dump(exact))
    duplicate["resources"] << required.first
    refute NovaStationPinballReviewSubmission.review_submitted?(
      SubmissionClient.new([duplicate]), "app-1", required
    )
    assert_raises(RuntimeError) do
      NovaStationPinballReviewSubmission.exact_submission_resources!(
        SubmissionClient.new([duplicate]), "review-1", required
      )
    end

    second = Marshal.load(Marshal.dump(exact)).merge("id" => "review-2")
    assert_raises(RuntimeError) do
      NovaStationPinballReviewSubmission.review_submitted?(
        SubmissionClient.new([exact, second]), "app-1", required
      )
    end
  end

  def test_only_one_subset_draft_can_be_resumed
    required = [
      ["appStoreVersions", "v-1"],
      ["gameCenterLeaderboardVersions", "gcv-1"],
      ["inAppPurchaseVersions", "iapv-1"]
    ]
    draft = {
      "id" => "draft-1", "state" => "READY_FOR_REVIEW",
      "resources" => [["appStoreVersions", "v-1"]]
    }
    assert_equal draft,
                 NovaStationPinballReviewSubmission.resumable_draft!(
                   [draft], required
                 )
    assert_raises(RuntimeError) do
      NovaStationPinballReviewSubmission.resumable_draft!(
        [draft, draft.merge("id" => "draft-2")], required
      )
    end
  end

  def test_the_submission_path_reports_a_type_mismatch_against_the_configuration
    config = JSON.parse(File.binread(CONFIG_PATH))
    products = NovaStationPinballReviewSubmission.declared_products(config)
    error = assert_raises(RuntimeError) do
      NovaStationPinballReviewSubmission.product_submission_records(
        workshop_client(type: "CONSUMABLE"), "app-1", products
      )
    end
    assert_includes error.message, "release configuration"
    assert_includes error.message, "com.bnjdpn.NovaStationPinball.workshop"
    refute_match(/\btips?\b/i, error.message,
                 "the submission path must not talk about the removed jar")
  end

  def test_an_already_shipped_product_is_only_resubmitted_when_it_needs_review
    products = [
      { "product_id" => "com.bnjdpn.NovaStationPinball.workshop", "type" => "NON_CONSUMABLE" }
    ]
    settled = NovaStationPinballReviewSubmission.product_submission_records(
      workshop_client(state: "APPROVED", version_state: "APPROVED"), "app-1", products
    ).fetch(0)
    refute settled.fetch("must_bundle")
    refute settled.fetch("required")
    assert_equal [["appStoreVersions", "v-1"]],
                 NovaStationPinballReviewSubmission.required_resources("v-1", [settled])

    updated = NovaStationPinballReviewSubmission.product_submission_records(
      workshop_client(state: "APPROVED", version_state: "READY_FOR_REVIEW"), "app-1", products
    ).fetch(0)
    refute updated.fetch("must_bundle")
    assert updated.fetch("required")
  end

  # The readback that AGENTS.md requires after every ASC mutation must accept
  # the shipped catalogue and refuse a product left in the wrong state.
  def test_the_iap_readback_is_driven_by_the_release_configuration
    config = JSON.parse(File.binread(CONFIG_PATH))
    declared = NovaStationPinballIapStatus.declared(config)
    retired = NovaStationPinballIapStatus.retired(config)
    assert_equal ["com.bnjdpn.NovaStationPinball.workshop"],
                 declared.map { |product| product.fetch("product_id") }
    assert_equal 3, retired.length
    assert retired.all? { |product| product.fetch("target_state") == "DEVELOPER_REMOVED_FROM_SALE" }

    settled_items = [
      purchase(id: "iap-1", product_id: "com.bnjdpn.NovaStationPinball.workshop",
               type: "NON_CONSUMABLE", state: "READY_TO_SUBMIT")
    ] + retired.map.with_index do |product, index|
      purchase(id: "iap-r#{index}", product_id: product.fetch("product_id"),
               type: "CONSUMABLE", state: "DEVELOPER_REMOVED_FROM_SALE")
    end
    assert_empty NovaStationPinballIapStatus.problems(
      iap_payload(settled_items, declared, retired), declared, retired
    )

    live_tips = settled_items.map do |item|
      next item unless item.dig("attributes", "productId").include?(".tip.")

      copy = Marshal.load(Marshal.dump(item))
      copy["attributes"]["state"] = "WAITING_FOR_REVIEW"
      copy
    end
    problems = NovaStationPinballIapStatus.problems(
      iap_payload(live_tips, declared, retired), declared, retired
    )
    assert_equal 3, problems.length
    assert problems.all? { |problem| problem.include?("DEVELOPER_REMOVED_FROM_SALE") }

    wrong_type = settled_items.map do |item|
      next item unless item.dig("attributes", "productId").end_with?(".workshop")

      copy = Marshal.load(Marshal.dump(item))
      copy["attributes"]["inAppPurchaseType"] = "CONSUMABLE"
      copy
    end
    assert_equal 1, NovaStationPinballIapStatus.problems(
      iap_payload(wrong_type, declared, retired), declared, retired
    ).length
  end

  def iap_payload(items, declared, retired)
    expected_ids = declared.map { |product| product.fetch("product_id") }
    retired_ids = retired.map { |product| product.fetch("product_id") }
    actual_ids = items.map { |item| item.dig("attributes", "productId") }
    {
      "expected_count" => expected_ids.length,
      "actual_count" => items.length,
      "missing_product_ids" => (expected_ids - actual_ids).sort,
      "unexpected_product_ids" => (actual_ids - expected_ids - retired_ids).sort,
      "retired_product_ids" => (actual_ids & retired_ids).sort,
      "items" => items
    }
  end

  private

  def lane_body(source, name)
    match = source.match(
      /^\s*lane :#{Regexp.escape(name)}\b[^\n]*\n(?<body>.*?)(?=^\s*(?:lane|private_lane) :|^end\s*$)/m
    )
    raise "missing lane #{name}" unless match

    match[:body]
  end

  def assert_guarded_transport(body, kind:)
    assert_includes body, "nova_transport_once("
    assert_includes body, "upload_proof"
    assert_includes body, %Q{nova_mutation_proof("#{kind}"}
    assert_equal 1, body.scan("upload_to_app_store(").length
    assert_includes body, "nova_wait_for_state!"
    assert_includes body, "NovaStationPinballReleaseSupport.mark_observed!"
    assert_operator body.index("nova_transport_once"), :<, body.index("upload_to_app_store(")
    assert_operator body.index("upload_to_app_store("), :<, body.index("nova_wait_for_state!")
    assert_operator body.index("nova_wait_for_state!"), :<, body.index("mark_observed!")
  end
end
