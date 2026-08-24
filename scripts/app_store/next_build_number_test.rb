# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "next_build_number"

class NovaStationPinballNextBuildNumberTest < Minitest::Test
  BUNDLE_ID = "com.bnjdpn.NovaStationPinball"
  LOCAL_PROJECT = {
    "targets" => {
      "NovaStationPinball" => {
        "settings" => {
          "base" => {
            "PRODUCT_BUNDLE_IDENTIFIER" => BUNDLE_ID,
            "MARKETING_VERSION" => "1.1",
            "CURRENT_PROJECT_VERSION" => "2"
          }
        }
      }
    }
  }.freeze

  class FakeClient
    attr_reader :requests

    def initialize(builds:)
      @builds = builds
      @requests = []
    end

    def get_all(path, parameters)
      @requests << [path, parameters]
      case path
      when "/v1/apps"
        {
          "data" => [{
            "id" => "6799920176",
            "attributes" => { "bundleId" => BUNDLE_ID }
          }]
        }
      when "/v1/builds"
        {
          "data" => @builds.map do |number|
            { "attributes" => { "version" => number.to_s } }
          end
        }
      else
        raise "Unexpected GET #{path}"
      end
    end
  end

  def test_no_asc_build_never_lowers_local_build_two
    client = FakeClient.new(builds: [])

    result = target(client)

    assert_equal({ "version" => "1.0", "build" => "2" }, result)
    assert_equal "1.0",
                 client.requests.fetch(1).fetch(1).fetch("filter[preReleaseVersion.version]")
  end

  def test_asc_build_one_keeps_local_build_two
    assert_equal "2", target(FakeClient.new(builds: [1])).fetch("build")
  end

  def test_existing_asc_build_two_advances_to_three
    assert_equal "3", target(FakeClient.new(builds: [2])).fetch("build")
  end

  def test_cli_uses_repository_current_project_version_as_asc_floor
    output = StringIO.new
    error_output = StringIO.new
    client = FakeClient.new(builds: [])

    status = NovaStationPinballNextBuildNumber.run(
      ["--bundle-id", BUNDLE_ID, "--version", "1.0"],
      output: output,
      error_output: error_output,
      client_factory: ->(_key_path) { client }
    )

    assert_equal 0, status
    assert_equal({ "version" => "1.0", "build" => "2" }, JSON.parse(output.string))
    assert_empty error_output.string
  end

  private

  def target(client)
    NovaStationPinballNextBuildNumber.target(
      client: client,
      project: LOCAL_PROJECT,
      bundle_id: BUNDLE_ID,
      version: "1.0"
    )
  end
end
