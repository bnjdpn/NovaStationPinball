# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require_relative "adopt_media"

class NovaStationPinballReleasePipelineContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  CONFIG_PATH = File.join(ROOT, "fastlane", "release_config.json")
  FASTFILE_PATH = File.join(ROOT, "fastlane", "Fastfile")
  LOCALES = %w[en-US fr-FR].freeze
  DEVICES = %w[iphone-17-pro-max iphone-se-3 ipad-pro-13-m5].freeze
  SCENARIOS = %w[launch mission promotion multiball tilt game-over].freeze
  IAP = %w[
    com.bnjdpn.NovaStationPinball.tip.cafe
    com.bnjdpn.NovaStationPinball.tip.merci
    com.bnjdpn.NovaStationPinball.tip.soutien
  ].freeze

  def test_checkpoint_pipeline_configuration_is_exact_and_app_local
    config = JSON.parse(File.binread(CONFIG_PATH))
    assert_equal "1.0", config.fetch("version")
    assert_equal "NovaStationPinball.xcodeproj", config.fetch("project")
    assert_equal "NovaStationPinball", config.fetch("scheme")
    assert_equal "767SX34A7Z", config.fetch("team_id")
    assert_equal "Builds/AppStore/NovaStationPinball", config.fetch("artifact_root")
    assert_equal "/private/tmp/apps-factory/NovaStationPinball", config.fetch("scratch_root")
    assert_equal IAP, config.fetch("iap")
    assert_equal(
      {
        "price" => "0.00",
        "territory" => "FRA",
        "currency" => "EUR",
        "readback_contract" => "free-v1"
      },
      config.fetch("pricing")
    )

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
    assert_equal "fastlane/media_adoption_contract.json",
                 pipeline.fetch("media_adoption_contract")
    assert_equal "adopt_media", pipeline.fetch("media_adoption_lane")

    contract = JSON.parse(
      File.binread(File.join(ROOT, "fastlane", "media_adoption_contract.json"))
    )
    assert_equal 2, contract.fetch("schema_version")
    assert_equal "NovaStationPinball", contract.fetch("app_slug")
    assert_equal "20260810-nova-100-official-545d2d2a-precompute",
                 contract.fetch("release_run_id")
    assert_equal "b80afffac456388c21088b189a49c48da121d543",
                 contract.fetch("baseline_head")
    assert_equal "a2e195067298a7b07a4f2de011290d584efd4b1d7c30f69950b60a53ecfdfa0e",
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
      fastlane/release_config.json
      scripts/app_store/adopt_media.rb
      scripts/app_store/adopt_media_test.rb
      scripts/app_store/release_pipeline_contract_test.rb
    ], changes.map { |change| change.fetch("path") }
    assert changes.all? { |change|
      change.keys.sort == %w[after_sha256 before_sha256 class path] &&
        change.fetch("class") == "release_tooling" &&
        change.fetch("before_sha256").match?(/\A[0-9a-f]{64}\z/) &&
        change.fetch("after_sha256").match?(/\A[0-9a-f]{64}\z/)
    }
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

    select = File.binread(File.join(ROOT, "scripts", "app_store", "select_build.rb"))
    assert_includes select, "NovaStationPinballReleaseSupport.transport_once!"
    assert_includes select, "NovaStationPinballReleaseSupport.mark_observed!"
    assert_includes select, "selected_build_matches?"

    submit = File.binread(File.join(ROOT, "scripts", "app_store", "review_submission.rb"))
    assert_includes submit, "NovaStationPinballReleaseSupport.transport_once!"
    assert_includes submit, "NovaStationPinballReleaseSupport.mark_observed!"
    assert_includes submit, "review_submitted?"
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
    assert_includes body, "nova_transport_once(upload_proof)"
    assert_includes body, %Q{nova_mutation_proof("#{kind}"}
    assert_equal 1, body.scan("upload_to_app_store(").length
    assert_includes body, "nova_wait_for_state!"
    assert_includes body, "NovaStationPinballReleaseSupport.mark_observed!"
    assert_operator body.index("nova_transport_once"), :<, body.index("upload_to_app_store(")
    assert_operator body.index("upload_to_app_store("), :<, body.index("nova_wait_for_state!")
    assert_operator body.index("nova_wait_for_state!"), :<, body.index("mark_observed!")
  end
end
