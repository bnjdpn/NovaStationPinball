#!/usr/bin/env ruby
# frozen_string_literal: true

# Capture the Workshop paywall for the App Store Connect review screenshot.
#
# App Store Connect refuses to send a brand-new in-app purchase to review
# without a screenshot of the purchase screen, and App Review rejects a capture
# that shows an empty paywall ("we were unable to locate the in-app purchase").
# So the capture has to be produced by machinery that fails when the offer does
# not load, not by a human pointing a camera at a simulator.
#
# The route:
#
#   1. `-paywall-screenshot` opens the paywall at launch AND turns the store
#      bypass off (`StoreService.isStoreBypassEnabled`), so the capture shows
#      the real locked offer, never the "already unlocked" state.
#   2. `NovaStationPinballUITests/PaywallReviewUITests` drives StoreKit through
#      `SKTestSession`, loading `NovaStationPinball.storekit` out of the UI test
#      bundle and pinning the storefront to the base territory declared in
#      `fastlane/pro_products.json`. The scheme's `run.storeKitConfiguration`
#      cannot do this: `xcodebuild test` only applies it to the Run action, so
#      the app under test would query the live App Store catalogue and
#      photograph whatever price App Store Connect happens to carry.
#   3. The test attaches the PNG and, next to it, the exact price string the
#      paywall rendered.
#
# Alongside the PNG this writes a sidecar JSON: the rendered price plus the
# SHA-256 of the PNG it came from. That sidecar is what turns "look at it" into
# a machine check — `scripts/release_contract.rb` refuses a capture whose price
# differs from `fastlane/pro_products.json`, and refuses a sidecar that does not
# belong to the PNG sitting next to it. Never hand-edit the sidecar; recapture.
#
# Usage:
#   ruby scripts/capture_paywall_review_screenshot.rb --udid <UUID>
#
# The UDID must be an execution-owned simulator: never `booted`, never a device
# name. The capture runbook requires an iPad Pro 13-inch (M5) — the test itself
# refuses any other raster.

require "digest"
require "fileutils"
require "json"
require "optparse"
require "tmpdir"

