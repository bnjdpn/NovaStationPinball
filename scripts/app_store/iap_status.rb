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
end.parse!(ARGV)

begin
  config = NovaStationPinballAscStatus.load_config(options.fetch(:config))
  if options[:bundle_id] && options[:bundle_id] != config.fetch("bundle_id")
    raise "Bundle ID differs from release config"
  end
  client = NovaStationPinballAscClient.new(key_path: options.fetch(:key_path))
  app = NovaStationPinballAscStatus.find_app(client, config.fetch("bundle_id"))
  payload = NovaStationPinballAscStatus.iap(
    client, app.fetch("id"), config.fetch("iap")
  )
  puts JSON.pretty_generate(payload)
  exact = payload.fetch("missing_product_ids").empty? &&
    payload.fetch("unexpected_product_ids").empty? &&
    payload.fetch("actual_count") == payload.fetch("expected_count") &&
    payload.fetch("items").all? do |item|
      item.dig("attributes", "inAppPurchaseType") == "CONSUMABLE"
    end
  raise "ASC does not contain exactly the three optional consumable tips" unless exact
rescue ArgumentError, KeyError, RuntimeError, NovaStationPinballAscError => error
  warn "iap_status: #{error.message}"
  exit 1
end
