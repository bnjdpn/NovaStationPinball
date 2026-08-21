#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require_relative "iap_status"

# Mutating the App Store Connect purchase catalogue is never a side effect of a
# release lane: the products are provisioned by an explicitly authorized setup
# task, and this lane only reads the catalogue back.
argv = ARGV.dup
options = {}
OptionParser.new do |parser|
  parser.on("--apply") { options[:apply] = true }
  parser.on("--bundle-id ID") { |_value| }
  parser.on("--config PATH") { |_value| }
  parser.on("--key-path PATH") { |_value| }
end.parse!(argv.dup)

if options[:apply]
  warn "iap_sync: mutations are intentionally fail-closed; provision the products declared by fastlane/pro_products.json in an explicitly authorized setup task, then use iap_status"
  exit 1
end

NovaStationPinballIapStatus.run!(argv.reject { |value| value == "--apply" })
