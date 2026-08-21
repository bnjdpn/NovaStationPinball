#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "client"
require_relative "status"

# Reads the App Store Connect in-app purchase catalogue back and enforces
# exactly what fastlane/release_config.json declares: every sold product with
# its declared purchase type, and every product retired by this release parked
# in its declared target state. Nothing about the catalogue is hard-coded here,
# so the readback keeps working when the sold product changes.
module NovaStationPinballIapStatus
  module_function

  def declared(config)
    config.fetch("iap_products").map do |product|
      { "product_id" => product.fetch("product_id"), "type" => product.fetch("type") }
    end
  end

  def retired(config)
    config.fetch("retired_iap_products", []).map do |product|
      {
        "product_id" => product.fetch("product_id"),
        "target_state" => product.fetch("target_state")
      }
    end
  end

  def find(items, product_id)
    items.find { |item| item.dig("attributes", "productId") == product_id }
  end

  # Every way the live catalogue can disagree with the release configuration,
  # named one by one so the failure says what to fix in App Store Connect.
  def problems(payload, declared_products, retired_products)
    items = payload.fetch("items")
    problems = []
    unless payload.fetch("missing_product_ids").empty?
      problems << "sold products are missing from App Store Connect: " \
                  "#{payload.fetch('missing_product_ids').join(', ')}"
    end
    unless payload.fetch("unexpected_product_ids").empty?
      problems << "App Store Connect holds products the release configuration " \
                  "does not declare: #{payload.fetch('unexpected_product_ids').join(', ')}"
    end
    declared_products.each do |product|
      item = find(items, product.fetch("product_id"))
      next unless item

      actual = item.dig("attributes", "inAppPurchaseType")
      next if actual == product.fetch("type")

      problems << "#{product.fetch('product_id')} is #{actual} in App Store " \
                  "Connect but the release configuration declares " \
                  "#{product.fetch('type')}"
    end
    retired_products.each do |product|
      item = find(items, product.fetch("product_id"))
      next unless item

      state = item.dig("attributes", "state")
      next if state == product.fetch("target_state")

      problems << "#{product.fetch('product_id')} is retired by this release " \
                  "but is still #{state} in App Store Connect; it must be set " \
                  "to #{product.fetch('target_state')}"
    end
    problems
  end

  def run!(argv, app_root: File.expand_path("../..", __dir__))
    options = {
      config: File.join(app_root, "fastlane", "release_config.json"),
      key_path: ENV["ASC_API_KEY_PATH"]
    }
    OptionParser.new do |parser|
      parser.on("--bundle-id ID") { |value| options[:bundle_id] = value }
      parser.on("--config PATH") { |value| options[:config] = value }
      parser.on("--key-path PATH") { |value| options[:key_path] = value }
    end.parse!(argv)

    config = NovaStationPinballAscStatus.load_config(options.fetch(:config))
    if options[:bundle_id] && options[:bundle_id] != config.fetch("bundle_id")
      raise "Bundle ID differs from release config"
    end

    declared_products = declared(config)
    retired_products = retired(config)
    declared_ids = declared_products.map { |product| product.fetch("product_id") }
    unless declared_ids.sort == config.fetch("iap").sort
      raise "release_config.iap does not mirror release_config.iap_products"
    end

    client = NovaStationPinballAscClient.new(key_path: options.fetch(:key_path))
    app = NovaStationPinballAscStatus.find_app(client, config.fetch("bundle_id"))
    payload = NovaStationPinballAscStatus.iap(
      client, app.fetch("id"), declared_ids,
      retired_products.map { |product| product.fetch("product_id") }
    )
    puts JSON.pretty_generate(payload)
    found = problems(payload, declared_products, retired_products)
    return if found.empty?

    raise "App Store Connect does not match the declared purchase catalogue: " \
          "#{found.join('; ')}"
  rescue ArgumentError, KeyError, RuntimeError, NovaStationPinballAscError => error
    warn "iap_status: #{error.message}"
    exit 1
  end
end

NovaStationPinballIapStatus.run!(ARGV) if $PROGRAM_NAME == __FILE__
