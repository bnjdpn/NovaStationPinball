#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "client"
require_relative "game_center_contract"
require_relative "rejected_submission_recovery"
require_relative "release_provenance"
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
  REVIEW_RESOURCE_TYPES = %w[
    appStoreVersions gameCenterLeaderboardVersions inAppPurchaseVersions
  ].freeze

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
      unless NovaStationPinballRejectedSubmissionRecovery::RetiredIapReadback
               .not_for_sale_state?(actual_state)
        raise "Retired IAP does not match the release configuration: " \
              "#{product_id} is #{actual_state}, expected " \
              "#{product.fetch('target_state')} or an unapproved " \
              "READY_TO_SUBMIT product with no storefront availability"
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
      matches = catalogue.select do |item|
        item.dig("attributes", "productId") == product_id
      end
      unless matches.length == 1
        raise "IAP is missing or ambiguous in App Store Connect: #{product_id}"
      end
      purchase = matches.first

      declared_type = product.fetch("type")
      actual_type = purchase.dig("attributes", "inAppPurchaseType")
      unless actual_type == declared_type
        raise "IAP type differs from the release configuration: " \
              "#{product_id} is #{actual_type}, expected #{declared_type}"
      end
      contract = NovaStationPinballReleaseProvenance::CURRENT
      unless product_id == contract.workshop_product_id &&
             purchase.fetch("id") == contract.workshop_iap_id
        raise "IAP identity differs from the frozen Workshop release"
      end
      state = purchase.dig("attributes", "state")
      unless REVIEWABLE_PRODUCT_STATES.include?(state)
        raise "IAP is not reviewable: #{product_id}:#{state}"
      end

      versions = client.get_all(
        "/v2/inAppPurchases/#{purchase.fetch('id')}/versions",
        { "fields[inAppPurchaseVersions]" => "version,state", "limit" => "50" }
      ).fetch("data")
      candidates = versions.select do |item|
        item["id"] == contract.workshop_version_id &&
          item["type"] == "inAppPurchaseVersions" &&
          item.dig("attributes", "version").to_s == "1"
      end
      unless candidates.length == 1 && versions.length == 1
        raise "IAP version catalogue differs from the frozen Workshop release: #{product_id}"
      end
      candidate = candidates.first

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
    resources = [["appStoreVersions", app_version_id]] +
      leaderboard_records.map do |record|
        ["gameCenterLeaderboardVersions", record.fetch("version_id")]
      end +
      product_records.select { |record| record.fetch("required") }
                     .map do |record|
        ["inAppPurchaseVersions", record.fetch("version_id")]
      end
    canonical_required_resources!(resources)
  end

  def canonical_required_resources!(resources)
    unless resources.instance_of?(Array) && !resources.empty? &&
           resources.all? do |resource|
             resource.instance_of?(Array) && resource.length == 2 &&
               REVIEW_RESOURCE_TYPES.include?(resource.fetch(0)) &&
               resource.fetch(1).instance_of?(String) &&
               !resource.fetch(1).empty?
           end
      raise "Required review resources have an invalid shape"
    end
    if resources.uniq.length != resources.length
      raise "Required review resources contain a duplicate"
    end

    resources.sort
  end

  def exact_resource_set?(actual, required)
    expected = canonical_required_resources!(required)
    actual.instance_of?(Array) && actual.uniq.length == actual.length &&
      actual.sort == expected
  end

  def draft_resource_subset?(actual, required)
    expected = canonical_required_resources!(required)
    actual.instance_of?(Array) && actual.uniq.length == actual.length &&
      (actual - expected).empty?
  end

  def exact_submission_resources!(client, submission_id, required)
    actual = resources(client, submission_id)
    return actual if exact_resource_set?(actual, required)

    raise "Review submission resources differ from the exact release set: " \
          "#{submission_id}"
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
        "platform" => submission.dig("attributes", "platform"),
        "resources" => resources(client, submission.fetch("id"))
      }
    end
  end

  def review_submitted?(client, app_id, required_resources)
    active = submissions(client, app_id).reject do |submission|
      TERMINAL_STATES.include?(submission.fetch("state"))
    end
    !submitted_submission(active, required_resources).nil?
  end

  def submitted_submission(active, required_resources)
    matches = active.select do |submission|
      SUBMITTED_STATES.include?(submission.fetch("state")) &&
        submission.fetch("platform") == "IOS" &&
        exact_resource_set?(submission.fetch("resources"), required_resources)
    end
    return nil if matches.empty?
    unless matches.length == 1 && active.length == 1
      raise "Active submitted review state is ambiguous"
    end

    matches.first
  end

  def resumable_draft!(active, required_resources)
    unsafe = active.reject do |submission|
      submission.fetch("state") == "READY_FOR_REVIEW" &&
        submission.fetch("platform") == "IOS" &&
        draft_resource_subset?(
          submission.fetch("resources"), required_resources
        )
    end
    unless unsafe.empty?
      raise "An active review submission cannot be changed safely: " \
            "#{unsafe.map { |item| "#{item['id']}:#{item['state']}" }.join(',')}"
    end
    if active.length > 1
      raise "Multiple active review drafts cannot be resumed safely"
    end

    active.first
  end

  def require_missing_resource!(draft, resource)
    unless resource.instance_of?(Array) && resource.length == 2
      raise "Review resource has an invalid shape"
    end
    if draft.fetch("resources").include?(resource)
      raise "Review item appeared before item transport"
    end
    true
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

  def guarded_mutation(proof, preflight:)
    existing_intent = File.exist?(proof.fetch(:intent_path)) ||
      File.symlink?(proof.fetch(:intent_path))
    begin
      NovaStationPinballReleaseSupport.transport_once!(
        **proof, preflight: existing_intent ? nil : preflight
      ) { yield }
    rescue NovaStationPinballReleaseSupport::AmbiguousTransport => error
      warn "#{error.message}; continuing with GET-only review verification"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  app_root = File.expand_path("../..", __dir__)
  release_config_path = File.join(app_root, "fastlane", "release_config.json")
  options = {
    config: release_config_path,
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
    unless File.expand_path(options.fetch(:config)) == release_config_path &&
           File.file?(release_config_path) && !File.symlink?(release_config_path)
      raise "Review submission requires the checked-in release configuration"
    end
    raise "Bundle ID differs from release config" unless bundle_id == config.fetch("bundle_id")
    raise "Version differs from release config" unless version_string == config.fetch("version")
    NovaStationPinballReleaseProvenance.verify_release_arguments!(
      bundle_id: bundle_id, version: version_string
    )
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
    NovaStationPinballReleaseProvenance.verify_release_arguments!(
      bundle_id: bundle_id, version: version_string,
      build: target.fetch("build")
    )
    local_release = NovaStationPinballReleaseProvenance.verify_local!(
      run_id: run_id, candidate_id: candidate_id
    )
    client = NovaStationPinballAscClient.new(key_path: options.fetch(:key_path))
    live_build = NovaStationPinballReleaseProvenance.verify_live_build!(client: client)
    reviewable_app_states = %w[
      REJECTED PREPARE_FOR_SUBMISSION READY_FOR_REVIEW
    ].freeze
    submitted_app_states = %w[WAITING_FOR_REVIEW IN_REVIEW].freeze
    version = NovaStationPinballReleaseProvenance.verify_app_version!(
      client: client,
      allowed_states: reviewable_app_states + submitted_app_states
    )
    app = {
      "id" => NovaStationPinballReleaseProvenance::CURRENT.app_id,
      "attributes" => { "bundleId" => bundle_id }
    }
    NovaStationPinballGameCenterContract.app_version_enabled!(
      client: client, app_store_version_id: version.fetch("id")
    )
    NovaStationPinballReleaseProvenance.verify_selected_build!(
      client: client, version_id: version.fetch("id")
    )
    release_identity = NovaStationPinballReleaseProvenance.release_identity(
      local: local_release, build: live_build
    )
    proof_release = {
      "run_id" => run_id,
      "source_head" => release_identity.fetch("source_head"),
      "app_version_id" => version.fetch("id"),
      "build" => release_identity.fetch("build"),
      "build_id" => release_identity.fetch("asc_build_id"),
      "uploaded_date" => release_identity.fetch("uploaded_date"),
      "ipa_sha256" => release_identity.fetch("ipa_sha256")
    }
    source_notes =
      NovaStationPinballRejectedSubmissionRecovery::SourceNotes.load!(
        app_review_path: File.join(
          app_root, "fastlane", "metadata", "review_information", "notes.txt"
        ),
        products_path: File.join(app_root, "fastlane", "pro_products.json")
      )

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

    active = NovaStationPinballReviewSubmission.submissions(
      client, app.fetch("id")
    ).reject do |candidate|
      NovaStationPinballReviewSubmission::TERMINAL_STATES.include?(
        candidate.fetch("state")
      )
    end
    submitted = NovaStationPinballReviewSubmission.submitted_submission(
      active, required
    )
    if submitted
      NovaStationPinballRejectedSubmissionRecovery.verify_recovery_complete!(
        client: client, source_notes: source_notes,
        allowed_active_submission_ids: [submitted.fetch("id")]
      )
      NovaStationPinballReleaseProvenance.verify_review_readiness!(
        client: client,
        allowed_workshop_parent_states: %w[
          READY_TO_SUBMIT WAITING_FOR_REVIEW IN_REVIEW PENDING_BINARY_APPROVAL
        ],
        allowed_workshop_states: %w[
          WAITING_FOR_REVIEW IN_REVIEW ACCEPTED APPROVED
        ]
      )
      submit_proof = {
        intent_path: File.join(logs, "review-submit-intent.json"),
        receipt_path: File.join(logs, "review-submit-receipt.json"),
        kind: "submit_review", candidate_id: candidate_id,
        version: version_string,
        payload: proof_release.merge(
          "action" => "submit", "submission_id" => submitted.fetch("id"),
          "resources" => required.sort
        )
      }
      if File.exist?(submit_proof.fetch(:intent_path)) ||
         File.symlink?(submit_proof.fetch(:intent_path))
        NovaStationPinballReleaseSupport.mark_observed!(**submit_proof)
      end
      puts "Review submission is already complete for #{version_string}"
      exit 0
    end

    app_attributes = version.fetch("attributes")
    unless reviewable_app_states.include?(app_attributes["appStoreState"]) &&
           reviewable_app_states.include?(app_attributes["appVersionState"])
      raise "App Store version is not in a state that permits a new review transport"
    end
    submission = NovaStationPinballReviewSubmission.resumable_draft!(
      active, required
    )
    allowed_active_submission_ids = submission ? [submission.fetch("id")] : []
    NovaStationPinballRejectedSubmissionRecovery.verify_recovery_complete!(
      client: client, source_notes: source_notes,
      allowed_active_submission_ids: allowed_active_submission_ids
    )
    NovaStationPinballReleaseProvenance.verify_review_readiness!(client: client)

    release_resources_guard = lambda do
      local = NovaStationPinballReleaseProvenance.verify_local!(
        run_id: run_id, candidate_id: candidate_id
      )
      NovaStationPinballReleaseProvenance.verify_remote!
      current_build = NovaStationPinballReleaseProvenance.verify_live_build!(
        client: client
      )
      current_version = NovaStationPinballReleaseProvenance.verify_app_version!(
        client: client, allowed_states: reviewable_app_states
      )
      NovaStationPinballReleaseProvenance.verify_selected_build!(
        client: client, version_id: current_version.fetch("id")
      )
      NovaStationPinballReleaseProvenance.verify_review_readiness!(
        client: client
      )
      NovaStationPinballRejectedSubmissionRecovery.verify_recovery_complete!(
        client: client, source_notes: source_notes,
        allowed_active_submission_ids: allowed_active_submission_ids
      )
      current_identity = NovaStationPinballReleaseProvenance.release_identity(
        local: local, build: current_build
      )
      unless current_identity == release_identity &&
             current_version.fetch("id") == version.fetch("id")
        raise "Release provenance drifted before review transport"
      end
      NovaStationPinballGameCenterContract.app_version_enabled!(
        client: client, app_store_version_id: current_version.fetch("id")
      )
      current_records =
        NovaStationPinballReviewSubmission.product_submission_records(
          client, app.fetch("id"),
          NovaStationPinballReviewSubmission.declared_products(config)
        )
      NovaStationPinballReviewSubmission.validate_retired_products!(
        client, app.fetch("id"),
        NovaStationPinballReviewSubmission.declared_retired_products(config)
      )
      current_leaderboards =
        NovaStationPinballReviewSubmission.leaderboard_submission_records(
          client, app.fetch("id"),
          NovaStationPinballReviewSubmission.declared_leaderboards(config)
        )
      current_required = NovaStationPinballReviewSubmission.required_resources(
        current_version.fetch("id"), current_records, current_leaderboards
      )
      unless current_required == required
        raise "Required review resources drifted before review transport"
      end
      true
    end

    unless submission
      proof = {
        intent_path: File.join(logs, "review-create-intent.json"),
        receipt_path: File.join(logs, "review-create-receipt.json"),
        kind: "submit_review", candidate_id: candidate_id,
        version: version_string,
        payload: proof_release.merge(
          "action" => "create", "app_id" => app.fetch("id")
        )
      }
      create_preflight = lambda do
        release_resources_guard.call
        active_now = NovaStationPinballReviewSubmission.submissions(
          client, app.fetch("id")
        ).reject do |item|
          NovaStationPinballReviewSubmission::TERMINAL_STATES.include?(
            item.fetch("state")
          )
        end
        raise "An active review submission appeared before creation" unless active_now.empty?
      end
      NovaStationPinballReviewSubmission.guarded_mutation(
        proof, preflight: create_preflight
      ) do
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
        ).reject do |item|
          NovaStationPinballReviewSubmission::TERMINAL_STATES.include?(
            item.fetch("state")
          )
        end
        NovaStationPinballReviewSubmission.resumable_draft!(candidates, required)
      end
      NovaStationPinballReleaseSupport.mark_observed!(**proof)
    end
    allowed_active_submission_ids = [submission.fetch("id")]

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
        payload: proof_release.merge(
          "action" => "add_item", "submission_id" => submission.fetch("id"),
          "resource_type" => type, "resource_id" => resource_id
        )
      }
      item_preflight = lambda do
        release_resources_guard.call
        current = NovaStationPinballReviewSubmission.submissions(
          client, app.fetch("id")
        ).reject do |item|
          NovaStationPinballReviewSubmission::TERMINAL_STATES.include?(
            item.fetch("state")
          )
        end
        draft = NovaStationPinballReviewSubmission.resumable_draft!(
          current, required
        )
        unless draft && draft.fetch("id") == submission.fetch("id")
          raise "Review draft identity drifted before item transport"
        end
        NovaStationPinballReviewSubmission.require_missing_resource!(
          draft, [type, resource_id]
        )
      end
      NovaStationPinballReviewSubmission.guarded_mutation(
        proof, preflight: item_preflight
      ) do
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

    exact_resources =
      NovaStationPinballReviewSubmission.exact_submission_resources!(
        client, submission.fetch("id"), required
      )

    submit_proof = {
      intent_path: File.join(logs, "review-submit-intent.json"),
      receipt_path: File.join(logs, "review-submit-receipt.json"),
      kind: "submit_review", candidate_id: candidate_id,
      version: version_string,
      payload: proof_release.merge(
        "action" => "submit", "submission_id" => submission.fetch("id"),
        "resources" => exact_resources.sort
      )
    }
    submit_preflight = lambda do
      release_resources_guard.call
      current = NovaStationPinballReviewSubmission.submissions(
        client, app.fetch("id")
      ).reject do |item|
        NovaStationPinballReviewSubmission::TERMINAL_STATES.include?(
          item.fetch("state")
        )
      end
      draft = NovaStationPinballReviewSubmission.resumable_draft!(
        current, required
      )
      unless draft && draft.fetch("id") == submission.fetch("id")
        raise "Review draft identity drifted before submission transport"
      end
      NovaStationPinballReviewSubmission.exact_submission_resources!(
        client, submission.fetch("id"), required
      )
    end
    NovaStationPinballReviewSubmission.guarded_mutation(
      submit_proof, preflight: submit_preflight
    ) do
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
         NovaStationPinballReleaseSupport::PretransportFailure,
         NovaStationPinballAscError => error
    warn "review_submission: #{error.message}"
    exit 1
  end
end