module NovaPaywallCapture
  APP_ROOT = File.expand_path("..", __dir__)
  SCHEME = "NovaStationPinball"
  BUNDLE_ID = "com.bnjdpn.NovaStationPinball"
  TEST_IDENTIFIER = "NovaStationPinballUITests/PaywallReviewUITests/" \
                    "testCapturesTheWorkshopPaywallForReviewWithoutPurchasing"
  SCREENSHOT_ATTACHMENT = "iap-review-workshop-ipad-pro-13-m5-landscape"
  PRICE_ATTACHMENT = "iap-review-workshop-price"
  SPEC_PATH = File.join(APP_ROOT, "fastlane", "pro_products.json")
  DEFAULT_OUTPUT = File.join(APP_ROOT, "review_assets", "workshop_paywall_review.png")
  DEFAULT_DERIVED_DATA = "/private/tmp/apps-factory/NovaStationPinball/cache/DerivedData"
  UDID = /\A[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\z/
  # App Store Connect rejects review screenshots below 640x920.
  MIN_SIZE = [640, 920].freeze
  # xcresulttool decorates every attachment name with its index and a UUID:
  # `foo` comes back as `foo_0_251E2BFA-5715-4F70-8D05-5B57438F606B.png`.
  DECORATED = /\A(?<name>.+?)_\d+_[0-9A-Fa-f-]{36}\.[A-Za-z0-9]+\z/

  class CaptureError < StandardError; end

  module_function

  def parse_options(argv)
    options = {
      udid: ENV.fetch("FACTORY_SIMULATOR_UDID", ""),
      output: DEFAULT_OUTPUT,
      derived_data: DEFAULT_DERIVED_DATA
    }
    OptionParser.new do |parser|
      parser.banner = "Usage: capture_paywall_review_screenshot.rb --udid <UUID>"
      parser.on("--udid UUID") { |value| options[:udid] = value }
      parser.on("--output PATH") { |value| options[:output] = value }
      parser.on("--derived-data PATH") { |value| options[:derived_data] = value }
    end.parse!(argv)
    options
  end

  def validated_udid(value)
    value = value.to_s.strip
    unless UDID.match?(value)
      raise CaptureError,
            "--udid must be an execution-owned simulator UUID (never a device name, " \
            "never `booted`): #{value.inspect}"
    end
    value
  end

  def run!(command)
    warn("$ #{command.join(' ')}")
    raise CaptureError, "command failed: #{command.join(' ')}" unless system(*command, chdir: APP_ROOT)
  end

  def png_size(path)
    header = File.binread(path, 24).to_s
    raise CaptureError, "not a PNG file: #{path}" unless header[0, 8] == "\x89PNG\r\n\x1a\n".b
    header[16, 8].unpack("N2")
  end

  # `XCTAttachment(screenshot:)` writes the raw device raster and ignores the
  # interface orientation, so a landscape-only app comes back as a portrait PNG
  # rotated a quarter turn counter-clockwise. Uploaded as-is, App Review is
  # handed a sideways purchase screen. The rotation is conditional rather than
  # unconditional so that the day the raster arrives already upright, this stops
  # turning a correct capture into a wrong one.
  def normalize_orientation!(path)
    width, height = png_size(path)
    return [width, height] if width >= height

    run!(["sips", "--rotate", "90", path])
    width, height = png_size(path)
    unless width > height
      raise CaptureError, "the capture is still not landscape after rotation: #{width}x#{height}"
    end
    [width, height]
  end

  def attachment_name(suggested)
    match = DECORATED.match(suggested.to_s)
    match ? match[:name] : File.basename(suggested.to_s, ".*")
  end

  # The one exported file whose attachment name is exactly `name`. Matching on
  # a prefix is not enough: the price attachment and the screenshot share the
  # capture, and a failed run adds two more attachments whose names would also
  # match loosely.
  def exported_attachment(manifest_path, export_dir, name)
    payload = JSON.parse(File.read(manifest_path))
    entries = (payload.is_a?(Array) ? payload : [payload]).flat_map { |run| run.fetch("attachments", []) }
    matches = entries.select { |entry| attachment_name(entry["suggestedHumanReadableName"]) == name }
    unless matches.length == 1
      names = entries.map { |entry| entry["suggestedHumanReadableName"].to_s }.sort
      raise CaptureError,
            "expected exactly one #{name.inspect} attachment, got #{matches.length}; " \
            "attachments were #{names.inspect}"
    end
    File.join(export_dir, matches.first.fetch("exportedFileName"))
  end

  def spec_offer
    spec = JSON.parse(File.read(SPEC_PATH, encoding: "UTF-8"))
    product = spec.fetch("products").first
    {
      "product_id" => product.fetch("product_id"),
      "base_price" => product.fetch("base_price").to_s,
      "base_territory" => spec.fetch("base_territory", "FRA"),
      "base_currency" => spec.fetch("base_currency", "EUR")
    }
  end

  def write_sidecar(output, displayed_price, size)
    offer = spec_offer
    sidecar = output.sub(/\.png\z/, ".json")
    File.write(
      sidecar,
      JSON.pretty_generate(
        "captured_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S+00:00"),
        "screenshot" => File.basename(output),
        "screenshot_sha256" => Digest::SHA256.hexdigest(File.binread(output)),
        "screenshot_size" => size,
        "product_id" => offer.fetch("product_id"),
        "displayed_price" => displayed_price,
        "storefront" => offer.fetch("base_territory"),
        "expected_base_price" => offer.fetch("base_price"),
        "expected_base_currency" => offer.fetch("base_currency"),
        "price_source" => "NovaStationPinball.storekit via SKTestSession, pinned to the " \
                          "base territory of fastlane/pro_products.json"
      ) + "\n",
      encoding: "UTF-8"
    )
    sidecar
  end

  def main(argv)
    options = parse_options(argv)
    udid = validated_udid(options[:udid])
    output = File.expand_path(options[:output])
    unless output.start_with?("#{APP_ROOT}#{File::SEPARATOR}")
      raise CaptureError, "--output must stay inside #{APP_ROOT}: #{output}"
    end

    # App Review must see a fresh install: a container left over from a previous
    # run carries settings and a Founder flag, and a Founder install never sees
    # the paywall at all. Scoped to this bundle on the leased simulator: never a
    # device-wide erase, never `booted`.
    system("xcrun", "simctl", "uninstall", udid, BUNDLE_ID, out: File::NULL, err: File::NULL)

    width = height = nil
    sidecar = nil
    displayed_price = nil
    Dir.mktmpdir("nova-paywall-capture-") do |scratch|
      result_bundle = File.join(scratch, "capture.xcresult")
      run!(
        [
          "xcodebuild", "test",
          "-scheme", SCHEME,
          "-destination", "platform=iOS Simulator,id=#{udid}",
          "-derivedDataPath", options[:derived_data],
          "-resultBundlePath", result_bundle,
          "-only-testing:#{TEST_IDENTIFIER}",
          "-parallel-testing-enabled", "NO",
          "CODE_SIGNING_ALLOWED=NO"
        ]
      )

      export_dir = File.join(scratch, "attachments")
      run!(
        [
          "xcrun", "xcresulttool", "export", "attachments",
          "--path", result_bundle,
          "--output-path", export_dir
        ]
      )

      manifest = File.join(export_dir, "manifest.json")
      captured = exported_attachment(manifest, export_dir, SCREENSHOT_ATTACHMENT)
      width, height = png_size(captured)
      if width < MIN_SIZE[0] || height < MIN_SIZE[1]
        raise CaptureError,
              "captured paywall is #{width}x#{height}, below the App Store Connect " \
              "minimum #{MIN_SIZE[0]}x#{MIN_SIZE[1]}"
      end

      displayed_price = File.read(
        exported_attachment(manifest, export_dir, PRICE_ATTACHMENT),
        encoding: "UTF-8"
      ).strip
      if displayed_price.empty?
        raise CaptureError, "the UI test attached an empty price; the capture cannot be verified"
      end

      FileUtils.mkdir_p(File.dirname(output))
      FileUtils.cp(captured, output)
      width, height = normalize_orientation!(output)
      sidecar = write_sidecar(output, displayed_price, [width, height])
    end

    puts "paywall review screenshot: #{output} (#{width}x#{height})"
    puts "paywall review sidecar:    #{sidecar} (price #{displayed_price.inspect})"
    0
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit(NovaPaywallCapture.main(ARGV))
  rescue NovaPaywallCapture::CaptureError => error
    warn("error: #{error.message}")
    exit(1)
  end
end
