#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require_relative "game_center_contract"
require_relative "../../fastlane/release_support"

module NovaStationPinballAscSetup
  REQUIRED_FIELDS = {
    "name" => "app_store_name",
    "bundleId" => "bundle_id",
    "sku" => "sku",
    "primaryLocale" => "primary_locale"
  }.freeze

  class SetupError < StandardError; end

  module_function

  def expected_app_attributes(config)
    expected = REQUIRED_FIELDS.to_h do |attribute, config_key|
      value = config.fetch(config_key)
      unless value.instance_of?(String) && !value.empty?
        raise SetupError, "release configuration has an invalid #{config_key}"
      end
      [attribute, value]
    end
    expected
  end

  def matching_apps(client, expected)
    bundle_id = expected.fetch("bundleId")
    client.get_all("/v1/apps", {
      "filter[bundleId]" => bundle_id,
      "fields[apps]" => "name,bundleId,sku,primaryLocale,contentRightsDeclaration",
      "limit" => "20"
    }).fetch("data").select do |item|
      item.dig("attributes", "bundleId") == bundle_id
    end
  end

  def exact_app!(client, config)
    expected = expected_app_attributes(config)
    bundle_id = expected.fetch("bundleId")
    apps = matching_apps(client, expected)
    raise SetupError, "ASC app record is missing" if apps.empty?
    raise SetupError, "ASC app record is ambiguous" unless apps.length == 1

    app = apps.first
    mismatches = expected.map do |field, value|
      actual = app.dig("attributes", field)
      "#{field}=#{actual.inspect}" unless actual == value
    end.compact
    unless mismatches.empty?
      raise SetupError,
            "ASC app record differs from the release contract: #{mismatches.join(', ')}"
    end
    app
  end

  def exact_app_store_version!(client, app_id, version_string)
    versions = client.get_all(
      "/v1/apps/#{app_id}/appStoreVersions",
      {
        "filter[platform]" => "IOS",
        "filter[versionString]" => version_string,
        "fields[appStoreVersions]" => "versionString,appStoreState,platform",
        "limit" => "20"
      }
    ).fetch("data").select do |version|
      version.dig("attributes", "versionString").to_s == version_string.to_s &&
        version.dig("attributes", "platform").to_s == "IOS"
    end
    unless versions.length == 1
      raise SetupError,
            "Expected exactly one iOS App Store version #{version_string}, " \
            "found #{versions.length}"
    end

    versions.first
  end

  def inspect!(client:, config:, expectation:)
    unless %i[missing ready].include?(expectation)
      raise SetupError, "unsupported ASC setup expectation"
    end
    expected = expected_app_attributes(config)
    bundle_id = expected.fetch("bundleId")
    apps = matching_apps(client, expected)

    if expectation == :missing
      unless apps.empty?
        raise SetupError,
              "ASC app record must be exactly absent before the one-shot creation"
      end
      return {
        "status" => "missing",
        "bundle_id" => bundle_id,
        "mutations" => false
      }
    end

    app = exact_app!(client, config)
    definitions = NovaStationPinballGameCenterContract.declared(config)
    game_center =
      NovaStationPinballGameCenterContract.resolve_reviewable_versions(
        client: client, app_id: app.fetch("id"), definitions: definitions
      )
    app_store_version = exact_app_store_version!(
      client, app.fetch("id"), config.fetch("version")
    )
    game_center_app_version =
      NovaStationPinballGameCenterContract.app_version_enabled!(
        client: client, app_store_version_id: app_store_version.fetch("id")
      )
    {
      "status" => "ready",
      "app_id" => app.fetch("id"),
      "bundle_id" => bundle_id,
      "game_center" => game_center,
      "game_center_app_version" => game_center_app_version,
      "mutations" => false
    }
  rescue NovaStationPinballGameCenterContract::Error => error
    raise SetupError, error.message
  rescue KeyError => error
    raise SetupError, "ASC setup payload is incomplete: #{error.message}"
  end

  def leaderboard_attributes(definition)
    {
      referenceName: definition.fetch("reference_name"),
      vendorIdentifier: definition.fetch("id"),
      defaultFormatter: definition.fetch("default_formatter"),
      submissionType: definition.fetch("submission_type"),
      scoreSortType: definition.fetch("score_sort_type"),
      scoreRangeStart: definition.fetch("score_range_start"),
      scoreRangeEnd: definition.fetch("score_range_end"),
      visibility: "SHOW_FOR_ALL"
    }
  end

  def leaderboard_create_body(definition, detail_id, local_index)
    version_id = "${version-#{local_index}}"
    {
      data: {
        type: "gameCenterLeaderboards",
        attributes: leaderboard_attributes(definition),
        relationships: {
          gameCenterDetail: {
            data: { type: "gameCenterDetails", id: detail_id }
          },
          versions: {
            data: [{ type: "gameCenterLeaderboardVersions", id: version_id }]
          }
        }
      },
      included: [{ type: "gameCenterLeaderboardVersions", id: version_id }]
    }
  end

  def localization_attributes(locale, localization)
    {
      locale: locale,
      name: localization.fetch("name"),
      description: localization.fetch("description"),
      formatterSuffix: localization.fetch("suffix"),
      formatterSuffixSingular: localization.fetch("singular_suffix"),
      formatterOverride: nil
    }
  end

  def game_center_detail(client, app_id)
    response = client.get(
      "/v1/apps/#{app_id}/gameCenterDetail", {}, optional: true
    )
    response && response["data"]
  end

  def leaderboard_catalogue(client, detail_id)
    client.get_all(
      "/v1/gameCenterDetails/#{detail_id}/gameCenterLeaderboardsV2",
      {
        "fields[gameCenterLeaderboards]" =>
          "referenceName,vendorIdentifier,defaultFormatter,submissionType," \
          "scoreSortType,scoreRangeStart,scoreRangeEnd,recurrenceStartDate," \
          "recurrenceDuration,recurrenceRule,visibility,archived,versions",
        "limit" => "200"
      }
    ).fetch("data")
  end

  def versions_for_leaderboard(client, leaderboard_id)
    client.get_all(
      "/v2/gameCenterLeaderboards/#{leaderboard_id}/versions",
      {
        "include" => "localizations",
        "fields[gameCenterLeaderboardVersions]" => "version,state,localizations",
        "fields[gameCenterLeaderboardLocalizations]" =>
          "locale,name,description,formatterSuffix," \
          "formatterSuffixSingular,formatterOverride",
        "limit" => "200",
        "limit[localizations]" => "50"
      }
    )
  end

  def wait_until(timeout:, interval:,
                 monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                 sleeper: Kernel.method(:sleep))
    timeout = Float(timeout)
    interval = Float(interval)
    unless timeout.positive? && interval.positive?
      raise SetupError, "ASC setup timeout and interval must be positive"
    end
    deadline = monotonic.call + timeout
    loop do
      value = yield
      return value if value
      raise SetupError, "ASC setup GET readback timed out" if
        monotonic.call >= deadline

      sleeper.call(interval)
    end
  end

  def proof_identity(proof_root:, key:, candidate_id:, version:, payload:)
    unless key.to_s.match?(/\A[0-9A-Za-z][0-9A-Za-z._-]{2,127}\z/)
      raise SetupError, "Invalid ASC setup mutation key"
    end
    {
      intent_path: File.join(proof_root, "#{key}-intent.json"),
      receipt_path: File.join(proof_root, "#{key}-receipt.json"),
      kind: "setup_asc",
      candidate_id: candidate_id,
      version: version,
      payload: payload
    }
  end

  def apply_run_id!(explicit, environment = ENV)
    raw_run_id = explicit.to_s
    raw_run_id = environment["RELEASE_RUN_ID"].to_s if raw_run_id.empty?
    raw_run_id = environment["APP_RELEASE_RUN_ID"].to_s if raw_run_id.empty?
    if raw_run_id.empty?
      raise SetupError,
            "--apply requires --run-id, RELEASE_RUN_ID or APP_RELEASE_RUN_ID"
    end
    NovaStationPinballReleaseSupport.run_id!(raw_run_id)
  end

  def create_once_and_observe!(proof, confirmation)
    begin
      NovaStationPinballReleaseSupport.transport_once!(**proof) { yield }
    rescue NovaStationPinballReleaseSupport::AmbiguousTransport
      # The exclusive intent already exists. Recovery is GET-only from here;
      # never retry a transport whose response may merely have been lost.
    end
    observed = confirmation.call
    NovaStationPinballReleaseSupport.mark_observed!(**proof)
    observed
  end

  def ensure_game_center_detail!(client, app_id, proof_context,
                                 timeout:, interval:, monotonic:, sleeper:)
    detail = game_center_detail(client, app_id)
    return detail if detail

    proof = proof_identity(
      **proof_context,
      key: "game-center-detail",
      payload: { "action" => "create_game_center_detail", "app_id" => app_id }
    )
    create_once_and_observe!(
      proof,
      lambda do
        wait_until(
          timeout: timeout, interval: interval,
          monotonic: monotonic, sleeper: sleeper
        ) { game_center_detail(client, app_id) }
      end
    ) do
      client.post("/v1/gameCenterDetails", {
        data: {
          type: "gameCenterDetails",
          relationships: {
            app: { data: { type: "apps", id: app_id } }
          }
        }
      })
    end
  end

  def reviewable_inline_version(client, leaderboard_id, vendor_id)
    payload = versions_for_leaderboard(client, leaderboard_id)
    versions = payload.fetch("data").select do |version|
      version["type"] == "gameCenterLeaderboardVersions" &&
        NovaStationPinballGameCenterContract::REVIEWABLE_VERSION_STATES.include?(
          version.dig("attributes", "state")
        )
    end
    if versions.length > 1
      raise SetupError,
            "Game Center inline version is ambiguous for #{vendor_id}: " \
            + versions.length.to_s
    end
    return nil if versions.empty?

    [versions.first, payload]
  end

  def wait_for_inline_version!(client, leaderboard, definition,
                               timeout:, interval:, monotonic:, sleeper:)
    NovaStationPinballGameCenterContract.validate_leaderboard!(
      leaderboard, definition
    )
    wait_until(
      timeout: timeout, interval: interval,
      monotonic: monotonic, sleeper: sleeper
    ) do
      reviewable_inline_version(
        client, leaderboard.fetch("id"), definition.fetch("id")
      )
    end
  end

  def wait_for_leaderboard_and_inline_version!(client, detail_id, definition,
                                               timeout:, interval:,
                                               monotonic:, sleeper:)
    wait_until(
      timeout: timeout, interval: interval,
      monotonic: monotonic, sleeper: sleeper
    ) do
      matches = leaderboard_catalogue(client, detail_id).select do |leaderboard|
        leaderboard.dig("attributes", "vendorIdentifier") ==
          definition.fetch("id")
      end
      raise SetupError, "Game Center leaderboard is ambiguous" if matches.length > 1
      next if matches.empty?

      leaderboard = matches.first
      NovaStationPinballGameCenterContract.validate_leaderboard!(
        leaderboard, definition
      )
      pair = reviewable_inline_version(
        client, leaderboard.fetch("id"), definition.fetch("id")
      )
      next unless pair

      [leaderboard, pair.fetch(0), pair.fetch(1)]
    end
  end

  def localization_index!(version, payload, definition)
    included = payload.fetch("included", [])
    links = version.dig("relationships", "localizations", "data") || []
    by_locale = {}
    links.each do |link|
      unless link.fetch("type") == "gameCenterLeaderboardLocalizations"
        raise SetupError, "Game Center localization linkage has an invalid type"
      end
      resource = included.find do |candidate|
        candidate["type"] == link["type"] && candidate["id"] == link["id"]
      end
      raise SetupError, "Game Center localization linkage is unreadable" unless resource
      unless resource.fetch("type") == "gameCenterLeaderboardLocalizations"
        raise SetupError, "Game Center localization has an invalid type"
      end

      locale = resource.dig("attributes", "locale")
      raise SetupError, "Game Center localization has no locale" if locale.to_s.empty?
      raise SetupError, "Game Center localization is ambiguous: #{locale}" if
        by_locale.key?(locale)
      by_locale[locale] = resource
    end
    unexpected = by_locale.keys - definition.fetch("localizations").keys
    unless unexpected.empty?
      raise SetupError,
            "Unexpected Game Center leaderboard localizations: #{unexpected.join(',')}"
    end
    by_locale
  end

  def exact_localization?(resource, locale, localization)
    desired = localization_attributes(locale, localization)
    attributes = resource.fetch("attributes", {})
    desired.all? do |key, value|
      attributes.key?(key.to_s) && attributes[key.to_s] == value
    end
  end

  def wait_for_localization!(client, leaderboard_id, version_id, definition,
                             locale, localization, timeout:, interval:,
                             monotonic:, sleeper:)
    wait_until(
      timeout: timeout, interval: interval,
      monotonic: monotonic, sleeper: sleeper
    ) do
      payload = versions_for_leaderboard(client, leaderboard_id)
      version = payload.fetch("data").find { |item| item.fetch("id") == version_id }
      next unless version

      resource = localization_index!(version, payload, definition)[locale]
      next unless resource
      unless exact_localization?(resource, locale, localization)
        raise SetupError,
              "Existing Game Center localization differs from release_config: " \
              "#{definition.fetch('id')}:#{locale}"
      end
      resource
    end
  end

  def ensure_localizations!(client, leaderboard, version, payload, definition,
                            proof_context, timeout:, interval:, monotonic:, sleeper:)
    by_locale = localization_index!(version, payload, definition)
    definition.fetch("localizations").each do |locale, localization|
      existing = by_locale[locale]
      if existing
        unless exact_localization?(existing, locale, localization)
          raise SetupError,
                "Existing Game Center localization differs from release_config: " \
                "#{definition.fetch('id')}:#{locale}"
        end
        next
      end

      proof = proof_identity(
        **proof_context,
        key: "leaderboard-localization-#{definition.fetch('id')}-#{locale}",
        payload: {
          "action" => "create_game_center_localization",
          "leaderboard_id" => leaderboard.fetch("id"),
          "version_id" => version.fetch("id"),
          "vendor_identifier" => definition.fetch("id"),
          "locale" => locale,
          "attributes" => localization_attributes(locale, localization)
            .transform_keys(&:to_s)
        }
      )
      create_once_and_observe!(
        proof,
        lambda do
          wait_for_localization!(
            client, leaderboard.fetch("id"), version.fetch("id"), definition,
            locale, localization, timeout: timeout, interval: interval,
            monotonic: monotonic, sleeper: sleeper
          )
        end
      ) do
        client.post("/v2/gameCenterLeaderboardLocalizations", {
          data: {
            type: "gameCenterLeaderboardLocalizations",
            attributes: localization_attributes(locale, localization),
            relationships: {
              version: {
                data: {
                  type: "gameCenterLeaderboardVersions", id: version.fetch("id")
                }
              }
            }
          }
        })
      end
      payload = versions_for_leaderboard(client, leaderboard.fetch("id"))
      version_id = version.fetch("id")
      version = payload.fetch("data").find do |item|
        item.fetch("id") == version_id
      end
      raise SetupError, "Game Center inline version disappeared" unless version

      by_locale = localization_index!(version, payload, definition)
    end
  end

  def provision_game_center!(client:, app_id:, config:, proof_context:,
                             timeout:, interval:,
                             monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                             sleeper: Kernel.method(:sleep))
    definitions = NovaStationPinballGameCenterContract.declared(config)
    detail = ensure_game_center_detail!(
      client, app_id, proof_context, timeout: timeout, interval: interval,
      monotonic: monotonic, sleeper: sleeper
    )
    leaderboards = leaderboard_catalogue(client, detail.fetch("id"))
    expected_ids = definitions.map { |definition| definition.fetch("id") }
    unexpected = leaderboards.reject do |leaderboard|
      expected_ids.include?(leaderboard.dig("attributes", "vendorIdentifier"))
    end
    unless unexpected.empty?
      ids = unexpected.map do |leaderboard|
        leaderboard.dig("attributes", "vendorIdentifier").inspect
      end
      raise SetupError, "Unexpected Game Center leaderboards: #{ids.join(',')}"
    end

    definitions.each_with_index do |definition, index|
      matches = leaderboards.select do |leaderboard|
        leaderboard.dig("attributes", "vendorIdentifier") == definition.fetch("id")
      end
      if matches.length > 1
        raise SetupError,
              "Game Center leaderboard is ambiguous: #{definition.fetch('id')}"
      end
      if matches.empty?
        proof = proof_identity(
          **proof_context,
          key: "leaderboard-#{definition.fetch('id')}",
          payload: {
            "action" => "create_game_center_leaderboard_with_inline_version",
            "detail_id" => detail.fetch("id"),
            "vendor_identifier" => definition.fetch("id"),
            "attributes" => leaderboard_attributes(definition)
              .transform_keys(&:to_s)
          }
        )
        triple = create_once_and_observe!(
          proof,
          lambda do
            wait_for_leaderboard_and_inline_version!(
              client, detail.fetch("id"), definition,
              timeout: timeout, interval: interval,
              monotonic: monotonic, sleeper: sleeper
            )
          end
        ) do
          client.post(
            "/v2/gameCenterLeaderboards",
            leaderboard_create_body(definition, detail.fetch("id"), index)
          )
        end
        leaderboard, version, payload = triple
      else
        leaderboard = matches.first
        version, payload = wait_for_inline_version!(
          client, leaderboard, definition,
          timeout: timeout, interval: interval,
          monotonic: monotonic, sleeper: sleeper
        )
      end
      ensure_localizations!(
        client, leaderboard, version, payload, definition, proof_context,
        timeout: timeout, interval: interval,
        monotonic: monotonic, sleeper: sleeper
      )
      leaderboards = leaderboard_catalogue(client, detail.fetch("id"))
    end

    NovaStationPinballGameCenterContract.resolve_reviewable_versions(
      client: client, app_id: app_id, definitions: definitions
    )
  end

  def provision!(client:, config:, proof_root:, candidate_id:,
                 timeout: 60, interval: 1,
                 monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                 sleeper: Kernel.method(:sleep))
    app = exact_app!(client, config)
    proof_context = {
      proof_root: proof_root,
      candidate_id: candidate_id,
      version: config.fetch("version")
    }
    provision_game_center!(
      client: client, app_id: app.fetch("id"), config: config,
      proof_context: proof_context, timeout: timeout, interval: interval,
      monotonic: monotonic, sleeper: sleeper
    )
    result = inspect!(client: client, config: config, expectation: :ready)
    result.merge("mutations" => "apply_mode_with_durable_proofs")
  rescue NovaStationPinballGameCenterContract::Error => error
    raise SetupError, error.message
  rescue KeyError => error
    raise SetupError, "ASC provisioning payload is incomplete: #{error.message}"
  end

  module CLI
    module_function

    def run(argv)
      require_relative "client"
      app_root = File.expand_path("../..", __dir__)
      options = {
        config: File.join(app_root, "fastlane", "release_config.json"),
        key_path: ENV["ASC_API_KEY_PATH"],
        expectation: :ready,
        timeout: 60.0,
        interval: 1.0
      }
      OptionParser.new do |parser|
        parser.on("--config PATH") { |value| options[:config] = value }
        parser.on("--key-path PATH") { |value| options[:key_path] = value }
        parser.on("--run-id ID") { |value| options[:run_id] = value }
        parser.on("--timeout SECONDS", Float) { |value| options[:timeout] = value }
        parser.on("--interval SECONDS", Float) { |value| options[:interval] = value }
        parser.on("--expect-missing") { options[:expectation] = :missing }
        parser.on("--apply") { options[:apply] = true }
      end.parse!(argv)

      config_bytes = File.binread(options.fetch(:config))
      config = JSON.parse(config_bytes)
      if options[:apply] && options.fetch(:expectation) == :missing
        raise SetupError, "--apply cannot be combined with --expect-missing"
      end
      if options.fetch(:timeout) <= 0 || options.fetch(:interval) <= 0
        raise SetupError, "--timeout and --interval must be positive"
      end
      client = NovaStationPinballAscClient.new(
        key_path: options.fetch(:key_path)
      )
      result = if options[:apply]
                 run_id = NovaStationPinballAscSetup.apply_run_id!(
                   options[:run_id], ENV
                 )
                 artifact_root = File.expand_path(
                   config.fetch("artifact_root"), app_root
                 )
                 unless artifact_root.start_with?("#{app_root}/")
                   raise SetupError, "artifact_root escapes the app repository"
                 end
                 proof_root = File.join(
                   artifact_root, run_id, "logs", "setup-asc"
                 )
                 candidate_id = ENV["APPS_FACTORY_CANDIDATE_ID"].to_s
                 candidate_id = Digest::SHA256.hexdigest(config_bytes) if
                   candidate_id.empty?
                 NovaStationPinballAscSetup.provision!(
                   client: client, config: config,
                   proof_root: proof_root, candidate_id: candidate_id,
                   timeout: options.fetch(:timeout),
                   interval: options.fetch(:interval)
                 )
               else
                 NovaStationPinballAscSetup.inspect!(
                   client: client, config: config,
                   expectation: options.fetch(:expectation)
                 )
               end
      puts JSON.pretty_generate(
        result
      )
      0
    rescue ArgumentError, KeyError, JSON::ParserError, OptionParser::ParseError,
           NovaStationPinballAscSetup::SetupError,
           NovaStationPinballGameCenterContract::Error,
           NovaStationPinballAscError => error
      warn "setup_asc: #{error.message}"
      1
    end
  end
end

exit NovaStationPinballAscSetup::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
