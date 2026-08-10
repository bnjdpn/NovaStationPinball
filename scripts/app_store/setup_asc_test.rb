# frozen_string_literal: true

require "minitest/autorun"
require_relative "setup_asc"

class NovaStationPinballAscSetupTest < Minitest::Test
  CONFIG = {
    "app_store_name" => "Nova Station Pinball",
    "bundle_id" => "com.bnjdpn.NovaStationPinball",
    "sku" => "nova-station-pinball-ios",
    "primary_locale" => "en-US"
  }.freeze

  class FakeClient
    attr_reader :requests

    def initialize(apps)
      @apps = apps
      @requests = []
    end

    def get_all(path, parameters)
      @requests << [path, parameters]
      { "data" => @apps }
    end
  end

  def test_missing_preflight_accepts_only_zero_exact_records
    client = FakeClient.new([])

    result = NovaStationPinballAscSetup.inspect!(
      client: client, config: CONFIG, expectation: :missing
    )

    assert_equal "missing", result.fetch("status")
    assert_equal false, result.fetch("mutations")
    assert_equal "com.bnjdpn.NovaStationPinball",
                 client.requests.fetch(0).fetch(1).fetch("filter[bundleId]")

    assert_raises(NovaStationPinballAscSetup::SetupError) do
      NovaStationPinballAscSetup.inspect!(
        client: FakeClient.new([exact_app]),
        config: CONFIG, expectation: :missing
      )
    end
  end

  def test_ready_readback_requires_one_exact_name_bundle_sku_and_locale
    result = NovaStationPinballAscSetup.inspect!(
      client: FakeClient.new([exact_app]), config: CONFIG, expectation: :ready
    )

    assert_equal "ready", result.fetch("status")
    assert_equal "1234567890", result.fetch("app_id")
    assert_equal false, result.fetch("mutations")

    mismatched = exact_app
    mismatched["attributes"] = mismatched.fetch("attributes").merge(
      "sku" => "wrong-sku"
    )
    assert_raises(NovaStationPinballAscSetup::SetupError) do
      NovaStationPinballAscSetup.inspect!(
        client: FakeClient.new([mismatched]),
        config: CONFIG, expectation: :ready
      )
    end
  end

  def test_ready_readback_rejects_missing_or_ambiguous_records
    assert_raises(NovaStationPinballAscSetup::SetupError) do
      NovaStationPinballAscSetup.inspect!(
        client: FakeClient.new([]), config: CONFIG, expectation: :ready
      )
    end
    assert_raises(NovaStationPinballAscSetup::SetupError) do
      NovaStationPinballAscSetup.inspect!(
        client: FakeClient.new([exact_app, exact_app.merge("id" => "2")]),
        config: CONFIG, expectation: :ready
      )
    end
  end

  private

  def exact_app
    {
      "id" => "1234567890",
      "attributes" => {
        "name" => "Nova Station Pinball",
        "bundleId" => "com.bnjdpn.NovaStationPinball",
        "sku" => "nova-station-pinball-ios",
        "primaryLocale" => "en-US"
      }
    }
  end
end
