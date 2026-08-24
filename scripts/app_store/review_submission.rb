#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "client"
require_relative "game_center_contract"
require_relative "rejected_submission_recovery"
require_relative "../../fastlane/release_support"

module NovaStationPinballReviewSubmission
  SUBMITTED_STATES = %w[WAITING_FOR_REVIEW IN_REVIEW].freeze
  TERMINAL_STATES = %w[CANCELED COMPLETE].freeze
  # A product state App Review is able to act on at all.
  REVIEWABLE_PRODUCT_STATES = %w[
    READY_TO_SUBMIT WAITING_FOR_REVIEW IN_REVIEW PENDING_BINARY_APPROVAL APPROVED
  ].freeze
  # A product version already handed to App Review.
  SUBMITTED_VERSION_STATES = %w[WAITING_FOR_REVIEW IN_REVIEW ACCEPTED APPROVED].freeze
  # A product version that still has to be attached to a submission.
  ATTACHABLE_VERSION_STATES = %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW].freeze
  # Until a product has been approved once it has never shipped, so App Store
  # Connect requires its version to ride inside the same review submission as
  # the app version. That is exactly the case of a first paid product.
  SHIPPED_PRODUCT_STATE = "APPROVED"

  module_function

  # The purchase catalogue this release sells, read from the release
  # configuration instead of assumed: product id mapped to declared type.
  def declared_products(config)
    products = config.fetch("iap_products").map do |product|
      { "product_id" => product.fetch("product_id"), "type" => product.fetch("type") }
    end
    ids = products.map { |product| product.fetch("product_id") }
    unless ids.sort == config.fetch("iap").sort
      raise "release_config.iap does not mirror release_config.iap_products"
    end

    products
  end

  def declared_retired_products(config)
    config.fetch("retired_iap_products", []).map do |product|
      {
        "product_id" => product.fetch("product_id"),
        "type" => product.fetch("type"),
        "target_state" => product.fetch("target_state")
      }
    end
  end

  def validate_retired_products!(client, app_id, retired_products)
    return if retired_products.empty?

    catalogue = client.get_all("/v1/apps/#{app_id}/inAppPurchasesV2", {
      "fields[inAppPurchases]" => "productId,inAppPurchaseType,state",
      "limit" => "200"
    }).fetch("data")
    retired_products.each do |product|
      product_id = product.fetch("product_id")
      matches = catalogue.select do |item|
        item.dig("attributes", "productId") == product_id
      end
      unless matches.length == 1
        raise "Expected exactly one retired IAP in App Store Connect: " \
              "#{product_id}; found #{matches.length}"
      end

      item = matches.first
      actual_type = item.dig("attributes", "inAppPurchaseType")
      unless actual_type == product.fetch("type")
        raise "Retired IAP type differs from the release configuration: " \
              "#{product_id} is #{actual_type}, expected #{product.fetch('type')}"
      end
      actual_state = item.dig("attributes", "state")
      unless actual_state == product.fetch("target_state")
        raise "Retired IAP does not match the release configuration: " \
              "#{product_id} is #{actual_state}, expected " \
              "#{product.fetch('target_state')}"
      end

      NovaStationPinballRejectedSubmissionRecovery::RetiredIapReadback.exact!(
        client: client, iap_id: item.fetch("id"), product_id: product_id
      )
    end
  end

  def declared_leaderboards(config)
    NovaStationPinballGameCenterContract.declared(config)
  end

  def leaderboard_submission_records(client, app_id, definitions)
    NovaStationPinballGameCenterContract.resolve_reviewable_versions(
      client: client, app_id: app_id, definitions: definitions
    )
  end

  # One record per sold product: the version that has to travel with this app
  # version, and whether App Store Connect requires the bundling.
  def product_submission_records(client, app_id, products)
    return [] if products.empty?

    catalogue = client.get_all("/v1/apps/#{app_id}/inAppPurchasesV2", {
      "fields[inAppPurchases]" => "productId,inAppPurchaseType,state",
      "limit" => "200"
    }).fetch("data")

    products.map do |product|
      product_id = product.fetch("product_id")
      purchase = catalogue.find do |item|
        item.dig("attributes", "productId") == product_id
      end
      raise "IAP is missing from App Store Connect: #{product_id}" unless purchase

      declared_type = product.fetch("type")
      actual_type = purchase.dig("attributes", "inAppPurchaseType")
      unless actual_type == declared_type
        raise "IAP type differs from the release configuration: " \
              "#{product_id} is #{actual_type}, expected #{declared_type}"
      end
      state = purchase.dig("attributes", "state")
      unless REVIEWABLE_PRODUCT_STATES.include?(state)
        raise "IAP is not reviewable: #{product_id}:#{state}"
      end

      versions = client.get_all(
        "/v2/inAppPurchases/#{purchase.fetch('id')}/versions",
        { "fields[inAppPurchaseVersions]" => "version,state", "limit" => "50" }
      ).fetch("data")
      candidate = versions.max_by { |item| item.dig("attributes", "version").to_i }
      raise "IAP has no version: #{product_id}" unless candidate

      version_state = candidate.dig("attributes", "state")
      unless (SUBMITTED_VERSION_STATES + ATTACHABLE_VERSION_STATES).include?(version_state)
        raise "IAP version is not reviewable: #{product_id}:#{version_state}"
      end

      must_bundle = state != SHIPPED_PRODUCT_STATE
      {
        "product_id" => product_id,
        "version_id" => candidate.fetch("id"),
        "version_state" => version_state,
        "must_bundle" => must_bundle,
        # A never-shipped product must be part of this submission whatever its
        # version state; an already-shipped one only when it needs review.
        "required" => must_bundle || ATTACHABLE_VERSION_STATES.include?(version_state)
      }
    end
  end

  # The exact resources this app version has to be submitted with.
  def required_resources(app_version_id, product_records, leaderboard_records = [])
    [["appStoreVersions", app_version_id]] +
      leaderboard_records.map do |record|
        ["gameCenterLeaderboardVersions", record.fetch("version_id")]
      end +
      product_records.select { |record| record.fetch("required") }
                     .map do |record|
        ["inAppPurchaseVersions", record.fetch("version_id")]
      end
  end

  def resources(client, submission_id)
    client.get_all("/v1/reviewSubmissions/#{submission_id}/items", {
      "include" =>
        "appStoreVersion,gameCenterLeaderboardVersion,inAppPurchaseVersion",
      "fields[reviewSubmissionItems]" =>
        "state,appStoreVersion,gameCenterLeaderboardVersion,inAppPurchaseVersion",
      "fields[gameCenterLeaderboardVersions]" => "version,state",
      "limit" => "200"
    }).fetch("data").map { |item| review_item_resource!(item) }
  end

  def review_item_resource!(item)
    relationships = {
      "appStoreVersion" => "appStoreVersions",
      "gameCenterLeaderboardVersion" => "gameCenterLeaderboardVersions",
      "inAppPurchaseVersion" => "inAppPurchaseVersions"
    }
    resources = relationships.map do |relationship, expected_type|
      resource = item.dig("relationships", relationship, "data")
      next unless resource
      unless resource.fetch("type") == expected_type
        raise "Review item #{item.fetch('id')} has an invalid #{relationship} type"
      end

      [resource.fetch("type"), resource.fetch("id")]
    end.compact
    unless resources.length == 1
      raise "Review item #{item.fetch('id')} must reference exactly one review resource"
    end

    resources.first
  end

  def review_item_relationship(resource_type)
    case resource_type
    when "appStoreVersions" then "appStoreVersion"
    when "gameCenterLeaderboardVersions" then "gameCenterLeaderboardVersion"
    when "inAppPurchaseVersions" then "inAppPurchaseVersion"
    else
      raise "Unsupported review resource type: #{resource_type}"
    end
  end

  def submissions(client, app_id)
    client.get_all("/v1/apps/#{app_id}/reviewSubmissions", {
      "fields[reviewSubmissions]" => "state,submittedDate,platform",
      "limit" => "50"
    }).fetch("data").map do |submission|
      {
        "id" => submission.fetch("id"),
        "state" => submission.dig("attributes", "state"),
        "resources" => resources(client, submission.fetch("id"))
      }
    end
  end

  def review_submitted?(client, app_id, required_resources)
    submissions(client, app_id).any? do |submission|
      SUBMITTED_STATES.include?(submission.fetch("state")) &&
        (required_resources - submission.fetch("resources")).empty?
    end
  end

  def wait_until(timeout:, interval:)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Float(timeout)
    loop do
      value = yield
      return value if value
      raise "Review submission GET readback timed out" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep(Float(interval))
    end
  end

  def guarded_mutation(proof)
    begin
      NovaStationPinballReleaseSupport.transport_once!(**proof) { yield }
    rescue NovaStationPinballReleaseSupport::AmbiguousTransport => error
      warn "#{error.message}; continuing with GET-only review verification"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  app_root = File.expand_path("../..", __dir__)
  options = {
    config: File.join(app_root, "fastlane", "release_config.json"),
    key_path: ENV["ASC_API_KEY_PATH"],
    timeout: 600,
    interval: 10
  }
  OptionParser.new do |parser|
    parser.on("--bundle-id ID") { |value| options[:bundle_id] = value }
    parser.on("--version VERSION") { |value| options[:version] = value }
    parser.on("--key-path PATH") { |value| options[:key_path] = value }
    parser.on("--config PATH") { |value| options[:config] = value }
    parser.on("--submit") { options[:submit] = true }
    parser.on("--timeout SECONDS", Float) { |value| options[:timeout] = value }
    parser.on("--interval SECONDS", Float) { |value| options[:interval] = value }
  end.parse!(ARGV)

  begin
    raise "--submit is required" unless options[:submit]
    config = JSON.parse(File.binread(options.fetch(:config)))
    bundle_id = options[:bundle_id] || config.fetch("bundle_id")
    version_string = options[:version] || config.fetch("version")
    raise "Bundle ID differs from release config" unless bundle_id == config.fetch("bundle_id")
    raise "Version differs from release config" unless version_string == config.fetch("version")
    candidate_id = NovaStationPinballReleaseSupport.candidate_id!(
      ENV["APPS_FACTORY_CANDIDATE_ID"]
    )
    run_id = NovaStationPinballReleaseSupport.run_id!(
      ENV["RELEASE_RUN_ID"].to_s.empty? ?
        ENV["APP_RELEASE_RUN_ID"] : ENV["RELEASE_RUN_ID"]
    )
    logs = File.join(app_root, config.fetch("artifact_root"), run_id, "logs")
    target = NovaStationPinballReleaseSupport.read_target_build!(
      path: File.join(logs, "target-build.json"), version: version_string
    )
    client = NovaStationPinballAscClient.new(key_path: options.fetch(:key_path))
    app = client.get_all("/v1/apps", {
      "filter[bundleId]" => bundle_id,
      "fields[apps]" => "bundleId",
      "limit" => "20"
    }).fetch("data").find { |item| item.dig("attributes", "bundleId") == bundle_id }
    raise "App not found for #{bundle_id}" unless app
    version = client.get_all(
      "/v1/apps/#{app.fetch('id')}/appStoreVersions",
      {
        "filter[platform]" => "IOS",
        "filter[versionString]" => version_string,
        "include" => "build",
        "fields[appStoreVersions]" => "versionString,appStoreState,build",
        "fields[builds]" => "version,processingState,expired",
        "limit" => "20"
      }
    ).fetch("data").find do |item|
      item.dig("attributes", "versionString") == version_string
    end
    raise "Version #{version_string} not found" unless version
    NovaStationPinballGameCenterContract.app_version_enabled!(
      client: client, app_store_version_id: version.fetch("id")
    )
    selected = client.get(
      "/v1/appStoreVersions/#{version.fetch('id')}/build",
      { "fields[builds]" => "version,processingState,expired" }, optional: true
    )&.fetch("data", nil)
    unless selected && selected.dig("attributes", "version").to_s == target.fetch("build") &&
           selected.dig("attributes", "processingState") == "VALID" &&
           selected.dig("attributes", "expired") != true
      raise "Exact target build is not selected and valid"
    end

    records = NovaStationPinballReviewSubmission.product_submission_records(
      client, app.fetch("id"),
      NovaStationPinballReviewSubmission.declared_products(config)
    )
    NovaStationPinballReviewSubmission.validate_retired_products!(
      client, app.fetch("id"),
      NovaStationPinballReviewSubmission.declared_retired_products(config)
    )
    leaderboard_records =
      NovaStationPinballReviewSubmission.leaderboard_submission_records(
        client, app.fetch("id"),
        NovaStationPinballReviewSubmission.declared_leaderboards(config)
      )
    required = NovaStationPinballReviewSubmission.required_resources(
      version.fetch("id"), records, leaderboard_records
    )
    bundled = required.map { |type, id| id if type == "inAppPurchaseVersions" }.compact
    records.each do |record|
      next unless record.fetch("must_bundle")
      next if bundled.include?(record.fetch("version_id"))

      raise "IAP version must be submitted with the app version: " \
            "#{record.fetch('product_id')}"
    end

    if NovaStationPinballReviewSubmission.review_submitted?(
      client, app.fetch("id"), required
    )
      puts "Review submission is already complete for #{version_string}"
      exit 0
    end

    active = NovaStationPinballReviewSubmission.submissions(
      client, app.fetch("id")
    ).reject do |submission|
      NovaStationPinballReviewSubmission::TERMINAL_STATES.include?(
        submission.fetch("state")
      )
    end
    unsafe = active.reject do |submission|
      submission.fetch("state") == "READY_FOR_REVIEW" &&
        (submission.fetch("resources") - required).empty?
    end
    unless unsafe.empty?
      raise "An active review submission cannot be changed safely: " \
            "#{unsafe.map { |item| "#{item['id']}:#{item['state']}" }.join(',')}"
    end
    submission = active.first
    unless submission
      proof = {
        intent_path: File.join(logs, "review-create-intent.json"),
        receipt_path: File.join(logs, "review-create-receipt.json"),
        kind: "submit_review", candidate_id: candidate_id,
        version: version_string,
        payload: { "action" => "create", "app_id" => app.fetch("id") }
      }
      NovaStationPinballReviewSubmission.guarded_mutation(proof) do
        client.post("/v1/reviewSubmissions", {
          data: {
            type: "reviewSubmissions",
            relationships: {
              app: { data: { type: "apps", id: app.fetch("id") } }
            }
          }
        })
      end
      submission = NovaStationPinballReviewSubmission.wait_until(
        timeout: options.fetch(:timeout), interval: options.fetch(:interval)
      ) do
        candidates = NovaStationPinballReviewSubmission.submissions(
          client, app.fetch("id")
        ).select { |item| item.fetch("state") == "READY_FOR_REVIEW" }
        raise "Review submission creation became ambiguous" if candidates.length > 1
        candidates.first
      end
      NovaStationPinballReleaseSupport.mark_observed!(**proof)
    end

    missing = required - submission.fetch("resources")
    missing.each do |type, resource_id|
      relationship =
        NovaStationPinballReviewSubmission.review_item_relationship(type)
      safe_id = resource_id.gsub(/[^0-9A-Za-z._-]/, "-")
      proof = {
        intent_path: File.join(logs, "review-item-#{safe_id}-intent.json"),
        receipt_path: File.join(logs, "review-item-#{safe_id}-receipt.json"),
        kind: "submit_review", candidate_id: candidate_id,
        version: version_string,
        payload: {
          "action" => "add_item", "submission_id" => submission.fetch("id"),
          "resource_type" => type, "resource_id" => resource_id
        }
      }
      NovaStationPinballReviewSubmission.guarded_mutation(proof) do
        client.post("/v1/reviewSubmissionItems", {
          data: {
            type: "reviewSubmissionItems",
            relationships: {
              reviewSubmission: {
                data: { type: "reviewSubmissions", id: submission.fetch("id") }
              },
              relationship => { data: { type: type, id: resource_id } }
            }
          }
        })
      end
      NovaStationPinballReviewSubmission.wait_until(
        timeout: options.fetch(:timeout), interval: options.fetch(:interval)
      ) do
        NovaStationPinballReviewSubmission.resources(
          client, submission.fetch("id")
        ).include?([type, resource_id])
      end
      NovaStationPinballReleaseSupport.mark_observed!(**proof)
    end

    submit_proof = {
      intent_path: File.join(logs, "review-submit-intent.json"),
      receipt_path: File.join(logs, "review-submit-receipt.json"),
      kind: "submit_review", candidate_id: candidate_id,
      version: version_string,
      payload: {
        "action" => "submit", "submission_id" => submission.fetch("id"),
        "resources" => required.sort
      }
    }
    NovaStationPinballReviewSubmission.guarded_mutation(submit_proof) do
      client.patch("/v1/reviewSubmissions/#{submission.fetch('id')}", {
        data: {
          type: "reviewSubmissions", id: submission.fetch("id"),
          attributes: { submitted: true }
        }
      })
    end
    NovaStationPinballReviewSubmission.wait_until(
      timeout: options.fetch(:timeout), interval: options.fetch(:interval)
    ) do
      NovaStationPinballReviewSubmission.review_submitted?(
        client, app.fetch("id"), required
      )
    end
    NovaStationPinballReleaseSupport.mark_observed!(**submit_proof)
    puts "Submitted #{bundle_id} #{version_string} build #{target.fetch('build')}"
  rescue ArgumentError, KeyError, JSON::ParserError, RuntimeError,
         NovaStationPinballRejectedSubmissionRecovery::Error,
         NovaStationPinballAscError => error
    warn "review_submission: #{error.message}"
    exit 1
  end
end
