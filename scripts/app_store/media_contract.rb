#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "time"

module NovaStationPinballMediaContract
  APP_SLUG = "NovaStationPinball"
  LOCALES = %w[en-US fr-FR].freeze
  SCENARIOS = %w[launch mission promotion multiball tilt game-over].freeze
  SCREENSHOT_SEGMENT_SAMPLE_OFFSET_SECONDS = 1.0
  DEVICES = [
    { id: "iphone-17-pro-max", width: 2_868, height: 1_320, preview_width: 1_920, preview_height: 886, raw_transform: "transpose=clock" },
    { id: "iphone-se-3", width: 1_334, height: 750, preview_width: 1_334, preview_height: 750, raw_transform: "transpose=clock" },
    { id: "ipad-pro-13-m5", width: 2_752, height: 2_064, preview_width: 1_600, preview_height: 1_200, raw_transform: "transpose=clock" }
  ].freeze
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
  MANIFEST_PATH = "logs/media-manifest.json"
  PROOF_PATH = "logs/media-contract.json"
  SYSTEM_OVERLAY_REPORT_ROOT = "logs/system-overlay"

  class ContractError < StandardError; end

  def self.screenshot_source_offset(scenario)
    index = SCENARIOS.index(scenario)
    raise ContractError, "unknown screenshot scenario: #{scenario}" unless index

    index * 4.0 + SCREENSHOT_SEGMENT_SAMPLE_OFFSET_SECONDS
  end

  class PNGMetadata
    class << self
      def orientation(path)
        chunks(path).each do |type, data, _raw|
          return tiff_orientation(data) if type == "eXIf"
        end
        nil
      end

      def strip_orientation!(path)
        signature, records = chunks(path, include_signature: true)
        kept = records.reject do |type, data, _raw|
          type == "eXIf" || (type == "iTXt" && data.start_with?("XML:com.adobe.xmp\0"))
        end
        temporary = "#{path}.metadata-#{Process.pid}-#{Thread.current.object_id}"
        File.binwrite(temporary, signature + kept.map(&:last).join)
        File.chmod(File.stat(path).mode & 0o777, temporary)
        File.rename(temporary, path)
        path
      ensure
        FileUtils.rm_f(temporary) if defined?(temporary) && temporary
      end

      private

      def chunks(path, include_signature: false)
        bytes = File.binread(path)
        raise ContractError, "invalid PNG signature: #{File.basename(path)}" unless bytes.start_with?(PNG_SIGNATURE)
        offset = PNG_SIGNATURE.bytesize
        records = []
        while offset < bytes.bytesize
          length = bytes.byteslice(offset, 4)&.unpack1("N")
          type = bytes.byteslice(offset + 4, 4)
          raise ContractError, "invalid PNG chunks: #{File.basename(path)}" unless length && type && offset + 12 + length <= bytes.bytesize
          raw = bytes.byteslice(offset, length + 12)
          records << [type, bytes.byteslice(offset + 8, length), raw]
          offset += length + 12
        end
        include_signature ? [PNG_SIGNATURE, records] : records
      end

      def tiff_orientation(data)
        endian = data.byteslice(0, 2)
        order = endian == "MM" ? "n" : endian == "II" ? "v" : nil
        raise ContractError, "invalid PNG EXIF byte order" unless order
        long_order = endian == "MM" ? "N" : "V"
        ifd_offset = data.byteslice(4, 4)&.unpack1(long_order)
        count = ifd_offset && data.byteslice(ifd_offset, 2)&.unpack1(order)
        raise ContractError, "invalid PNG EXIF directory" unless count
        count.times do |index|
          entry = data.byteslice(ifd_offset + 2 + index * 12, 12)
          raise ContractError, "invalid PNG EXIF entry" unless entry&.bytesize == 12
          next unless entry.byteslice(0, 2).unpack1(order) == 0x0112
          return entry.byteslice(8, 2).unpack1(order)
        end
        nil
      end
    end
  end

  module Paths
    module_function

    def inside!(run_root, relative)
      value = relative.to_s
      raise ContractError, "media path escapes run root: #{value}" if value.empty? || Pathname.new(value).absolute?

      root = File.expand_path(run_root)
      candidate = File.expand_path(value, root)
      unless candidate.start_with?("#{root}#{File::SEPARATOR}")
        raise ContractError, "media path escapes run root: #{value}"
      end
      current = root
      Pathname.new(candidate).relative_path_from(Pathname.new(root)).each_filename do |component|
        current = File.join(current, component)
        if File.exist?(current) || File.symlink?(current)
          raise ContractError, "symbolic link is forbidden in media path: #{value}" if File.lstat(current).symlink?
        end
      end
      candidate
    end
  end

  class SystemOverlayGuard
    FRAME_RATE = 30.0
    EXPECTED_FRAME_COUNT = 720
    TOP_BAND_FILTER =
      "crop=iw*0.75:ih*0.20:iw*0.125:0,signalstats," \
      "metadata=print:key=lavfi.signalstats.YAVG:file=-"
    MAX_TOP_BAND_YAVG = 64.0
    TIMESTAMP_TOLERANCE_SECONDS = 0.000_01

    def self.report_path(run_root:, locale:, device:)
      unless LOCALES.include?(locale) && DEVICES.any? { |candidate| candidate.fetch(:id) == device }
        raise ContractError, "invalid system-overlay report identity"
      end
      Paths.inside!(run_root, File.join(SYSTEM_OVERLAY_REPORT_ROOT, "#{locale}-#{device}.json"))
    end

    def initialize(executable: "/opt/homebrew/bin/ffmpeg", runner: Open3, captured_at: nil)
      @executable = executable
      @runner = runner
      @captured_at = captured_at || -> { Time.now.utc }
    end

    def validate!(path:, report_path:)
      video_path = File.expand_path(path)
      report_path = File.expand_path(report_path)
      report_written = false
      unless File.file?(video_path) && !File.symlink?(video_path)
        message = "system-overlay guard input must be a regular non-symlink file"
        write_report!(report_path, failure_report(video_path, message))
        report_written = true
        raise ContractError, message
      end

      stdout, stderr, status = capture(
        @executable, "-hide_banner", "-v", "error", "-i", video_path,
        "-vf", TOP_BAND_FILTER, "-an", "-f", "null", "/dev/null"
      )
      unless status.success?
        message = "system-overlay guard scan failed: #{stderr.to_s.strip}"
        write_report!(report_path, failure_report(video_path, message))
        report_written = true
        raise ContractError, message
      end

      frames = parse_frames!(stdout)
      violations = frames.select { |frame| frame.fetch("top_band_yavg") >= MAX_TOP_BAND_YAVG }
      report = {
        "schema_version" => 1,
        "status" => violations.empty? ? "pass" : "fail",
        "generated_at" => @captured_at.call.utc.iso8601(6),
        "video_path" => video_path,
        "video_sha256" => Digest::SHA256.file(video_path).hexdigest,
        "expected_frame_count" => EXPECTED_FRAME_COUNT,
        "scanned_frame_count" => frames.length,
        "frame_rate" => FRAME_RATE,
        "top_band" => {
          "x_ratio" => 0.125, "y_ratio" => 0.0,
          "width_ratio" => 0.75, "height_ratio" => 0.20,
          "metric" => "lavfi.signalstats.YAVG",
          "reject_at_or_above" => MAX_TOP_BAND_YAVG
        },
        "violation_count" => violations.length,
        "violation_spans" => violation_spans(violations),
        "violating_frames" => violations
      }
      write_report!(report_path, report)
      report_written = true
      return report if violations.empty?

      first = violations.first
      last = violations.last
      raise ContractError,
            format(
              "system UI top-band guard rejected %d frame(s), PTS %.6f-%.6f; inspect %s",
              violations.length, first.fetch("pts_seconds"), last.fetch("pts_seconds"), report_path
            )
    rescue ContractError => error
      unless report_written
        write_report!(report_path, failure_report(video_path, error.message))
      end
      raise
    rescue StandardError => error
      message = "system-overlay guard failed closed: #{error.class}: #{error.message}"
      write_report!(report_path, failure_report(video_path, message)) unless report_written
      raise ContractError, message
    end

    private

    def capture(*arguments)
      return @runner.capture3(*arguments) if @runner.respond_to?(:capture3)
      return @runner.capture(*arguments) if @runner.respond_to?(:capture)

      raise ContractError, "system-overlay guard runner cannot capture commands"
    end

    def parse_frames!(output)
      frames = []
      current = nil
      output.to_s.each_line do |line|
        if (match = line.match(/\Aframe:(\d+)\s+pts:\S+\s+pts_time:([-+0-9.eE]+)\s*\z/))
          raise ContractError, "system-overlay scan omitted a frame metric" if current
          current = { "frame" => Integer(match[1], 10), "pts_seconds" => Float(match[2]) }
        elsif (match = line.match(/\Alavfi\.signalstats\.YAVG=([-+0-9.eE]+)\s*\z/))
          raise ContractError, "system-overlay scan returned an orphan frame metric" unless current
          value = Float(match[1])
          raise ContractError, "system-overlay scan returned a non-finite metric" unless value.finite?
          frames << current.merge("top_band_yavg" => value.round(6))
          current = nil
        end
      end
      raise ContractError, "system-overlay scan omitted a frame metric" if current
      unless frames.length == EXPECTED_FRAME_COUNT && frames.map { |frame| frame.fetch("frame") } == (0...EXPECTED_FRAME_COUNT).to_a
        raise ContractError,
              "system-overlay scan must cover exactly 720 sequential frames"
      end
      frames.each do |frame|
        expected = frame.fetch("frame") / FRAME_RATE
        unless (frame.fetch("pts_seconds") - expected).abs <= TIMESTAMP_TOLERANCE_SECONDS
          raise ContractError, "system-overlay scan returned an irregular frame timeline"
        end
        frame["pts_seconds"] = frame.fetch("pts_seconds").round(6)
      end
      frames
    rescue ArgumentError, TypeError
      raise ContractError, "system-overlay scan returned invalid frame metadata"
    end

    def violation_spans(violations)
      violations.slice_when do |left, right|
        right.fetch("frame") != left.fetch("frame") + 1
      end.map do |span|
        first = span.first
        last = span.last
        {
          "first_frame" => first.fetch("frame"),
          "last_frame" => last.fetch("frame"),
          "first_pts_seconds" => first.fetch("pts_seconds"),
          "last_pts_seconds" => last.fetch("pts_seconds"),
          "end_pts_exclusive_seconds" => ((last.fetch("frame") + 1) / FRAME_RATE).round(6),
          "frame_count" => span.length,
          "max_top_band_yavg" => span.map { |frame| frame.fetch("top_band_yavg") }.max
        }
      end
    end

    def failure_report(video_path, message)
      {
        "schema_version" => 1,
        "status" => "error",
        "generated_at" => @captured_at.call.utc.iso8601(6),
        "video_path" => video_path,
        "expected_frame_count" => EXPECTED_FRAME_COUNT,
        "scanned_frame_count" => 0,
        "error" => message
      }
    end

    def write_report!(path, payload)
      if File.exist?(path) || File.symlink?(path)
        raise ContractError, "system-overlay report path must be a regular non-symlink file" if File.symlink?(path) || !File.file?(path)
      end
      FileUtils.mkdir_p(File.dirname(path))
      temporary = "#{path}.tmp-#{Process.pid}-#{Thread.current.object_id}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write("#{JSON.pretty_generate(payload)}\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(0o600, path)
      path
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end
  end

  class SourceFingerprint
    EXCLUDED_PREFIXES = %w[
      .git/ .build/ .swiftpm/ Builds/ DerivedData/ .superpowers/
      fastlane/report.xml fastlane/asc_api_key.json docs/validation-report.md
    ].freeze

    def initialize(app_root)
      @app_root = File.expand_path(app_root)
    end

    def value
      candidates = Dir.glob(File.join(@app_root, "**", "*"), File::FNM_DOTMATCH)
      relevant_symlink = candidates.find do |path|
        relative = Pathname.new(path).relative_path_from(Pathname.new(@app_root)).to_s
        File.symlink?(path) && !excluded?(relative)
      end
      raise ContractError, "source fingerprint forbids symbolic links" if relevant_symlink

      entries = candidates.select { |path| File.file?(path) && !File.symlink?(path) }
                          .map { |path| Pathname.new(path).relative_path_from(Pathname.new(@app_root)).to_s }
                          .reject { |relative| excluded?(relative) }
                          .sort
      digest = Digest::SHA256.new
      entries.each do |relative|
        absolute = File.join(@app_root, relative)
        mode = File.stat(absolute).mode & 0o777
        digest << relative << "\0" << format("%03o", mode) << "\0" << Digest::SHA256.file(absolute).hexdigest << "\n"
      end
      digest.hexdigest
    end

    private

    def excluded?(relative)
      EXCLUDED_PREFIXES.any? do |prefix|
        prefix.end_with?("/") ? relative == prefix.delete_suffix("/") || relative.start_with?(prefix) : relative == prefix
      end ||
        relative.include?(".xcuserdatad/") || relative.end_with?(".xcuserstate")
    end
  end

  class ManifestBuilder
    def initialize(run_root:, source_revision:, captured_at: Time.now.utc)
      @run_root = File.expand_path(run_root)
      @source_revision = source_revision
      @captured_at = captured_at.utc
    end

    def prepare!
      validate_source_revision!
      FileUtils.mkdir_p(File.join(@run_root, "logs"))
      FileUtils.mkdir_p(File.join(@run_root, "screenshots"))
      FileUtils.mkdir_p(File.join(@run_root, "app_previews"))
      manifest = {
        "schema_version" => 1,
        "app_slug" => APP_SLUG,
        "generated_at" => @captured_at.iso8601(6),
        "source_revision" => @source_revision,
        "locales" => LOCALES,
        "devices" => DEVICES.map { |device| device.fetch(:id) },
        "scenarios" => SCENARIOS,
        "cells" => cells
      }
      write_json(File.join(@run_root, MANIFEST_PATH), manifest)
      manifest
    end

    private

    def cells
      LOCALES.flat_map do |locale|
        DEVICES.flat_map do |device|
          SCENARIOS.each_with_index.map do |scenario, index|
            {
              "locale" => locale,
              "device" => device.fetch(:id),
              "scenario" => scenario,
              "source_revision" => @source_revision,
              "width" => device.fetch(:width),
              "height" => device.fetch(:height),
              "preview_width" => device.fetch(:preview_width),
              "preview_height" => device.fetch(:preview_height),
              "preview_offset_seconds" => index * 4.0,
              "capture_trim_offset_seconds" => nil,
              "preview_raw_source_sha256" => nil,
              "preview_raw_source_run_id" => nil,
              "preview_raw_width" => nil,
              "preview_raw_height" => nil,
              "preview_raw_transform" => nil,
              "preview_raw_udid" => nil,
              "preview_raw_locale" => nil,
              "preview_raw_handshake_sha256" => nil,
              "screenshot_source_preview_path" => nil,
              "screenshot_source_offset_seconds" => nil,
              "screenshot_captured_at" => nil,
              "screenshot_path" => format("screenshots/%s/%02d-%s-%s.png", locale, index + 1, scenario, device.fetch(:id)),
              "preview_path" => "app_previews/#{locale}/NovaStationPinball-#{device.fetch(:id)}.mov",
              "status" => "pending",
              "screenshot_sha256" => nil,
              "preview_sha256" => nil
            }
          end
        end
      end
    end

    def validate_source_revision!
      return if @source_revision.to_s.match?(/\A[0-9a-f]{64}\z/)

      raise ContractError, "source revision must be a SHA-256 fingerprint"
    end

    def write_json(path, payload)
      File.write(path, "#{JSON.pretty_generate(payload)}\n", mode: "w", perm: 0o600)
    end
  end

  class FFProbe
    def initialize(executable: "/opt/homebrew/bin/ffprobe", runner: Open3)
      @executable = executable
      @runner = runner
    end

    def probe(path)
      stdout, stderr, status = @runner.capture3(
        @executable, "-v", "error", "-count_frames", "-print_format", "json",
        "-show_format", "-show_streams", path
      )
      raise ContractError, "ffprobe failed for #{File.basename(path)}: #{stderr.strip}" unless status.success?

      payload = JSON.parse(stdout)
      streams = payload.fetch("streams")
      raise ContractError, "invalid stream list in #{File.basename(path)}" unless streams.instance_of?(Array)
      videos = streams.select { |stream| stream["codec_type"] == "video" }
      audios = streams.select { |stream| stream["codec_type"] == "audio" }
      raise ContractError, "missing video stream in #{File.basename(path)}" if videos.empty?
      raise ContractError, "missing audio stream in #{File.basename(path)}" if audios.empty?
      video = videos.first
      audio = audios.first

      {
        "width" => strict_integer(video.fetch("width")),
        "height" => strict_integer(video.fetch("height")),
        "duration" => strict_float(payload.fetch("format").fetch("duration")),
        "video_duration" => strict_float(video.fetch("duration")),
        "audio_duration" => strict_float(audio.fetch("duration")),
        "video_frames" => strict_integer(video["nb_read_frames"] || video.fetch("nb_frames")),
        "frame_rate" => rational(video.fetch("avg_frame_rate")),
        "video_codec" => video.fetch("codec_name"),
        "video_profile" => video.fetch("profile"),
        "video_level" => strict_integer(video.fetch("level")),
        "pixel_format" => video.fetch("pix_fmt"),
        "field_order" => video.fetch("field_order"),
        "rotation" => video_rotation(video),
        "video_bit_rate" => strict_integer(video.fetch("bit_rate")),
        "audio_codec" => audio.fetch("codec_name"),
        "audio_profile" => audio.fetch("profile"),
        "audio_bit_rate" => strict_integer(audio.fetch("bit_rate")),
        "audio_channels" => strict_integer(audio.fetch("channels")),
        "audio_sample_rate" => strict_integer(audio.fetch("sample_rate")),
        "video_enabled" => video.fetch("disposition", {}).fetch("default", 0) == 1,
        "audio_enabled" => audio.fetch("disposition", {}).fetch("default", 0) == 1,
        "video_streams" => videos.length,
        "audio_streams" => audios.length
      }
    rescue JSON::ParserError, KeyError, ArgumentError, TypeError => error
      raise ContractError, "invalid ffprobe result for #{File.basename(path)}: #{error.message}"
    end

    private

    def rational(value)
      parts = value.to_s.split("/", 2)
      raise ArgumentError, "invalid rational" unless parts.length == 2
      numerator = strict_float(parts[0])
      denominator = strict_float(parts[1])
      raise ArgumentError, "invalid rational denominator" unless denominator.positive?
      numerator / denominator
    end

    def video_rotation(video)
      values = video.fetch("side_data_list", []).each_with_object([]) do |entry, result|
        result << entry["rotation"] if entry.key?("rotation")
      end
      values << video.fetch("tags", {})["rotate"] if video.fetch("tags", {}).key?("rotate")
      return 0.0 if values.empty?
      rotations = values.map { |value| strict_float(value) }
      raise ArgumentError, "conflicting video rotation metadata" unless rotations.uniq.length == 1
      rotations.first
    end

    def strict_float(value)
      parsed = Float(value)
      raise ArgumentError, "non-finite number" unless parsed.finite?
      parsed
    end

    def strict_integer(value)
      Integer(value)
    end
  end

  class PNGVisualProbe
    def initialize(executable: "/opt/homebrew/bin/magick", runner: Open3)
      @executable = executable
      @runner = runner
    end

    def probe(path)
      stdout, stderr, status = @runner.capture3(
        @executable, path, "-fuzz", "2%", "-trim", "-format", "%w %h", "info:"
      )
      raise ContractError, "visual probe failed for #{File.basename(path)}: #{stderr.strip}" unless status.success?

      trimmed_width, trimmed_height = stdout.split.map { |value| Integer(value, 10) }
      width, height = PNGMetadata.send(:chunks, path).find { |type, _data, _raw| type == "IHDR" }[1].unpack("NN")
      {
        "width_ratio" => trimmed_width.to_f / width,
        "height_ratio" => trimmed_height.to_f / height
      }
    rescue ArgumentError, NoMethodError
      raise ContractError, "visual probe returned invalid geometry for #{File.basename(path)}"
    end
  end

  class Contract
    def initialize(run_root:, source_revision:, probe: FFProbe.new, visual_probe: PNGVisualProbe.new,
                   overlay_guard: SystemOverlayGuard.new, allow_pending: false)
      @run_root = File.expand_path(run_root)
      @source_revision = source_revision
      @probe = probe
      @visual_probe = visual_probe
      @overlay_guard = overlay_guard
      @allow_pending = allow_pending
      @errors = []
    end

    def validate!
      invalidate_proof!
      manifest = read_manifest
      validate_header(manifest)
      cells = manifest.fetch("cells", [])
      validate_matrix(cells)
      validate_cells(cells)
      validate_media_tree(cells)
      raise ContractError, @errors.uniq.join("\n") unless @errors.empty?

      report = report_for(cells)
      write_proof(report) if report.fetch("pending_cells").zero?
      report
    rescue JSON::ParserError => error
      raise ContractError, "invalid media manifest JSON: #{error.message}"
    end

    private

    def read_manifest
      path = Paths.inside!(@run_root, MANIFEST_PATH)
      raise ContractError, "missing media manifest" unless File.file?(path)

      JSON.parse(File.read(path, encoding: "UTF-8"))
    end

    def validate_header(manifest)
      error("media manifest schema mismatch") unless manifest["schema_version"] == 1
      error("media manifest app mismatch") unless manifest["app_slug"] == APP_SLUG
      error("media manifest locales mismatch") unless manifest["locales"] == LOCALES
      error("media manifest devices mismatch") unless manifest["devices"] == DEVICES.map { |device| device.fetch(:id) }
      error("media manifest scenarios mismatch") unless manifest["scenarios"] == SCENARIOS
      error("stale media manifest") unless manifest["source_revision"] == @source_revision
      Time.iso8601(manifest.fetch("generated_at"))
    rescue KeyError, ArgumentError
      error("media manifest must contain a valid generated_at timestamp")
    end

    def validate_matrix(cells)
      expected = LOCALES.product(DEVICES.map { |device| device.fetch(:id) }, SCENARIOS)
      keys = cells.map { |cell| cell.values_at("locale", "device", "scenario") }
      counts = keys.each_with_object(Hash.new(0)) { |key, result| result[key] += 1 }
      duplicates = counts.select { |_key, count| count > 1 }.keys
      missing = expected - keys
      foreign = keys - expected
      error("duplicate media cell: #{duplicates.first.join('/')}") unless duplicates.empty?
      error("missing media cell: #{missing.first.join('/')}") unless missing.empty?
      error("foreign media cell: #{foreign.first.join('/')}") unless foreign.empty?
    end

    def validate_cells(cells)
      previews = {}
      preview_trim_offsets = Hash.new { |hash, key| hash[key] = [] }
      screenshot_paths = cells.map { |cell| cell["screenshot_path"] }.compact
      duplicate_screenshots = screenshot_paths.group_by { |path| path }.select { |_path, entries| entries.length > 1 }.keys
      error("duplicate screenshot artifact path: #{duplicate_screenshots.first}") unless duplicate_screenshots.empty?
      cells.each do |cell|
        device = DEVICES.find { |candidate| candidate.fetch(:id) == cell["device"] }
        next unless device && LOCALES.include?(cell["locale"]) && SCENARIOS.include?(cell["scenario"])

        error("stale media cell: #{cell.values_at('locale', 'device', 'scenario').join('/')}") unless cell["source_revision"] == @source_revision
        validate_dimensions(cell, device)
        validate_artifact_paths(cell)
        screenshot = safe_path(cell["screenshot_path"])
        preview = safe_path(cell["preview_path"])
        next unless screenshot && preview

        if cell["status"] == "pending"
          unless cell.key?("capture_trim_offset_seconds") && cell["capture_trim_offset_seconds"].nil?
            error("pending capture trim offset must be empty: #{cell['preview_path']}")
          end
          error("pending media cell: #{cell.values_at('locale', 'device', 'scenario').join('/')}") unless @allow_pending
          next
        end
        unless cell["status"] == "captured"
          error("invalid media cell status: #{cell['status'].inspect}")
          next
        end
        validate_screenshot(cell, screenshot, device)
        validate_raw_preview_provenance(cell, device)
        validate_capture_trim_offset(cell)
        preview_trim_offsets[preview] << cell["capture_trim_offset_seconds"]
        previews[preview] ||= [cell, device]
      end
      preview_trim_offsets.each do |path, offsets|
        error("inconsistent capture trim offset: #{path}") unless offsets.uniq.length == 1
      end
      previews.each { |path, (cell, device)| validate_preview(cell, path, device) }
    end

    def validate_capture_trim_offset(cell)
      offset = cell["capture_trim_offset_seconds"]
      unless offset.is_a?(Numeric) && offset.finite? && offset.positive? && offset <= 45.0
        error("invalid capture trim offset: #{cell['preview_path']}")
      end
    end

    def validate_raw_preview_provenance(cell, device)
      valid = cell["preview_raw_source_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
              cell["preview_raw_source_run_id"].to_s.match?(/\A[0-9A-Za-z][0-9A-Za-z._-]{0,79}\z/) &&
              cell.values_at("preview_raw_width", "preview_raw_height") == device.values_at(:height, :width) &&
              cell["preview_raw_transform"] == device.fetch(:raw_transform) &&
              cell["preview_raw_udid"].to_s.match?(/\A[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}\z/i) &&
              cell["preview_raw_locale"] == cell["locale"] &&
              cell["preview_raw_handshake_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
      error("invalid raw App Preview provenance: #{cell['preview_path']}") unless valid
    end

    def validate_artifact_paths(cell)
      index = SCENARIOS.index(cell.fetch("scenario"))
      expected_screenshot = format(
        "screenshots/%s/%02d-%s-%s.png",
        cell.fetch("locale"), index + 1, cell.fetch("scenario"), cell.fetch("device")
      )
      expected_preview = "app_previews/#{cell.fetch('locale')}/NovaStationPinball-#{cell.fetch('device')}.mov"
      error("screenshot path mismatch: #{cell['screenshot_path']}") unless cell["screenshot_path"] == expected_screenshot
      error("preview path mismatch: #{cell['preview_path']}") unless cell["preview_path"] == expected_preview
    end

    def validate_dimensions(cell, device)
      error("screenshot dimensions mismatch for #{cell['device']}") unless
        cell.values_at("width", "height") == device.values_at(:width, :height)
      error("preview dimensions mismatch for #{cell['device']}") unless
        cell.values_at("preview_width", "preview_height") == device.values_at(:preview_width, :preview_height)
      index = SCENARIOS.index(cell["scenario"])
      error("preview timeline mismatch for #{cell['scenario']}") unless cell["preview_offset_seconds"] == index * 4.0
    end

    def validate_screenshot(cell, path, device)
      unless File.file?(path)
        error("missing screenshot artifact: #{cell['screenshot_path']}")
        return
      end
      expected_hash = cell["screenshot_sha256"].to_s
      error("screenshot checksum mismatch: #{cell['screenshot_path']}") unless
        expected_hash.match?(/\A[0-9a-f]{64}\z/) && Digest::SHA256.file(path).hexdigest == expected_hash
      dimensions = png_dimensions(path)
      error("screenshot dimensions mismatch: #{cell['screenshot_path']}") unless dimensions == device.values_at(:width, :height)
      orientation = PNGMetadata.orientation(path)
      error("screenshot orientation metadata must be absent or 1: #{cell['screenshot_path']}") unless orientation.nil? || orientation == 1
      expected_offset = NovaStationPinballMediaContract.screenshot_source_offset(cell.fetch("scenario"))
      error("screenshot preview provenance mismatch: #{cell['screenshot_path']}") unless
        cell["screenshot_source_preview_path"] == cell["preview_path"] &&
        cell["screenshot_source_offset_seconds"] == expected_offset
      begin
        Time.iso8601(cell.fetch("screenshot_captured_at"))
      rescue KeyError, ArgumentError, TypeError
        error("invalid screenshot capture timestamp: #{cell['screenshot_path']}")
      end
      coverage = @visual_probe.probe(path)
      error("screenshot content coverage is too small: #{cell['screenshot_path']}") if
        coverage.fetch("width_ratio") < 0.55 || coverage.fetch("height_ratio") < 0.50
    rescue ContractError => exception
      error(exception.message)
    end

    def validate_preview(cell, path, device)
      unless File.file?(path)
        error("missing preview artifact: #{cell['preview_path']}")
        return
      end
      expected_hash = cell["preview_sha256"].to_s
      error("preview checksum mismatch: #{cell['preview_path']}") unless
        expected_hash.match?(/\A[0-9a-f]{64}\z/) && Digest::SHA256.file(path).hexdigest == expected_hash
      info = @probe.probe(path)
      error("preview dimensions mismatch: #{cell['preview_path']}") unless
        info.values_at("width", "height") == device.values_at(:preview_width, :preview_height)
      error("preview duration must be exactly 24 seconds: #{cell['preview_path']}") unless (info.fetch("duration") - 24.0).abs <= 0.001
      error("preview video track must be exactly 24 seconds: #{cell['preview_path']}") unless (info.fetch("video_duration") - 24.0).abs <= 0.001
      error("preview audio track must be exactly 24 seconds: #{cell['preview_path']}") unless (info.fetch("audio_duration") - 24.0).abs <= 0.001
      error("preview must contain exactly 720 video frames: #{cell['preview_path']}") unless info.fetch("video_frames") == 720
      error("preview frame rate must be exactly 30 fps: #{cell['preview_path']}") unless (info.fetch("frame_rate") - 30.0).abs <= 0.01
      error("preview video codec must be H.264: #{cell['preview_path']}") unless info.fetch("video_codec") == "h264"
      error("preview H.264 profile must be High: #{cell['preview_path']}") unless info.fetch("video_profile") == "High"
      error("preview H.264 level must be 4.0 or lower: #{cell['preview_path']}") unless info.fetch("video_level").between?(1, 40)
      error("preview pixel format must be yuv420p: #{cell['preview_path']}") unless info.fetch("pixel_format") == "yuv420p"
      error("preview must be progressive: #{cell['preview_path']}") unless info.fetch("field_order") == "progressive"
      error("preview rotation metadata must be zero: #{cell['preview_path']}") unless info.fetch("rotation") == 0.0
      error("preview video bit rate must be 10-12 Mbps: #{cell['preview_path']}") unless info.fetch("video_bit_rate").between?(10_000_000, 12_000_000)
      error("preview audio codec must be AAC: #{cell['preview_path']}") unless info.fetch("audio_codec") == "aac"
      error("preview audio profile must be AAC-LC: #{cell['preview_path']}") unless info.fetch("audio_profile") == "LC"
      # Native AAC reports the encoded payload average below its 256 kb/s target;
      # keep a narrow ±10% acceptance window while rejecting low-bit-rate forgeries.
      error("preview audio bit rate must be 256 kbps: #{cell['preview_path']}") unless info.fetch("audio_bit_rate").between?(230_400, 281_600)
      error("preview audio must be stereo: #{cell['preview_path']}") unless info.fetch("audio_channels") == 2
      error("preview audio sample rate must be 44.1 or 48 kHz: #{cell['preview_path']}") unless [44_100, 48_000].include?(info.fetch("audio_sample_rate"))
      error("preview must contain exactly one video stream: #{cell['preview_path']}") unless info.fetch("video_streams") == 1
      error("preview must contain exactly one stereo audio stream: #{cell['preview_path']}") unless info.fetch("audio_streams") == 1
      error("preview tracks must be enabled: #{cell['preview_path']}") unless info.fetch("video_enabled", true) && info.fetch("audio_enabled", true)
      @overlay_guard.validate!(
        path: path,
        report_path: SystemOverlayGuard.report_path(
          run_root: @run_root, locale: cell.fetch("locale"), device: cell.fetch("device")
        )
      )
    rescue ContractError, KeyError => exception
      error(exception.message)
    end

    def validate_media_tree(cells)
      expected = cells.flat_map { |cell| [cell["screenshot_path"], cell["preview_path"]] }.compact.uniq.sort
      actual = %w[screenshots app_previews].flat_map do |folder|
        root = File.join(@run_root, folder)
        next [] unless Dir.exist?(root)

        Dir.glob(File.join(root, "**", "*")).select { |path| File.file?(path) || File.symlink?(path) }.map do |path|
          Pathname.new(path).relative_path_from(Pathname.new(@run_root)).to_s
        end
      end.sort
      (actual - expected).each { |relative| error("foreign media artifact: #{relative}") }
    end

    def safe_path(relative)
      Paths.inside!(@run_root, relative)
    rescue ContractError => exception
      error(exception.message)
      nil
    end

    def png_dimensions(path)
      File.open(path, "rb") do |file|
        raise ContractError, "invalid PNG signature: #{File.basename(path)}" unless file.read(8) == PNG_SIGNATURE
        length = file.read(4)&.unpack1("N")
        type = file.read(4)
        raise ContractError, "invalid PNG header: #{File.basename(path)}" unless length == 13 && type == "IHDR"
        file.read(8).unpack("NN")
      end
    end

    def report_for(cells)
      pending = cells.count { |cell| cell["status"] == "pending" }
      {
        "schema_version" => 1,
        "validated_at" => Time.now.utc.iso8601(6),
        "source_revision" => @source_revision,
        "pending_cells" => pending,
        "cells" => cells,
        "screenshots" => cells.map { |cell| cell["screenshot_path"] }.uniq,
        "app_previews" => cells.map { |cell| cell["preview_path"] }.uniq
      }
    end

    def invalidate_proof!
      FileUtils.rm_f(File.join(@run_root, PROOF_PATH))
    end

    def write_proof(report)
      path = Paths.inside!(@run_root, PROOF_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#{JSON.pretty_generate(report)}\n", mode: "w", perm: 0o600)
    end

    def error(message)
      @errors << message
    end
  end

  module CLI
    module_function

    def run(argv)
      options = { allow_pending: false }
      OptionParser.new do |flags|
        flags.banner = "Usage: media_contract.rb --run-root PATH [--allow-pending]"
        flags.on("--run-root PATH") { |value| options[:run_root] = value }
        flags.on("--allow-pending") { options[:allow_pending] = true }
      end.parse!(argv)
      raise ContractError, "--run-root is required" unless options[:run_root]

      run_root = File.expand_path(options.fetch(:run_root))
      app_root = File.expand_path("../../../..", run_root)
      expected_parent = File.join(app_root, "Builds", "AppStore", APP_SLUG)
      raise ContractError, "run root must be an app-local #{APP_SLUG} release directory" unless File.dirname(run_root) == expected_parent

      revision = SourceFingerprint.new(app_root).value
      report = Contract.new(
        run_root: run_root,
        source_revision: revision,
        allow_pending: options.fetch(:allow_pending)
      ).validate!
      puts "media_contract: OK (#{report.fetch('cells').length} cells, #{report.fetch('pending_cells')} pending)"
      0
    rescue ContractError, OptionParser::ParseError => error
      warn "media_contract: #{error.message}"
      1
    end
  end
end

exit NovaStationPinballMediaContract::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
