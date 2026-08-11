# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "metadata_pretransport_recovery"

class NovaStationPinballMetadataPretransportRecoveryTest < Minitest::Test
  CANDIDATE = "a" * 64
  RUN_ID = "nova-metadata-recovery-test"

  def test_archives_exact_historical_proofs_only_after_fresh_incomplete_get
    with_fixture do |fixture|
      result = fixture.fetch(:recovery).recover!(
        status_reader: -> { incomplete_status }
      )

      assert_equal :recovered, result.fetch("state").to_sym
      fixture.fetch(:active).each_value { |path| refute File.exist?(path) }
      fixture.fetch(:archive).each_value do |path|
        assert File.exist?(path)
        assert_equal 0o600, File.stat(path).mode & 0o777
      end
      assert_equal :already_recovered,
                   fixture.fetch(:recovery).recover!(
                     status_reader: -> { flunk "GET must not repeat after exact recovery" }
                   ).fetch("state").to_sym
    end
  end

  def test_refuses_cleanup_when_fresh_get_reports_metadata_complete
    with_fixture do |fixture|
      assert_raises(
        NovaStationPinballMetadataPretransportRecovery::RecoveryError
      ) do
        fixture.fetch(:recovery).recover!(
          status_reader: -> { complete_status }
        )
      end
      fixture.fetch(:active).each_value { |path| assert File.exist?(path) }
      fixture.fetch(:archive).each_value { |path| refute File.exist?(path) }
    end
  end

  def test_refuses_cleanup_on_any_historical_hash_drift
    with_fixture do |fixture|
      File.binwrite(fixture.dig(:active, :intent), "drift")
      assert_raises(
        NovaStationPinballMetadataPretransportRecovery::RecoveryError
      ) do
        fixture.fetch(:recovery).recover!(status_reader: -> { incomplete_status })
      end
      assert File.exist?(fixture.dig(:active, :intent))
      fixture.fetch(:archive).each_value { |path| refute File.exist?(path) }
    end
  end

  def test_refuses_recovery_without_the_exact_offline_pretransport_proof
    assert_raises(
      NovaStationPinballMetadataPretransportRecovery::RecoveryError
    ) do
      with_fixture(pretransport_proven: false) do |fixture|
        fixture.fetch(:recovery).recover!(status_reader: -> { incomplete_status })
      end
    end
  end

  private

  def with_fixture(pretransport_proven: true)
    Dir.mktmpdir("nova-metadata-recovery", "/private/tmp") do |root|
      run_root = File.join(root, "Builds", "AppStore", "NovaStationPinball", RUN_ID)
      logs = File.join(run_root, "logs")
      FileUtils.mkdir_p(logs)
      active = {
        intent: File.join(logs, "metadata-upload-intent.json"),
        checkpoints: File.join(logs, "release-checkpoints.json"),
        adoption: File.join(logs, "media-adoption.json")
      }
      write_json(active.fetch(:intent), {
        "schema_version" => 1,
        "phase" => "intent",
        "kind" => "metadata",
        "candidate_id" => CANDIDATE,
        "version" => "1.0",
        "payload" => { "count" => 20, "sha256" => "c" * 64 }
      })
      write_json(active.fetch(:checkpoints), {
        "schema_version" => 1,
        "identity" => {
          "app" => "NovaStationPinball",
          "version" => "1.0",
          "candidate_id" => CANDIDATE
        },
        "checkpoints" => {
          "metadata_upload" => {
            "state" => "failed",
            "attempts" => 2,
            "command" => ["metadata_upload"],
            "evidence" => nil,
            "error" => "checkpoint metadata_upload remained unverified",
            "updated_at" => "2026-08-11T06:59:15.484906Z"
          }
        }
      })
      write_json(active.fetch(:adoption), {
        "schema_version" => 1,
        "provenance_mode" => "adopted_from",
        "app_slug" => "NovaStationPinball",
        "release_run_id" => RUN_ID,
        "source_candidate_id" => CANDIDATE
      })
      archive_root = File.join(logs, "recovery", "metadata-pretransport-v1")
      archive = active.transform_values do |path|
        File.join(archive_root, File.basename(path))
      end
      contract = {
        "schema_version" => 1,
        "app_slug" => "NovaStationPinball",
        "release_run_id" => RUN_ID,
        "historical_head" => "b" * 40,
        "historical_candidate_id" => CANDIDATE,
        "historical_adoption_contract_sha256" => "e" * 64,
        "metadata_expected_sha256" => "c" * 64,
        "pretransport_proof" => {
          "proven" => pretransport_proven,
          "configuration_error" =>
            "Error setting value './metadata/app_rating_config.json' for option 'app_rating_config_path'",
          "invalid_parameters_error" =>
            "You passed invalid parameters to 'upload_to_app_store'.",
          "wrapper_classification" =>
            "metadata transport returned ambiguously after its intent was recorded (FastlaneCore::Interface::FastlaneError)",
          "action_run_called" => false
        },
        "active_files" => active.to_h do |_name, path|
          [File.basename(path), Digest::SHA256.file(path).hexdigest]
        end,
        "source_changes" => []
      }
      contract["contract_self_sha256"] = Digest::SHA256.hexdigest(
        JSON.generate(canonical(contract))
      )
      recovery = NovaStationPinballMetadataPretransportRecovery::Recovery.new(
        app_root: root,
        run_id: RUN_ID,
        contract: contract,
        current_candidate_id: CANDIDATE,
        source_verifier: ->(_document) { true },
        pretransport_verifier: ->(_document) { true }
      )
      yield active: active, archive: archive, recovery: recovery
    end
  end

  def incomplete_status
    {
      "metadata" => {
        "complete" => false,
        "expected_sha256" => "c" * 64,
        "actual_sha256" => "d" * 64
      }
    }
  end

  def complete_status
    {
      "metadata" => {
        "complete" => true,
        "expected_sha256" => "c" * 64,
        "actual_sha256" => "c" * 64
      }
    }
  end

  def canonical(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end


  def write_json(path, payload)
    File.binwrite(path, JSON.pretty_generate(payload) + "\n")
  end
end
