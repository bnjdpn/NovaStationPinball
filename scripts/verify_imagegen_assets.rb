#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "pathname"
require "time"
require "zlib"

module NovaStationImagegenContract
  MASTER_FILES = {
    "Art/ImageGen/table-master.png" => %w[table_composition_4x3],
    "Art/ImageGen/table-background-master.png" => %w[table_runtime_background_4x3],
    "Art/ImageGen/components-checker-master.png" => %w[component_atlas_intermediate],
    "Art/ImageGen/components-master.png" => %w[
      crt_console station_panels flippers bumpers targets ramps portals lamps
      plunger ball menu_surfaces hud_surfaces
    ],
    "Art/ImageGen/app-icon-master.png" => %w[app_icon],
    "Art/ImageGen/key-art-master.png" => %w[key_art],
    "Art/ImageGen/store-creatives-master.png" => %w[store_creatives]
  }.freeze

  MASTER_ROLES = MASTER_FILES.values.flatten.freeze
  REFERENCE_PATH = "NovaStationPinball/Resources/Art/greybox-table-guide.png"
  MASTER_REFERENCES = {
    "Art/ImageGen/table-master.png" => [REFERENCE_PATH],
    "Art/ImageGen/table-background-master.png" => ["Art/ImageGen/table-master.png"],
    "Art/ImageGen/components-checker-master.png" => ["Art/ImageGen/table-master.png"],
    "Art/ImageGen/components-master.png" => ["Art/ImageGen/components-checker-master.png"],
    "Art/ImageGen/app-icon-master.png" => ["Art/ImageGen/table-master.png"],
    "Art/ImageGen/key-art-master.png" => ["Art/ImageGen/table-master.png"],
    "Art/ImageGen/store-creatives-master.png" => ["Art/ImageGen/table-master.png", "Art/ImageGen/key-art-master.png"]
  }.freeze

  DERIVATIVE_ROLES = {
    "app_icon" => "NovaStationPinball/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    "table_composition_4x3" => "NovaStationPinball/Resources/Art/table-composition.png",
    "crt_console" => "NovaStationPinball/Resources/Art/crt-console.png",
    "station_panels" => "NovaStationPinball/Resources/Art/station-panels.png",
    "flipper_left" => "NovaStationPinball/Resources/Art/flipper-left.png",
    "flipper_right" => "NovaStationPinball/Resources/Art/flipper-right.png",
    "bumper" => "NovaStationPinball/Resources/Art/bumper.png",
    "target" => "NovaStationPinball/Resources/Art/target.png",
    "ramp" => "NovaStationPinball/Resources/Art/ramp.png",
    "portal" => "NovaStationPinball/Resources/Art/portal.png",
    "lamp" => "NovaStationPinball/Resources/Art/lamp.png",
    "plunger" => "NovaStationPinball/Resources/Art/plunger.png",
    "ball" => "NovaStationPinball/Resources/Art/ball.png",
    "menu_background" => "NovaStationPinball/Resources/Art/menu-background.png",
    "hud_overlay" => "NovaStationPinball/Resources/Art/hud-overlay.png",
    "key_art" => "NovaStationPinball/Resources/Art/key-art.png",
    "store_creative" => "NovaStationPinball/Resources/Art/store-creative.png"
  }.freeze

  DERIVATIVE_SOURCES = {
    "app_icon" => "Art/ImageGen/app-icon-master.png",
    "table_composition_4x3" => "Art/ImageGen/table-background-master.png",
    "menu_background" => "Art/ImageGen/key-art-master.png",
    "key_art" => "Art/ImageGen/key-art-master.png",
    "store_creative" => "Art/ImageGen/store-creatives-master.png"
  }.freeze

  ALLOWED_OPERATIONS = %w[crop resize chroma_key defringe mask normalize_srgb strip_metadata].freeze
  CHROMA_OPERATION = {
    "name" => "chroma_key", "color" => "#00FF00",
    "algorithm" => "distance_decontaminate", "edge_threshold" => 0.2
  }.freeze
  DEFRINGE_OPERATION = {
    "name" => "defringe", "erode_radius" => 1,
    "feather_sigma" => 0.45, "color_cleanup_alpha" => 0.76
  }.freeze
  COMPONENT_RECIPE = lambda do |geometry, width, height|
    [
      { "name" => "crop", "geometry" => geometry }, CHROMA_OPERATION.dup,
      { "name" => "resize", "width" => width, "height" => height }, DEFRINGE_OPERATION.dup,
      { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }
    ]
  end
  DERIVATIVE_RECIPES = {
    "app_icon" => { "source_master" => "Art/ImageGen/app-icon-master.png", "operations" => [{ "name" => "crop", "geometry" => "1254x1254+0+0" }, { "name" => "resize", "width" => 1024, "height" => 1024 }, { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }] },
    "table_composition_4x3" => { "source_master" => "Art/ImageGen/table-background-master.png", "operations" => [{ "name" => "crop", "geometry" => "1448x1086+0+0" }, { "name" => "resize", "width" => 2048, "height" => 1536 }, { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }] },
    "crt_console" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("230x215+575+500", 460, 430) },
    "station_panels" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("366x232+43+724", 732, 464) },
    "flipper_left" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("272x156+34+77", 272, 156) },
    "flipper_right" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("272x156+407+77", 272, 156) },
    "bumper" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("179x189+743+48", 192, 192) },
    "target" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("130x228+52+252", 104, 182) },
    "ramp" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("220x370+1295+310", 210, 353) },
    "portal" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("210x210+860+325", 226, 226) },
    "lamp" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("80x80+59+514", 80, 80) },
    "plunger" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("275x87+999+252", 330, 104) },
    "ball" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("114x116+728+370", 96, 96) },
    "menu_background" => { "source_master" => "Art/ImageGen/key-art-master.png", "operations" => [{ "name" => "crop", "geometry" => "1536x1024+0+0" }, { "name" => "resize", "width" => 1536, "height" => 1024 }, { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }] },
    "hud_overlay" => { "source_master" => "Art/ImageGen/components-master.png", "operations" => COMPONENT_RECIPE.call("206x304+1031+672", 412, 608) },
    "key_art" => { "source_master" => "Art/ImageGen/key-art-master.png", "operations" => [{ "name" => "crop", "geometry" => "1536x1024+0+0" }, { "name" => "resize", "width" => 1536, "height" => 1024 }, { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }] },
    "store_creative" => { "source_master" => "Art/ImageGen/store-creatives-master.png", "operations" => [{ "name" => "crop", "geometry" => "1774x887+0+0" }, { "name" => "resize", "width" => 1774, "height" => 887 }, { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }] }
  }.freeze

  class PNGInspector
    SIGNATURE = "\x89PNG\r\n\x1a\n".b
    KNOWN_SRGB_ICC_SHA256 = %w[
      2b3aa1645779a9e634744faf9b01e9102b0c9b88fd6deced7934df86b949af7e
    ].freeze

    def self.read(path)
      data = File.binread(path)
      raise "not a PNG" unless data.start_with?(SIGNATURE)

      offset = SIGNATURE.bytesize
      chunks = []
      iccp_payload = nil
      ihdr = nil
      while offset + 12 <= data.bytesize
        length = data.byteslice(offset, 4).unpack1("N")
        type = data.byteslice(offset + 4, 4)
        payload = data.byteslice(offset + 8, length)
        raise "truncated PNG chunk" unless payload && payload.bytesize == length

        chunks << type
        ihdr = payload.unpack("NNC5") if type == "IHDR"
        iccp_payload = payload if type == "iCCP"
        offset += length + 12
        break if type == "IEND"
      end
      raise "missing PNG IHDR" unless ihdr

      {
        "width" => ihdr[0],
        "height" => ihdr[1],
        "alpha" => [4, 6].include?(ihdr[3]),
        "profile" => if iccp_payload && chunks.include?("sRGB")
                       "ambiguous-rgb-profile"
                     elsif iccp_payload
                       srgb_icc_profile?(iccp_payload) ? "sRGB" : "non-sRGB-icc"
                     elsif chunks.include?("sRGB")
                       "sRGB"
                     elsif chunks.include?("gAMA") && chunks.include?("cHRM")
                       "sRGB-chromaticity"
                     else
                       "untagged-rgb"
                     end
      }
    end

    def self.srgb_icc_profile?(payload)
      _profile_name, encoded = payload.split("\0", 2)
      return false unless encoded&.getbyte(0) == 0
      profile = Zlib::Inflate.inflate(encoded.byteslice(1..))
      profile.bytesize >= 128 && profile.byteslice(36, 4) == "acsp" &&
        profile.byteslice(16, 4) == "RGB " && KNOWN_SRGB_ICC_SHA256.include?(Digest::SHA256.hexdigest(profile))
    rescue Zlib::Error
      false
    end
  end

  class Verifier
    def initialize(root)
      @root = File.expand_path(root)
      @errors = []
    end

    def run
      reject_vectors
      manifest = load_manifest
      return finish unless manifest

      validate_manifest_header(manifest)
      validate_reference(manifest["reference_guide"])
      validate_masters(manifest["masters"])
      validate_manifest_time_order(manifest)
      validate_derivatives(manifest["derivatives"], manifest["masters"])
      validate_qa_overlay(manifest["qa_overlays"])
      validate_app_icon_catalog
      finish
    end

    private

    def reject_vectors
      %w[Art NovaStationPinball/Resources].each do |relative_root|
        directory = absolute(relative_root)
        next unless Dir.exist?(directory)

        Dir.glob(File.join(directory, "**", "*"), File::FNM_CASEFOLD).sort.each do |path|
          next unless File.file?(path)
          next unless %w[.svg .svgz .pdf].include?(File.extname(path).downcase)

          error("forbidden vector asset: #{relative(path)}")
        end
      end
    end

    def load_manifest
      path = absolute("Art/imagegen-provenance.json")
      unless File.file?(path)
        error("missing provenance manifest: Art/imagegen-provenance.json")
        return nil
      end
      JSON.parse(File.read(path, encoding: "UTF-8"))
    rescue JSON::ParserError => exception
      error("invalid provenance manifest JSON: #{exception.message}")
      nil
    end

    def validate_manifest_header(manifest)
      error("invalid schema_version") unless manifest["schema_version"] == 1
      error("invalid generated_at") unless iso8601?(manifest["generated_at"])
    end

    def validate_manifest_time_order(manifest)
      return unless iso8601?(manifest["generated_at"])
      times = Array(manifest["masters"]).each_with_object([]) do |entry, result|
        next unless entry.is_a?(Hash)
        [entry["generated_at"], entry.dig("visual_review", "inspected_at")].each do |value|
          result << Time.iso8601(value) if iso8601?(value)
        end
      end
      if times.any? && Time.iso8601(manifest.fetch("generated_at")) < times.max
        error("generated_at precedes master or review")
      end
    end

    def validate_reference(entry)
      unless entry.is_a?(Hash)
        error("missing reference_guide metadata")
        return
      end
      error("invalid reference guide path") unless entry["path"] == REFERENCE_PATH
      validate_repo_path(entry["path"], "reference guide path")
      validate_png_entry(entry, "reference guide", require_embedded_profile: true)
      width = entry["width"].to_i
      height = entry["height"].to_i
      error("reference guide must be 4:3") unless width.positive? && height.positive? && width * 3 == height * 4
      error("invalid reference guide role") unless entry["role"] == "mechanical_reference_4x3"
    end

    def validate_masters(entries)
      unless entries.is_a?(Array)
        error("missing masters inventory")
        return
      end

      MASTER_FILES.each do |expected_path, expected_roles|
        matches = entries.select { |entry| entry.is_a?(Hash) && entry["path"] == expected_path }
        if matches.empty?
          error("missing required master #{expected_path}")
          next
        end
        error("duplicate master #{expected_path}") if matches.length > 1
        entry = matches.first
        error("invalid roles for master #{expected_path}") unless entry["roles"] == expected_roles
      end

      known_paths = entries.each_with_object([]) { |entry, paths| paths << entry["path"] if entry.is_a?(Hash) }
      entries.each do |entry|
        next unless entry.is_a?(Hash)
        validate_repo_path(entry["path"], "master path")
        roles = entry["roles"]
        unless roles.is_a?(Array) && !roles.empty? && roles.all? { |role| MASTER_ROLES.include?(role) }
          error("invalid roles for master #{entry['path']}")
          roles = []
        end
        error("invalid prompt for master #{entry['path']}") unless entry["prompt"].is_a?(String) && !entry["prompt"].strip.empty?
        error("invalid generated_at for master #{entry['path']}") unless iso8601?(entry["generated_at"])
        validate_imagegen_source(entry, known_paths)
        error("invalid references for master #{entry['path']}") unless entry["references"] == MASTER_REFERENCES[entry["path"]]
        validate_visual_review(entry)
        validate_png_entry(entry, "master #{roles.join(',')}", require_embedded_profile: false)
      end
    end

    def validate_imagegen_source(entry, known_paths)
      source = entry["source"]
      unless source.is_a?(Hash) && source["provider"] == "openai-imagegen" &&
             %w[generation edit].include?(source["mode"]) && source["artifact"].is_a?(String) && !source["artifact"].empty?
        error("invalid source for master #{entry['path']}")
        return
      end

      if source["mode"] == "edit"
        parent = source["parent_master"]
        validate_repo_path(parent, "parent_master")
        if !known_paths.include?(parent) || parent == entry["path"]
          error("invalid parent_master for master #{entry['path']}")
        end
      elsif source.key?("parent_master")
        error("invalid parent_master for generated master #{entry['path']}")
      end
      Array(entry["references"]).each { |path| validate_repo_path(path, "master reference") }
    end

    def validate_visual_review(entry)
      review = entry["visual_review"]
      expected_status = entry["path"] == "Art/ImageGen/components-checker-master.png" ? "provenance_only" : "accepted"
      unless review.is_a?(Hash) && review["status"] == expected_status && iso8601?(review["inspected_at"]) &&
             review["notes"].is_a?(String) && !review["notes"].strip.empty?
        error("invalid visual_review for master #{entry['path']}")
      end
      if iso8601?(entry["generated_at"]) && review.is_a?(Hash) && iso8601?(review["inspected_at"]) &&
         Time.iso8601(review["inspected_at"]) < Time.iso8601(entry["generated_at"])
        error("visual_review precedes master #{entry['path']}")
      end
    end

    def validate_derivatives(entries, masters)
      unless entries.is_a?(Array)
        error("missing derivatives inventory")
        return
      end
      master_paths = Array(masters).each_with_object([]) do |entry, paths|
        paths << entry["path"] if entry.is_a?(Hash)
      end

      DERIVATIVE_ROLES.each do |role, expected_path|
        matches = entries.select { |entry| entry.is_a?(Hash) && entry["role"] == role }
        if matches.empty?
          error("missing required derivative role #{role}")
          next
        end
        error("duplicate derivative role #{role}") if matches.length > 1
        error("invalid path for derivative role #{role}") unless matches.first["path"] == expected_path
      end

      entries.each do |entry|
        next unless entry.is_a?(Hash)
        role = entry["role"].to_s
        validate_repo_path(entry["path"], "derivative output")
        validate_repo_path(entry["source_master"], "derivative source_master")
        error("invalid role for derivative #{entry['path']}") unless DERIVATIVE_ROLES.key?(role)
        unless master_paths.include?(entry["source_master"])
          error("invalid source_master for derivative #{entry['path']}")
        end
        expected = DERIVATIVE_RECIPES[role]
        expected_source = expected && expected["source_master"]
        unless entry["source_master"] == expected_source
          error("invalid source_master for derivative #{role}")
        end
        operations = entry["operations"]
        if !operations.is_a?(Array) || operations.empty?
          error("missing operations for derivative #{entry['path']}")
        else
          operations.each do |operation|
            name = operation["name"] if operation.is_a?(Hash)
            error("invalid operation for derivative #{entry['path']}") unless ALLOWED_OPERATIONS.include?(name)
            validate_repo_path(operation["path"], "operation mask") if name == "mask"
          end
        end
        error("invalid exact recipe for derivative #{role}") unless expected && operations == expected["operations"]
        validate_png_entry(entry, "derivative #{role}", require_embedded_profile: true)
      end
    end

    def validate_qa_overlay(entries)
      entry = Array(entries).find { |candidate| candidate.is_a?(Hash) && candidate["role"] == "mechanical_overlay" }
      unless entry
        error("missing mechanical overlay metadata")
        return
      end
      error("invalid mechanical overlay path") unless entry["path"] == "Art/QA/table-guide-overlay.png"
      validate_repo_path(entry["path"], "mechanical overlay output")
      validate_repo_path(entry["source_art"], "mechanical overlay source_art")
      validate_repo_path(entry["source_reference"], "mechanical overlay source_reference")
      unless entry["source_art"] == DERIVATIVE_ROLES.fetch("table_composition_4x3") && entry["source_reference"] == REFERENCE_PATH
        error("invalid mechanical overlay sources")
      end
      operations = entry["operations"]
      unless operations.is_a?(Array) && operations == [{ "name" => "blend", "art_percent" => 65, "guide_percent" => 35 }]
        error("invalid mechanical overlay operations")
      end
      validate_png_entry(entry, "mechanical overlay", require_embedded_profile: true)
    end

    def validate_png_entry(entry, label, require_embedded_profile:)
      path = safe_absolute(entry["path"])
      unless path && File.file?(path)
        error("missing #{label} PNG: #{entry['path']}")
        return
      end
      unless File.extname(path).downcase == ".png"
        error("invalid PNG path for #{label}: #{entry['path']}")
        return
      end

      actual = PNGInspector.read(path)
      error("sha256 mismatch for #{entry['path']}") unless entry["sha256"] == Digest::SHA256.file(path).hexdigest
      %w[width height alpha profile].each do |field|
        error("#{field} mismatch for #{entry['path']}") unless entry[field] == actual[field]
      end
      if require_embedded_profile && actual["profile"] == "untagged-rgb"
        error("missing embedded RGB profile for #{entry['path']}")
      end
      if actual["profile"] == "non-sRGB-icc"
        error("non-sRGB ICC profile for #{entry['path']}")
      elsif actual["profile"] == "ambiguous-rgb-profile"
        error("ambiguous mixed RGB profile for #{entry['path']}")
      end
    rescue StandardError => exception
      error("invalid PNG #{entry['path']}: #{exception.message}")
    end

    def validate_app_icon_catalog
      path = absolute("NovaStationPinball/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")
      unless File.file?(path)
        error("missing AppIcon Contents.json")
        return
      end
      catalog = JSON.parse(File.read(path, encoding: "UTF-8"))
      filenames = Array(catalog["images"]).map { |image| image["filename"] }
      error("AppIcon catalog does not reference AppIcon-1024.png") unless filenames.include?("AppIcon-1024.png")
    rescue JSON::ParserError => exception
      error("invalid AppIcon Contents.json: #{exception.message}")
    end

    def iso8601?(value)
      return false unless value.is_a?(String)
      Time.iso8601(value)
      true
    rescue ArgumentError
      false
    end

    def safe_absolute(relative_path)
      return unless relative_path.is_a?(String) && !relative_path.empty?
      candidate = absolute(relative_path)
      return unless candidate == @root || candidate.start_with?(@root + File::SEPARATOR)
      candidate
    end

    def validate_repo_path(relative_path, label)
      return if safe_absolute(relative_path)
      error("path escapes repository: #{label}")
    end

    def absolute(relative_path)
      File.expand_path(relative_path, @root)
    end

    def relative(path)
      Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
    end

    def error(message)
      @errors << message
    end

    def finish
      if @errors.empty?
        puts "ImageGen asset contract verified: #{MASTER_FILES.length} masters, #{DERIVATIVE_ROLES.length} derivatives"
        true
      else
        warn @errors.map { |message| "ERROR: #{message}" }.join("\n")
        false
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = { root: File.expand_path("..", __dir__) }
  OptionParser.new do |parser|
    parser.on("--root PATH", "Repository root") { |path| options[:root] = path }
  end.parse!
  exit(NovaStationImagegenContract::Verifier.new(options.fetch(:root)).run ? 0 : 1)
end
