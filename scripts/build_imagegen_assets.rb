#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require_relative "verify_imagegen_assets"

module NovaStationImagegenAssets
  class Builder
    def initialize(root)
      @root = File.expand_path(root)
      @manifest_path = absolute("Art/imagegen-provenance.json")
      @magick = File.executable?("/opt/homebrew/bin/magick") ? "/opt/homebrew/bin/magick" : "magick"
      @srgb_profile = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"
    end

    def run
      manifest = load_manifest
      preflight_masters(manifest.fetch("masters"))
      manifest.fetch("derivatives").each { |entry| build_derivative(entry) }
      write_app_icon_catalog
      build_overlay(manifest.fetch("qa_overlays").first)
      refresh_metadata(manifest)
      File.write(@manifest_path, JSON.pretty_generate(manifest) + "\n")
      puts "Built #{manifest.fetch('derivatives').length} deterministic PNG derivatives and mechanical overlay"
      true
    rescue StandardError => exception
      warn "ERROR: #{exception.message}"
      false
    end

    private

    def load_manifest
      raise "missing provenance manifest: Art/imagegen-provenance.json" unless File.file?(@manifest_path)
      JSON.parse(File.read(@manifest_path, encoding: "UTF-8"))
    rescue JSON::ParserError => exception
      raise "invalid provenance manifest JSON: #{exception.message}"
    end

    def preflight_masters(entries)
      raise "missing masters inventory" unless entries.is_a?(Array)
      entries.each do |entry|
        path = absolute(entry.fetch("path"))
        raise "missing source master: #{entry.fetch('path')}" unless File.file?(path)
        raise "source master is not PNG: #{entry.fetch('path')}" unless File.extname(path).downcase == ".png"

        actual = NovaStationImagegenContract::PNGInspector.read(path)
        expected_sha = entry.fetch("sha256")
        actual_sha = Digest::SHA256.file(path).hexdigest
        raise "source master SHA mismatch: #{entry.fetch('path')}" unless expected_sha == actual_sha
        %w[width height alpha profile].each do |field|
          raise "source master #{field} mismatch: #{entry.fetch('path')}" unless entry.fetch(field) == actual.fetch(field)
        end
      end
    end

    def build_derivative(entry)
      source = absolute(entry.fetch("source_master"))
      raise "missing source master: #{entry.fetch('source_master')}" unless File.file?(source)
      output = absolute(entry.fetch("path"))
      FileUtils.mkdir_p(File.dirname(output))

      arguments = [@magick, source]
      entry.fetch("operations").each { |operation| append_operation(arguments, operation) }
      raise "missing system sRGB profile: #{@srgb_profile}" unless File.file?(@srgb_profile)
      arguments.concat(["-profile", @srgb_profile, "+set", "date:create", "+set", "date:modify"])
      arguments.concat(["-alpha", "off"]) if entry.fetch("role") == "app_icon"
      arguments << output
      execute(arguments, "derivative #{entry.fetch('role')}")
      embed_srgb_profile(output, "derivative #{entry.fetch('role')}")
    end

    def append_operation(arguments, operation)
      case operation.fetch("name")
      when "crop"
        arguments.concat(["-crop", operation.fetch("geometry"), "+repage"])
      when "resize"
        geometry = "#{Integer(operation.fetch('width'))}x#{Integer(operation.fetch('height'))}!"
        arguments.concat(["-resize", geometry])
      when "chroma_key"
        unless operation.fetch("algorithm") == "distance_decontaminate" && operation.fetch("color").upcase == "#00FF00"
          raise "unsupported chroma_key recipe"
        end
        threshold = Float(operation.fetch("edge_threshold"))
        raise "invalid chroma edge_threshold" unless threshold.positive? && threshold < 0.5
        scale = 1.0 - threshold
        alpha = "min(1,max(0,(1-(g-max(r,b))-#{threshold})/#{scale}))"
        arguments.concat(["-alpha", "on", "-channel", "A", "-fx", alpha, "+channel"])
        arguments.concat(["-channel", "R", "-fx", "a>0.001?min(1,max(0,r/a)):0", "+channel"])
        arguments.concat(["-channel", "G", "-fx", "a>0.001?min(1,max(0,(g-(1-a))/a)):0", "+channel"])
        arguments.concat(["-channel", "B", "-fx", "a>0.001?min(1,max(0,b/a)):0", "+channel"])
      when "defringe"
        radius = Integer(operation.fetch("erode_radius"))
        sigma = Float(operation.fetch("feather_sigma"))
        cutoff = Float(operation.fetch("color_cleanup_alpha"))
        raise "invalid defringe erode_radius" unless radius == 1
        raise "invalid defringe feather_sigma" unless sigma.positive? && sigma <= 1
        raise "invalid defringe color_cleanup_alpha" unless cutoff.positive? && cutoff < 1

        arguments.concat(["-channel", "A", "-morphology", "Erode", "Diamond:#{radius}", "-blur", "0x#{sigma}", "+channel"])
        arguments.concat([
          "-channel", "RB", "-fx",
          "a<#{cutoff}?g:u",
          "+channel"
        ])
      when "mask"
        mask = absolute(operation.fetch("path"))
        raise "missing derivative mask: #{operation.fetch('path')}" unless File.file?(mask)
        arguments.concat([mask, "-alpha", "off", "-compose", "CopyOpacity", "-composite"])
      when "normalize_srgb"
        arguments.concat(["-colorspace", "sRGB"])
      when "strip_metadata"
        arguments << "-strip"
      else
        raise "unsupported derivative operation: #{operation['name']}"
      end
    end

    def build_overlay(entry)
      raise "missing mechanical overlay recipe" unless entry.is_a?(Hash)
      source_art = absolute(entry.fetch("source_art"))
      source_reference = absolute(entry.fetch("source_reference"))
      output = absolute(entry.fetch("path"))
      operation = entry.fetch("operations").fetch(0)
      raise "unsupported overlay operation" unless operation.fetch("name") == "blend"
      FileUtils.mkdir_p(File.dirname(output))
      blend = "#{Integer(operation.fetch('art_percent'))},#{Integer(operation.fetch('guide_percent'))}"
      execute(
        [@magick, source_art, source_reference, "-define", "compose:args=#{blend}", "-compose", "blend", "-composite",
         "-strip", "-colorspace", "sRGB", "-profile", @srgb_profile,
         "+set", "date:create", "+set", "date:modify", output],
        "mechanical overlay"
      )
      embed_srgb_profile(output, "mechanical overlay")
    end

    def refresh_metadata(manifest)
      manifest.fetch("derivatives").each { |entry| refresh_png_entry(entry) }
      manifest.fetch("qa_overlays").each { |entry| refresh_png_entry(entry) }
    end

    def refresh_png_entry(entry)
      path = absolute(entry.fetch("path"))
      metadata = NovaStationImagegenContract::PNGInspector.read(path)
      entry["sha256"] = Digest::SHA256.file(path).hexdigest
      %w[width height alpha profile].each { |field| entry[field] = metadata.fetch(field) }
    end

    def write_app_icon_catalog
      path = absolute("NovaStationPinball/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")
      FileUtils.mkdir_p(File.dirname(path))
      contents = {
        "images" => [
          { "filename" => "AppIcon-1024.png", "idiom" => "universal", "platform" => "ios", "size" => "1024x1024" }
        ],
        "info" => { "author" => "xcode", "version" => 1 }
      }
      File.write(path, JSON.pretty_generate(contents) + "\n")
    end

    def execute(arguments, label)
      stdout, stderr, status = Open3.capture3(*arguments)
      return if status.success?
      raise "failed to build #{label}: #{stdout}\n#{stderr}".strip
    end

    def embed_srgb_profile(path, label)
      execute(["sips", "-m", @srgb_profile, path], "sRGB normalization for #{label}")
    end

    def absolute(relative_path)
      candidate = File.expand_path(relative_path, @root)
      raise "path escapes repository: #{relative_path}" unless candidate.start_with?(@root + File::SEPARATOR)
      candidate
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = { root: File.expand_path("..", __dir__) }
  OptionParser.new do |parser|
    parser.on("--root PATH", "Repository root") { |path| options[:root] = path }
  end.parse!
  exit(NovaStationImagegenAssets::Builder.new(options.fetch(:root)).run ? 0 : 1)
end
