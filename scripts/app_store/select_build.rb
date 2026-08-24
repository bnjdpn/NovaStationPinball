#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "time"
require_relative "client"
require_relative "rejected_submission_recovery"
require_relative "release_provenance"
require_relative "../../fastlane/release_support"

module NovaStationPinballBuildSelection
  module_function

  def selected_build_matches?(client, version_id, build_id,
                              contract: NovaStationPinballReleaseProvenance::CURRENT)
    return false unless build_id == contract.asc_build_id

    NovaStationPinballReleaseProvenance.selected_build_exact?(
      client: client, version_id: version_id, contract: contract
    )
  end

  def wait_until_selected(client, version_id, build_id, timeout:, interval:)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Float(timeout)
    loop do
      return true if selected_build_matches?(client, version_id, build_id)
      raise "Selected-build readback timed out" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep(Float(interval))
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
    parser.on("--build BUILD") { |value| options[:build] = value }
    parser.on("--key-path PATH") { |value| options[:key_path] = value }
    parser.on("--config PATH") { |value| options[:config] = value }
    parser.on("--timeout SECONDS", Float) { |value| options[:timeout] = value }
    parser.on("--interval SECONDS", Float) { |value| options[:interval] = value }
  end.parse!(ARGV)

  begin
    config = JSON.parse(File.binread(options.fetch(:config)))
    bundle_id = options.fetch(:bundle_id)
    version_string = options.fetch(:version)
    build_number = options.fetch(:build).to_s
    unless File.expand_path(options.fetch(:config)) == release_config_path &&
           File.file?(release_config_path) && !File.symlink?(release_config_path)
      raise "Build selection requires the checked-in release configuration"
    end
    raise "Bundle ID differs from release config" unless bundle_id == config.fetch("bundle_id")
    raise "Version differs from release config" unless version_string == config.fetch("version")
    raise "Build must be a positive integer" unless build_number.match?(/\A[1-9][0-9]*\z/)
    NovaStationPinballReleaseProvenance.verify_release_arguments!(
      bundle_id: bundle_id, version: version_string, build: build_number
    )
    candidate_id = NovaStationPinballReleaseSupport.candidate_id!(
      ENV["APPS_FACTORY_CANDIDATE_ID"]
    )
    run_id = NovaStationPinballReleaseSupport.run_id!(
      ENV["RELEASE_RUN_ID"].to_s.empty? ?
        ENV["APP_RELEASE_RUN_ID"] : ENV["RELEASE_RUN_ID"]
    )
    release_logs = File.join(
      app_root, config.fetch("artifact_root"), run_id, "logs"
    )
    local_release = NovaStationPinballReleaseProvenance.verify_local!(
      run_id: run_id, candidate_id: candidate_id
    )
    client = NovaStationPinballAscClient.new(key_path: options.fetch(:key_path))
    build = NovaStationPinballReleaseProvenance.verify_live_build!(client: client)
    version = NovaStationPinballReleaseProvenance.verify_app_version!(
      client: client, allowed_states: ["REJECTED"]
    )
    release_identity = NovaStationPinballReleaseProvenance.release_identity(
      local: local_release, build: build
    )
    source_notes =
      NovaStationPinballRejectedSubmissionRecovery::SourceNotes.load!(
        app_review_path: File.join(
          app_root, "fastlane", "metadata", "review_information", "notes.txt"
        ),
        products_path: File.join(app_root, "fastlane", "pro_products.json")
      )
    NovaStationPinballRejectedSubmissionRecovery.verify_recovery_complete!(
      client: client, source_notes: source_notes
    )
    NovaStationPinballReleaseProvenance.verify_review_readiness!(client: client)
    selection_state = NovaStationPinballReleaseProvenance.selected_build_state!(
      client: client, version_id: version.fetch("id")
    )
    mutation_guard = lambda do
      local = NovaStationPinballReleaseProvenance.verify_local!(
        run_id: run_id, candidate_id: candidate_id
      )
      NovaStationPinballReleaseProvenance.verify_remote!
      current_build = NovaStationPinballReleaseProvenance.verify_live_build!(
        client: client
      )
      current_version = NovaStationPinballReleaseProvenance.verify_app_version!(
        client: client, allowed_states: ["REJECTED"]
      )
      current = NovaStationPinballReleaseProvenance.release_identity(
        local: local, build: current_build
      )
      unless current == release_identity && current_version.fetch("id") == version.fetch("id")
        raise "Release provenance drifted before build selection transport"
      end
      NovaStationPinballRejectedSubmissionRecovery.verify_recovery_complete!(
        client: client, source_notes: source_notes
      )
      NovaStationPinballReleaseProvenance.verify_review_readiness!(client: client)
      unless NovaStationPinballReleaseProvenance.selected_build_state!(
        client: client, version_id: current_version.fetch("id")
      ) == :source
        raise "Build selection source changed before transport"
      end
    end

    if selection_state == :target
      puts "Build #{build_number} is already selected"
      exit 0
    end

    proof = {
      intent_path: File.join(release_logs, "select-build-intent.json"),
      receipt_path: File.join(release_logs, "select-build-receipt.json"),
      kind: "select_build",
      candidate_id: candidate_id,
      version: version_string,
      payload: {
        "run_id" => run_id,
        "source_head" => release_identity.fetch("source_head"),
        "app_version_id" => version.fetch("id"),
        "build" => build_number,
        "build_id" => build.fetch("id"),
        "uploaded_date" => release_identity.fetch("uploaded_date"),
        "ipa_sha256" => release_identity.fetch("ipa_sha256")
      }
    }
    begin
      existing_intent = File.exist?(proof.fetch(:intent_path)) ||
        File.symlink?(proof.fetch(:intent_path))
      NovaStationPinballReleaseSupport.transport_once!(
        **proof, preflight: existing_intent ? nil : mutation_guard
      ) do
        client.patch(
          "/v1/appStoreVersions/#{version.fetch('id')}/relationships/build",
          { data: { type: "builds", id: build.fetch("id") } }
        )
      end
    rescue NovaStationPinballReleaseSupport::AmbiguousTransport => error
      warn "#{error.message}; continuing with GET-only selected-build verification"
    end
    NovaStationPinballBuildSelection.wait_until_selected(
      client, version.fetch("id"), build.fetch("id"),
      timeout: options.fetch(:timeout), interval: options.fetch(:interval)
    )
    NovaStationPinballReleaseSupport.mark_observed!(**proof)
    puts "Selected build #{build_number} for #{bundle_id} #{version_string}"
  rescue ArgumentError, KeyError, JSON::ParserError, RuntimeError,
         NovaStationPinballReleaseProvenance::Error,
         NovaStationPinballReleaseSupport::PretransportFailure,
         NovaStationPinballAscError => error
    warn "select_build: #{error.message}"
    exit 1
  end
end
