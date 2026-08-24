# frozen_string_literal: true

module NovaStationPinballGameCenterContract
  class Error < RuntimeError; end

  ASC_API_BASE_URL = "https://api.appstoreconnect.apple.com".freeze
  RESOURCE_ID_PATTERN = /\A[A-Za-z0-9-]+\z/
  REVIEWABLE_VERSION_STATES = %w[
    PREPARE_FOR_SUBMISSION READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW
    ACCEPTED PENDING_RELEASE
  ].freeze
  DEFINITION_KEYS = %w[
    id reference_name default_formatter submission_type score_sort_type
    score_range_start score_range_end recurrence_start_date
    recurrence_duration recurrence_rule localizations
  ].freeze
  LOCALIZATION_KEYS = %w[description name suffix singular_suffix].freeze

  module_function

  def declared(config)
    ids = config.fetch("leaderboard_ids")
    definitions = config.fetch("leaderboards")
    raise Error, "leaderboard_ids must be a non-empty array" unless
      ids.is_a?(Array) && !ids.empty?
    raise Error, "leaderboards must be a non-empty array" unless
      definitions.is_a?(Array) && !definitions.empty?

    definitions.each_with_index do |definition, index|
      unless definition.is_a?(Hash) && definition.keys.sort == DEFINITION_KEYS.sort
        raise Error, "leaderboard definition #{index} has an invalid shape"
      end
      %w[id reference_name default_formatter submission_type score_sort_type].each do |key|
        raise Error, "leaderboard definition #{index} has an empty #{key}" if
          definition.fetch(key).to_s.strip.empty?
      end
      %w[score_range_start score_range_end].each do |key|
        value = definition.fetch(key)
        raise Error, "leaderboard definition #{index} has an invalid #{key}" unless
          value.is_a?(Integer)
      end
      unless definition.fetch("score_range_start") <= definition.fetch("score_range_end")
        raise Error, "leaderboard definition #{index} has an inverted score range"
      end
      unless %w[recurrence_start_date recurrence_duration recurrence_rule].all? do |key|
        definition.fetch(key).nil?
      end
        raise Error, "leaderboard definition #{index} must be classic, not recurring"
      end

      localizations = definition.fetch("localizations")
      expected_locales = config.fetch("locales").sort
      unless localizations.is_a?(Hash) && localizations.keys.sort == expected_locales
        raise Error, "leaderboard definition #{index} must localize every release locale exactly"
      end
      localizations.each do |locale, localization|
        unless localization.is_a?(Hash) &&
               localization.keys.sort == LOCALIZATION_KEYS.sort &&
               localization.values.all? { |value| !value.to_s.strip.empty? }
          raise Error, "leaderboard localization #{locale} has an invalid shape"
        end
      end
    end

    definition_ids = definitions.map { |definition| definition.fetch("id") }
    raise Error, "leaderboard ids must be unique" unless
      definition_ids.uniq.length == definition_ids.length && ids.uniq.length == ids.length
    unless ids == definition_ids
      raise Error, "leaderboard_ids must mirror leaderboards in release order"
    end

    definitions
  rescue KeyError => error
    raise Error, "invalid Game Center release contract: #{error.message}"
  end

  def resolve_reviewable_versions(client:, app_id:, definitions:)
    detail_response = client.get(
      "/v1/apps/#{app_id}/gameCenterDetail", {}, optional: true
    )
    detail = detail_response && detail_response["data"]
    raise Error, "Game Center detail is not configured" unless detail

    leaderboards = client.get_all(
      "/v1/gameCenterDetails/#{detail.fetch('id')}/gameCenterLeaderboardsV2",
      {
        "fields[gameCenterLeaderboards]" =>
          "referenceName,vendorIdentifier,defaultFormatter,submissionType," \
          "scoreSortType,scoreRangeStart,scoreRangeEnd,recurrenceStartDate," \
          "recurrenceDuration,recurrenceRule,visibility,archived,versions",
        "limit" => "200"
      }
    ).fetch("data")
    expected_ids = definitions.map { |definition| definition.fetch("id") }
    actual_ids = leaderboards.map do |leaderboard|
      leaderboard.dig("attributes", "vendorIdentifier")
    end
    unless actual_ids.length == expected_ids.length &&
           actual_ids.compact.sort == expected_ids.sort
      missing = expected_ids - actual_ids
      unexpected = actual_ids - expected_ids
      raise Error,
            "Game Center leaderboard catalogue differs from release_config " \
            "(missing=#{missing.join(',')}; unexpected=#{unexpected.compact.join(',')})"
    end

    definitions.map do |definition|
      vendor_id = definition.fetch("id")
      matches = leaderboards.select do |leaderboard|
        leaderboard.dig("attributes", "vendorIdentifier") == vendor_id
      end
      unless matches.length == 1
        raise Error,
              "Expected exactly one Game Center leaderboard for #{vendor_id}, " \
              "found #{matches.length}"
      end

      leaderboard = matches.first
      validate_leaderboard!(leaderboard, definition)
      version_response = client.get_all(
        "/v2/gameCenterLeaderboards/#{leaderboard.fetch('id')}/versions",
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
      reviewable = version_response.fetch("data").select do |version|
        version["type"] == "gameCenterLeaderboardVersions" &&
          REVIEWABLE_VERSION_STATES.include?(version.dig("attributes", "state"))
      end
      unless reviewable.length == 1
        states = version_response.fetch("data").map do |version|
          "#{version.fetch('id')}:#{version.dig('attributes', 'state')}"
        end
        raise Error,
              "Expected exactly one reviewable Game Center leaderboard version " \
              "for #{vendor_id}, found #{reviewable.length} (#{states.join(',')})"
      end

      version = reviewable.first
      localizations = resolve_localizations!(version_response, version, definition)
      {
        "vendor_id" => vendor_id,
        "leaderboard_id" => leaderboard.fetch("id"),
        "version_id" => version.fetch("id"),
        "version" => version.dig("attributes", "version"),
        "state" => version.dig("attributes", "state"),
        "reference_name" => leaderboard.dig("attributes", "referenceName"),
        "default_formatter" => leaderboard.dig("attributes", "defaultFormatter"),
        "submission_type" => leaderboard.dig("attributes", "submissionType"),
        "score_sort_type" => leaderboard.dig("attributes", "scoreSortType"),
        "score_range_start" => integer_attribute!(leaderboard, "scoreRangeStart"),
        "score_range_end" => integer_attribute!(leaderboard, "scoreRangeEnd"),
        "localizations" => localizations
      }
    end
  rescue KeyError => error
    raise Error, "Invalid Game Center readback: #{error.message}"
  end

  def validate_leaderboard!(leaderboard, definition)
    vendor_id = definition.fetch("id")
    unless leaderboard.fetch("type") == "gameCenterLeaderboards"
      raise Error, "Game Center leaderboard has an invalid resource type: #{vendor_id}"
    end
    if leaderboard.dig("attributes", "archived") != false
      raise Error, "Game Center leaderboard is archived or unreadable: #{vendor_id}"
    end
    expected = {
      "vendorIdentifier" => vendor_id,
      "referenceName" => definition.fetch("reference_name"),
      "defaultFormatter" => definition.fetch("default_formatter"),
      "submissionType" => definition.fetch("submission_type"),
      "scoreSortType" => definition.fetch("score_sort_type"),
      "scoreRangeStart" => definition.fetch("score_range_start"),
      "scoreRangeEnd" => definition.fetch("score_range_end"),
      "recurrenceStartDate" => definition.fetch("recurrence_start_date"),
      "recurrenceDuration" => definition.fetch("recurrence_duration"),
      "recurrenceRule" => definition.fetch("recurrence_rule"),
      "visibility" => "SHOW_FOR_ALL"
    }
    mismatches = expected.map do |attribute, value|
      actual = if %w[scoreRangeStart scoreRangeEnd].include?(attribute)
                 integer_attribute!(leaderboard, attribute)
               else
                 leaderboard.dig("attributes", attribute)
               end
      attribute unless actual == value
    end.compact
    return if mismatches.empty?

    raise Error,
          "Game Center leaderboard configuration mismatch for #{vendor_id}: " +
          mismatches.join(",")
  end

  def integer_attribute!(resource, attribute)
    value = resource.dig("attributes", attribute)
    raise Error, "Game Center #{attribute} is missing" if value.nil?

    Integer(value.to_s, 10)
  rescue ArgumentError
    raise Error, "Game Center #{attribute} is not an integer: #{value.inspect}"
  end

  def resolve_localizations!(response, version, definition)
    included = response.fetch("included", []).each_with_object({}) do |resource, index|
      index[[resource.fetch("type"), resource.fetch("id")]] = resource
    end
    links = version.dig("relationships", "localizations", "data") || []
    resources = links.map do |link|
      unless link.fetch("type") == "gameCenterLeaderboardLocalizations"
        raise Error, "Game Center localization linkage has an invalid resource type"
      end
      resource = included[[link.fetch("type"), link.fetch("id")]]
      raise Error, "Game Center localization linkage has no included resource" unless resource
      unless resource.fetch("type") == "gameCenterLeaderboardLocalizations"
        raise Error, "Game Center localization has an invalid resource type"
      end

      resource
    end
    locales = resources.map { |resource| resource.dig("attributes", "locale") }
    expected = definition.fetch("localizations")
    unless locales.length == locales.uniq.length && locales.sort == expected.keys.sort
      raise Error,
            "Game Center leaderboard localization catalogue differs for " \
            "#{definition.fetch('id')}"
    end

    resources.sort_by { |resource| resource.dig("attributes", "locale").to_s }.map do |resource|
      locale = resource.dig("attributes", "locale")
      expected_localization = expected.fetch(locale)
      attributes = resource.fetch("attributes")
      unless attributes.key?("formatterOverride") &&
             attributes["formatterOverride"].nil?
        raise Error,
              "Game Center leaderboard localization formatter override must " \
              "be explicitly null for #{definition.fetch('id')}:#{locale}"
      end
      actual = {
        "name" => attributes["name"],
        "description" => attributes["description"],
        "suffix" => attributes["formatterSuffix"],
        "singular_suffix" =>
          attributes["formatterSuffixSingular"],
        "formatter_override" => attributes["formatterOverride"]
      }
      expected_readback = expected_localization.merge("formatter_override" => nil)
      unless actual == expected_readback
        raise Error,
              "Game Center leaderboard localization mismatch for " \
              "#{definition.fetch('id')}:#{locale}"
      end
      actual.merge("locale" => locale)
    end
  end

  def app_version_enabled!(client:, app_store_version_id:)
    response = client.get(
      "/v1/appStoreVersions/#{app_store_version_id}/gameCenterAppVersion",
      {
        "fields[gameCenterAppVersions]" => "enabled,appStoreVersion"
      },
      optional: true
    )
    resource = response && response["data"]
    raise Error, "Game Center is not configured for App Store version" unless resource
    unless resource.is_a?(Hash) &&
           resource["type"] == "gameCenterAppVersions" &&
           resource.dig("attributes", "enabled") == true
      raise Error, "Game Center is not enabled for App Store version"
    end
    expected = {
      "type" => "appStoreVersions", "id" => app_store_version_id
    }
    relationship_container = resource.dig("relationships", "appStoreVersion")
    unless relationship_container.is_a?(Hash)
      raise Error, "Game Center app version relationship is missing or malformed"
    end

    relationship = relationship_container["data"]
    if relationship.nil?
      game_center_app_version_id = resource.fetch("id")
      unless game_center_app_version_id.is_a?(String) &&
             RESOURCE_ID_PATTERN.match?(game_center_app_version_id)
        raise Error, "Game Center app-version ID is invalid"
      end

      related_path =
        "/v1/gameCenterAppVersions/#{game_center_app_version_id}/appStoreVersion"
      expected_related = "#{ASC_API_BASE_URL}#{related_path}"
      links = relationship_container["links"]
      related = links["related"] if links.is_a?(Hash)
      unless related == expected_related
        raise Error,
              "Game Center app version related link is missing or does not match " \
              "#{game_center_app_version_id}"
      end

      related_response = client.get(related_path, {}, optional: true)
      relationship = related_response && related_response["data"]
    end
    unless relationship.is_a?(Hash) &&
           relationship["type"] == expected.fetch("type") &&
           relationship["id"] == expected.fetch("id")
      raise Error,
            "Game Center app version relationship does not match " \
            "#{app_store_version_id}"
    end

    {
      "id" => resource.fetch("id"),
      "enabled" => true,
      "app_store_version_id" => app_store_version_id
    }
  rescue KeyError => error
    raise Error, "Invalid Game Center app-version readback: #{error.message}"
  end
end
