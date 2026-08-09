#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "securerandom"
require "time"

module NovaStationFinalValidation
  REQUIRED_RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
  REQUIRED_DEVICES = {
    "iphone-17-pro-max" => ["iphone-1", "iphone", "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"],
    "iphone-se-3" => ["iphone-2", "iphone", "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"],
    "ipad-pro-13-m5" => ["ipad", "ipad", "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"]
  }.freeze
  IDENTIFIER = /\A[a-z0-9][a-z0-9._-]{0,79}\z/
  UUID = /\A[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}\z/i

  class PoolBusy < StandardError; end
  class LeaseLost < StandardError; end

  class LeaseHold
    def initialize(input:, signal_only:, poller: -> { sleep(0.25) })
      @input = input
      @signal_only = signal_only
      @poller = poller
    end

    def wait(stopped:)
      loop do
        return if stopped.call
        if @signal_only
          @poller.call
          next
        end
        ready = IO.select([@input], nil, nil, 0.25)
        next unless ready
        line = @input.gets
        return if line.nil? || line.strip == "release"
      end
    end
  end

  class PoolLeaseSession
    attr_reader :lease_paths, :udids

    def initialize(pool_config_path:, app:, execution_id:, token_factory: -> { SecureRandom.hex(16) }, now: -> { Time.now.utc })
      @pool_config_path = File.expand_path(pool_config_path.to_s)
      @app = app
      @execution_id = execution_id
      @token_factory = token_factory
      @now = now
      @documents = {}
      @lease_paths = {}
      @udids = {}
      @acquired = false
      validate_identifiers!
      load_pool!
    end

    def acquire!
      raise LeaseLost, "pool session is already acquired" if @acquired

      @devices.each do |media_id, device|
        acquire_device!(media_id, device)
      end
      @acquired = true
      true
    rescue StandardError
      rollback_new_locks!
      raise
    end

    def release!
      raise LeaseLost, "pool session is not acquired" unless @acquired

      assert_all_owned!
      @lease_paths.each_value { |path| File.unlink(path) }
      @acquired = false
      true
    rescue Errno::ENOENT, Errno::ELOOP, Errno::EACCES, JSON::ParserError => error
      raise LeaseLost, "simulator lease cleanup is ambiguous: #{error.class}"
    end

    private

    def validate_identifiers!
      unless @app.is_a?(String) && IDENTIFIER.match?(@app)
        raise ArgumentError, "app is invalid"
      end
      unless @execution_id.is_a?(String) && IDENTIFIER.match?(@execution_id)
        raise ArgumentError, "execution_id is invalid"
      end
    end

    def load_pool!
      unless File.file?(@pool_config_path) && !File.symlink?(@pool_config_path)
        raise ArgumentError, "simulator pool config must be a regular non-symlink file"
      end
      pool = JSON.parse(File.binread(@pool_config_path))
      unless pool.is_a?(Hash) && pool.keys.sort == %w[devices lock_root schema_version] &&
             pool["schema_version"] == 1 && pool["devices"].is_a?(Array) &&
             pool["lock_root"].is_a?(String) && File.expand_path(pool["lock_root"]) == pool["lock_root"]
        raise ArgumentError, "simulator pool config is invalid"
      end
      @lock_root = pool.fetch("lock_root")
      unless Dir.exist?(@lock_root) && !File.symlink?(@lock_root)
        raise ArgumentError, "simulator lock root must be an existing non-symlink directory"
      end
      @devices = REQUIRED_DEVICES.to_h do |media_id, (id, role, device_type)|
        matches = pool.fetch("devices").select { |candidate| candidate["media_id"] == media_id }
        device = matches.one? ? matches.first : nil
        unless device && device["id"] == id && device["role"] == role &&
               device["device_type"] == device_type && device["runtime"] == REQUIRED_RUNTIME &&
               device["udid"].to_s.match?(UUID)
          raise ArgumentError, "pool device #{media_id} is not the exact required iOS 26.2 simulator"
        end
        [media_id, device.freeze]
      end.freeze
      unless @devices.values.map { |device| device.fetch("udid").upcase }.uniq.length == REQUIRED_DEVICES.length
        raise ArgumentError, "pool devices must have distinct UDIDs"
      end
    rescue JSON::ParserError => error
      raise ArgumentError, "simulator pool config is invalid: #{error.message}"
    end

    def acquire_device!(media_id, device)
      path = File.join(@lock_root, "#{device.fetch('id')}.lock")
      token = @token_factory.call.to_s
      raise ArgumentError, "lease token is invalid" unless token.match?(/\A[0-9a-f]{32}\z/)

      document = {
        "schema_version" => 1,
        "device_id" => device.fetch("id"),
        "udid" => device.fetch("udid").upcase,
        "app" => @app,
        "pid" => Process.pid,
        "started_at" => @now.call.utc.iso8601(6),
        "execution_id" => @execution_id,
        "token" => token
      }
      flags = File::WRONLY | File::CREAT | File::EXCL
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      File.open(path, flags, 0o600) do |file|
        file.write(JSON.generate(document) + "\n")
        file.flush
        file.fsync
      end
      @documents[media_id] = document.freeze
      @lease_paths[media_id] = path.freeze
      @udids[media_id] = device.fetch("udid").upcase.freeze
    rescue Errno::EEXIST
      raise PoolBusy, "fixed-pool simulator #{device.fetch('id')} is already leased"
    rescue Errno::ELOOP, Errno::EACCES => error
      raise LeaseLost, "unsafe fixed-pool lock #{device.fetch('id')}: #{error.class}"
    end

    def assert_all_owned!
      @lease_paths.each do |media_id, path|
        current = JSON.parse(File.binread(path))
        unless current == @documents.fetch(media_id)
          raise LeaseLost, "simulator lease ownership changed for #{media_id}"
        end
      end
    end

    def rollback_new_locks!
      @lease_paths.each do |media_id, path|
        current = JSON.parse(File.binread(path))
        File.unlink(path) if current == @documents.fetch(media_id)
      rescue Errno::ENOENT, Errno::ELOOP, Errno::EACCES, JSON::ParserError
        # Ambiguous locks are deliberately preserved.
      end
      @documents.clear
      @lease_paths.clear
      @udids.clear
    end
  end

  module CLI
    module_function

    def run(argv, input: $stdin, output: $stdout, error: $stderr)
      options = {
        pool_config_path: "/private/tmp/apps-factory/simulator-pool.json",
        app: "nova-station-pinball",
        hold_until_signal: false
      }
      OptionParser.new do |flags|
        flags.banner = "Usage: final_validation_pool.rb --execution-id ID [--pool-config PATH]"
        flags.on("--execution-id ID") { |value| options[:execution_id] = value }
        flags.on("--pool-config PATH") { |value| options[:pool_config_path] = value }
        flags.on("--hold-until-signal") { options[:hold_until_signal] = true }
      end.parse!(argv)
      raise OptionParser::MissingArgument, "--execution-id" if options[:execution_id].to_s.empty?

      signal_only = options.delete(:hold_until_signal)
      session = PoolLeaseSession.new(**options)
      session.acquire!
      payload = {
        "schema_version" => 1,
        "execution_id" => options.fetch(:execution_id),
        "pid" => Process.pid,
        "lease_paths" => session.lease_paths,
        "udids" => session.udids
      }
      output.puts(JSON.generate(payload))
      output.puts("READY")
      output.flush

      stop = false
      previous_int = Signal.trap("INT") { stop = true }
      previous_term = Signal.trap("TERM") { stop = true }
      LeaseHold.new(input: input, signal_only: signal_only).wait(stopped: -> { stop })
      session.release!
      output.puts("RELEASED")
      output.flush
      0
    rescue ArgumentError, OptionParser::ParseError, PoolBusy, LeaseLost => exception
      error.puts("final_validation_pool: #{exception.message}")
      1
    ensure
      Signal.trap("INT", previous_int) if defined?(previous_int) && previous_int
      Signal.trap("TERM", previous_term) if defined?(previous_term) && previous_term
    end
  end
end

exit NovaStationFinalValidation::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
