#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "client"

app_root = File.expand_path("../..", __dir__)
options = {
  config: File.join(app_root, "fastlane", "release_config.json"),
  key_path: ENV["ASC_API_KEY_PATH"]
}
OptionParser.new do |parser|
  parser.on("--config PATH") { |value| options[:config] = value }
  parser.on("--key-path PATH") { |value| options[:key_path] = value }
  parser.on("--apply") { options[:apply] = true }
end.parse!(ARGV)

begin
  raise "setup_asc does not create records implicitly; remove --apply" if options[:apply]
  config = JSON.parse(File.binread(options.fetch(:config)))
  client = NovaStationPinballAscClient.new(key_path: options.fetch(:key_path))
  apps = client.get_all("/v1/apps", {
    "filter[bundleId]" => config.fetch("bundle_id"),
    "fields[apps]" => "name,bundleId,sku,primaryLocale,contentRightsDeclaration",
    "limit" => "20"
  }).fetch("data").select do |item|
    item.dig("attributes", "bundleId") == config.fetch("bundle_id")
  end
  raise "ASC app record is missing; create it in an explicitly authorized setup task" if apps.empty?
  raise "ASC app record is ambiguous" unless apps.length == 1
  app = apps.first
  mismatches = []
  {
    "name" => config.fetch("app_store_name"),
    "bundleId" => config.fetch("bundle_id"),
    "sku" => config.fetch("sku"),
    "primaryLocale" => config.fetch("primary_locale")
  }.each do |field, expected|
    actual = app.dig("attributes", field)
    mismatches << "#{field}=#{actual.inspect}" unless actual == expected
  end
  unless mismatches.empty?
    raise "ASC app record differs from the release contract: #{mismatches.join(', ')}"
  end
  puts JSON.pretty_generate(
    "status" => "ready",
    "app_id" => app.fetch("id"),
    "bundle_id" => config.fetch("bundle_id"),
    "mutations" => false
  )
rescue ArgumentError, KeyError, JSON::ParserError, RuntimeError,
       NovaStationPinballAscError => error
  warn "setup_asc: #{error.message}"
  exit 1
end
