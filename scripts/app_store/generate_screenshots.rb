#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require_relative "media_generation"

module NovaStationPinballScreenshotGeneration
  class PreviewFrameExtraction
    def self.arguments(source:, destination:, width:, height:, scenario_index:)
      scenario = NovaStationPinballMediaContract::SCENARIOS.fetch(scenario_index)
      source_offset = NovaStationPinballMediaContract.screenshot_source_offset(scenario)
      [
        "/opt/homebrew/bin/ffmpeg", "-y", "-ss", format("%.3f", source_offset),
        "-i", source, "-frames:v", "1", "-vf", "scale=#{width}:#{height}:flags=lanczos",
        "-map_metadata", "-1", "-update", "1", destination
      ]
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
        extract_preview_frames!(locale, device)
      end
    end

    def extract_preview_frames!(locale, device)
      preview = File.join(run_root, "app_previews", locale, "NovaStationPinball-#{device}.mov")
      unless File.file?(preview) && !File.symlink?(preview)
        raise NovaStationPinballMediaContract::ContractError,
              "screenshots require the current run App Preview first: #{locale}/#{device}"
      end
      definition = NovaStationPinballMediaContract::DEVICES.find { |candidate| candidate.fetch(:id) == device }
      NovaStationPinballMediaContract::SCENARIOS.each_with_index do |scenario, index|
        relative = format("screenshots/%s/%02d-%s-%s.png", locale, index + 1, scenario, device)
        destination = File.join(run_root, relative)
        FileUtils.mkdir_p(File.dirname(destination))
        arguments = PreviewFrameExtraction.arguments(
          source: preview, destination: destination,
          width: definition.fetch(:width), height: definition.fetch(:height), scenario_index: index
        )
        stdout, stderr, status = runner.capture(*arguments, chdir: app_root)
        unless status.success? && File.file?(destination)
          raise NovaStationPinballMediaContract::ContractError,
                "could not extract stable preview frame #{locale}/#{device}/#{scenario}: #{[stdout, stderr].join("\n").strip}"
        end
        NovaStationPinballMediaContract::PNGMetadata.strip_orientation!(destination)
        mark_artifact!(
          locale: locale, device: device, kind: :screenshot, path: destination,
          screenshot_source_offset: NovaStationPinballMediaContract.screenshot_source_offset(scenario)
        )
      end
    end
  end

  module CLI
    module_function

    def run(argv)
      options = NovaStationPinballMediaGeneration::CLIOptions.parse(argv, program: "generate_screenshots.rb")
      generator = Generator.new(**options)
      options[:prepare_only] ? generator.prepare_only! : generator.generate!
      puts "screenshots: #{options[:prepare_only] ? 'prepared pending manifest' : 'captured'} at #{generator.run_root}"
      0
    rescue NovaStationPinballMediaContract::ContractError, OptionParser::ParseError => error
      warn "screenshots: #{error.message}"
      1
    end

  end
end

exit NovaStationPinballScreenshotGeneration::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
