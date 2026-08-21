#!/usr/bin/env ruby
# frozen_string_literal: true

require "bigdecimal"
require "json"
require "optparse"
require "time"
require_relative "client"
require_relative "metadata_readback"
require_relative "../../fastlane/release_support"

module NovaStationPinballAscStatus
  APP_ROOT = File.expand_path("../..", __dir__)
  SCREENSHOTS_PER_LOCALE = 18
  PREVIEWS_PER_LOCALE = 3
  SUBMITTED_STATES = %w[
    WAITING_FOR_REVIEW IN_REVIEW UNRESOLVED_ISSUES
  ].freeze

  module_function

  def load_config(path)
    unless File.file?(path) && !File.symlink?(path)
      raise ArgumentError, "Release config must be a regular file: #{path}"
    end
    JSON.parse(File.binread(path))
  rescue JSON::ParserError => error
    raise ArgumentError, "Invalid release config: #{error.message}"
  end

  def find_app(client, bundle_id)
    items = client.get_all("/v1/apps", {
      "filter[bundleId]" => bundle_id,
      "fields[apps]" =>
        "name,bundleId,sku,primaryLocale,contentRightsDeclaration",
      "limit" => "20"
    }).fetch("data").select do |item|
      item.dig("attributes", "bundleId") == bundle_id
    end
    raise "Expected exactly one app for #{bundle_id}, found #{items.length}" unless
      items.length == 1

    items.first
  end

  def versions(client, app_id, requested_version)
    response = client.get_all("/v1/apps/#{app_id}/appStoreVersions", {
      "filter[platform]" => "IOS",
      "filter[versionString]" => requested_version,
      "include" => "build",
      "fields[appStoreVersions]" =>
        "versionString,appStoreState,createdDate,copyright,releaseType,build",
      "fields[builds]" =>
        "version,processingState,uploadedDate,expired,usesNonExemptEncryption",
      "limit" => "20"
    })
    selected = response.fetch("data").select do |item|
      item.dig("attributes", "versionString").to_s == requested_version.to_s
    end
    raise "App Store version #{requested_version} is ambiguous" if selected.length > 1

    [selected.first, included_index(response.fetch("included", []))]
  end

  def included_index(items)
    items.each_with_object({}) do |item, index|
      index[[item.fetch("type"), item.fetch("id")]] = item
    end
  end

  def build_payload(build)
    return nil unless build

    {
      "id" => build.fetch("id"),
      "build" => build.dig("attributes", "version").to_s,
      "state" => build.dig("attributes", "processingState"),
      "uploaded" => build.dig("attributes", "uploadedDate"),
      "expired" => build.dig("attributes", "expired"),
      "uses_non_exempt_encryption" =>
        build.dig("attributes", "usesNonExemptEncryption")
    }
  end

  def selected_build(client, version, included)
    return nil unless version

    build_id = version.dig("relationships", "build", "data", "id")
    return nil unless build_id
    build = included[["builds", build_id]]
    unless build
      response = client.get(
        "/v1/appStoreVersions/#{version.fetch('id')}/build",
        {
          "fields[builds]" =>
            "version,processingState,uploadedDate,expired,usesNonExemptEncryption"
        },
        optional: true
      )
      build = response && response["data"]
    end
    build_payload(build)
  end

  def recent_builds(client, app_id, marketing_version)
    client.get_all("/v1/builds", {
      "filter[app]" => app_id,
      "filter[preReleaseVersion.version]" => marketing_version,
      "filter[preReleaseVersion.platform]" => "IOS",
      "sort" => "-uploadedDate",
      "fields[builds]" =>
        "version,processingState,uploadedDate,expired,usesNonExemptEncryption",
      "limit" => "200"
    }).fetch("data").map { |build| build_payload(build) }
  end

  def review_submissions(client, app_id)
    client.get_all("/v1/apps/#{app_id}/reviewSubmissions", {
      "fields[reviewSubmissions]" => "state,submittedDate,platform",
      "limit" => "50"
    }).fetch("data").map do |submission|
      items = client.get_all(
        "/v1/reviewSubmissions/#{submission.fetch('id')}/items",
        {
          "include" => "appStoreVersion,inAppPurchaseVersion",
          "fields[reviewSubmissionItems]" =>
            "state,appStoreVersion,inAppPurchaseVersion",
          "fields[appStoreVersions]" => "versionString,appStoreState,platform",
          "fields[inAppPurchaseVersions]" => "version,state",
          "limit" => "200"
        }
      )
      included = included_index(items.fetch("included", []))
      {
        "id" => submission.fetch("id"),
        "state" => submission.dig("attributes", "state"),
        "submitted" => submission.dig("attributes", "submittedDate"),
        "items" => items.fetch("data").map do |item|
          app_version = item.dig(
            "relationships", "appStoreVersion", "data"
          )
          iap_version = item.dig(
            "relationships", "inAppPurchaseVersion", "data"
          )
          version_resource = app_version &&
            included[[app_version.fetch("type"), app_version.fetch("id")]]
          {
            "id" => item.fetch("id"),
            "state" => item.dig("attributes", "state"),
            "resource_type" => (app_version || iap_version)&.fetch("type", nil),
            "resource_id" => (app_version || iap_version)&.fetch("id", nil),
            "version" => version_resource&.dig("attributes", "versionString")
          }
        end
      }
    end
  end

  def delivery(client, path, fields_key, state_key)
    items = client.get_all(path, {
      fields_key => "fileName,#{state_key}",
      "limit" => "200"
    }).fetch("data")
    states = items.map do |item|
      state = item.dig("attributes", state_key, "state")
      {
        "id" => item.fetch("id"),
        "file_name" => item.dig("attributes", "fileName"),
        "state" => state,
        "errors" => item.dig("attributes", state_key, "errors") || []
      }
    end
    {
      "total_count" => states.length,
      "complete_count" => states.count { |item| item["state"] == "COMPLETE" },
      "failed" => states.select { |item| item["state"] == "FAILED" },
      "states" => states
    }
  end

  def assets(client, version, expected_locales)
    return empty_assets unless version

    localizations = client.get_all(
      "/v1/appStoreVersions/#{version.fetch('id')}/appStoreVersionLocalizations",
      {
        "fields[appStoreVersionLocalizations]" => "locale",
        "limit" => "200"
      }
    ).fetch("data")
    locales = localizations.map do |localization|
      screenshot_sets = client.get_all(
        "/v1/appStoreVersionLocalizations/#{localization.fetch('id')}/appScreenshotSets",
        {
          "fields[appScreenshotSets]" => "screenshotDisplayType",
          "limit" => "50"
        }
      ).fetch("data")
      preview_sets = client.get_all(
        "/v1/appStoreVersionLocalizations/#{localization.fetch('id')}/appPreviewSets",
        {
          "fields[appPreviewSets]" => "previewType",
          "limit" => "50"
        }
      ).fetch("data")
      screenshots = screenshot_sets.map do |set|
        delivery(
          client,
          "/v1/appScreenshotSets/#{set.fetch('id')}/appScreenshots",
          "fields[appScreenshots]", "assetDeliveryState"
        ).merge(
          "display_type" => set.dig("attributes", "screenshotDisplayType")
        )
      end
      previews = preview_sets.map do |set|
        delivery(
          client,
          "/v1/appPreviewSets/#{set.fetch('id')}/appPreviews",
          "fields[appPreviews]", "videoDeliveryState"
        ).merge("preview_type" => set.dig("attributes", "previewType"))
      end
      {
        "locale" => localization.dig("attributes", "locale"),
        "screenshots" => screenshots,
        "previews" => previews,
        "screenshot_count" => screenshots.sum { |set| set.fetch("complete_count") },
        "screenshot_total_count" => screenshots.sum { |set| set.fetch("total_count") },
        "preview_count" => previews.sum { |set| set.fetch("complete_count") },
        "preview_total_count" => previews.sum { |set| set.fetch("total_count") },
        "failed" => (screenshots + previews).flat_map { |set| set.fetch("failed") }
      }
    end.sort_by { |item| item.fetch("locale").to_s }
    locale_names = locales.map { |item| item.fetch("locale") }
    screenshots_complete = locale_names == expected_locales.sort &&
      locales.all? do |locale|
        locale.fetch("screenshot_count") == SCREENSHOTS_PER_LOCALE &&
          locale.fetch("screenshot_total_count") == SCREENSHOTS_PER_LOCALE &&
          locale.fetch("failed").empty?
      end
    previews_complete = locale_names == expected_locales.sort &&
      locales.all? do |locale|
        locale.fetch("preview_count") == PREVIEWS_PER_LOCALE &&
          locale.fetch("preview_total_count") == PREVIEWS_PER_LOCALE &&
          locale.fetch("failed").empty?
      end
    {
      "locales" => locales,
      "screenshot_count" => locales.sum { |item| item.fetch("screenshot_count") },
      "preview_count" => locales.sum { |item| item.fetch("preview_count") },
      "screenshots_complete" => screenshots_complete,
      "previews_complete" => previews_complete,
      "failed" => locales.flat_map { |item| item.fetch("failed") }
    }
  end

  def empty_assets
    {
      "locales" => [],
      "screenshot_count" => 0,
      "preview_count" => 0,
      "screenshots_complete" => false,
      "previews_complete" => false,
      "failed" => []
    }
  end

  def pricing(client, app_id, config)
    expected = config.fetch("pricing")
    territory = expected.fetch("territory")
    schedule = client.get("/v1/apps/#{app_id}/appPriceSchedule", {
      "fields[appPriceSchedules]" => "baseTerritory,manualPrices,automaticPrices"
    }).fetch("data")
    base = client.get(
      "/v1/appPriceSchedules/#{schedule.fetch('id')}/baseTerritory",
      { "fields[territories]" => "currency" }
    ).fetch("data")
    candidates = %w[manualPrices automaticPrices].flat_map do |relationship|
      response = client.get_all(
        "/v1/appPriceSchedules/#{schedule.fetch('id')}/#{relationship}",
        {
          "filter[territory]" => territory,
          "include" => "appPricePoint",
          "fields[appPrices]" =>
            "manual,startDate,endDate,appPricePoint,territory",
          "fields[appPricePoints]" => "customerPrice,territory",
          "limit" => "200"
        }
      )
      included = included_index(response.fetch("included", []))
      response.fetch("data").map do |price|
        point = price.dig("relationships", "appPricePoint", "data")
        resource = point && included[[point.fetch("type"), point.fetch("id")]]
        {
          "relationship" => relationship,
          "start_date" => price.dig("attributes", "startDate"),
          "end_date" => price.dig("attributes", "endDate"),
          "customer_price" => resource&.dig("attributes", "customerPrice")
        }
      end
    end
    now = Time.now.utc
    active = candidates.select do |price|
      start_time = price["start_date"] && Time.parse(price.fetch("start_date"))
      end_time = price["end_date"] && Time.parse(price.fetch("end_date"))
      (!start_time || start_time <= now) && (!end_time || end_time > now)
    rescue ArgumentError
      false
    end
    current = active.find { |price| price["relationship"] == "manualPrices" } ||
      active.first
    current_price = current && current["customer_price"]
    matches_configured_price = current_price &&
      BigDecimal(current_price.to_s) == BigDecimal(expected.fetch("price")) &&
      base.fetch("id").to_s == territory.to_s &&
      base.dig("attributes", "currency").to_s == expected.fetch("currency")
    {
      "schedule_id" => schedule.fetch("id"),
      "base_territory" => base.fetch("id"),
      "base_currency" => base.dig("attributes", "currency"),
      "territory" => territory,
      "current_price" => current_price,
      "target_price" => expected.fetch("price"),
      "matches_configured_price" => matches_configured_price == true,
      "active_prices" => active
    }
  end

  # Retired product ids are declared by the release configuration: products a
  # previous version sold and this one no longer does. They still exist in App
  # Store Connect, so they are reported on their own line instead of polluting
  # the unexpected list.
  def iap(client, app_id, expected_ids, retired_ids = [])
    items = client.get_all("/v1/apps/#{app_id}/inAppPurchasesV2", {
      "fields[inAppPurchases]" =>
        "name,productId,inAppPurchaseType,state,reviewNote",
      "limit" => "200"
    }).fetch("data")
    actual_ids = items.map { |item| item.dig("attributes", "productId") }.compact
    {
      "expected_count" => expected_ids.length,
      "actual_count" => items.length,
      "missing_product_ids" => (expected_ids - actual_ids).sort,
      "unexpected_product_ids" => (actual_ids - expected_ids - retired_ids).sort,
      "retired_product_ids" => (actual_ids & retired_ids).sort,
      "items" => items
    }
  end

  def app_info(client, app_id)
    infos = client.get_all("/v1/apps/#{app_id}/appInfos", {
      "fields[appInfos]" => "state,appStoreAgeRating,ageRatingDeclaration",
      "limit" => "50"
    }).fetch("data")
    infos.find do |item|
      %w[PREPARE_FOR_SUBMISSION WAITING_FOR_REVIEW REJECTED DEVELOPER_REJECTED]
        .include?(item.dig("attributes", "state"))
    end || infos.first
  end

  def target_build(config, environment = ENV)
    run_id = environment["RELEASE_RUN_ID"].to_s
    run_id = environment["APP_RELEASE_RUN_ID"].to_s if run_id.empty?
    return nil unless run_id.match?(/\A[0-9A-Za-z][0-9A-Za-z._-]{2,127}\z/)

    path = File.join(
      APP_ROOT, config.fetch("artifact_root"), run_id, "logs", "target-build.json"
    )
    return nil unless File.exist?(path) || File.symlink?(path)

    NovaStationPinballReleaseSupport.read_target_build!(
      path: path, version: config.fetch("version")
    )
  end

  def submitted?(payload, version_string)
    version_submitted = payload.dig("version", "version").to_s ==
      version_string.to_s &&
      SUBMITTED_STATES.include?(payload.dig("version", "state"))
    submission = payload.fetch("review_submissions", []).any? do |item|
      SUBMITTED_STATES.include?(item["state"]) &&
        item.fetch("items", []).any? do |review_item|
          review_item["version"].to_s == version_string.to_s
        end
    end
    version_submitted || submission
  end

  def read(client:, config:, environment: ENV)
    app = find_app(client, config.fetch("bundle_id"))
    version, included = versions(client, app.fetch("id"), config.fetch("version"))
    info = app_info(client, app.fetch("id"))
    payload = {
      "app" => {
        "id" => app.fetch("id"),
        "name" => app.dig("attributes", "name"),
        "bundle_id" => app.dig("attributes", "bundleId"),
        "sku" => app.dig("attributes", "sku"),
        "primary_locale" => app.dig("attributes", "primaryLocale"),
        "content_rights_declaration" =>
          app.dig("attributes", "contentRightsDeclaration")
      },
      "version" => version && {
        "id" => version.fetch("id"),
        "version" => version.dig("attributes", "versionString"),
        "state" => version.dig("attributes", "appStoreState"),
        "created" => version.dig("attributes", "createdDate")
      },
      "selected_build" => selected_build(client, version, included),
      "recent_builds" => recent_builds(
        client, app.fetch("id"), config.fetch("version")
      ),
      "review_submissions" => review_submissions(client, app.fetch("id")),
      "assets" => assets(
        client, version, config.dig("release_pipeline", "metadata_locales")
      ),
      "pricing" => pricing(client, app.fetch("id"), config),
      "iap" => iap(
        client, app.fetch("id"), config.fetch("iap"),
        config.fetch("retired_iap_products", []).map { |product| product.fetch("product_id") }
      ),
      "metadata" => if version && info
                      NovaStationPinballMetadataReadback.proof(
                        client: client, version: version, app_info: info,
                        config: config, root: APP_ROOT
                      )
                    end,
      "target_build" => target_build(config, environment)
    }
    payload
  end

  def print_human(payload)
    puts "App: #{payload.dig('app', 'name')} (#{payload.dig('app', 'bundle_id')})"
    if payload["version"]
      puts "Version: #{payload.dig('version', 'version')} state=#{payload.dig('version', 'state')}"
    else
      puts "Version: none"
    end
    selected = payload["selected_build"]
    puts selected ? "Selected build: #{selected['build']} state=#{selected['state']}" : "Selected build: none"
    assets = payload.fetch("assets")
    puts "Media: screenshots=#{assets['screenshot_count']} complete=#{assets['screenshots_complete']} previews=#{assets['preview_count']} complete=#{assets['previews_complete']}"
    puts "Pricing: #{payload.dig('pricing', 'current_price')} #{payload.dig('pricing', 'base_currency')} matches_configured=#{payload.dig('pricing', 'matches_configured_price')}"
    puts "IAP: expected=#{payload.dig('iap', 'expected_count')} actual=#{payload.dig('iap', 'actual_count')}"
    puts "Metadata complete: #{payload.dig('metadata', 'complete')}"
  end
