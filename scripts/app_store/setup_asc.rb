#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"

module NovaStationPinballAscSetup
  REQUIRED_FIELDS = {
    "name" => "app_store_name",
    "bundleId" => "bundle_id",
    "sku" => "sku",
    "primaryLocale" => "primary_locale"
  }.freeze

  class SetupError < StandardError; end

  module_function

  def inspect!(client:, config:, expectation:)
    unless %i[missing ready].include?(expectation)
      raise SetupError, "unsupported ASC setup expectation"
    end
    expected = REQUIRED_FIELDS.to_h do |attribute, config_key|
      value = config.fetch(config_key)
      unless value.instance_of?(String) && !value.empty?
        raise SetupError, "release configuration has an invalid #{config_key}"
      end
      [attribute, value]
    end
    bundle_id = expected.fetch("bundleId")
    apps = client.get_all("/v1/apps", {
      "filter[bundleId]" => bundle_id,
      "fields[apps]" => "name,bundleId,sku,primaryLocale,contentRightsDeclaration",
      "limit" => "20"
    }).fetch("data").select do |item|
      item.dig("attributes", "bundleId") == bundle_id
    end

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
    {
      "status" => "ready",
      "app_id" => app.fetch("id"),
      "bundle_id" => bundle_id,
      "mutations" => false
    }
  rescue KeyError => error
    raise SetupError, "ASC setup payload is incomplete: #{error.message}"
  end

  module CLI
    module_function

    def run(argv)
      require_relative "client"
      app_root = File.expand_path("../..", __dir__)
      options = {
        config: File.join(app_root, "fastlane", "release_config.json"),
        key_path: ENV["ASC_API_KEY_PATH"],
        expectation: :ready
      }
      OptionParser.new do |parser|
        parser.on("--config PATH") { |value| options[:config] = value }
        parser.on("--key-path PATH") { |value| options[:key_path] = value }
        parser.on("--expect-missing") { options[:expectation] = :missing }
        parser.on("--apply") do
          raise SetupError,
                "setup_asc is GET-only; create the app in App Store Connect web after explicit authorization"
        end
      end.parse!(argv)

      config = JSON.parse(File.binread(options.fetch(:config)))
      client = NovaStationPinballAscClient.new(
        key_path: options.fetch(:key_path)
      )
      puts JSON.pretty_generate(
        NovaStationPinballAscSetup.inspect!(
          client: client, config: config,
          expectation: options.fetch(:expectation)
        )
      )
      0
    rescue ArgumentError, KeyError, JSON::ParserError, OptionParser::ParseError,
           NovaStationPinballAscSetup::SetupError,
           NovaStationPinballAscError => error
      warn "setup_asc: #{error.message}"
      1
    end
  end
end

exit NovaStationPinballAscSetup::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
