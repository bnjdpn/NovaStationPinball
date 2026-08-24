# frozen_string_literal: true

require "json"
require "minitest/autorun"
require_relative "game_center_contract"

class NovaStationPinballGameCenterContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  class FakeClient
    attr_reader :calls

    def initialize(detail: true, leaderboards: nil, versions: nil,
                   localizations: nil, app_version: :default,
                   related_app_version: :default)
      @detail = detail
      @leaderboards = leaderboards
      @versions = versions
      @localizations = localizations
      @app_version = app_version
      @related_app_version = related_app_version
      @calls = []
    end

    def get(path, parameters = {}, optional: false)
      @calls << [:get, path, parameters, optional]
      case path
      when "/v1/apps/app-1/gameCenterDetail"
        return nil unless @detail

        { "data" => { "type" => "gameCenterDetails", "id" => "detail-1" } }
      when "/v1/appStoreVersions/app-version-1/gameCenterAppVersion"
        return nil if @app_version.nil?

        { "data" => @app_version == :default ? exact_app_version : @app_version }
      when "/v1/gameCenterAppVersions/game-center-app-version-1/appStoreVersion"
        return nil if @related_app_version.nil?

        data = if @related_app_version == :default
                 {
                   "type" => "appStoreVersions",
                   "id" => "app-version-1",
                   "attributes" => {
                     "platform" => "IOS",
                     "versionString" => "1.0"
                   },
                   "relationships" => {
                     "app" => {
                       "data" => { "type" => "apps", "id" => "app-1" }
                     }
                   },
                   "links" => {
                     "self" =>
                       "https://api.appstoreconnect.apple.com/v1/" \
                       "appStoreVersions/app-version-1"
                   }
                 }
               else
                 @related_app_version
               end
        { "data" => data }
      else
        raise "unexpected GET #{path}"
      end
    end

    def get_all(path, parameters = {})
      @calls << [:get_all, path, parameters]
      case path
      when "/v1/gameCenterDetails/detail-1/gameCenterLeaderboardsV2"
        { "data" => @leaderboards || [leaderboard] }
      when "/v2/gameCenterLeaderboards/leaderboard-1/versions"
        version_resources
      else
        raise "unexpected GET collection #{path}"
      end
    end

    private

    def leaderboard
      {
        "type" => "gameCenterLeaderboards",
        "id" => "leaderboard-1",
        "attributes" => {
          "vendorIdentifier" => "com.bnjdpn.NovaStationPinball.score.high",
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

    def version_resources
      versions = @versions || [
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
      ]
      {
        "data" => versions,
        "included" => @localizations || [
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
      }
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

    def exact_app_version
      {
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
    end
  end

  def test_declared_contract_is_exact_and_classic
    definitions = NovaStationPinballGameCenterContract.declared(config)

    assert_equal ["com.bnjdpn.NovaStationPinball.score.high"],
                 config.fetch("leaderboard_ids")
    assert_equal 1, definitions.length
    definition = definitions.first
    assert_equal "Nova Station High Score", definition.fetch("reference_name")
    assert_equal "INTEGER", definition.fetch("default_formatter")
    assert_equal "BEST_SCORE", definition.fetch("submission_type")
    assert_equal "DESC", definition.fetch("score_sort_type")
    assert_equal 0, definition.fetch("score_range_start")
    assert_equal 999_999_999, definition.fetch("score_range_end")
    assert_nil definition.fetch("recurrence_start_date")
    assert_nil definition.fetch("recurrence_duration")
    assert_nil definition.fetch("recurrence_rule")
    assert_equal(
      "Highest score from a standard game. Runs using Workshop tools are excluded.",
      definition.dig("localizations", "en-US", "description")
    )
    assert_equal(
      "Meilleur score d’une partie standard. Les parties utilisant l’Atelier sont exclues.",
      definition.dig("localizations", "fr-FR", "description")
    )
  end

  def test_declared_contract_rejects_vendor_ids_outside_apples_character_set
    invalid = Marshal.load(Marshal.dump(config))
    invalid["leaderboard_ids"] = ["nova-station-high-score"]
    invalid.fetch("leaderboards").first["id"] = "nova-station-high-score"

    error = assert_raises(NovaStationPinballGameCenterContract::Error) do
      NovaStationPinballGameCenterContract.declared(invalid)
    end
    assert_match(/invalid id/, error.message)
  end

  def test_exact_vendor_version_attributes_and_localizations_resolve
    client = FakeClient.new

    records = NovaStationPinballGameCenterContract.resolve_reviewable_versions(
      client: client, app_id: "app-1", definitions: definitions
    )

    assert_equal 1, records.length
    record = records.first
    assert_equal "com.bnjdpn.NovaStationPinball.score.high",
                 record.fetch("vendor_id")
    assert_equal "leaderboard-version-1", record.fetch("version_id")
    assert_equal "READY_FOR_REVIEW", record.fetch("state")
    assert_equal %w[en-US fr-FR],
                 record.fetch("localizations").map { |item| item.fetch("locale") }
    catalogue_call = client.calls.find do |kind, path, _parameters|
      kind == :get_all && path.end_with?("/gameCenterLeaderboardsV2")
    end
    assert_includes catalogue_call.fetch(2).fetch("fields[gameCenterLeaderboards]"),
                    "vendorIdentifier"
    localization_call = client.calls.find do |kind, path, _parameters|
      kind == :get_all && path.end_with?("/versions")
    end
    assert_includes(
      localization_call.fetch(2).fetch("fields[gameCenterLeaderboardLocalizations]"),
      "description"
    )
  end

  def test_missing_detail_or_leaderboard_fails_closed
    assert_raises(NovaStationPinballGameCenterContract::Error) do
      resolve(FakeClient.new(detail: false))
    end
    assert_raises(NovaStationPinballGameCenterContract::Error) do
      resolve(FakeClient.new(leaderboards: []))
    end
  end

  def test_duplicate_vendor_identifier_fails_closed
    normal = FakeClient.new.send(:leaderboard)
    duplicate = Marshal.load(Marshal.dump(normal)).merge("id" => "leaderboard-2")

    error = assert_raises(NovaStationPinballGameCenterContract::Error) do
      resolve(FakeClient.new(leaderboards: [normal, duplicate]))
    end
    assert_match(/catalogue|exactly one/i, error.message)
  end

  def test_zero_or_multiple_reviewable_versions_fail_closed
    live = version("live", "LIVE")
    assert_raises(NovaStationPinballGameCenterContract::Error) do
      resolve(FakeClient.new(versions: [live]))
    end

    ready_a = version("ready-a", "READY_FOR_REVIEW")
    ready_b = version("ready-b", "PREPARE_FOR_SUBMISSION")
    error = assert_raises(NovaStationPinballGameCenterContract::Error) do
      resolve(FakeClient.new(versions: [ready_a, ready_b]))
    end
    assert_includes error.message, "found 2"
  end

  def test_attribute_or_localization_drift_fails_closed
    wrong_board = FakeClient.new.send(:leaderboard)
    wrong_board["attributes"]["scoreRangeEnd"] = "1000000000"
    assert_raises(NovaStationPinballGameCenterContract::Error) do
      resolve(FakeClient.new(leaderboards: [wrong_board]))
    end

    wrong_localizations = [
      FakeClient.new.send(
        :localization, "loc-en", "en-US", "Nova Station High Scores",
        "Wrong description", "points", "point"
      ),
      FakeClient.new.send(
        :localization, "loc-fr", "fr-FR", "Scores de Nova Station",
        "Meilleur score d’une partie standard. Les parties utilisant l’Atelier sont exclues.",
        "points", "point"
      )
    ]
    assert_raises(NovaStationPinballGameCenterContract::Error) do
      resolve(FakeClient.new(localizations: wrong_localizations))
    end
  end

  def test_localization_formatter_override_must_be_present_and_null
    exact = FakeClient.new
    missing = exact.send(
      :localization, "loc-en", "en-US", "Nova Station High Scores",
      "Highest score from a standard game. Runs using Workshop tools are excluded.",
      "points", "point"
    )
    missing.fetch("attributes").delete("formatterOverride")
    french = exact.send(
      :localization, "loc-fr", "fr-FR", "Scores de Nova Station",
      "Meilleur score d’une partie standard. Les parties utilisant l’Atelier sont exclues.",
      "points", "point"
    )
    assert_raises(NovaStationPinballGameCenterContract::Error) do
      resolve(FakeClient.new(localizations: [missing, french]))
    end

    overridden = exact.send(
      :localization, "loc-en", "en-US", "Nova Station High Scores",
      "Highest score from a standard game. Runs using Workshop tools are excluded.",
      "points", "point"
    )
    overridden.fetch("attributes")["formatterOverride"] = "INTEGER"
    assert_raises(NovaStationPinballGameCenterContract::Error) do
      resolve(FakeClient.new(localizations: [overridden, french]))
    end
  end

  def test_game_center_app_version_requires_enabled_exact_relationship
    exact = FakeClient.new
    record = NovaStationPinballGameCenterContract.app_version_enabled!(
      client: exact, app_store_version_id: "app-version-1"
    )
    assert_equal true, record.fetch("enabled")
    assert_equal "app-version-1", record.fetch("app_store_version_id")
    assert_equal 1, exact.calls.length

    assert_raises(NovaStationPinballGameCenterContract::Error) do
      NovaStationPinballGameCenterContract.app_version_enabled!(
        client: FakeClient.new(app_version: nil),
        app_store_version_id: "app-version-1"
      )
    end

    disabled = exact.send(:exact_app_version)
    disabled = Marshal.load(Marshal.dump(disabled))
    disabled.fetch("attributes")["enabled"] = false
    assert_raises(NovaStationPinballGameCenterContract::Error) do
      NovaStationPinballGameCenterContract.app_version_enabled!(
        client: FakeClient.new(app_version: disabled),
        app_store_version_id: "app-version-1"
      )
    end

    wrong = exact.send(:exact_app_version)
    wrong = Marshal.load(Marshal.dump(wrong))
    wrong.dig("relationships", "appStoreVersion", "data")["id"] = "other"
    assert_raises(NovaStationPinballGameCenterContract::Error) do
      NovaStationPinballGameCenterContract.app_version_enabled!(
        client: FakeClient.new(app_version: wrong),
        app_store_version_id: "app-version-1"
      )
    end
  end

  def test_game_center_app_version_resolves_exact_related_link_when_data_is_omitted
    client = FakeClient.new(app_version: app_version_with_related_link)

    record = NovaStationPinballGameCenterContract.app_version_enabled!(
      client: client, app_store_version_id: "app-version-1"
    )

    assert_equal true, record.fetch("enabled")
    assert_equal "app-version-1", record.fetch("app_store_version_id")
    assert_equal(
      "/v1/gameCenterAppVersions/game-center-app-version-1/appStoreVersion",
      client.calls.last.fetch(1)
    )
    assert_equal({}, client.calls.last.fetch(2))
    assert_equal true, client.calls.last.fetch(3)
  end

  def test_game_center_app_version_rejects_related_link_mismatch_without_following_it
    app_version = app_version_with_related_link
    app_version.dig("relationships", "appStoreVersion", "links")["related"] =
      "https://example.com/v1/gameCenterAppVersions/game-center-app-version-1/appStoreVersion"
    client = FakeClient.new(app_version: app_version)

    assert_raises(NovaStationPinballGameCenterContract::Error) do
      NovaStationPinballGameCenterContract.app_version_enabled!(
        client: client, app_store_version_id: "app-version-1"
      )
    end
    assert_equal 1, client.calls.length
  end

  def test_game_center_app_version_rejects_missing_or_malformed_related_link
    missing = app_version_with_related_link
    missing.dig("relationships", "appStoreVersion").delete("links")
    malformed = app_version_with_related_link
    malformed.dig("relationships", "appStoreVersion")["links"] = "not-a-link-object"

    [missing, malformed].each do |app_version|
      client = FakeClient.new(app_version: app_version)
      assert_raises(NovaStationPinballGameCenterContract::Error) do
        NovaStationPinballGameCenterContract.app_version_enabled!(
          client: client, app_store_version_id: "app-version-1"
        )
      end
      assert_equal 1, client.calls.length
    end
  end

  def test_game_center_app_version_rejects_malformed_resource_id_without_request
    app_version = app_version_with_related_link
    app_version["id"] = "../foreign-resource"
    client = FakeClient.new(app_version: app_version)

    assert_raises(NovaStationPinballGameCenterContract::Error) do
      NovaStationPinballGameCenterContract.app_version_enabled!(
        client: client, app_store_version_id: "app-version-1"
      )
    end
    assert_equal 1, client.calls.length
  end

  def test_game_center_app_version_rejects_invalid_related_readbacks
    invalid_readbacks = [
      nil,
      { "type" => "apps", "id" => "app-version-1" },
      { "type" => "appStoreVersions", "id" => "other-app-version" }
    ]

    invalid_readbacks.each do |related_app_version|
      client = FakeClient.new(
        app_version: app_version_with_related_link,
        related_app_version: related_app_version
      )

      assert_raises(NovaStationPinballGameCenterContract::Error) do
        NovaStationPinballGameCenterContract.app_version_enabled!(
          client: client, app_store_version_id: "app-version-1"
        )
      end
      assert_equal 2, client.calls.length
    end
  end

  private

  def config
    @config ||= JSON.parse(
      File.binread(File.join(ROOT, "fastlane", "release_config.json"))
    )
  end

  def definitions
    NovaStationPinballGameCenterContract.declared(config)
  end

  def resolve(client)
    NovaStationPinballGameCenterContract.resolve_reviewable_versions(
      client: client, app_id: "app-1", definitions: definitions
    )
  end

  def app_version_with_related_link
    app_version = FakeClient.new.send(:exact_app_version)
    relationship = app_version.dig("relationships", "appStoreVersion")
    relationship.delete("data")
    relationship["links"] = {
      "related" =>
        "https://api.appstoreconnect.apple.com/v1/gameCenterAppVersions/" \
        "game-center-app-version-1/appStoreVersion"
    }
    app_version
  end

  def version(id, state)
    {
      "type" => "gameCenterLeaderboardVersions",
      "id" => id,
      "attributes" => { "version" => "1", "state" => state },
      "relationships" => { "localizations" => { "data" => [] } }
    }
  end
end
