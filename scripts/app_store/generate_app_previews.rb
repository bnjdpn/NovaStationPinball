#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "securerandom"
require_relative "media_generation"

module NovaStationPinballPreviewGeneration
  class RawFrameTimelineError < NovaStationPinballMediaContract::ContractError; end

  class CaptureWindow
    TIMELINE_SECONDS = 24.0
    FRAME_RATE = 30
    TARGET_FRAME_COUNT = 720
    # simctl can create and grow the recording file before its first usable
    # screen frames are committed. Keep the launch scene static for a bounded
    # pre-roll to reduce that startup risk; the strict raw-frame timeline guard
    # below remains the acceptance proof for every capture.
    RECORDER_WARMUP_SECONDS = 5.0
    RAW_TAIL_MARGIN_SECONDS = 1.0
    MAX_FINAL_PADDING_SECONDS = 1.0 / FRAME_RATE
    MAX_TRIM_OFFSET_SECONDS = 45.0

    def self.minimum_raw_elapsed(trim_offset)
      trim = finite_number!(trim_offset, "capture trim offset")
      unless trim.positive? && trim <= MAX_TRIM_OFFSET_SECONDS
        raise NovaStationPinballMediaContract::ContractError, "invalid App Preview capture trim offset"
      end
      trim + TIMELINE_SECONDS + RAW_TAIL_MARGIN_SECONDS
    end

    def self.residual_padding(raw_end:, trim_offset:)
      ending = finite_number!(raw_end, "raw App Preview end time")
      trim = finite_number!(trim_offset, "capture trim offset")
      available = ending - trim
      unless available.positive?
        raise NovaStationPinballMediaContract::ContractError, "raw App Preview has no post-trim timeline"
      end
      deficit = TIMELINE_SECONDS - available
      return 0.0 unless deficit.positive?
      if deficit > MAX_FINAL_PADDING_SECONDS
        raise NovaStationPinballMediaContract::ContractError,
              format("raw App Preview is %.3fs short; residual padding is limited to %.3fs", deficit, MAX_FINAL_PADDING_SECONDS)
      end
      MAX_FINAL_PADDING_SECONDS
    end

    def self.finite_number!(value, label)
      parsed = Float(value)
      raise ArgumentError unless parsed.finite?
      parsed
    rescue ArgumentError, TypeError
      raise NovaStationPinballMediaContract::ContractError, "invalid #{label}"
    end
    private_class_method :finite_number!
  end

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

  class RawTimeline
    def self.end_time(path, runner: NovaStationPinballMediaGeneration::SystemRunner.new)
      stdout, stderr, status = runner.capture(
        "/opt/homebrew/bin/ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_packets", "-show_entries", "packet=pts_time,duration_time", "-of", "json", path
      )
      unless status.success?
        raise NovaStationPinballMediaContract::ContractError,
              "raw App Preview timeline probe failed: #{stderr.strip}"
      end
      packets = JSON.parse(stdout).fetch("packets")
      ends = packets.map do |packet|
        pts = Float(packet.fetch("pts_time"))
        duration = Float(packet.fetch("duration_time"))
        raise ArgumentError unless pts.finite? && duration.finite? && duration.positive?
        pts + duration
      end
      raise ArgumentError if ends.empty?
      ends.max
    rescue JSON::ParserError, KeyError, ArgumentError, TypeError
      raise NovaStationPinballMediaContract::ContractError, "raw App Preview timeline probe returned invalid packets"
    end
  end

  class RawFrameTimeline
    def self.validate!(path, runner: NovaStationPinballMediaGeneration::SystemRunner.new)
      stdout, stderr, status = runner.capture(
        "/opt/homebrew/bin/ffprobe", "-fflags", "+igndts", "-v", "error", "-select_streams", "v:0",
        "-show_frames", "-show_entries", "frame=best_effort_timestamp_time,pts_time",
        "-of", "json", path
      )
      unless status.success?
        raise RawFrameTimelineError,
              "raw App Preview frame timeline probe failed: #{stderr.strip}"
      end
      frames = JSON.parse(stdout).fetch("frames")
      timestamps = frames.map do |frame|
        Float(frame["best_effort_timestamp_time"] || frame.fetch("pts_time"))
      end
      unless timestamps.length >= CaptureWindow::TARGET_FRAME_COUNT &&
             timestamps.all?(&:finite?)
        raise RawFrameTimelineError,
              "raw App Preview frame timestamps must be complete and finite"
      end
      unless timestamps.all? { |timestamp| timestamp >= 0 }
        raise RawFrameTimelineError,
              "raw App Preview frame timestamps must be non-negative"
      end
      timestamps.each_cons(2).with_index do |(previous, current), index|
        next if current >= previous

        raise RawFrameTimelineError,
              format(
                "raw App Preview frame timestamps regress at frame %d: %.6f -> %.6f",
                index + 1, previous, current
              )
      end
      true
    rescue JSON::ParserError, KeyError, ArgumentError, TypeError
      raise RawFrameTimelineError,
            "raw App Preview frame timeline probe returned invalid frames"
    end
  end

  class EncodedMedia
    Capture3Adapter = Struct.new(:runner) do
      def capture3(*arguments)
        runner.capture(*arguments)
      end
    end

    def self.validate!(path, runner: NovaStationPinballMediaGeneration::SystemRunner.new)
      info = NovaStationPinballMediaContract::FFProbe.new(runner: Capture3Adapter.new(runner)).probe(path)
      exact_durations = %w[duration video_duration audio_duration].all? do |key|
        (info.fetch(key) - CaptureWindow::TIMELINE_SECONDS).abs <= 0.001
      end
      unless exact_durations && info.fetch("video_frames") == CaptureWindow::TARGET_FRAME_COUNT &&
             (info.fetch("frame_rate") - CaptureWindow::FRAME_RATE).abs <= 0.001
        raise NovaStationPinballMediaContract::ContractError,
              "encoded App Preview must contain exactly 24.000s of audio/video and 720 video frames"
      end
      info
    end
  end

  class Encoding
    def self.arguments(source:, destination:, width:, height:, trim_offset:, transform: "transpose=clock",
                       padding_duration: 0.0)
      padding = Float(padding_duration)
      unless padding.finite? && padding >= 0.0 && padding <= CaptureWindow::MAX_FINAL_PADDING_SECONDS
        raise NovaStationPinballMediaContract::ContractError, "invalid residual App Preview padding"
      end
      [
        "/opt/homebrew/bin/ffmpeg", "-y", "-fflags", "+igndts",
        "-ss", format("%.3f", trim_offset), "-i", source,
        "-f", "lavfi", "-i",
        "aevalsrc=0.025*sin(2*PI*110*t)+0.015*sin(2*PI*220*t)+0.002*random(0)|0.025*sin(2*PI*110*t)+0.015*sin(2*PI*277.18*t)+0.002*random(1):s=48000:d=24",
        "-map", "0:v:0", "-map", "1:a:0", "-t", "24",
        "-frames:v", CaptureWindow::TARGET_FRAME_COUNT.to_s,
        "-vf", "#{transform},scale=#{width}:#{height}:flags=lanczos,tpad=stop_mode=clone:stop_duration=#{format('%.6f', padding)},fps=30,trim=end_frame=#{CaptureWindow::TARGET_FRAME_COUNT},setpts=N/(30*TB),setfield=prog,format=yuv420p",
        "-af", "atrim=duration=24,asetpts=N/SR/TB",
        "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p",
        "-b:v", "11M", "-minrate", "11M", "-maxrate", "11M", "-bufsize", "22M",
        "-x264-params", "nal-hrd=cbr:force-cfr=1:filler=1",
        "-c:a", "aac", "-profile:a", "aac_low", "-aac_coder", "twoloop",
        "-b:a", "256k", "-ar", "48000", "-ac", "2",
        "-movflags", "+faststart", destination
      ]
    rescue ArgumentError, TypeError
      raise NovaStationPinballMediaContract::ContractError, "invalid residual App Preview padding"
    end
  end

  class Handshake
    BUNDLE_ID = "com.bnjdpn.NovaStationPinball"

    attr_reader :token

    def initialize(udid:, runner:, token: SecureRandom.hex(16), timeout: 90.0)
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
    def initialize(path:, pid:, timeout: 8.0, poll_interval: 0.05, clock: nil, sleeper: nil)
      @path = File.expand_path(path)
      @pid = pid
      @timeout = timeout
      @poll_interval = poll_interval
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @sleeper = sleeper || ->(duration) { sleep(duration) }
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
        @sleeper.call(@poll_interval)
      end
    end

    def wait_until_elapsed!(recording_origin:, minimum_duration:)
      origin = Float(recording_origin)
      duration = Float(minimum_duration)
      unless origin.finite? && duration.finite? && duration.positive? &&
             duration <= CaptureWindow::MAX_TRIM_OFFSET_SECONDS +
               CaptureWindow::TIMELINE_SECONDS + CaptureWindow::RAW_TAIL_MARGIN_SECONDS
        raise NovaStationPinballMediaContract::ContractError, "invalid raw App Preview capture deadline"
      end
      target = origin + duration
      loop do
        ensure_process_live!
        current = monotonic
        return current if current >= target
        @sleeper.call([@poll_interval, target - current].min)
      end
    rescue ArgumentError, TypeError
      raise NovaStationPinballMediaContract::ContractError, "invalid raw App Preview capture deadline"
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
      @clock.call
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
    MAX_RAW_CAPTURE_ATTEMPTS = 5
    CanonicalTestArtifacts = Struct.new(:derived_data, :xctestrun, keyword_init: true)

    def generate!
      prepare_only!
      configuration.udids.each_key { |device| generate_device!(device) }
      run_root
    end

    private

    def generate_device!(device)
      udid = configuration.udids.fetch(device)
      begin
        configuration.assert_owned!
        canonical = prepare_canonical_test_artifacts!(device)
        boot_owned_simulator!(udid)
        configuration.locales.each do |locale|
          configuration.assert_owned!
          generate_locale!(locale, device, canonical)
        end
      ensure
        shutdown_owned_simulator!(udid)
      end
    end

    def prepare_canonical_test_artifacts!(device)
      arguments = configuration.build_for_testing_arguments(
        kind: :app_previews, device: device, run_root: run_root
      )
      run_xcodebuild!(arguments)
      canonical_root = configuration.canonical_scratch_root(run_root, device, :app_previews)
      derived_data = File.join(canonical_root, "DerivedData")
      xctestrun = NovaStationPinballMediaGeneration::XCTestRunConfigurator.new.find!(
        derived_data: derived_data
      )
      CanonicalTestArtifacts.new(derived_data: derived_data, xctestrun: xctestrun).freeze
    end

    def boot_owned_simulator!(udid)
      stdout, stderr, status = runner.capture("xcrun", "simctl", "boot", udid)
      message = [stdout, stderr].join("\n")
      unless status.success?
        raise NovaStationPinballMediaContract::ContractError,
              "could not boot owned App Preview simulator #{udid}: #{message.strip}"
      end
      stdout, stderr, status = runner.capture("xcrun", "simctl", "bootstatus", udid, "-b")
      return if status.success?

      raise NovaStationPinballMediaContract::ContractError,
            "owned App Preview simulator did not become ready #{udid}: #{[stdout, stderr].join("\n").strip}"
    end

    def shutdown_owned_simulator!(udid)
      stdout, stderr, status = runner.capture("xcrun", "simctl", "shutdown", udid)
      message = [stdout, stderr].join("\n")
      return if status.success? || message.include?("Unable to shutdown device in current state: Shutdown")

      raise NovaStationPinballMediaContract::ContractError,
            "could not shut down owned App Preview simulator #{udid}: #{message.strip}"
    end

    def generate_locale!(locale, device, canonical)
      udid = configuration.udids.fetch(device)
      device_definition = NovaStationPinballMediaContract::DEVICES.find { |candidate| candidate.fetch(:id) == device }
      destination = File.join(run_root, "app_previews", locale, "NovaStationPinball-#{device}.mov")
      FileUtils.mkdir_p(File.dirname(destination))
      1.upto(MAX_RAW_CAPTURE_ATTEMPTS) do |attempt|
        scratch = configuration.scratch_root(
          run_root, locale, device, :app_previews, attempt: attempt
        )
        FileUtils.mkdir_p(scratch)
        raw = File.join(scratch, "raw.mov")
        handshake = handshake_for(udid)
        begin
          capture = capture_after_app_ready!(
            locale: locale, device: device, raw: raw, scratch: scratch,
            canonical: canonical, handshake: handshake, attempt: attempt
          )
          trim_offset = capture.fetch(:trim_offset)
          geometry = transcode!(raw, destination, device, trim_offset)
          validate_system_overlay!(destination, locale, device)
          mark_artifact!(
            locale: locale, device: device, kind: :preview, path: destination,
            capture_trim_offset: trim_offset,
            preview_provenance: {
              "source_sha256" => Digest::SHA256.file(raw).hexdigest,
              "source_run_id" => configuration.execution_id,
              "width" => geometry.fetch(0), "height" => geometry.fetch(1),
              "transform" => device_definition.fetch(:raw_transform), "udid" => udid,
              "locale" => locale, "handshake_sha256" => capture.fetch(:handshake_sha256)
            }
          )
          return
        rescue RawFrameTimelineError => error
          warn format(
            "app_previews: %s/%s rejected raw timeline attempt %d/%d: %s",
            locale, device, attempt, MAX_RAW_CAPTURE_ATTEMPTS, error.message
          )
          raise if attempt == MAX_RAW_CAPTURE_ATTEMPTS
        end
      end
    end

    def handshake_for(udid)
      Handshake.new(udid: udid, runner: runner)
    end

    def validate_system_overlay!(path, locale, device)
      NovaStationPinballMediaContract::SystemOverlayGuard.new(runner: runner).validate!(
        path: path,
        report_path: NovaStationPinballMediaContract::SystemOverlayGuard.report_path(
          run_root: run_root, locale: locale, device: device
        )
      )
    end

    def capture_after_app_ready!(locale:, device:, raw:, scratch:, canonical:, handshake:, attempt:)
      udid = configuration.udids.fetch(device)
      configured_xctestrun = File.join(scratch, "xctestrun", "NovaStationPinball-AppPreviewUITests.xctestrun")
      NovaStationPinballMediaGeneration::XCTestRunConfigurator.new.inject_environment!(
        source: canonical.xctestrun, destination: configured_xctestrun,
        isolation_root: scratch,
        target_name: "NovaStationPinballUITests",
        environment: {
          "NOVA_MEDIA_HANDSHAKE_TOKEN" => handshake.token,
          "NOVA_MEDIA_LOCALE" => locale
        }
      )
      test_arguments = configuration.test_without_building_arguments(
        kind: :app_previews, locale: locale, device: device, run_root: run_root,
        xctestrun: configured_xctestrun, attempt: attempt
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
        # HEVC is simctl's native default. Its VFR stream can contain DTS values
        # that are unsuitable as presentation timestamps, so probing and final
        # transcoding explicitly ignore DTS. The App Store artifact is still
        # encoded to H.264 below.
        "xcrun", "simctl", "io", udid, "recordVideo", "--codec=hevc", "--force", raw,
        out: recorder_log, err: [:child, :out]
      )
      recorder = RecorderReadiness.new(path: raw, pid: record_pid)
      recording_origin = recorder.wait_until_writing!
      recorder.wait_until_elapsed!(
        recording_origin: recording_origin,
        minimum_duration: CaptureWindow::RECORDER_WARMUP_SECONDS
      )
      handshake.write!("recording")
      handshake.wait_for!("started")
      timeline_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      trim_offset = CaptureTiming.trim_offset(
        recording_origin: recording_origin, timeline_started: timeline_started
      )
      handshake.wait_for!("complete")
      recorder.wait_until_elapsed!(
        recording_origin: recording_origin,
        minimum_duration: CaptureWindow.minimum_raw_elapsed(trim_offset)
      )
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
      RawFrameTimeline.validate!(source, runner: runner)
      geometry = RawGeometry.probe(source, runner: runner)
      RawGeometry.validate!(width: geometry.fetch(0), height: geometry.fetch(1), device: device)
      raw_end = RawTimeline.end_time(source, runner: runner)
      padding = CaptureWindow.residual_padding(raw_end: raw_end, trim_offset: trim_offset)
      arguments = Encoding.arguments(
        source: source, destination: destination,
        width: device.fetch(:preview_width), height: device.fetch(:preview_height),
        trim_offset: trim_offset, transform: device.fetch(:raw_transform),
        padding_duration: padding
      )
      stdout, stderr, status = runner.capture(*arguments, chdir: app_root)
      if status.success?
        EncodedMedia.validate!(destination, runner: runner)
        return geometry
      end

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
