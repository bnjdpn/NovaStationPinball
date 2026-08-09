#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "securerandom"
require_relative "media_generation"

module NovaStationPinballPreviewGeneration
  class RawGeometry
    def self.validate!(width:, height:, device:)
      return true if [width, height] == device.values_at(:height, :width)

      raise NovaStationPinballMediaContract::ContractError,
            "raw App Preview geometry must be the portrait inverse of #{device.fetch(:id)}"
    end

    def self.probe(path, runner: NovaStationPinballMediaGeneration::SystemRunner.new)
      stdout, stderr, status = runner.capture(
        "/opt/homebrew/bin/ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "json", path
      )
      raise NovaStationPinballMediaContract::ContractError,
            "raw App Preview probe failed: #{stderr.strip}" unless status.success?
      stream = JSON.parse(stdout).fetch("streams").fetch(0)
      [Integer(stream.fetch("width")), Integer(stream.fetch("height"))]
    rescue JSON::ParserError, KeyError, ArgumentError
      raise NovaStationPinballMediaContract::ContractError, "raw App Preview probe returned invalid geometry"
    end
  end

  class Encoding
    def self.arguments(source:, destination:, width:, height:, trim_offset:, transform: "transpose=clock")
      [
        "/opt/homebrew/bin/ffmpeg", "-y", "-ss", format("%.3f", trim_offset), "-i", source,
        "-f", "lavfi", "-i",
        "aevalsrc=0.025*sin(2*PI*110*t)+0.015*sin(2*PI*220*t)+0.002*random(0)|0.025*sin(2*PI*110*t)+0.015*sin(2*PI*277.18*t)+0.002*random(1):s=48000:d=24",
        "-map", "0:v:0", "-map", "1:a:0", "-t", "24",
        "-vf", "#{transform},scale=#{width}:#{height}:flags=lanczos,fps=30,setfield=prog,format=yuv420p",
        "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p",
        "-b:v", "11M", "-minrate", "11M", "-maxrate", "11M", "-bufsize", "22M",
        "-x264-params", "nal-hrd=cbr:force-cfr=1:filler=1",
        "-c:a", "aac", "-profile:a", "aac_low", "-aac_coder", "twoloop",
        "-b:a", "256k", "-ar", "48000", "-ac", "2",
        "-movflags", "+faststart", "-shortest", destination
      ]
    end
  end

  class Handshake
    BUNDLE_ID = "com.bnjdpn.NovaStationPinball"

    attr_reader :token

    def initialize(udid:, runner:, token: SecureRandom.hex(16), timeout: 35.0)
      @udid = udid
      @runner = runner
      @token = token
      @timeout = timeout
      unless token.match?(/\A[0-9a-f]{32}\z/)
        raise NovaStationPinballMediaContract::ContractError, "invalid App Preview handshake token"
      end
    end

    def wait_for!(marker)
      deadline = monotonic + @timeout
      loop do
        path = marker_path(marker)
        if path && File.file?(path) && !File.symlink?(path) && File.binread(path) == token
          return true
        end
        raise NovaStationPinballMediaContract::ContractError, "App Preview handshake timed out waiting for #{marker}" if monotonic >= deadline
        sleep(0.025)
      end
    end

    def write!(marker)
      path = marker_path(marker)
      raise NovaStationPinballMediaContract::ContractError, "unsafe App Preview handshake marker" if File.symlink?(path)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.write(temporary, token, mode: "wb", perm: 0o600)
      File.rename(temporary, path)
      true
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    private

    def marker_path(marker)
      unless %w[ready recording started complete].include?(marker)
        raise NovaStationPinballMediaContract::ContractError, "unknown App Preview handshake marker"
      end
      root = container_root!
      return nil unless root
      components = ["Library", "Caches", "NovaStationMediaHandshake", token, marker]
      current = root
      components.each do |component|
        current = File.join(current, component)
        if (File.exist?(current) || File.symlink?(current)) && File.lstat(current).symlink?
          raise NovaStationPinballMediaContract::ContractError, "unsafe App Preview handshake path"
        end
      end
      current
    end

    def container_root!
      stdout, stderr, status = @runner.capture(
        "xcrun", "simctl", "get_app_container", @udid, BUNDLE_ID, "data"
      )
      return nil unless status.success?
      candidate = stdout.to_s.strip
      unless Pathname.new(candidate).absolute? && Dir.exist?(candidate) && !File.symlink?(candidate)
        raise NovaStationPinballMediaContract::ContractError, "unsafe App Preview app container"
      end
      candidate
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  class RecorderReadiness
    def initialize(path:, pid:, timeout: 8.0, poll_interval: 0.05)
      @path = File.expand_path(path)
      @pid = pid
      @timeout = timeout
      @poll_interval = poll_interval
    end

    def wait_until_writing!
      deadline = monotonic + @timeout
      last_positive_size = nil
      recording_origin = nil
      loop do
        ensure_process_live!
        if File.exist?(@path) || File.symlink?(@path)
          stat = File.lstat(@path)
          unless stat.file? && !stat.symlink?
            raise NovaStationPinballMediaContract::ContractError,
                  "App Preview recorder output must be a regular non-symlink file"
          end
          size = stat.size
          if size.positive?
            recording_origin ||= monotonic
            return recording_origin if last_positive_size && size > last_positive_size
            last_positive_size = size
          end
        end
        if monotonic >= deadline
          raise NovaStationPinballMediaContract::ContractError,
                "App Preview recorder did not produce a growing non-empty file before timeout"
        end
        sleep(@poll_interval)
      end
    end

    private

    def ensure_process_live!
      exited = Process.waitpid(@pid, Process::WNOHANG)
      return unless exited
      raise NovaStationPinballMediaContract::ContractError,
            "App Preview recorder exited before becoming ready"
    rescue Errno::ECHILD, Errno::ESRCH
      raise NovaStationPinballMediaContract::ContractError,
            "App Preview recorder PID is not owned or no longer exists"
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  class CaptureTiming
    MAX_TRIM_OFFSET_SECONDS = 45.0

    def self.trim_offset(recording_origin:, timeline_started:)
      values = [recording_origin, timeline_started]
      unless values.all? { |value| value.is_a?(Numeric) && value.finite? }
        raise NovaStationPinballMediaContract::ContractError,
              "App Preview capture timing must use finite monotonic timestamps"
      end
      offset = timeline_started - recording_origin
      unless offset.positive? && offset <= MAX_TRIM_OFFSET_SECONDS
        raise NovaStationPinballMediaContract::ContractError,
              "App Preview capture trim offset is outside the handshake window"
      end
      offset.round(3)
    end
  end

  class Generator < NovaStationPinballMediaGeneration::GeneratorBase
    def generate!
      prepare_only!
      configuration.locale_batches.each do |batch|
        batch.each { |locale| generate_locale!(locale) }
      end
      run_root
    end

    private

    def generate_locale!(locale)
      configuration.udids.each_key do |device|
        configuration.assert_owned!
        device_definition = NovaStationPinballMediaContract::DEVICES.find { |candidate| candidate.fetch(:id) == device }
        scratch = configuration.scratch_root(run_root, locale, device, :app_previews)
        FileUtils.mkdir_p(scratch)
        raw = File.join(scratch, "raw.mov")
        destination = File.join(run_root, "app_previews", locale, "NovaStationPinball-#{device}.mov")
        FileUtils.mkdir_p(File.dirname(destination))
        capture = capture_after_app_ready!(locale: locale, device: device, raw: raw, scratch: scratch)
        trim_offset = capture.fetch(:trim_offset)
        geometry = transcode!(raw, destination, device, trim_offset)
        mark_artifact!(
          locale: locale, device: device, kind: :preview, path: destination,
          capture_trim_offset: trim_offset,
          preview_provenance: {
            "source_sha256" => Digest::SHA256.file(raw).hexdigest,
            "source_run_id" => configuration.execution_id,
            "width" => geometry.fetch(0), "height" => geometry.fetch(1),
            "transform" => device_definition.fetch(:raw_transform), "udid" => configuration.udids.fetch(device),
            "locale" => locale, "handshake_sha256" => capture.fetch(:handshake_sha256)
          }
        )
      end
    end

    def capture_after_app_ready!(locale:, device:, raw:, scratch:)
      udid = configuration.udids.fetch(device)
      handshake = Handshake.new(udid: udid, runner: runner)
      build_arguments = configuration.build_for_testing_arguments(
        kind: :app_previews, locale: locale, device: device, run_root: run_root
      )
      run_xcodebuild!(build_arguments)
      derived_data = File.join(scratch, "DerivedData")
      configured_xctestrun = File.join(scratch, "xctestrun", "NovaStationPinball-AppPreviewUITests.xctestrun")
      NovaStationPinballMediaGeneration::XCTestRunConfigurator.new.find_and_inject!(
        derived_data: derived_data, destination: configured_xctestrun,
        isolation_root: scratch,
        target_name: "NovaStationPinballUITests",
        environment: {
          "NOVA_MEDIA_HANDSHAKE_TOKEN" => handshake.token,
          "NOVA_MEDIA_LOCALE" => locale
        }
      )
      test_arguments = configuration.test_without_building_arguments(
        kind: :app_previews, locale: locale, device: device, run_root: run_root,
        xctestrun: configured_xctestrun
      )
      log_path = File.join(scratch, "AppPreviewUITests.log")
      log = File.open(log_path, "wb", 0o600)
      test_pid = Process.spawn(
        *test_arguments,
        chdir: app_root, out: log, err: [:child, :out]
      )
      handshake.wait_for!("ready")
      if File.exist?(raw) || File.symlink?(raw)
        raise NovaStationPinballMediaContract::ContractError, "App Preview raw recording path must be new"
      end
      recorder_log_path = File.join(scratch, "recordVideo.log")
      recorder_log = File.open(recorder_log_path, "wb", 0o600)
      record_pid = Process.spawn(
        "xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", raw,
        out: recorder_log, err: [:child, :out]
      )
      recording_origin = RecorderReadiness.new(path: raw, pid: record_pid).wait_until_writing!
      handshake.write!("recording")
      handshake.wait_for!("started")
      timeline_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      trim_offset = CaptureTiming.trim_offset(
        recording_origin: recording_origin, timeline_started: timeline_started
      )
      handshake.wait_for!("complete")
      stop_owned_process!(record_pid, "INT")
      record_pid = nil
      _, status = Process.wait2(test_pid)
      test_pid = nil
      unless status.success?
        raise NovaStationPinballMediaContract::ContractError,
              "App Preview XCTest failed; inspect #{log_path}"
      end
      { trim_offset: trim_offset, handshake_sha256: Digest::SHA256.hexdigest(handshake.token) }
    ensure
      stop_owned_process!(record_pid, "INT") if record_pid
      stop_owned_process!(test_pid, "TERM") if test_pid
      log&.close
      recorder_log&.close
    end

    def stop_owned_process!(pid, signal, timeout: 4.0)
      Process.kill(signal, pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        return if Process.waitpid(pid, Process::WNOHANG)
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep(0.025)
      end
      Process.kill("KILL", pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def transcode!(source, destination, device_id, trim_offset)
      device = NovaStationPinballMediaContract::DEVICES.find { |candidate| candidate.fetch(:id) == device_id }
      geometry = RawGeometry.probe(source, runner: runner)
      RawGeometry.validate!(width: geometry.fetch(0), height: geometry.fetch(1), device: device)
      arguments = Encoding.arguments(
        source: source, destination: destination,
        width: device.fetch(:preview_width), height: device.fetch(:preview_height),
        trim_offset: trim_offset, transform: device.fetch(:raw_transform)
      )
      stdout, stderr, status = runner.capture(*arguments, chdir: app_root)
      return geometry if status.success?

      raise NovaStationPinballMediaContract::ContractError,
            "App Preview transcoding failed: #{[stdout, stderr].join("\n").strip}"
    end
  end

  module CLI
    module_function

    def run(argv)
      options = NovaStationPinballMediaGeneration::CLIOptions.parse(argv, program: "generate_app_previews.rb")
      generator = Generator.new(**options)
      options[:prepare_only] ? generator.prepare_only! : generator.generate!
      puts "app_previews: #{options[:prepare_only] ? 'prepared pending manifest' : 'captured'} at #{generator.run_root}"
      0
    rescue NovaStationPinballMediaContract::ContractError, OptionParser::ParseError => error
      warn "app_previews: #{error.message}"
      1
    end
  end
end

exit NovaStationPinballPreviewGeneration::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
