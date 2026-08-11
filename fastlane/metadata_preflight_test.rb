# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "metadata_preflight"

gem "fastlane", "2.237.0"
require "fastlane"
require "fastlane/actions/upload_to_app_store"

class NovaStationPinballMetadataPreflightTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_historical_relative_rating_path_fails_before_action_run
    action_runs = 0
    error = assert_raises(FastlaneCore::Interface::FastlaneError) do
      Dir.chdir(ROOT) do
        configuration = FastlaneCore::Configuration.create(
          Fastlane::Actions::UploadToAppStoreAction.available_options,
          app_rating_config_path: "./metadata/app_rating_config.json"
        )
        action_runs += 1
        Fastlane::Actions::UploadToAppStoreAction.run(configuration)
      end
    end

    assert_includes error.message, "Could not find config file"
    assert_equal 0, action_runs
  end

  def test_preflight_returns_absolute_configuration_accepted_offline
    config = JSON.parse(File.binread(File.join(ROOT, "fastlane", "release_config.json")))
    paths = NovaStationPinballMetadataPreflight.resolve!(
      root: ROOT, config: config
    )

    assert Pathname.new(paths.fetch(:metadata_path)).absolute?
    assert Pathname.new(paths.fetch(:app_rating_config_path)).absolute?
    configuration = Dir.chdir(ROOT) do
      FastlaneCore::Configuration.create(
        Fastlane::Actions::UploadToAppStoreAction.available_options,
        app_rating_config_path: paths.fetch(:app_rating_config_path)
      )
    end
    assert_equal paths.fetch(:app_rating_config_path),
                 configuration[:app_rating_config_path]
  end

  def test_preflight_rejects_a_symlinked_metadata_component
    Dir.mktmpdir("nova-metadata-preflight", "/private/tmp") do |root|
      FileUtils.mkdir_p(File.join(root, "fastlane"))
      File.symlink(File.join(ROOT, "fastlane", "metadata"),
                   File.join(root, "fastlane", "metadata"))
      config = { "age_rating" => "fastlane/metadata/app_rating_config.json" }

      assert_raises(ArgumentError) do
        NovaStationPinballMetadataPreflight.resolve!(root: root, config: config)
      end
    end
  end
end
