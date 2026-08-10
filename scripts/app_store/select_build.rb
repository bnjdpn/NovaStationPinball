#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "time"
require_relative "client"
require_relative "../../fastlane/release_support"

module NovaStationPinballBuildSelection
  module_function

  def selected_build_matches?(client, version_id, build_id)
    response = client.get(
      "/v1/appStoreVersions/#{version_id}/build",
      {
        "fields[builds]" => "version,processingState,expired"
      },
      optional: true
    )
    selected = response && response["data"]
    selected && selected["id"] == build_id &&
      selected.dig("attributes", "processingState") == "VALID" &&
      selected.dig("attributes", "expired") != true
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
  options = {
    config: File.join(app_root, "fastlane", "release_config.json"),
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
    raise "Bundle ID differs from release config" unless bundle_id == config.fetch("bundle_id")
    raise "Version differs from release config" unless version_string == config.fetch("version")
    raise "Build must be a positive integer" unless build_number.match?(/\A[1-9][0-9]*\z/)
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
    client = NovaStationPinballAscClient.new(key_path: options.fetch(:key_path))
    app = client.get_all("/v1/apps", {
      "filter[bundleId]" => bundle_id,
      "fields[apps]" => "bundleId",
      "limit" => "20"
    }).fetch("data").find do |item|
      item.dig("attributes", "bundleId") == bundle_id
    end
    raise "App not found for #{bundle_id}" unless app
    version = client.get_all(
      "/v1/apps/#{app.fetch('id')}/appStoreVersions",
      {
        "filter[platform]" => "IOS",
        "filter[versionString]" => version_string,
        "fields[appStoreVersions]" => "versionString,appStoreState,build",
        "limit" => "20"
      }
    ).fetch("data").find do |item|
      item.dig("attributes", "versionString") == version_string
    end
    raise "Version #{version_string} not found" unless version
    builds = client.get_all("/v1/builds", {
      "filter[app]" => app.fetch("id"),
      "filter[preReleaseVersion.version]" => version_string,
      "filter[preReleaseVersion.platform]" => "IOS",
      "fields[builds]" => "version,processingState,uploadedDate,expired",
      "limit" => "200"
    }).fetch("data").select do |item|
      item.dig("attributes", "version").to_s == build_number
    end
    raise "Build #{build_number} is missing or ambiguous" unless builds.length == 1
    build = builds.first
    unless build.dig("attributes", "processingState") == "VALID" &&
           build.dig("attributes", "expired") != true
      raise "Build #{build_number} is not a valid non-expired build"
    end

    if NovaStationPinballBuildSelection.selected_build_matches?(
      client, version.fetch("id"), build.fetch("id")
    )
      puts "Build #{build_number} is already selected"
      exit 0
    end

    proof = {
      intent_path: File.join(release_logs, "select-build-intent.json"),
      receipt_path: File.join(release_logs, "select-build-receipt.json"),
      kind: "select_build",
      candidate_id: candidate_id,
      version: version_string,
      payload: { "build" => build_number, "build_id" => build.fetch("id") }
    }
    begin
      NovaStationPinballReleaseSupport.transport_once!(**proof) do
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
         NovaStationPinballAscError => error
    warn "select_build: #{error.message}"
    exit 1
  end
end
