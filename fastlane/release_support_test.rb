# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "release_support"

class NovaStationPinballReleaseSupportTest < Minitest::Test
  CANDIDATE = "a" * 64

  def test_transport_is_attempted_at_most_once_and_then_get_only
    Dir.mktmpdir do |root|
      identity = proof_identity(root, kind: "metadata")
      calls = 0
      first = NovaStationPinballReleaseSupport.transport_once!(**identity) { calls += 1 }
      second = NovaStationPinballReleaseSupport.transport_once!(**identity) { calls += 1 }
      NovaStationPinballReleaseSupport.mark_observed!(**identity)
      third = NovaStationPinballReleaseSupport.transport_once!(**identity) { calls += 1 }

      assert_equal :transported, first
      assert_equal :get_only, second
      assert_equal :observed, third
      assert_equal 1, calls
    end
  end

  def test_ambiguous_transport_never_allows_a_second_mutation
    Dir.mktmpdir do |root|
      identity = proof_identity(root, kind: "previews")
      calls = 0
      error = assert_raises(NovaStationPinballReleaseSupport::AmbiguousTransport) do
        NovaStationPinballReleaseSupport.transport_once!(**identity) do
          calls += 1
          raise "response lost"
        end
      end
      resumed = NovaStationPinballReleaseSupport.transport_once!(**identity) { calls += 1 }

      assert_equal "previews", error.kind
      assert_equal :get_only, resumed
      assert_equal 1, calls
    end
  end

  def test_pretransport_failure_is_not_attempted_and_writes_no_intent
    Dir.mktmpdir do |root|
      identity = proof_identity(root, kind: "metadata")
      error = assert_raises(
        NovaStationPinballReleaseSupport::PretransportFailure
      ) do
        NovaStationPinballReleaseSupport.transport_once!(
          **identity,
          preflight: -> { raise ArgumentError, "metadata path is relative" }
        ) { flunk "transport must not run" }
      end

      assert_equal "metadata", error.kind
      assert_equal :not_attempted, error.state
      refute File.exist?(identity.fetch(:intent_path))
      refute File.exist?(identity.fetch(:receipt_path))
    end
  end

  def test_proof_rejects_candidate_or_payload_drift
    Dir.mktmpdir do |root|
      identity = proof_identity(root, kind: "screenshots")
      NovaStationPinballReleaseSupport.transport_once!(**identity) {}

      assert_raises(ArgumentError) do
        NovaStationPinballReleaseSupport.transport_once!(
          **identity.merge(candidate_id: "b" * 64)
        ) {}
      end
      assert_raises(ArgumentError) do
        NovaStationPinballReleaseSupport.transport_once!(
          **identity.merge(payload: identity.fetch(:payload).merge("count" => 99))
        ) {}
      end
    end
  end

  def test_competing_processes_allow_one_transport
    skip "fork unavailable" unless Process.respond_to?(:fork)

    Dir.mktmpdir do |root|
      identity = proof_identity(root, kind: "ipa")
      log = File.join(root, "transport.log")
      children = 8.times.map do
        fork do
          NovaStationPinballReleaseSupport.transport_once!(**identity) do
            File.open(log, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
              file.flock(File::LOCK_EX)
              file.puts(Process.pid)
            end
          end
          exit! 0
        rescue StandardError
          exit! 1
        end
      end
      statuses = children.map { |pid| Process.wait2(pid).last }

      assert statuses.all?(&:success?)
      assert_equal 1, File.readlines(log).length
    end
  end

  def test_target_build_is_write_once_and_exact
    Dir.mktmpdir do |root|
      path = File.join(root, "logs", "target-build.json")
      target = NovaStationPinballReleaseSupport.write_target_build_once!(
        path: path, version: "1.0", build: "7"
      )
      assert_equal target, NovaStationPinballReleaseSupport.read_target_build!(
        path: path, version: "1.0"
      )
      assert_raises(ArgumentError) do
        NovaStationPinballReleaseSupport.write_target_build_once!(
          path: path, version: "1.0", build: "8"
        )
      end
    end
  end

  def test_media_payload_is_an_exact_regular_file_tree_digest
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "en-US"))
      FileUtils.mkdir_p(File.join(root, "fr-FR"))
      File.binwrite(File.join(root, "en-US", "a.mov"), "one")
      File.binwrite(File.join(root, "fr-FR", "b.mov"), "two")

      payload = NovaStationPinballReleaseSupport.tree_payload!(
        path: root, extensions: %w[.mov], expected_count: 2
      )
      assert_equal 2, payload.fetch("count")
      assert_match(/\A[0-9a-f]{64}\z/, payload.fetch("sha256"))

      File.symlink(File.join(root, "en-US", "a.mov"), File.join(root, "fr-FR", "link.mov"))
      assert_raises(ArgumentError) do
        NovaStationPinballReleaseSupport.tree_payload!(
          path: root, extensions: %w[.mov], expected_count: 3
        )
      end
    end
  end

  private

  def proof_identity(root, kind:)
    {
      intent_path: File.join(root, "logs", "#{kind}-intent.json"),
      receipt_path: File.join(root, "logs", "#{kind}-receipt.json"),
      kind: kind,
      candidate_id: CANDIDATE,
      version: "1.0",
      payload: { "sha256" => "c" * 64, "count" => 3 }
    }
  end
end
