#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require_relative "generate_app_previews"

module NovaStationPinballPreviewReencoding
  module Source
    module_function

    IDENTIFIER = /\A[0-9A-Za-z][0-9A-Za-z._-]{0,79}\z/

    def validate_id!(value)
      return value if value.to_s.match?(IDENTIFIER)

      raise NovaStationPinballMediaContract::ContractError, "invalid raw source execution id"
    end

    def handshake_sha256(path)
      body = File.read(path, encoding: "UTF-8")
      token = body[/<key>NOVA_MEDIA_HANDSHAKE_TOKEN<\/key>\s*<string>([0-9a-f]{32})<\/string>/, 1]
      raise NovaStationPinballMediaContract::ContractError, "missing verified raw App Preview handshake" unless token

      Digest::SHA256.hexdigest(token)
    end
  end

  class SourceReceipt
    PROVENANCE_KEYS = %w[
      capture_trim_offset_seconds preview_raw_source_sha256 preview_raw_source_run_id
      preview_raw_width preview_raw_height preview_raw_transform preview_raw_udid
      preview_raw_locale preview_raw_handshake_sha256
    ].freeze

    def self.load!(manifest_path:, source_execution_id:, locale:, device_id:, raw_path:, xctestrun_path:,
                   expected_udid:, runner:)
      new(
        manifest_path: manifest_path, source_execution_id: source_execution_id,
        locale: locale, device_id: device_id, raw_path: raw_path,
        xctestrun_path: xctestrun_path, expected_udid: expected_udid,
        runner: runner
      ).load!
    end

    def initialize(manifest_path:, source_execution_id:, locale:, device_id:, raw_path:, xctestrun_path:,
                   expected_udid:, runner:)
      @manifest_path = manifest_path
      @source_execution_id = Source.validate_id!(source_execution_id)
      @locale = locale
      @device_id = device_id
      @raw_path = raw_path
      @xctestrun_path = xctestrun_path
      @expected_udid = expected_udid.to_s.upcase
      @runner = runner
    end

    def load!
      manifest = read_manifest!
      cells = source_cells!(manifest)
      provenance = coherent_provenance!(cells)
      validate_identity!(provenance)
      geometry = validate_raw!(provenance)
      handshake_sha256 = validate_xctestrun!(provenance)
      {
        "capture_trim_offset_seconds" => provenance.fetch("capture_trim_offset_seconds"),
        "source_sha256" => provenance.fetch("preview_raw_source_sha256"),
        "source_run_id" => provenance.fetch("preview_raw_source_run_id"),
        "width" => geometry.fetch(0), "height" => geometry.fetch(1),
        "source_transform" => provenance.fetch("preview_raw_transform"),
        "udid" => provenance.fetch("preview_raw_udid").upcase,
        "locale" => provenance.fetch("preview_raw_locale"),
        "handshake_sha256" => handshake_sha256
      }
    end

    private

    def read_manifest!
      unless File.file?(@manifest_path) && !File.symlink?(@manifest_path)
        raise NovaStationPinballMediaContract::ContractError,
              "source media manifest must be a regular non-symlink file"
      end
      payload = JSON.parse(File.binread(@manifest_path))
      unless payload.is_a?(Hash) && payload["cells"].is_a?(Array)
        raise NovaStationPinballMediaContract::ContractError, "invalid source media manifest"
      end
      payload
    rescue JSON::ParserError
      raise NovaStationPinballMediaContract::ContractError, "invalid source media manifest JSON"
    end

    def source_cells!(manifest)
      cells = manifest.fetch("cells").select do |cell|
        cell.is_a?(Hash) && cell["locale"] == @locale && cell["device"] == @device_id
      end
      scenarios = cells.map { |cell| cell["scenario"] }
      unless cells.length == NovaStationPinballMediaContract::SCENARIOS.length &&
             scenarios.sort == NovaStationPinballMediaContract::SCENARIOS.sort
        raise NovaStationPinballMediaContract::ContractError,
              "source manifest must contain exactly six source preview cells for locale/device"
      end
      cells
    end

    def coherent_provenance!(cells)
      values = PROVENANCE_KEYS.to_h do |key|
        candidates = cells.map { |cell| cell[key] }.uniq
        unless candidates.length == 1
          label = key == "capture_trim_offset_seconds" ? "source capture trim offset" : "source raw provenance"
          raise NovaStationPinballMediaContract::ContractError, "inconsistent #{label} across source preview cells"
        end
        [key, candidates.first]
      end
      trim = values.fetch("capture_trim_offset_seconds")
      unless trim.is_a?(Numeric) && trim.finite? && trim.positive? && trim <= 45.0
        raise NovaStationPinballMediaContract::ContractError, "invalid source capture trim offset"
      end
      values
    end

    def validate_identity!(provenance)
      unless provenance.fetch("preview_raw_source_run_id") == @source_execution_id
        raise NovaStationPinballMediaContract::ContractError, "source run id does not match requested execution"
      end
      unless provenance.fetch("preview_raw_locale") == @locale
        raise NovaStationPinballMediaContract::ContractError, "source locale does not match requested locale"
      end
      unless provenance.fetch("preview_raw_udid").to_s.casecmp?(@expected_udid)
        raise NovaStationPinballMediaContract::ContractError,
              "source capture UDID does not match the owned source device"
      end
    end

    def validate_raw!(provenance)
      unless File.file?(@raw_path) && !File.symlink?(@raw_path)
        raise NovaStationPinballMediaContract::ContractError, "raw source must be a regular non-symlink file"
      end
      actual_sha = Digest::SHA256.file(@raw_path).hexdigest
      unless provenance.fetch("preview_raw_source_sha256") == actual_sha
        raise NovaStationPinballMediaContract::ContractError, "raw source checksum does not match source manifest"
      end
      device = NovaStationPinballMediaContract::DEVICES.find { |candidate| candidate.fetch(:id) == @device_id }
      raise NovaStationPinballMediaContract::ContractError, "unknown source device" unless device

      geometry = NovaStationPinballPreviewGeneration::RawGeometry.probe(@raw_path, runner: @runner)
      NovaStationPinballPreviewGeneration::RawGeometry.validate!(
        width: geometry.fetch(0), height: geometry.fetch(1), device: device
      )
      unless provenance.values_at("preview_raw_width", "preview_raw_height") == geometry &&
             %w[transpose=clock transpose=cclock].include?(provenance.fetch("preview_raw_transform"))
        raise NovaStationPinballMediaContract::ContractError,
              "source raw provenance dimensions or transform do not match capture"
      end
      geometry
    end

    def validate_xctestrun!(provenance)
      unless File.file?(@xctestrun_path) && !File.symlink?(@xctestrun_path)
        raise NovaStationPinballMediaContract::ContractError,
              "source xctestrun must be a regular non-symlink file"
      end
      payload = CFPropertyList.native_types(CFPropertyList::List.new(file: @xctestrun_path).value)
      configurations = payload["TestConfigurations"]
      candidates = if configurations.is_a?(Array)
        configurations.flat_map do |configuration|
          configuration.is_a?(Hash) && configuration["TestTargets"].is_a?(Array) ?
            configuration["TestTargets"] : []
        end
      else
        payload.reject { |key, _value| key == "__xctestrun_metadata__" }.values
      end
      targets = candidates.select do |target|
        target.is_a?(Hash) &&
          (target["BlueprintName"] == "NovaStationPinballUITests" ||
           File.basename(target["TestBundlePath"].to_s).include?("NovaStationPinballUITests"))
      end
      unless targets.length == 1
        raise NovaStationPinballMediaContract::ContractError,
              "source xctestrun UI target must be present exactly once"
      end
      target = targets.first
      environment = target["EnvironmentVariables"]
      testing_environment = target["TestingEnvironmentVariables"]
      enabled = target["EnvironmentVariablesEnabled"]
      token = environment.is_a?(Hash) && environment["NOVA_MEDIA_HANDSHAKE_TOKEN"]
      locale = environment.is_a?(Hash) && environment["NOVA_MEDIA_LOCALE"]
      unless token.to_s.match?(/\A[0-9a-f]{32}\z/) &&
             testing_environment.is_a?(Hash) &&
             testing_environment["NOVA_MEDIA_HANDSHAKE_TOKEN"] == token &&
             testing_environment["NOVA_MEDIA_LOCALE"] == locale &&
             enabled.is_a?(Hash) && enabled["NOVA_MEDIA_HANDSHAKE_TOKEN"] == true &&
             enabled["NOVA_MEDIA_LOCALE"] == true
        raise NovaStationPinballMediaContract::ContractError,
              "source xctestrun handshake environment is not verified"
      end
      unless locale == @locale
        raise NovaStationPinballMediaContract::ContractError,
              "source xctestrun locale does not match source cells"
      end
      handshake_sha256 = Digest::SHA256.hexdigest(token)
      unless handshake_sha256 == provenance.fetch("preview_raw_handshake_sha256")
        raise NovaStationPinballMediaContract::ContractError,
              "source handshake hash does not match real xctestrun token"
      end
      handshake_sha256
    rescue KeyError, CFFormatError, NoMethodError
      raise NovaStationPinballMediaContract::ContractError, "invalid source xctestrun"
    end
  end

  class Generator < NovaStationPinballMediaGeneration::GeneratorBase
    def initialize(source_execution_id:, **options)
      super(**options)
      @source_execution_id = Source.validate_id!(source_execution_id)
    end

    def generate!
      prepare_only!
      configuration.locale_batches.each do |batch|
        batch.each do |locale|
          configuration.udids.each_key do |device|
            configuration.assert_owned!
            reencode!(locale, device)
          end
        end
      end
      run_root
    end

    private

    def reencode!(locale, device_id)
      source_root = File.join(
        "/private/tmp/apps-factory/NovaStationPinball", @source_execution_id,
        "app_previews", locale, device_id
      )
      raw = safe_regular_file!(File.join(source_root, "raw.mov"))
      xctestrun = safe_regular_file!(File.join(source_root, "xctestrun", "NovaStationPinball-AppPreviewUITests.xctestrun"))
      log = safe_regular_file!(File.join(source_root, "AppPreviewUITests.log"))
      unless File.read(log, encoding: "UTF-8").include?("** TEST EXECUTE SUCCEEDED **")
        raise NovaStationPinballMediaContract::ContractError, "raw source App Preview handshake test did not pass"
      end

      device = NovaStationPinballMediaContract::DEVICES.find { |candidate| candidate.fetch(:id) == device_id }
      receipt = SourceReceipt.load!(
        manifest_path: File.join(
          app_root, "Builds", "AppStore", "NovaStationPinball", @source_execution_id,
          NovaStationPinballMediaContract::MANIFEST_PATH
        ),
        source_execution_id: @source_execution_id, locale: locale, device_id: device_id,
        raw_path: raw, xctestrun_path: xctestrun,
        expected_udid: configuration.udids.fetch(device_id), runner: runner
      )
      trim_offset = receipt.fetch("capture_trim_offset_seconds")
      raw_end = NovaStationPinballPreviewGeneration::RawTimeline.end_time(raw, runner: runner)
      padding = NovaStationPinballPreviewGeneration::CaptureWindow.residual_padding(
        raw_end: raw_end, trim_offset: trim_offset
      )
      destination = File.join(run_root, "app_previews", locale, "NovaStationPinball-#{device_id}.mov")
      FileUtils.mkdir_p(File.dirname(destination))
      arguments = NovaStationPinballPreviewGeneration::Encoding.arguments(
        source: raw, destination: destination,
        width: device.fetch(:preview_width), height: device.fetch(:preview_height),
        trim_offset: trim_offset, transform: device.fetch(:raw_transform),
        padding_duration: padding
      )
      stdout, stderr, status = runner.capture(*arguments, chdir: app_root)
      unless status.success?
        raise NovaStationPinballMediaContract::ContractError,
              "raw App Preview reencoding failed: #{[stdout, stderr].join("\n").strip}"
      end
      NovaStationPinballPreviewGeneration::EncodedMedia.validate!(destination, runner: runner)
      NovaStationPinballMediaContract::SystemOverlayGuard.new(runner: runner).validate!(
        path: destination,
        report_path: NovaStationPinballMediaContract::SystemOverlayGuard.report_path(
          run_root: run_root, locale: locale, device: device_id
        )
      )

      mark_artifact!(
        locale: locale, device: device_id, kind: :preview, path: destination,
        capture_trim_offset: trim_offset,
        preview_provenance: {
          "source_sha256" => receipt.fetch("source_sha256"),
          "source_run_id" => receipt.fetch("source_run_id"),
          "width" => receipt.fetch("width"), "height" => receipt.fetch("height"),
          "transform" => device.fetch(:raw_transform), "udid" => receipt.fetch("udid"),
          "locale" => receipt.fetch("locale"),
          "handshake_sha256" => receipt.fetch("handshake_sha256")
        }
      )
    end

    def safe_regular_file!(path)
      unless File.file?(path) && !File.symlink?(path)
        raise NovaStationPinballMediaContract::ContractError, "unsafe or missing raw App Preview source"
      end
      path
    end
  end

  module CLI
    module_function

    def run(argv)
      source_execution_id = nil
      index = argv.index("--source-execution-id")
      if index
        source_execution_id = argv.fetch(index + 1)
        argv.slice!(index, 2)
      end
      options = NovaStationPinballMediaGeneration::CLIOptions.parse(argv, program: "reencode_app_previews.rb")
      raise NovaStationPinballMediaContract::ContractError, "--source-execution-id is required" unless source_execution_id

      generator = Generator.new(**options, source_execution_id: source_execution_id)
      generator.generate!
      puts "app_previews: reencoded at #{generator.run_root}"
      0
    rescue NovaStationPinballMediaContract::ContractError, OptionParser::ParseError, IndexError => error
      warn "app_previews: #{error.message}"
      1
    end
  end
end

exit NovaStationPinballPreviewReencoding::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
