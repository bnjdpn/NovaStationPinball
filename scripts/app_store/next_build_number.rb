#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "client"

options = { key_path: ENV["ASC_API_KEY_PATH"] }
OptionParser.new do |parser|
  parser.on("--bundle-id ID") { |value| options[:bundle_id] = value }
  parser.on("--version VERSION") { |value| options[:version] = value }
  parser.on("--key-path PATH") { |value| options[:key_path] = value }
end.parse!(ARGV)

begin
  %i[bundle_id version].each do |key|
    raise "--#{key.to_s.tr('_', '-')} is required" if options[key].to_s.empty?
  end
  client = NovaStationPinballAscClient.new(key_path: options.fetch(:key_path))
  app = client.get_all("/v1/apps", {
    "filter[bundleId]" => options.fetch(:bundle_id),
    "fields[apps]" => "bundleId",
    "limit" => "20"
  }).fetch("data").find do |item|
    item.dig("attributes", "bundleId") == options.fetch(:bundle_id)
  end
  raise "App not found for #{options.fetch(:bundle_id)}" unless app
  builds = client.get_all("/v1/builds", {
    "filter[app]" => app.fetch("id"),
    "filter[preReleaseVersion.version]" => options.fetch(:version),
    "filter[preReleaseVersion.platform]" => "IOS",
    "fields[builds]" => "version,processingState,uploadedDate,expired",
    "limit" => "200"
  }).fetch("data")
  numbers = builds.map { |build| Integer(build.dig("attributes", "version"), 10) }
  target = numbers.empty? ? 1 : numbers.max + 1
  puts JSON.generate("version" => options.fetch(:version), "build" => target.to_s)
rescue ArgumentError, KeyError, RuntimeError, NovaStationPinballAscError => error
  warn "next_build_number: #{error.message}"
  exit 1
end
