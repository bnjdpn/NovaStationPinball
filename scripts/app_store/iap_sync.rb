#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"

options = {}
OptionParser.new do |parser|
  parser.on("--apply") { options[:apply] = true }
  parser.on("--bundle-id ID") { |_value| }
  parser.on("--config PATH") { |_value| }
  parser.on("--key-path PATH") { |_value| }
end.parse!(ARGV)

if options[:apply]
  warn "iap_sync: mutations are intentionally fail-closed; prepare the three tip products in an explicitly authorized setup task, then use iap_status"
  exit 1
end

require_relative "iap_status"
