#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "client"
require_relative "status"

app_root = File.expand_path("../..", __dir__)
options = {
  config: File.join(app_root, "fastlane", "release_config.json"),
  key_path: ENV["ASC_API_KEY_PATH"]
}
OptionParser.new do |parser|
  parser.on("--bundle-id ID") { |value| options[:bundle_id] = value }
  parser.on("--config PATH") { |value| options[:config] = value }
  parser.on("--key-path PATH") { |value| options[:key_path] = value }
  parser.on("--apply") { options[:apply] = true }
end.parse!(ARGV)

begin
  raise "pricing is GET-only in the release pipeline; remove --apply" if options[:apply]
  config = NovaStationPinballAscStatus.load_config(options.fetch(:config))
  if options[:bundle_id] && options[:bundle_id] != config.fetch("bundle_id")
    raise "Bundle ID differs from release config"
  end
  client = NovaStationPinballAscClient.new(key_path: options.fetch(:key_path))
  app = NovaStationPinballAscStatus.find_app(client, config.fetch("bundle_id"))
  payload = NovaStationPinballAscStatus.pricing(client, app.fetch("id"), config)
  puts JSON.pretty_generate(payload)
  raise "ASC does not prove an exact free FRA/EUR schedule" unless payload["free"]
rescue ArgumentError, KeyError, RuntimeError, NovaStationPinballAscError => error
  warn "pricing: #{error.message}"
  exit 1
end
