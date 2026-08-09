#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tempfile"
require "tmpdir"
require "zlib"
require_relative "verify_imagegen_assets"

class VerifyImagegenAssetsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  VERIFIER = File.join(ROOT, "scripts", "verify_imagegen_assets.rb")
  BUILDER = File.join(ROOT, "scripts", "build_imagegen_assets.rb")

  MASTER_ROLES = {
    "table-master.png" => %w[table_composition_4x3],
    "table-background-master.png" => %w[table_runtime_background_4x3],
    "components-checker-master.png" => %w[component_atlas_intermediate],
    "components-master.png" => %w[
      crt_console station_panels flippers bumpers targets ramps portals lamps
      plunger ball menu_surfaces hud_surfaces
    ],
    "app-icon-master.png" => %w[app_icon],
    "key-art-master.png" => %w[key_art],
    "store-creatives-master.png" => %w[store_creatives]
  }.freeze

  DERIVATIVE_ROLES = {
    "NovaStationPinball/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" => "app_icon",
    "NovaStationPinball/Resources/Art/table-composition.png" => "table_composition_4x3",
    "NovaStationPinball/Resources/Art/crt-console.png" => "crt_console",
    "NovaStationPinball/Resources/Art/station-panels.png" => "station_panels",
    "NovaStationPinball/Resources/Art/flipper-left.png" => "flipper_left",
    "NovaStationPinball/Resources/Art/flipper-right.png" => "flipper_right",
    "NovaStationPinball/Resources/Art/bumper.png" => "bumper",
    "NovaStationPinball/Resources/Art/target.png" => "target",
    "NovaStationPinball/Resources/Art/ramp.png" => "ramp",
    "NovaStationPinball/Resources/Art/portal.png" => "portal",
    "NovaStationPinball/Resources/Art/lamp.png" => "lamp",
    "NovaStationPinball/Resources/Art/plunger.png" => "plunger",
    "NovaStationPinball/Resources/Art/ball.png" => "ball",
    "NovaStationPinball/Resources/Art/menu-background.png" => "menu_background",
    "NovaStationPinball/Resources/Art/hud-overlay.png" => "hud_overlay",
    "NovaStationPinball/Resources/Art/key-art.png" => "key_art",
    "NovaStationPinball/Resources/Art/store-creative.png" => "store_creative"
  }.freeze

  DERIVATIVE_SOURCES = {
    "app_icon" => "Art/ImageGen/app-icon-master.png",
    "table_composition_4x3" => "Art/ImageGen/table-background-master.png",
    "menu_background" => "Art/ImageGen/key-art-master.png",
    "key_art" => "Art/ImageGen/key-art-master.png",
    "store_creative" => "Art/ImageGen/store-creatives-master.png"
  }.freeze

  chroma = {
    "name" => "chroma_key", "color" => "#00FF00",
    "algorithm" => "distance_decontaminate", "edge_threshold" => 0.2
  }.freeze
  defringe = {
    "name" => "defringe", "erode_radius" => 1,
    "feather_sigma" => 0.45, "color_cleanup_alpha" => 0.76
  }.freeze
  component_recipe = lambda do |geometry, width, height|
    [
      { "name" => "crop", "geometry" => geometry }, chroma.dup,
      { "name" => "resize", "width" => width, "height" => height }, defringe.dup,
      { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }
    ]
  end
  EXPECTED_RECIPES = {
    "app_icon" => [{ "name" => "crop", "geometry" => "1254x1254+0+0" }, { "name" => "resize", "width" => 1024, "height" => 1024 }, { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }],
    "table_composition_4x3" => [{ "name" => "crop", "geometry" => "1448x1086+0+0" }, { "name" => "resize", "width" => 2048, "height" => 1536 }, { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }],
    "crt_console" => component_recipe.call("230x215+575+500", 460, 430),
    "station_panels" => component_recipe.call("366x232+43+724", 732, 464),
    "flipper_left" => component_recipe.call("272x156+34+77", 272, 156),
    "flipper_right" => component_recipe.call("272x156+407+77", 272, 156),
    "bumper" => component_recipe.call("179x189+743+48", 192, 192),
    "target" => component_recipe.call("130x228+52+252", 104, 182),
    "ramp" => component_recipe.call("220x370+1295+310", 210, 353),
    "portal" => component_recipe.call("210x210+860+325", 226, 226),
    "lamp" => component_recipe.call("80x80+59+514", 80, 80),
    "plunger" => component_recipe.call("275x87+999+252", 330, 104),
    "ball" => component_recipe.call("114x116+728+370", 96, 96),
    "menu_background" => [{ "name" => "crop", "geometry" => "1536x1024+0+0" }, { "name" => "resize", "width" => 1536, "height" => 1024 }, { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }],
    "hud_overlay" => component_recipe.call("206x304+1031+672", 412, 608),
    "key_art" => [{ "name" => "crop", "geometry" => "1536x1024+0+0" }, { "name" => "resize", "width" => 1536, "height" => 1024 }, { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }],
    "store_creative" => [{ "name" => "crop", "geometry" => "1774x887+0+0" }, { "name" => "resize", "width" => 1774, "height" => 887 }, { "name" => "normalize_srgb" }, { "name" => "strip_metadata" }]
  }.freeze

  def test_accepts_complete_png_only_provenance_contract
    in_fixture do |root, _manifest|
      stdout, stderr, status = verify(root)

      assert status.success?, "expected success:\n#{stdout}\n#{stderr}"
      assert_includes stdout, "ImageGen asset contract verified"
    end
  end

  def test_rejects_a_missing_required_master
    in_fixture do |root, _manifest|
      FileUtils.rm(File.join(root, "Art/ImageGen/table-master.png"))

      stdout, stderr, status = verify(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "missing master table_composition_4x3 PNG"
    end
  end

  def test_rejects_missing_provenance_manifest
    Dir.mktmpdir("nova-imagegen-contract") do |root|
      stdout, stderr, status = verify(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "missing provenance manifest"
    end
  end

  def test_rejects_sha_dimension_alpha_and_profile_mismatches
    {
      "sha256" => "0" * 64,
      "width" => 999,
      "alpha" => false,
      "profile" => "Display P3"
    }.each do |field, bad_value|
      in_fixture do |root, manifest|
        manifest.fetch("masters").first[field] = bad_value
        write_manifest(root, manifest)

        stdout, stderr, status = verify(root)

        refute status.success?, "expected #{field} mismatch to fail"
        assert_includes "#{stdout}\n#{stderr}", "#{field} mismatch"
      end
    end
  end

  def test_rejects_missing_prompt_date_role_and_imagegen_source
    {
      "prompt" => "",
      "generated_at" => "not-a-date",
      "roles" => ["wrong-role"],
      "source" => { "provider" => "hand-drawn", "mode" => "generation" }
    }.each do |field, bad_value|
      in_fixture do |root, manifest|
        manifest.fetch("masters").first[field] = bad_value
        write_manifest(root, manifest)

        stdout, stderr, status = verify(root)

        refute status.success?, "expected invalid #{field} to fail"
        assert_includes "#{stdout}\n#{stderr}", "invalid #{field}"
      end
    end
  end

  def test_rejects_derivative_without_reproducible_source_and_operations
    in_fixture do |root, manifest|
      derivative = manifest.fetch("derivatives").first
      derivative.delete("source_master")
      derivative["operations"] = []
      write_manifest(root, manifest)

      stdout, stderr, status = verify(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "invalid source_master"
      assert_includes "#{stdout}\n#{stderr}", "missing operations"
    end
  end

  def test_repository_manifest_uses_distinct_semantic_portal_and_complete_ramp_crops
    manifest = JSON.parse(File.read(File.join(ROOT, "Art/imagegen-provenance.json"), encoding: "UTF-8"))
    entries = manifest.fetch("derivatives").to_h { |entry| [entry.fetch("role"), entry] }
    crop = ->(role) { entries.fetch(role).fetch("operations").find { |operation| operation.fetch("name") == "crop" }.fetch("geometry") }

    assert_equal "210x210+860+325", crop.call("portal")
    refute_equal crop.call("crt_console"), crop.call("portal"), "portal must not duplicate the CRT crop"
    assert_equal "220x370+1295+310", crop.call("ramp")
  end

  def test_rejects_any_derivative_recipe_change
    in_fixture do |root, manifest|
      portal = manifest.fetch("derivatives").find { |entry| entry.fetch("role") == "portal" }
      portal.fetch("operations").first["geometry"] = "226x215+578+499"
      write_manifest(root, manifest)

      stdout, stderr, status = verify(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "invalid exact recipe for derivative portal"
    end
  end

  def test_accepts_only_the_bounded_dynamic_sprite_defringe_recipe
    in_fixture do |root, manifest|
      derivative = manifest.fetch("derivatives").find { |entry| entry.fetch("role") == "flipper_left" }
      write_manifest(root, manifest)

      stdout, stderr, status = verify(root)
      assert status.success?, "expected bounded defringe to pass:\n#{stdout}\n#{stderr}"

      derivative.fetch("operations").find { |operation| operation.fetch("name") == "defringe" }["erode_radius"] = 2
      write_manifest(root, manifest)
      stdout, stderr, status = verify(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "invalid exact recipe for derivative flipper_left"
    end
  end

  def test_rejects_arbitrary_iccp_profile_labeled_as_srgb
    in_fixture do |root, manifest|
      derivative = manifest.fetch("derivatives").first
      path = File.join(root, derivative.fetch("path"))
      write_png(path, width: 8, height: 8, alpha: false, profile: false, iccp_name: "Display P3")
      derivative["sha256"] = Digest::SHA256.file(path).hexdigest
      write_manifest(root, manifest)

      stdout, stderr, status = verify(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "non-sRGB ICC profile"
    end
  end

  def test_png_inspector_rejects_spoofed_srgb_iccp_payload
    Tempfile.create(["spoofed-srgb", ".png"]) do |file|
      write_png(file.path, width: 8, height: 8, alpha: false, profile: false, iccp_name: "sRGB forged profile")

      metadata = NovaStationImagegenContract::PNGInspector.read(file.path)

      assert_equal "non-sRGB-icc", metadata.fetch("profile")
    end
  end

  def test_png_inspector_rejects_mixed_srgb_chunk_and_display_p3_iccp
    Tempfile.create(["mixed-rgb", ".png"]) do |file|
      write_png(file.path, width: 8, height: 8, alpha: false, profile: true, iccp_name: "Display P3")

      metadata = NovaStationImagegenContract::PNGInspector.read(file.path)

      assert_equal "ambiguous-rgb-profile", metadata.fetch("profile")
    end
  end

  def test_rejects_paths_escaping_repository_in_entries_masks_and_outputs
    in_fixture do |root, manifest|
      manifest.fetch("masters").first["path"] = "../outside-master.png"
      write_manifest(root, manifest)
      stdout, stderr, status = verify(root)
      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "path escapes repository"
    end

    in_fixture do |root, manifest|
      derivative = manifest.fetch("derivatives").find { |entry| entry.fetch("role") == "portal" }
      derivative.fetch("operations").insert(-2, { "name" => "mask", "path" => "../outside-mask.png" })
      write_manifest(root, manifest)
      stdout, stderr, status = verify(root)
      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "path escapes repository"
    end

    in_fixture do |root, manifest|
      manifest.fetch("derivatives").first["path"] = "../outside-output.png"
      write_manifest(root, manifest)
      stdout, stderr, status = build(root)
      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "path escapes repository"
    end
  end

  def test_rejects_manifest_generated_before_master_or_review
    in_fixture do |root, manifest|
      manifest["generated_at"] = "2026-07-22T09:59:59Z"
      write_manifest(root, manifest)

      stdout, stderr, status = verify(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "generated_at precedes master or review"
    end
  end

  def test_rejects_runtime_table_derived_from_the_complete_table_master
    in_fixture do |root, manifest|
      table = manifest.fetch("derivatives").find { |entry| entry.fetch("role") == "table_composition_4x3" }
      table["source_master"] = "Art/ImageGen/table-master.png"
      write_manifest(root, manifest)

      stdout, stderr, status = verify(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "invalid source_master for derivative table_composition_4x3"
    end
  end

  def test_rejects_imagegen_edit_without_a_valid_parent_master
    in_fixture do |root, manifest|
      edited = manifest.fetch("masters").find { |entry| entry.fetch("path").end_with?("components-master.png") }
      edited.fetch("source")["parent_master"] = "Art/ImageGen/unknown.png"
      write_manifest(root, manifest)

      stdout, stderr, status = verify(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "invalid parent_master"
    end
  end

  def test_rejects_missing_mechanical_guide_overlay_proof
    in_fixture do |root, manifest|
      overlay = manifest.fetch("qa_overlays").first
      FileUtils.rm(File.join(root, overlay.fetch("path")))

      stdout, stderr, status = verify(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "missing mechanical overlay PNG"
    end
  end

  def test_rejects_svg_and_pdf_anywhere_in_art_surfaces
    ["Art/ImageGen/vector.svg", "NovaStationPinball/Resources/Art/mock.pdf"].each do |relative_path|
      in_fixture do |root, _manifest|
        path = File.join(root, relative_path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "forbidden")

        stdout, stderr, status = verify(root)

        refute status.success?
        assert_includes "#{stdout}\n#{stderr}", "forbidden vector asset"
      end
    end
  end

  def test_rejects_png_without_embedded_rgb_profile
    in_fixture do |root, manifest|
      derivative = manifest.fetch("derivatives").first
      path = File.join(root, derivative.fetch("path"))
      write_png(path, width: 8, height: 8, alpha: true, profile: false)
      derivative["sha256"] = Digest::SHA256.file(path).hexdigest
      write_manifest(root, manifest)

      stdout, stderr, status = verify(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "missing embedded RGB profile"
    end
  end

  def test_records_native_untagged_imagegen_master_without_rewriting_it
    in_fixture do |root, manifest|
      master = manifest.fetch("masters").first
      path = File.join(root, master.fetch("path"))
      write_png(path, width: 8, height: 6, alpha: true, profile: false)
      master["sha256"] = Digest::SHA256.file(path).hexdigest
      master["profile"] = "untagged-rgb"
      write_manifest(root, manifest)

      stdout, stderr, status = verify(root)

      assert status.success?, "native ImageGen master should remain byte-exact:\n#{stdout}\n#{stderr}"
    end
  end

  def test_builder_recreates_derivatives_deterministically_from_declared_masters
    in_fixture do |root, manifest|
      manifest.fetch("derivatives").each do |entry|
        entry["operations"] = [
          { "name" => "crop", "geometry" => "8x6+0+0" },
          { "name" => "resize", "width" => 8, "height" => entry.fetch("role") == "app_icon" ? 8 : 6 },
          { "name" => "normalize_srgb" },
          { "name" => "strip_metadata" }
        ]
      end
      write_manifest(root, manifest)
      manifest.fetch("derivatives").each { |entry| FileUtils.rm_f(File.join(root, entry.fetch("path"))) }

      first_stdout, first_stderr, first_status = build(root)
      assert first_status.success?, "expected build success:\n#{first_stdout}\n#{first_stderr}"
      first_hashes = manifest.fetch("derivatives").to_h do |entry|
        path = File.join(root, entry.fetch("path"))
        [entry.fetch("path"), Digest::SHA256.file(path).hexdigest]
      end
      assert File.file?(File.join(root, "Art/QA/table-guide-overlay.png"))

      second_stdout, second_stderr, second_status = build(root)
      assert second_status.success?, "expected repeat build success:\n#{second_stdout}\n#{second_stderr}"
      second_hashes = first_hashes.keys.to_h { |relative_path| [relative_path, Digest::SHA256.file(File.join(root, relative_path)).hexdigest] }
      assert_equal first_hashes, second_hashes

    end
  end

  def test_builder_refuses_to_fabricate_a_missing_master
    in_fixture do |root, manifest|
      FileUtils.rm(File.join(root, manifest.fetch("masters").last.fetch("path")))

      stdout, stderr, status = build(root)

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "missing source master"
    end
  end

  def test_pinball_scene_uses_only_raster_nodes_for_visible_table_art
    source = File.read(File.join(ROOT, "NovaStationPinball/Game/PinballScene.swift"), encoding: "UTF-8")
    root_view = File.read(File.join(ROOT, "NovaStationPinball/App/RootView.swift"), encoding: "UTF-8")

    refute_includes source, "SKShapeNode", "visible procedural shapes must not survive raster integration"
    refute_includes source, "SKLabelNode", "dynamic HUD text must be rasterized into a texture"
    refute_includes source, "mediaScenarioLayer", "media scenarios must not add decorative mechanics"
    refute_includes source, "addMediaSprite", "media scenarios must drive the production session"
    refute_match(/greybox/i, source, "runtime node names must no longer claim greybox art")
    %w[table-composition flipper-left flipper-right plunger ball].each do |asset_name|
      assert_includes source, "SKTexture(imageNamed: \"#{asset_name}\")", "missing raster role #{asset_name}"
    end
    %w[station-panels bumper target ramp portal lamp].each do |asset_name|
      refute_includes source, "SKTexture(imageNamed: \"#{asset_name}\")", "#{asset_name} duplicates art already painted into the background"
    end
    assert_includes source, "RasterHUDRenderer"
    assert_includes source, "SKTexture(imageNamed: \"hud-overlay\")"
    assert_includes source, "private var ballNodes: [UInt64: SKSpriteNode]"
    assert_includes source, "NovaStationTable.definition"
    assert_includes source, "static let playfieldWidthRatio: CGFloat = 0.70"
    assert_includes source, "private static func scenePoint(for vector: Vector2) -> CGPoint"
    table = File.read(File.join(ROOT, "NovaStationCore/Sources/NovaStationCore/NovaStationTable.swift"), encoding: "UTF-8")
    assert_includes table, 'id: "flipper-left"'
    assert_includes table, 'id: "flipper-right"'
    assert_includes table, "public static let launchPosition"
    refute_includes root_view, "GreyboxConsoleView", "the SwiftUI greybox console must not cover the raster scene"
    refute_includes root_view, "[ GREYBOX ]"
    refute_match(/greybox/i, root_view, "accessibility surfaces must describe the final raster composition")
    assert_match(/SpriteView\(scene: model\.scene.*?\)\s*\.frame\(width: width, height: height\)/m, root_view)
  end

  def test_launch_and_game_over_use_distinct_imagegen_rasters
    source = File.read(File.join(ROOT, "NovaStationPinball/Game/PinballScene.swift"), encoding: "UTF-8")
    launch = File.join(ROOT, "NovaStationPinball/Resources/Art/key-art.png")
    game_over = File.join(ROOT, "NovaStationPinball/Resources/Art/store-creative.png")

    refute_equal Digest::SHA256.file(launch).hexdigest, Digest::SHA256.file(game_over).hexdigest
    assert_includes source, 'launchArtwork = SKSpriteNode(texture: SKTexture(imageNamed: "key-art"))'
    assert_includes source, 'gameOverArtwork = SKSpriteNode(texture: SKTexture(imageNamed: "store-creative"))'
    assert_includes source, 'launchArtwork.isHidden = phase != .launch'
    assert_includes source, 'gameOverArtwork.isHidden = phase != .gameOver'
    refute_includes source, 'SKTexture(imageNamed: "menu-background")'
  end

  def test_sprite_node_names_do_not_collide_with_swiftui_accessibility_identifiers
    scene = File.read(File.join(ROOT, "NovaStationPinball/Game/PinballScene.swift"), encoding: "UTF-8")
    root_view = File.read(File.join(ROOT, "NovaStationPinball/App/RootView.swift"), encoding: "UTF-8")
    sprite_names = scene.scan(/\bname:\s*"([^"]+)"/).flatten
    accessibility_identifiers = root_view.scan(/\.accessibilityIdentifier\("([^"]+)"\)/).flatten

    assert_equal [
      "art.frame.4x3",
      "art.table",
      "art.console",
      'media.scenario.\(mediaScenario.rawValue)'
    ], accessibility_identifiers
    assert_empty sprite_names & accessibility_identifiers,
                 "SpriteKit node names leak into XCUI and collide with SwiftUI accessibility overlays"
    assert sprite_names.all? { |name| name.start_with?("sprite.") },
           "visible SpriteKit node names must use the sprite.* namespace"
  end

  def test_runtime_component_edges_are_antialiased_and_free_of_green_or_magenta_spill
    asset_names = %w[
      flipper-left flipper-right bumper target ramp portal lamp plunger ball
      crt-console station-panels hud-overlay
    ]
    asset_names.each do |asset_name|
      path = File.join(ROOT, "NovaStationPinball/Resources/Art/#{asset_name}.png")
      pixels = rgba_pixels(path)
      green_dominant = pixels.count do |red, green, blue, alpha|
        alpha.positive? && green > 80 && green > red + 24 && green > blue + 24
      end
      magenta_fringe = pixels.count do |red, green, blue, alpha|
        alpha.positive? && alpha < 192 && red > green + 20 && blue > green + 20
      end
      partial_alpha = pixels.count { |_red, _green, _blue, alpha| alpha.positive? && alpha < 255 }

      assert_equal 0, green_dominant, "green spill remains in #{asset_name}.png"
      assert_equal 0, magenta_fringe, "low-alpha magenta fringe remains in #{asset_name}.png"
      assert_operator partial_alpha, :>, 0, "#{asset_name}.png has binary alpha and jagged edges"
    end
  end

  def test_dynamic_sprite_feather_has_no_low_alpha_magenta_fringe
    %w[flipper-left flipper-right plunger ball].each do |asset_name|
      path = File.join(ROOT, "NovaStationPinball/Resources/Art/#{asset_name}.png")
      magenta_fringe = rgba_pixels(path).count do |red, green, blue, alpha|
        alpha.positive? && alpha < 192 && red > green + 20 && blue > green + 20
      end

      assert_equal 0, magenta_fringe,
                   "low-alpha magenta fringe remains in #{asset_name}.png (#{magenta_fringe} pixels)"
    end
  end

  private

  def verify(root)
    Open3.capture3("ruby", VERIFIER, "--root", root)
  end

  def build(root)
    Open3.capture3("ruby", BUILDER, "--root", root)
  end

  def rgba_pixels(path)
    stdout, stderr, status = Open3.capture3("/opt/homebrew/bin/magick", path, "-depth", "8", "rgba:-")
    assert status.success?, "failed to inspect pixels in #{path}: #{stderr}"
    stdout.unpack("C*").each_slice(4).to_a
  end

  def in_fixture
    Dir.mktmpdir("nova-imagegen-contract") do |root|
      manifest = build_fixture(root)
      yield root, manifest
    end
  end

  def build_fixture(root)
    guide_path = File.join(root, "NovaStationPinball/Resources/Art/greybox-table-guide.png")
    write_png(guide_path, width: 8, height: 6, alpha: true)

    masters = MASTER_ROLES.map do |filename, roles|
      relative_path = File.join("Art/ImageGen", filename)
      path = File.join(root, relative_path)
      write_png(path, width: 8, height: roles.include?("app_icon") ? 8 : 6, alpha: true)
      source = { "provider" => "openai-imagegen", "mode" => "generation", "artifact" => "exec-fixture-#{filename}" }
      references = ["Art/ImageGen/table-master.png"]
      references = ["NovaStationPinball/Resources/Art/greybox-table-guide.png"] if filename == "table-master.png"
      if filename == "components-master.png"
        source["mode"] = "edit"
        source["parent_master"] = "Art/ImageGen/components-checker-master.png"
        references = ["Art/ImageGen/components-checker-master.png"]
      elsif filename == "components-checker-master.png"
        references = ["Art/ImageGen/table-master.png"]
      elsif filename == "table-background-master.png"
        source["mode"] = "edit"
        source["parent_master"] = "Art/ImageGen/table-master.png"
        references = ["Art/ImageGen/table-master.png"]
      elsif filename == "store-creatives-master.png"
        references = ["Art/ImageGen/table-master.png", "Art/ImageGen/key-art-master.png"]
      end
      metadata(relative_path, path, roles).merge(
        "prompt" => "Original Nova Station #{roles.join(' ')} bitmap, no text, no logos",
        "generated_at" => "2026-07-22T10:00:00Z",
        "source" => source,
        "references" => references,
        "visual_review" => {
          "status" => filename == "components-checker-master.png" ? "provenance_only" : "accepted",
          "inspected_at" => "2026-07-22T10:05:00Z",
          "notes" => "Inspected at native size"
        }
      )
    end

    derivatives = DERIVATIVE_ROLES.map do |relative_path, role|
      path = File.join(root, relative_path)
      write_png(path, width: 8, height: role == "app_icon" ? 8 : 6, alpha: role != "app_icon")
      expected_source = DERIVATIVE_SOURCES.fetch(role, "Art/ImageGen/components-master.png")
      source = masters.find { |entry| entry.fetch("path") == expected_source }
      metadata(relative_path, path, role).merge(
        "source_master" => source.fetch("path"),
        "operations" => Marshal.load(Marshal.dump(EXPECTED_RECIPES.fetch(role)))
      )
    end


    overlay_path = File.join(root, "Art/QA/table-guide-overlay.png")
    write_png(overlay_path, width: 8, height: 6, alpha: true)

    manifest = {
      "schema_version" => 1,
      "generated_at" => "2026-07-22T10:10:00Z",
      "reference_guide" => metadata(
        "NovaStationPinball/Resources/Art/greybox-table-guide.png",
        guide_path,
        "mechanical_reference_4x3"
      ),
      "masters" => masters,
      "derivatives" => derivatives,
      "qa_overlays" => [metadata("Art/QA/table-guide-overlay.png", overlay_path, "mechanical_overlay").merge(
        "source_art" => "NovaStationPinball/Resources/Art/table-composition.png",
        "source_reference" => "NovaStationPinball/Resources/Art/greybox-table-guide.png",
        "operations" => [{ "name" => "blend", "art_percent" => 65, "guide_percent" => 35 }]
      )]
    }
    write_manifest(root, manifest)

    appicon_contents = {
      "images" => [{ "filename" => "AppIcon-1024.png", "idiom" => "universal", "platform" => "ios", "size" => "1024x1024" }],
      "info" => { "author" => "xcode", "version" => 1 }
    }
    contents_path = File.join(root, "NovaStationPinball/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")
    File.write(contents_path, JSON.pretty_generate(appicon_contents) + "\n")
    manifest
  end

  def metadata(relative_path, absolute_path, role_or_roles)
    png = png_metadata(absolute_path)
    {
      "path" => relative_path,
      (role_or_roles.is_a?(Array) ? "roles" : "role") => role_or_roles,
      "sha256" => Digest::SHA256.file(absolute_path).hexdigest,
      "width" => png.fetch(:width),
      "height" => png.fetch(:height),
      "alpha" => png.fetch(:alpha),
      "profile" => "sRGB"
    }
  end

  def write_manifest(root, manifest)
    path = File.join(root, "Art/imagegen-provenance.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(manifest) + "\n")
  end

  def write_png(path, width:, height:, alpha:, profile: true, iccp_name: nil)
    color_type = alpha ? 6 : 2
    channels = alpha ? 4 : 3
    pixel = alpha ? [30, 70, 110, 255] : [30, 70, 110]
    scanline = [0, *(pixel * width)].pack("C*")
    raw = scanline * height
    chunks = [png_chunk("IHDR", [width, height, 8, color_type, 0, 0, 0].pack("NNC5"))]
    chunks << png_chunk("sRGB", [0].pack("C")) if profile
    if iccp_name
      fake_icc = "\0" * 128
      fake_icc[16, 4] = "RGB "
      fake_icc[36, 4] = "acsp"
      fake_icc << iccp_name
      chunks << png_chunk("iCCP", iccp_name + "\0\0" + Zlib::Deflate.deflate(fake_icc))
    end
    chunks << png_chunk("IDAT", Zlib::Deflate.deflate(raw))
    chunks << png_chunk("IEND", "")
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "\x89PNG\r\n\x1a\n".b + chunks.join)
  end

  def png_chunk(type, data)
    payload = type.b + data
    [data.bytesize, payload, Zlib.crc32(payload)].pack("NA* N")
  end

  def png_metadata(path)
    data = File.binread(path)
    ihdr = data.byteslice(16, 13).unpack("NNC5")
    { width: ihdr[0], height: ihdr[1], alpha: [4, 6].include?(ihdr[3]) }
  end
end
