#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "client"
require_relative "../../fastlane/release_support"

module NovaStationPinballReviewSubmission
  SUBMITTED_STATES = %w[WAITING_FOR_REVIEW IN_REVIEW].freeze
  TERMINAL_STATES = %w[CANCELED COMPLETE].freeze

  module_function

  def resources(client, submission_id)
    client.get_all("/v1/reviewSubmissions/#{submission_id}/items", {
      "fields[reviewSubmissionItems]" =>
        "state,appStoreVersion,inAppPurchaseVersion",
      "limit" => "200"
    }).fetch("data").flat_map do |item|
      %w[appStoreVersion inAppPurchaseVersion].map do |relationship|
        resource = item.dig("relationships", relationship, "data")
        resource && [resource.fetch("type"), resource.fetch("id")]
      end.compact
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
    selected = client.get(
      "/v1/appStoreVersions/#{version.fetch('id')}/build",
      { "fields[builds]" => "version,processingState,expired" }, optional: true
    )&.fetch("data", nil)
    unless selected && selected.dig("attributes", "version").to_s == target.fetch("build") &&
           selected.dig("attributes", "processingState") == "VALID" &&
           selected.dig("attributes", "expired") != true
      raise "Exact target build is not selected and valid"
    end

    iaps = client.get_all("/v1/apps/#{app.fetch('id')}/inAppPurchasesV2", {
      "fields[inAppPurchases]" => "productId,inAppPurchaseType,state",
      "limit" => "200"
    }).fetch("data")
    iap_version_ids = config.fetch("iap").map do |product_id|
      iap = iaps.find { |item| item.dig("attributes", "productId") == product_id }
      raise "Tip IAP is missing: #{product_id}" unless iap
      raise "Tip IAP is not consumable: #{product_id}" unless
        iap.dig("attributes", "inAppPurchaseType") == "CONSUMABLE"
      state = iap.dig("attributes", "state")
      unless %w[READY_TO_SUBMIT WAITING_FOR_REVIEW IN_REVIEW PENDING_BINARY_APPROVAL APPROVED].include?(state)
        raise "Tip IAP is not reviewable: #{product_id}:#{state}"
      end
      versions = client.get_all(
        "/v2/inAppPurchases/#{iap.fetch('id')}/versions",
        {
          "fields[inAppPurchaseVersions]" => "version,state",
          "limit" => "50"
        }
      ).fetch("data")
      candidate = versions.max_by do |item|
        item.dig("attributes", "version").to_i
      end
      raise "Tip IAP has no version: #{product_id}" unless candidate
      version_state = candidate.dig("attributes", "state")
      if %w[WAITING_FOR_REVIEW IN_REVIEW ACCEPTED APPROVED].include?(version_state)
        nil
      elsif %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW].include?(version_state)
        candidate.fetch("id")
      else
        raise "Tip IAP version is not reviewable: #{product_id}:#{version_state}"
      end
    end.compact
    required = [["appStoreVersions", version.fetch("id")]] +
      iap_version_ids.map { |id| ["inAppPurchaseVersions", id] }
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
      relationship = type == "appStoreVersions" ?
        "appStoreVersion" : "inAppPurchaseVersion"
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
         NovaStationPinballAscError => error
    warn "review_submission: #{error.message}"
    exit 1
  end
end
