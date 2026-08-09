#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "final_validation_pool"

class FinalValidationPoolTest < Minitest::Test
  DEVICES = [
    {
      "id" => "iphone-1", "role" => "iphone",
      "udid" => "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
      "media_id" => "iphone-17-pro-max",
      "device_type" => "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max",
      "runtime" => "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
    },
    {
      "id" => "iphone-2", "role" => "iphone",
      "udid" => "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
      "media_id" => "iphone-se-3",
      "device_type" => "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation",
      "runtime" => "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
    },
    {
      "id" => "ipad", "role" => "ipad",
      "udid" => "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
      "media_id" => "ipad-pro-13-m5",
      "device_type" => "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB",
      "runtime" => "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
    }
  ].freeze

  def test_acquires_all_three_exact_locks_with_live_owner_document
    with_pool do |pool_path, lock_root|
      session = NovaStationFinalValidation::PoolLeaseSession.new(
        pool_config_path: pool_path,
        app: "nova-station-pinball",
        execution_id: "task12-test",
        token_factory: -> { "a" * 32 },
        now: -> { Time.utc(2026, 7, 22, 10, 0, 0) }
      )

      session.acquire!

      assert_equal DEVICES.to_h { |device| [device.fetch("media_id"), device.fetch("udid")] }, session.udids
      assert_equal DEVICES.to_h { |device| [device.fetch("media_id"), File.join(lock_root, "#{device.fetch('id')}.lock")] }, session.lease_paths
      session.lease_paths.each_value do |path|
        document = JSON.parse(File.binread(path))
        assert_equal Process.pid, document.fetch("pid")
        assert_equal "nova-station-pinball", document.fetch("app")
        assert_equal "task12-test", document.fetch("execution_id")
      end

      assert session.release!
      assert_empty Dir.glob(File.join(lock_root, "*.lock"))
    end
  end

  def test_rolls_back_only_newly_owned_locks_when_pool_is_partly_busy
    with_pool do |pool_path, lock_root|
      foreign = File.join(lock_root, "iphone-2.lock")
      File.write(foreign, "foreign\n", mode: "wb", perm: 0o600)
      session = NovaStationFinalValidation::PoolLeaseSession.new(
        pool_config_path: pool_path,
        app: "nova-station-pinball",
        execution_id: "task12-test"
      )

      error = assert_raises(NovaStationFinalValidation::PoolBusy) { session.acquire! }

      assert_includes error.message, "iphone-2"
      assert_equal "foreign\n", File.binread(foreign)
      refute File.exist?(File.join(lock_root, "iphone-1.lock"))
      refute File.exist?(File.join(lock_root, "ipad.lock"))
    end
  end

  def test_changed_lock_is_preserved_and_release_fails_closed
    with_pool do |pool_path, _lock_root|
      session = NovaStationFinalValidation::PoolLeaseSession.new(
        pool_config_path: pool_path,
        app: "nova-station-pinball",
        execution_id: "task12-test"
      )
      session.acquire!
      changed = session.lease_paths.fetch("iphone-se-3")
      File.write(changed, "changed\n", mode: "wb", perm: 0o600)

      assert_raises(NovaStationFinalValidation::LeaseLost) { session.release! }
      assert_equal "changed\n", File.binread(changed)
      assert File.exist?(session.lease_paths.fetch("iphone-17-pro-max")), "ambiguous cleanup must stop before deleting other locks"
    end
  end

  def test_signal_only_hold_ignores_closed_stdin_until_owner_is_stopped
    polls = 0
    input = Object.new
    input.define_singleton_method(:gets) { raise("signal-only hold must not read stdin") }
    hold = NovaStationFinalValidation::LeaseHold.new(
      input: input,
      signal_only: true,
      poller: -> { polls += 1 }
    )

    hold.wait(stopped: -> { polls >= 2 })

    assert_equal 2, polls
  end

  private

  def with_pool
    Dir.mktmpdir("nova-final-pool-") do |root|
      lock_root = File.join(root, "locks")
      Dir.mkdir(lock_root, 0o700)
      pool_path = File.join(root, "pool.json")
      File.write(pool_path, JSON.generate({
        "schema_version" => 1,
        "lock_root" => lock_root,
        "devices" => DEVICES.map(&:dup)
      }))
      yield pool_path, lock_root
    end
  end
end
