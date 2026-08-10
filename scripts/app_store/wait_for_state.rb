#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"

module NovaStationPinballStateWaiter
  CONDITIONS = %w[metadata screenshots previews build selected submitted].freeze

  class TimeoutError < StandardError; end
  class FailedState < StandardError; end

  module_function

  def complete?(payload, condition, version:)
    case condition
    when "metadata" then payload.dig("metadata", "complete") == true
    when "screenshots" then payload.dig("assets", "screenshots_complete") == true
    when "previews" then payload.dig("assets", "previews_complete") == true
    when "build"
      target = payload.dig("target_build", "build").to_s
      !target.empty? && payload.fetch("recent_builds", []).any? do |build|
        build["build"].to_s == target && build["state"] == "VALID" &&
          build["expired"] != true
      end
    when "selected"
      target = payload.dig("target_build", "build").to_s
      selected = payload["selected_build"]
      !target.empty? && selected && selected["build"].to_s == target &&
        selected["state"] == "VALID" && selected["expired"] != true
    when "submitted"
      submitted?(payload, version)
    else
      raise ArgumentError, "Unknown wait condition #{condition.inspect}"
    end
  end

  def submitted?(payload, version)
    states = %w[WAITING_FOR_REVIEW IN_REVIEW UNRESOLVED_ISSUES]
    version_submitted = payload.dig("version", "version").to_s ==
      version.to_s && states.include?(payload.dig("version", "state"))
    submission = payload.fetch("review_submissions", []).any? do |item|
      states.include?(item["state"]) && item.fetch("items", []).any? do |review_item|
        review_item["version"].to_s == version.to_s
      end
    end
    version_submitted || submission
  end

  def fail_if_terminal!(payload, condition)
    media_failures = payload.dig("assets", "failed") || []
    if %w[screenshots previews].include?(condition) && !media_failures.empty?
      raise FailedState, "ASC media delivery entered FAILED"
    end
    return unless condition == "build"

    target = payload.dig("target_build", "build").to_s
    failed = payload.fetch("recent_builds", []).find do |build|
      build["build"].to_s == target &&
        %w[FAILED INVALID].include?(build["state"])
    end
    raise FailedState, "Target build #{target} entered #{failed['state']}" if failed
  end

  def wait(reader:, condition:, version:, timeout:, interval:,
           monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
           sleeper: Kernel.method(:sleep))
    raise ArgumentError, "Unknown wait condition" unless CONDITIONS.include?(condition)
    timeout = Float(timeout)
    interval = Float(interval)
    raise ArgumentError, "timeout must be positive" unless timeout.positive?
    raise ArgumentError, "interval must be positive" unless interval.positive?

    deadline = monotonic.call + timeout
    loop do
      payload = reader.call
      return payload if complete?(payload, condition, version: version)

      fail_if_terminal!(payload, condition)
      remaining = deadline - monotonic.call
      raise TimeoutError, "ASC #{condition} readback timed out" unless remaining.positive?

      sleeper.call([interval, remaining].min)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require_relative "status"
  options = {
    config: File.join(
      NovaStationPinballAscStatus::APP_ROOT, "fastlane", "release_config.json"
    ),
    key_path: ENV["ASC_API_KEY_PATH"],
    timeout: 900,
    interval: 15
  }
  OptionParser.new do |parser|
    parser.on("--condition NAME") { |value| options[:condition] = value }
    parser.on("--config PATH") { |value| options[:config] = value }
    parser.on("--key-path PATH") { |value| options[:key_path] = value }
    parser.on("--timeout SECONDS", Float) { |value| options[:timeout] = value }
    parser.on("--interval SECONDS", Float) { |value| options[:interval] = value }
  end.parse!(ARGV)

  begin
    config = NovaStationPinballAscStatus.load_config(options.fetch(:config))
    unless NovaStationPinballAscCredentials.available?(key_path: options[:key_path])
      raise ArgumentError, "Provide an ASC API key through bin/apple-release"
    end
    client = NovaStationPinballAscClient.new(key_path: options[:key_path])
    result = NovaStationPinballStateWaiter.wait(
      reader: lambda {
        NovaStationPinballAscStatus.read(client: client, config: config)
      },
      condition: options.fetch(:condition),
      version: config.fetch("version"),
      timeout: options.fetch(:timeout),
      interval: options.fetch(:interval)
    )
    puts JSON.generate(result)
  rescue ArgumentError, KeyError, RuntimeError, NovaStationPinballAscError,
         NovaStationPinballStateWaiter::TimeoutError,
         NovaStationPinballStateWaiter::FailedState => error
    warn "wait_for_state: #{error.message}"
    exit 1
  end
end
