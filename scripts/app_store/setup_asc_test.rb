# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "setup_asc"

class NovaStationPinballAscSetupTest < Minitest::Test
  CONFIG = {
    "app_store_name" => "Nova Station Pinball",
    "bundle_id" => "com.bnjdpn.NovaStationPinball",
    "sku" => "nova-station-pinball-ios",
    "primary_locale" => "en-US",
    "version" => "1.0",
    "locales" => %w[en-US fr-FR],
    "leaderboard_ids" => ["nova-station-high-score"],
    "leaderboards" => [{
      "id" => "nova-station-high-score",
      "reference_name" => "Nova Station High Score",
      "default_formatter" => "INTEGER",
      "submission_type" => "BEST_SCORE",
      "score_sort_type" => "DESC",
      "score_range_start" => 0,
      "score_range_end" => 999_999_999,
      "recurrence_start_date" => nil,
      "recurrence_duration" => nil,
      "recurrence_rule" => nil,
      "localizations" => {
        "en-US" => {
          "name" => "Nova Station High Scores",
          "description" =>
            "Highest score from a standard game. Runs using Workshop tools are excluded.",
          "suffix" => "points",
          "singular_suffix" => "point"
        },
        "fr-FR" => {
          "name" => "Scores de Nova Station",
          "description" =>
            "Meilleur score d’une partie standard. Les parties utilisant l’Atelier sont exclues.",
          "suffix" => "points",
          "singular_suffix" => "point"
        }
      }
    }]
  }.freeze

  class FakeClient
    attr_reader :requests

    def initialize(apps, leaderboards: nil, versions: nil, localizations: nil)
      @apps = apps
      @leaderboards = leaderboards || [exact_leaderboard]
      @versions = versions || [exact_version]
      @localizations = localizations || exact_localizations
      @requests = []
    end

    def get_all(path, parameters)
      @requests << [path, parameters]
      case path
      when "/v1/apps"
        { "data" => @apps }
      when "/v1/apps/1234567890/appStoreVersions"
        { "data" => [exact_app_store_version] }
      when "/v1/gameCenterDetails/detail-1/gameCenterLeaderboardsV2"
        { "data" => @leaderboards }
      when "/v2/gameCenterLeaderboards/leaderboard-1/versions"
        { "data" => @versions, "included" => @localizations }
      else
        raise "unexpected GET collection #{path}"
      end
    end

    def get(path, parameters = {}, optional: false)
      @requests << [path, parameters]
      raise "Game Center detail must be optional" unless optional
      case path
      when "/v1/apps/1234567890/gameCenterDetail"
        { "data" => { "type" => "gameCenterDetails", "id" => "detail-1" } }
      when "/v1/appStoreVersions/app-version-1/gameCenterAppVersion"
        { "data" => exact_game_center_app_version }
      else
        raise "unexpected GET #{path}"
      end
    end

    private

    def exact_leaderboard
      {
        "type" => "gameCenterLeaderboards",
        "id" => "leaderboard-1",
        "attributes" => {
          "vendorIdentifier" => "nova-station-high-score",
          "referenceName" => "Nova Station High Score",
          "defaultFormatter" => "INTEGER",
          "submissionType" => "BEST_SCORE",
          "scoreSortType" => "DESC",
          "scoreRangeStart" => "0",
          "scoreRangeEnd" => "999999999",
          "recurrenceStartDate" => nil,
          "recurrenceDuration" => nil,
          "recurrenceRule" => nil,
          "visibility" => "SHOW_FOR_ALL",
          "archived" => false
        }
      }
    end

    def exact_version
      {
        "type" => "gameCenterLeaderboardVersions",
        "id" => "leaderboard-version-1",
        "attributes" => { "version" => "1", "state" => "READY_FOR_REVIEW" },
        "relationships" => {
          "localizations" => {
            "data" => [
              { "type" => "gameCenterLeaderboardLocalizations", "id" => "loc-en" },
              { "type" => "gameCenterLeaderboardLocalizations", "id" => "loc-fr" }
            ]
          }
        }
      }
    end

    def exact_app_store_version
      {
        "type" => "appStoreVersions",
        "id" => "app-version-1",
        "attributes" => {
          "versionString" => "1.0", "appStoreState" => "PREPARE_FOR_SUBMISSION",
          "platform" => "IOS"
        }
      }
    end

    def exact_game_center_app_version
      {
        "type" => "gameCenterAppVersions",
        "id" => "game-center-app-version-1",
        "attributes" => { "enabled" => true },
        "relationships" => {
          "appStoreVersion" => {
            "data" => { "type" => "appStoreVersions", "id" => "app-version-1" }
          }
        }
      }
    end

    def exact_localizations
      [
        localization(
          "loc-en", "en-US", "Nova Station High Scores",
          "Highest score from a standard game. Runs using Workshop tools are excluded.",
          "points", "point"
        ),
        localization(
          "loc-fr", "fr-FR", "Scores de Nova Station",
          "Meilleur score d’une partie standard. Les parties utilisant l’Atelier sont exclues.",
          "points", "point"
        )
      ]
    end

    def localization(id, locale, name, description, suffix, singular_suffix)
      {
        "type" => "gameCenterLeaderboardLocalizations",
        "id" => id,
        "attributes" => {
          "locale" => locale,
          "name" => name,
          "description" => description,
          "formatterSuffix" => suffix,
          "formatterSuffixSingular" => singular_suffix,
          "formatterOverride" => nil
        }
      }
    end
  end

  class ProvisionClient
    attr_reader :posts, :patches

    def initialize(inline_delay_reads: 0, existing_drift: nil)
      @leaderboards = []
      @version = nil
      @pending_version = nil
      @inline_delay_reads = inline_delay_reads
      @version_reads = 0
      @localizations = []
      @posts = []
      @patches = []
      seed_existing!(existing_drift) if existing_drift
    end

    def get(path, _parameters = {}, optional: false)
      raise "Game Center detail must be optional" unless optional
      case path
      when "/v1/apps/1234567890/gameCenterDetail"
        { "data" => { "type" => "gameCenterDetails", "id" => "detail-1" } }
      when "/v1/appStoreVersions/app-version-1/gameCenterAppVersion"
        {
          "data" => {
            "type" => "gameCenterAppVersions",
            "id" => "game-center-app-version-1",
            "attributes" => { "enabled" => true },
            "relationships" => {
              "appStoreVersion" => {
                "data" => {
                  "type" => "appStoreVersions", "id" => "app-version-1"
                }
              }
            }
          }
        }
      else
        raise "unexpected GET #{path}"
      end
    end

    def get_all(path, _parameters = {})
      case path
      when "/v1/apps"
        { "data" => [app] }
      when "/v1/apps/1234567890/appStoreVersions"
        {
          "data" => [{
            "type" => "appStoreVersions",
            "id" => "app-version-1",
            "attributes" => {
              "versionString" => "1.0", "appStoreState" => "PREPARE_FOR_SUBMISSION",
              "platform" => "IOS"
            }
          }]
        }
      when "/v1/gameCenterDetails/detail-1/gameCenterLeaderboardsV2"
        { "data" => @leaderboards }
      when "/v2/gameCenterLeaderboards/leaderboard-1/versions"
        @version_reads += 1
        if @pending_version && @version_reads > @inline_delay_reads
          @version = @pending_version
          @pending_version = nil
        end
        {
          "data" => @version ? [@version] : [],
          "included" => @localizations
        }
      else
        raise "unexpected GET collection #{path}"
      end
    end

    def post(path, body)
      @posts << [path, body]
      case path
      when "/v2/gameCenterLeaderboards"
        attributes = body.dig(:data, :attributes).transform_keys(&:to_s)
        @leaderboards = [{
          "type" => "gameCenterLeaderboards",
          "id" => "leaderboard-1",
          "attributes" => attributes.merge(
            "recurrenceStartDate" => nil,
            "recurrenceDuration" => nil,
            "recurrenceRule" => nil,
            "archived" => false
          )
        }]
        @pending_version = {
          "type" => "gameCenterLeaderboardVersions",
          "id" => "leaderboard-version-1",
          "attributes" => { "version" => "1", "state" => "READY_FOR_REVIEW" },
          "relationships" => { "localizations" => { "data" => [] } }
        }
        if @inline_delay_reads.zero?
          @version = @pending_version
          @pending_version = nil
        end
        { "data" => @leaderboards.first }
      when "/v2/gameCenterLeaderboardLocalizations"
        attributes = body.dig(:data, :attributes).transform_keys(&:to_s)
        id = "loc-#{attributes.fetch('locale')}"
        resource = {
          "type" => "gameCenterLeaderboardLocalizations",
          "id" => id,
          "attributes" => attributes
        }
        @localizations << resource
        @version.dig("relationships", "localizations", "data") << {
          "type" => resource.fetch("type"), "id" => id
        }
        { "data" => resource }
      else
        raise "unexpected POST #{path}"
      end
    end

    def patch(path, body)
      @patches << [path, body]
      raise "unexpected PATCH #{path}"
    end

    private

    def seed_existing!(drift)
      attributes = {
        "vendorIdentifier" => "nova-station-high-score",
        "referenceName" => "Nova Station High Score",
        "defaultFormatter" => "INTEGER",
        "submissionType" => "BEST_SCORE",
        "scoreSortType" => "DESC",
        "scoreRangeStart" => "0",
        "scoreRangeEnd" => "999999999",
        "recurrenceStartDate" => nil,
        "recurrenceDuration" => nil,
        "recurrenceRule" => nil,
        "visibility" => "SHOW_FOR_ALL",
        "archived" => false
      }
      attributes["referenceName"] = "Wrong" if drift == :leaderboard
      @leaderboards = [{
        "type" => "gameCenterLeaderboards", "id" => "leaderboard-1",
        "attributes" => attributes
      }]
      @version = {
        "type" => "gameCenterLeaderboardVersions",
        "id" => "leaderboard-version-1",
        "attributes" => { "version" => "1", "state" => "READY_FOR_REVIEW" },
        "relationships" => { "localizations" => { "data" => [] } }
      }
      return unless drift == :localization

      resource = {
        "type" => "gameCenterLeaderboardLocalizations", "id" => "loc-en-US",
        "attributes" => {
          "locale" => "en-US", "name" => "Nova Station High Scores",
          "formatterSuffix" => "points",
          "description" => "Wrong description",
          "formatterSuffixSingular" => "point", "formatterOverride" => nil
        }
      }
      @localizations << resource
      @version.dig("relationships", "localizations", "data") << {
        "type" => resource.fetch("type"), "id" => resource.fetch("id")
      }
    end

    def app
      {
        "id" => "1234567890",
        "attributes" => {
          "name" => "Nova Station Pinball",
          "bundleId" => "com.bnjdpn.NovaStationPinball",
          "sku" => "nova-station-pinball-ios",
          "primaryLocale" => "en-US"
        }
      }
    end
  end

  def test_missing_preflight_accepts_only_zero_exact_records
    client = FakeClient.new([])

    result = NovaStationPinballAscSetup.inspect!(
      client: client, config: CONFIG, expectation: :missing
    )

    assert_equal "missing", result.fetch("status")
    assert_equal false, result.fetch("mutations")
    assert_equal "com.bnjdpn.NovaStationPinball",
                 client.requests.fetch(0).fetch(1).fetch("filter[bundleId]")

    assert_raises(NovaStationPinballAscSetup::SetupError) do
      NovaStationPinballAscSetup.inspect!(
        client: FakeClient.new([exact_app]),
        config: CONFIG, expectation: :missing
      )
    end
  end

  def test_ready_readback_requires_one_exact_name_bundle_sku_and_locale
    client = FakeClient.new([exact_app])
    result = NovaStationPinballAscSetup.inspect!(
      client: client, config: CONFIG, expectation: :ready
    )

    assert_equal "ready", result.fetch("status")
    assert_equal "1234567890", result.fetch("app_id")
    assert_equal false, result.fetch("mutations")
    assert_equal ["leaderboard-version-1"],
                 result.fetch("game_center").map { |item| item.fetch("version_id") }
    localization_request = client.requests.find do |path, _parameters|
      path == "/v2/gameCenterLeaderboards/leaderboard-1/versions"
    end
    assert_includes(
      localization_request.fetch(1).fetch("fields[gameCenterLeaderboardLocalizations]"),
      "description"
    )

    mismatched = exact_app
    mismatched["attributes"] = mismatched.fetch("attributes").merge(
      "sku" => "wrong-sku"
    )
    assert_raises(NovaStationPinballAscSetup::SetupError) do
      NovaStationPinballAscSetup.inspect!(
        client: FakeClient.new([mismatched]),
        config: CONFIG, expectation: :ready
      )
    end
  end

  def test_ready_readback_rejects_missing_or_ambiguous_records
    assert_raises(NovaStationPinballAscSetup::SetupError) do
      NovaStationPinballAscSetup.inspect!(
        client: FakeClient.new([]), config: CONFIG, expectation: :ready
      )
    end
    assert_raises(NovaStationPinballAscSetup::SetupError) do
      NovaStationPinballAscSetup.inspect!(
        client: FakeClient.new([exact_app, exact_app.merge("id" => "2")]),
        config: CONFIG, expectation: :ready
      )
    end
  end

  def test_ready_readback_rejects_missing_or_ambiguous_game_center_records
    assert_raises(NovaStationPinballAscSetup::SetupError) do
      NovaStationPinballAscSetup.inspect!(
        client: FakeClient.new([exact_app], leaderboards: []),
        config: CONFIG, expectation: :ready
      )
    end

    client = FakeClient.new([exact_app])
    leaderboard = client.send(:exact_leaderboard)
    duplicate = Marshal.load(Marshal.dump(leaderboard)).merge(
      "id" => "leaderboard-2"
    )
    assert_raises(NovaStationPinballAscSetup::SetupError) do
      NovaStationPinballAscSetup.inspect!(
        client: FakeClient.new(
          [exact_app], leaderboards: [leaderboard, duplicate]
        ),
        config: CONFIG, expectation: :ready
      )
    end
  end

  def test_v2_leaderboard_creation_embeds_the_first_version
    body = NovaStationPinballAscSetup.leaderboard_create_body(
      CONFIG.fetch("leaderboards").first, "detail-1", 0
    )

    assert_equal "gameCenterLeaderboards", body.dig(:data, :type)
    assert_equal "nova-station-high-score",
                 body.dig(:data, :attributes, :vendorIdentifier)
    assert_equal 0, body.dig(:data, :attributes, :scoreRangeStart)
    assert_equal 999_999_999, body.dig(:data, :attributes, :scoreRangeEnd)
    version = body.dig(:data, :relationships, :versions, :data).fetch(0)
    assert_equal "gameCenterLeaderboardVersions", version.fetch(:type)
    assert_equal version.fetch(:id), body.fetch(:included).first.fetch(:id)

    localization = NovaStationPinballAscSetup.localization_attributes(
      "en-US", CONFIG.dig("leaderboards", 0, "localizations", "en-US")
    )
    assert_equal(
      "Highest score from a standard game. Runs using Workshop tools are excluded.",
      localization.fetch(:description)
    )
  end

  def test_apply_requires_an_explicit_or_environment_run_id
    assert_raises(NovaStationPinballAscSetup::SetupError) do
      NovaStationPinballAscSetup.apply_run_id!(nil, {})
    end
    assert_equal "manual-run", NovaStationPinballAscSetup.apply_run_id!(
      "manual-run", {}
    )
    assert_equal "release-run", NovaStationPinballAscSetup.apply_run_id!(
      nil, { "RELEASE_RUN_ID" => "release-run" }
    )
  end

  def test_apply_never_fabricates_a_candidate_from_configuration_bytes
    source = File.binread(
      File.join(File.expand_path("../..", __dir__), "scripts/app_store/setup_asc.rb")
    )
    refute_includes source, "Digest::SHA256.hexdigest(config_bytes)"
    assert_includes source,
                    "NovaStationPinballReleaseSupport.candidate_id!("
    assert_includes source,
                    "NovaStationPinballReleaseProvenance.verify_local!("
  end

  def test_apply_provisions_v2_leaderboard_and_localizations_then_reads_back_exactly
    client = ProvisionClient.new

    Dir.mktmpdir do |proof_root|
      result = NovaStationPinballAscSetup.provision!(
        client: client, config: CONFIG, proof_root: proof_root,
        candidate_id: "a" * 64, mutation_guard: -> {},
        release_identity: release_identity
      )

      assert_equal "apply_mode_with_durable_proofs", result.fetch("mutations")
      assert_equal ["leaderboard-version-1"],
                   result.fetch("game_center").map { |item| item.fetch("version_id") }
      assert_equal [
        "/v2/gameCenterLeaderboards",
        "/v2/gameCenterLeaderboardLocalizations",
        "/v2/gameCenterLeaderboardLocalizations"
      ], client.posts.map(&:first)
      localization_posts = client.posts.select do |path, _body|
        path == "/v2/gameCenterLeaderboardLocalizations"
      end
      assert_equal(
        [
          "Highest score from a standard game. Runs using Workshop tools are excluded.",
          "Meilleur score d’une partie standard. Les parties utilisant l’Atelier sont exclues."
        ],
        localization_posts.map { |_path, body| body.dig(:data, :attributes, :description) }
      )
      refute_includes client.posts.map(&:first),
                      "/v2/gameCenterLeaderboardVersions"
      assert_equal 3, Dir.glob(File.join(proof_root, "*-intent.json")).length
      assert_equal 3, Dir.glob(File.join(proof_root, "*-receipt.json")).length
      Dir.glob(File.join(proof_root, "*-intent.json")).each do |path|
        document = JSON.parse(File.binread(path))
        assert_equal release_identity, document.dig("payload", "release")
      end
      assert_empty client.patches
    end
  end

  def test_resource_appearance_during_mutation_preflight_blocks_the_post
    client = ProvisionClient.new
    injected = false
    guard = lambda do
      next if injected

      injected = true
      client.send(:seed_existing!, nil)
    end
    Dir.mktmpdir do |proof_root|
      assert_raises(NovaStationPinballReleaseSupport::PretransportFailure) do
        NovaStationPinballAscSetup.provision!(
          client: client, config: CONFIG, proof_root: proof_root,
          candidate_id: "a" * 64, mutation_guard: guard,
          release_identity: release_identity
        )
      end
    end
    assert_empty client.posts
  end

  def test_existing_intent_without_receipt_forces_get_only_and_never_posts
    client = ProvisionClient.new
    definition = CONFIG.fetch("leaderboards").first
    Dir.mktmpdir do |proof_root|
      identity = NovaStationPinballAscSetup.proof_identity(
        proof_root: proof_root,
        key: "leaderboard-#{definition.fetch('id')}",
        candidate_id: "a" * 64,
        version: CONFIG.fetch("version"),
        mutation_guard: -> {},
        release_identity: release_identity,
        payload: {
          "action" => "create_game_center_leaderboard_with_inline_version",
          "detail_id" => "detail-1",
          "vendor_identifier" => definition.fetch("id"),
          "attributes" => NovaStationPinballAscSetup
            .leaderboard_attributes(definition).transform_keys(&:to_s)
        }
      )
      NovaStationPinballReleaseSupport.transport_once!(
        **identity.merge(preflight: nil)
      ) {}
      tick = -1

      assert_raises(NovaStationPinballAscSetup::SetupError) do
        NovaStationPinballAscSetup.provision!(
          client: client, config: CONFIG, proof_root: proof_root,
          candidate_id: "a" * 64,
          mutation_guard: -> { raise "must stay GET-only" },
          release_identity: release_identity,
          timeout: 1, interval: 0.1,
          monotonic: -> { tick += 1 }, sleeper: ->(_seconds) {}
        )
      end

      assert_empty client.posts
      refute File.exist?(identity.fetch(:receipt_path))
    end
  end

  def test_inline_version_may_appear_late_but_is_never_posted_separately
    client = ProvisionClient.new(inline_delay_reads: 3)
    Dir.mktmpdir do |proof_root|
      NovaStationPinballAscSetup.provision!(
        client: client, config: CONFIG, proof_root: proof_root,
        candidate_id: "a" * 64, mutation_guard: -> {},
        release_identity: release_identity,
        timeout: 5, interval: 0.01,
        sleeper: ->(_seconds) {}
      )
    end

    assert_equal 1,
                 client.posts.count { |path, _body| path == "/v2/gameCenterLeaderboards" }
    assert_equal 0,
                 client.posts.count { |path, _body|
                   path == "/v2/gameCenterLeaderboardVersions"
                 }
  end

  def test_existing_leaderboard_or_localization_drift_never_patches
    %i[leaderboard localization].each do |drift|
      client = ProvisionClient.new(existing_drift: drift)
      Dir.mktmpdir do |proof_root|
        assert_raises(NovaStationPinballAscSetup::SetupError) do
          NovaStationPinballAscSetup.provision!(
            client: client, config: CONFIG, proof_root: proof_root,
            candidate_id: "a" * 64, mutation_guard: -> {},
            release_identity: release_identity
          )
        end
      end
      assert_empty client.posts
      assert_empty client.patches
    end
  end

  private

  def release_identity
    {
      "candidate_id" => "a" * 64,
      "run_id" => "test-run", "source_head" => "b" * 40,
      "version" => "1.0", "build" => "2", "asc_build_id" => "build-2",
      "uploaded_date" => "2026-08-24T00:29:40-07:00",
      "ipa_sha256" => "c" * 64
    }
  end

  def exact_app
    {
      "id" => "1234567890",
      "attributes" => {
        "name" => "Nova Station Pinball",
        "bundleId" => "com.bnjdpn.NovaStationPinball",
        "sku" => "nova-station-pinball-ios",
        "primaryLocale" => "en-US"
      }
    }
  end
end