end

if $PROGRAM_NAME == __FILE__
  options = {
    config: File.join(
      NovaStationPinballAscStatus::APP_ROOT, "fastlane", "release_config.json"
    ),
    key_path: ENV["ASC_API_KEY_PATH"]
  }
  OptionParser.new do |parser|
    parser.on("--bundle-id ID") { |value| options[:bundle_id] = value }
    parser.on("--config PATH") { |value| options[:config] = value }
    parser.on("--key-path PATH") { |value| options[:key_path] = value }
    parser.on("--version VERSION") { |value| options[:version] = value }
    parser.on("--json") { options[:json] = true }
  end.parse!(ARGV)

  begin
    config = NovaStationPinballAscStatus.load_config(options.fetch(:config))
    if options[:bundle_id] && options[:bundle_id] != config.fetch("bundle_id")
      raise ArgumentError, "--bundle-id differs from release config"
    end
    if options[:version] && options[:version] != config.fetch("version")
      raise ArgumentError, "--version differs from release config"
    end
    unless NovaStationPinballAscCredentials.available?(key_path: options[:key_path])
      raise ArgumentError, "Provide an ASC API key through bin/apple-release"
    end
    client = NovaStationPinballAscClient.new(key_path: options[:key_path])
    payload = NovaStationPinballAscStatus.read(client: client, config: config)
    if options[:json]
      puts JSON.pretty_generate(payload)
    else
      NovaStationPinballAscStatus.print_human(payload)
    end
  rescue ArgumentError, KeyError, RuntimeError, NovaStationPinballAscError => error
    warn "asc_status: #{error.message}"
    exit 1
  end
end
