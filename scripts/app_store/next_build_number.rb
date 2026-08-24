#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "yaml"
require_relative "client"

module NovaStationPinballNextBuildNumber
  PROJECT_SPEC_PATH = File.expand_path("../../project.yml", __dir__)

  class TargetError < StandardError; end

  module_function

  def load_project_spec(path)
    document = YAML.safe_load(
      File.binread(path), permitted_classes: [], permitted_symbols: [], aliases: false
    )
    raise TargetError, "project.yml must contain an object" unless document.is_a?(Hash)

    document
  rescue Errno::ENOENT, Psych::Exception => error
    raise TargetError, "Could not read local project settings: #{error.message}"
  end

  def local_build_number(project:, bundle_id:)
    targets = project.fetch("targets")
    unless targets.is_a?(Hash)
      raise TargetError, "project.yml targets must contain an object"
    end

    matches = targets.values.map do |target|
      settings = target.dig("settings", "base") if target.is_a?(Hash)
      next unless settings.is_a?(Hash)
      next unless settings["PRODUCT_BUNDLE_IDENTIFIER"] == bundle_id

      settings["CURRENT_PROJECT_VERSION"]
    end.compact
    unless matches.length == 1
      raise TargetError, "Expected one local app target for #{bundle_id}, found #{matches.length}"
    end

    build = matches.first.to_s
    unless build.match?(/\A[1-9][0-9]*\z/)
      raise TargetError, "Invalid local CURRENT_PROJECT_VERSION #{build.inspect}"
    end
    Integer(build, 10)
  rescue KeyError => error
    raise TargetError, "Invalid local project settings: #{error.message}"
  end

  def target(client:, project:, bundle_id:, version:)
    local_build = local_build_number(project: project, bundle_id: bundle_id)
    app = client.get_all("/v1/apps", {
      "filter[bundleId]" => bundle_id,
      "fields[apps]" => "bundleId",
      "limit" => "20"
    }).fetch("data").find do |item|
      item.dig("attributes", "bundleId") == bundle_id
    end
    raise TargetError, "App not found for #{bundle_id}" unless app

    builds = client.get_all("/v1/builds", {
      "filter[app]" => app.fetch("id"),
      "filter[preReleaseVersion.version]" => version,
      "filter[preReleaseVersion.platform]" => "IOS",
      "fields[builds]" => "version,processingState,uploadedDate,expired",
      "limit" => "200"
    }).fetch("data")
    numbers = builds.map { |build| Integer(build.dig("attributes", "version"), 10) }
    asc_next = numbers.empty? ? 1 : numbers.max + 1
    {
      "version" => version,
      "build" => [local_build, asc_next].max.to_s
    }
  end

  def run(argv, output: $stdout, error_output: $stderr,
          project_path: PROJECT_SPEC_PATH,
          client_factory: ->(key_path) { NovaStationPinballAscClient.new(key_path: key_path) })
    options = { key_path: ENV["ASC_API_KEY_PATH"] }
    OptionParser.new do |parser|
      parser.on("--bundle-id ID") { |value| options[:bundle_id] = value }
      parser.on("--version VERSION") { |value| options[:version] = value }
      parser.on("--key-path PATH") { |value| options[:key_path] = value }
    end.parse!(argv)

    %i[bundle_id version].each do |key|
      raise TargetError, "--#{key.to_s.tr('_', '-')} is required" if options[key].to_s.empty?
    end
    result = target(
      client: client_factory.call(options.fetch(:key_path)),
      project: load_project_spec(project_path),
      bundle_id: options.fetch(:bundle_id),
      version: options.fetch(:version)
    )
    output.puts JSON.generate(result)
    0
  rescue TargetError, ArgumentError, KeyError, RuntimeError, OptionParser::ParseError,
         NovaStationPinballAscError => error
    error_output.puts "next_build_number: #{error.message}"
    1
  end
end

exit NovaStationPinballNextBuildNumber.run(ARGV) if $PROGRAM_NAME == __FILE__
