# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "adopt_media"
require File.expand_path(
  "../../../AppsFactory/lib/apps_factory/release_candidate", __dir__
)

class NovaStationPinballMediaAdoptionTest < Minitest::Test
  RUN_ID = "20260810-nova-100-official-545d2d2a-precompute"

  def test_adoption_binds_exact_baseline_candidate_and_media_payloads
    with_fixture do |fixture|
      receipt = fixture.fetch(:adoption).validate!

      assert_equal "adopted_from", receipt.fetch("provenance_mode")
      assert_equal fixture.fetch(:baseline), receipt.fetch("baseline_head")
      assert_equal fixture.fetch(:baseline_contract_sha256),
                   receipt.fetch("baseline_contract_sha256")
      assert_equal fixture.fetch(:head), receipt.fetch("release_head")
      assert_equal fixture.fetch(:candidate_id),
                   receipt.fetch("source_candidate_id")
      assert_equal 36, receipt.dig("media", "screenshots", "count")
      assert_equal 6, receipt.dig("media", "previews", "count")
      assert_equal 6, receipt.dig("media", "system_overlay", "reports")
      assert_equal 4_320,
                   receipt.dig("media", "system_overlay", "scanned_frames")
      assert_match(/\A[0-9a-f]{64}\z/, receipt.fetch("media_candidate_id"))
      contract_change = receipt.fetch("source_changes").find do |change|
        change.fetch("path") == NovaStationPinballMediaAdoption::CONTRACT_PATH
      end
      assert_equal fixture.fetch(:baseline_contract_sha256),
                   contract_change.fetch("before_sha256")
      assert_equal Digest::SHA256.file(fixture.fetch(:contract_path)).hexdigest,
                   contract_change.fetch("after_sha256")
      assert_equal receipt, fixture.fetch(:adoption).validate!
      assert_equal 0o600, File.stat(fixture.fetch(:output)).mode & 0o777
    end
  end

  def test_check_only_validates_everything_without_writing_a_receipt
    with_fixture do |fixture|
      receipt = fixture.fetch(:adoption).validate!(write_receipt: false)

      assert_equal "adopted_from", receipt.fetch("provenance_mode")
      refute File.exist?(fixture.fetch(:output))
      refute File.symlink?(fixture.fetch(:output))
    end
  end

  def test_successive_schema_two_contract_binds_the_previous_valid_contract
    with_fixture do |fixture|
      repo = fixture.fetch(:repo)
      previous_head = fixture.fetch(:head)
      previous_contract_sha256 = Digest::SHA256.file(
        fixture.fetch(:contract_path)
      ).hexdigest
      successor_path = File.join(
        repo, "scripts", "app_store", "metadata_recovery.rb"
      )
      File.write(successor_path, "absolute metadata preflight\n")
      contract = JSON.parse(File.binread(fixture.fetch(:contract_path)))
      contract["baseline_head"] = previous_head
      contract["baseline_contract_sha256"] = previous_contract_sha256
      contract["lineage"] = {
        "mode" => "successive",
        "previous_head" => previous_head,
        "previous_contract_sha256" => previous_contract_sha256
      }
      contract["allowed_source_changes"] = [{
        "path" => "scripts/app_store/metadata_recovery.rb",
        "class" => "release_tooling",
        "before_sha256" => nil,
        "after_sha256" => Digest::SHA256.file(successor_path).hexdigest
      }]
      contract["contract_self_sha256"] = Digest::SHA256.hexdigest(
        JSON.generate(
          NovaStationPinballMediaAdoption.canonical(
            contract.reject { |key, _| key == "contract_self_sha256" }
          )
        )
      )
      File.write(
        fixture.fetch(:contract_path), JSON.pretty_generate(contract) + "\n"
      )
      git!(repo, "add", "fastlane", "scripts")
      git!(repo, "commit", "-q", "-m", "successive recovery tooling")
      candidate = NovaStationPinballMediaAdoption.candidate_id(repo)
      adoption = NovaStationPinballMediaAdoption::Contract.new(
        **fixture.fetch(:arguments).merge(candidate_id: candidate)
      )

      receipt = adoption.validate!(write_receipt: false)

      assert_equal "successive", receipt.dig("lineage", "mode")
      assert_equal previous_head, receipt.dig("lineage", "previous_head")
      assert_equal previous_contract_sha256,
                   receipt.dig("lineage", "previous_contract_sha256")
      refute File.exist?(fixture.fetch(:output))
    end
  end

  def test_adoption_rejects_a_wrong_baseline_contract_lineage
    with_fixture(baseline_contract_sha256: "f" * 64) do |fixture|
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        fixture.fetch(:adoption).validate!(write_receipt: false)
      end
    end
  end

  def test_adoption_rejects_noncanonical_contract_run_and_output_paths
    with_fixture do |fixture|
      foreign_contract = File.join(
        fixture.fetch(:repo), "fastlane", "foreign-adoption-contract.json"
      )
      FileUtils.cp(fixture.fetch(:contract_path), foreign_contract)
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        NovaStationPinballMediaAdoption::Contract.new(
          **fixture.fetch(:arguments).merge(contract_path: foreign_contract)
        ).validate!(write_receipt: false)
      end

      foreign_run = File.join(
        fixture.fetch(:repo), "Builds", "AppStore", "NovaStationPinball",
        "foreign-run"
      )
      FileUtils.mkdir_p(File.join(foreign_run, "logs"))
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        NovaStationPinballMediaAdoption::Contract.new(
          **fixture.fetch(:arguments).merge(
            run_root: foreign_run,
            output_path: File.join(foreign_run, "logs", "media-adoption.json")
          )
        ).validate!(write_receipt: false)
      end

      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        NovaStationPinballMediaAdoption::Contract.new(
          **fixture.fetch(:arguments).merge(
            output_path: File.join(fixture.fetch(:run), "logs", "foreign.json")
          )
        ).validate!(write_receipt: false)
      end
    ensure
      FileUtils.rm_f(foreign_contract) if defined?(foreign_contract)
    end
  end

  def test_adoption_rejects_candidate_drift_and_product_source_changes
    with_fixture do |fixture|
      wrong = NovaStationPinballMediaAdoption::Contract.new(
        **fixture.fetch(:arguments).merge(candidate_id: "f" * 64)
      )
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        wrong.validate!
      end

      File.write(File.join(fixture.fetch(:repo), "Game.swift"), "product drift\n")
      git!(fixture.fetch(:repo), "add", "Game.swift")
      git!(fixture.fetch(:repo), "commit", "-m", "product drift")
      drifted_id = NovaStationPinballMediaAdoption.candidate_id(
        fixture.fetch(:repo)
      )
      drifted = NovaStationPinballMediaAdoption::Contract.new(
        **fixture.fetch(:arguments).merge(candidate_id: drifted_id)
      )
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        drifted.validate!
      end
    end
  end

  def test_adoption_rejects_byte_drift_on_an_allowlisted_path
    with_fixture do |fixture|
      tooling = File.join(
        fixture.fetch(:repo), "scripts", "app_store", "adopt_media.rb"
      )
      File.write(tooling, "same allowlisted path, different bytes\n")
      git!(fixture.fetch(:repo), "add", "scripts/app_store/adopt_media.rb")
      git!(fixture.fetch(:repo), "commit", "-m", "drift allowlisted bytes")
      drifted_id = NovaStationPinballMediaAdoption.candidate_id(
        fixture.fetch(:repo)
      )
      drifted = NovaStationPinballMediaAdoption::Contract.new(
        **fixture.fetch(:arguments).merge(candidate_id: drifted_id)
      )

      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        drifted.validate!
      end
    end
  end

  def test_adoption_rejects_incomplete_human_or_overlay_evidence
    with_fixture do |fixture|
      review = File.join(
        fixture.fetch(:run), "logs", "human-review", "review.md"
      )
      File.write(review, File.read(review).sub("Verdict: **PASS**", "Verdict: **FAIL**"))
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        fixture.fetch(:adoption).validate!
      end
    end

    with_fixture do |fixture|
      report = Dir.glob(
        File.join(fixture.fetch(:run), "logs", "system-overlay", "*.json")
      ).first
      payload = JSON.parse(File.binread(report))
      payload["scanned_frame_count"] = 719
      File.write(report, JSON.generate(payload))
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        fixture.fetch(:adoption).validate!
      end
    end

    with_fixture do |fixture|
      sheet = Dir.glob(
        File.join(
          fixture.fetch(:run), "logs", "human-review", "screenshots", "*.png"
        )
      ).first
      File.rename(sheet, File.join(File.dirname(sheet), "unexpected-name.png"))
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        fixture.fetch(:adoption).validate!
      end
    end
  end

  def test_adoption_rejects_frozen_media_and_review_evidence_byte_drift
    with_fixture do |fixture|
      screenshot = Dir.glob(
        File.join(fixture.fetch(:run), "screenshots", "*", "*.png")
      ).first
      File.binwrite(screenshot, "different but still image-shaped bytes")
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        fixture.fetch(:adoption).validate!
      end
    end

    with_fixture do |fixture|
      review = File.join(
        fixture.fetch(:run), "logs", "human-review", "review.md"
      )
      File.write(review, File.read(review) + "- Unfrozen annotation\n")
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        fixture.fetch(:adoption).validate!
      end
    end

    with_fixture do |fixture|
      report = Dir.glob(
        File.join(fixture.fetch(:run), "logs", "system-overlay", "*.json")
      ).first
      payload = JSON.parse(File.binread(report))
      payload.fetch("top_band")["reject_at_or_above"] = 63.0
      File.write(report, JSON.generate(payload))
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        fixture.fetch(:adoption).validate!
      end
    end


    with_fixture do |fixture|
      preview = Dir.glob(
        File.join(fixture.fetch(:run), "app_previews", "*", "*.mov")
      ).first
      File.binwrite(preview, "different preview bytes")
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        fixture.fetch(:adoption).validate!
      end
    end

    with_fixture do |fixture|
      manifest = File.join(
        fixture.fetch(:run), "logs", "media-manifest.json"
      )
      File.write(manifest, File.read(manifest) + "\n")
      assert_raises(NovaStationPinballMediaAdoption::AdoptionError) do
        fixture.fetch(:adoption).validate!
      end
    end
  end

  def test_overlay_rescan_timestamp_does_not_change_frozen_semantics
    with_fixture do |fixture|
      report = Dir.glob(
        File.join(fixture.fetch(:run), "logs", "system-overlay", "*.json")
      ).first
      payload = JSON.parse(File.binread(report))
      payload["generated_at"] = "2026-08-10T12:34:56Z"
      File.write(report, JSON.generate(payload))

      assert_equal "adopted_from",
                   fixture.fetch(:adoption).validate!.fetch("provenance_mode")
    end
  end

  def test_temporary_credential_bridge_changes_neither_candidate_algorithm
    with_fixture do |fixture|
      repo = fixture.fetch(:repo)
      local_before = NovaStationPinballMediaAdoption.candidate_id(repo)
      official_before = AppsFactory::ReleaseCandidateManifest.capture(repo)
        .candidate_id
      bridge = File.join(repo, "fastlane", "asc_api_key.json")
      File.write(bridge, "ephemeral credential bridge\n")

      assert_equal local_before,
                   NovaStationPinballMediaAdoption.candidate_id(repo)
      assert_equal official_before,
                   AppsFactory::ReleaseCandidateManifest.capture(repo).candidate_id

      FileUtils.rm_f(bridge)
      FileUtils.mkdir_p(bridge)
      File.write(File.join(bridge, "must-remain-visible"), "candidate drift\n")
      refute_equal local_before,
                   NovaStationPinballMediaAdoption.candidate_id(repo)
      refute_equal official_before,
                   AppsFactory::ReleaseCandidateManifest.capture(repo).candidate_id
    ensure
      FileUtils.rm_f(bridge) if defined?(bridge)
    end
  end

  private

  def with_fixture(baseline_contract_sha256: nil)
    Dir.mktmpdir("nova-media-adoption") do |directory|
      repo = File.join(directory, "repo")
      FileUtils.mkdir_p(repo)
      git!(repo, "init", "-q")
      git!(repo, "config", "user.email", "nova-tests@example.invalid")
      git!(repo, "config", "user.name", "Nova Tests")
      File.write(
        File.join(repo, ".gitignore"),
        "Builds/\n/fastlane/asc_api_key.json\n!/fastlane/asc_api_key.json/\n"
      )
      File.write(File.join(repo, "Game.swift"), "baseline\n")
      FileUtils.mkdir_p(File.join(repo, "fastlane"))
      FileUtils.mkdir_p(File.join(repo, "scripts", "app_store"))
      contract_path = File.join(repo, "fastlane", "media_adoption_contract.json")
      tooling_path = File.join(repo, "scripts", "app_store", "adopt_media.rb")
      File.write(
        contract_path,
        JSON.pretty_generate(
          "schema_version" => 2,
          "app_slug" => "NovaStationPinball",
          "release_run_id" => "historical-adoption-contract"
        ) + "\n"
      )
      File.write(tooling_path, "baseline release tooling\n")
      git!(repo, "add", ".gitignore", "Game.swift", "fastlane", "scripts")
      git!(repo, "commit", "-q", "-m", "baseline")
      baseline = git!(repo, "rev-parse", "HEAD").strip
      observed_baseline_contract_sha256 = Digest::SHA256.file(contract_path).hexdigest
      source_revision = NovaStationPinballMediaAdoption.source_fingerprint_at_commit(
        repo, baseline
      )

      File.write(File.join(repo, "scripts", "app_store", "adopt_media.rb"), "release tooling\n")
      contract = {
        "schema_version" => 2,
        "app_slug" => "NovaStationPinball",
        "release_run_id" => RUN_ID,
        "baseline_head" => baseline,
        "baseline_contract_sha256" => baseline_contract_sha256 ||
          observed_baseline_contract_sha256,
        "source_revision" => source_revision,
        "screenshot_count" => 36,
        "preview_count" => 6,
        "allowed_source_changes" => [{
          "path" => "scripts/app_store/adopt_media.rb",
          "class" => "release_tooling",
          "before_sha256" => NovaStationPinballMediaAdoption.file_sha256_at_commit(
            repo, baseline, "scripts/app_store/adopt_media.rb"
          ),
          "after_sha256" => Digest::SHA256.file(tooling_path).hexdigest
        }]
      }
      run = File.join(repo, "Builds", "AppStore", "NovaStationPinball", RUN_ID)
      build_media_fixture(run, source_revision)
      proof_builder = NovaStationPinballMediaAdoption::Contract.allocate
      proof_builder.instance_variable_set(:@run_root, File.realpath(run))
      contract["media_proof"] = proof_builder.send(:media_payload!, contract)
      contract["contract_self_sha256"] = Digest::SHA256.hexdigest(
        JSON.generate(
          NovaStationPinballMediaAdoption.canonical(
            contract.reject { |key, _| key == "contract_self_sha256" }
          )
        )
      )
      File.write(contract_path, JSON.pretty_generate(contract))
      git!(repo, "add", "fastlane", "scripts")
      git!(repo, "commit", "-q", "-m", "release tooling")
      head = git!(repo, "rev-parse", "HEAD").strip
      candidate_id = NovaStationPinballMediaAdoption.candidate_id(repo)

      output = File.join(run, "logs", "media-adoption.json")
      arguments = {
        repo_root: repo,
        run_root: run,
        contract_path: contract_path,
        candidate_id: candidate_id,
        output_path: output,
        media_validator: lambda do |source_revision|
          raise "wrong source" unless source_revision == contract.fetch("source_revision")

          {
            "pending_cells" => 0,
            "cells" => Array.new(36) { {} },
            "screenshots" => Array.new(36) { |index| "#{index}.png" },
            "app_previews" => Array.new(6) { |index| "#{index}.mov" }
          }
        end
      }
      adoption = NovaStationPinballMediaAdoption::Contract.new(**arguments)
      yield(
        repo: repo, run: run, baseline: baseline, head: head,
        baseline_contract_sha256: observed_baseline_contract_sha256,
        source_revision: source_revision,
        candidate_id: candidate_id, output: output, contract_path: contract_path,
        arguments: arguments, adoption: adoption
      )
    end
  end

  def build_media_fixture(run, source_revision)
    %w[en-US fr-FR].each do |locale|
      FileUtils.mkdir_p(File.join(run, "screenshots", locale))
      18.times do |index|
        File.binwrite(
          File.join(run, "screenshots", locale, format("%02d.png", index)),
          "#{locale}-screenshot-#{index}"
        )
      end
      FileUtils.mkdir_p(File.join(run, "app_previews", locale))
      3.times do |index|
        File.binwrite(
          File.join(run, "app_previews", locale, "preview-#{index}.mov"),
          "#{locale}-preview-#{index}"
        )
      end
    end
    FileUtils.mkdir_p(File.join(run, "logs", "human-review"))
    File.write(
      File.join(run, "logs", "human-review", "review.md"),
      "- Run: `#{RUN_ID}`\n" \
      "- Source fingerprint: `#{source_revision}`\n" \
      "- Verdict: **PASS**\n"
    )
    NovaStationPinballMediaAdoption::HUMAN_REVIEW_PATHS.each do |relative|
      next if relative == "review.md"

      path = File.join(run, "logs", "human-review", relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, "human-review-sheet:#{relative}")
    end
    FileUtils.mkdir_p(File.join(run, "logs", "system-overlay"))
    previews = Dir.glob(File.join(run, "app_previews", "*", "*.mov")).sort
    previews.each_with_index do |preview, index|
      File.write(
        File.join(run, "logs", "system-overlay", "report-#{index}.json"),
        JSON.generate(
          "schema_version" => 1,
          "status" => "pass",
          "generated_at" => "2026-08-10T00:00:00Z",
          "video_path" => preview,
          "video_sha256" => Digest::SHA256.file(preview).hexdigest,
          "expected_frame_count" => 720,
          "scanned_frame_count" => 720,
          "frame_rate" => 30.0,
          "top_band" => {
            "x_ratio" => 0.125,
            "y_ratio" => 0.0,
            "width_ratio" => 0.75,
            "height_ratio" => 0.2,
            "metric" => "lavfi.signalstats.YAVG",
            "reject_at_or_above" => 64.0
          },
          "violation_count" => 0,
          "violation_spans" => [],
          "violating_frames" => []
        )
      )
    end
    FileUtils.mkdir_p(File.join(run, "logs"))
    File.write(
      File.join(run, "logs", "media-manifest.json"),
      JSON.generate("schema_version" => 1, "source_revision" => source_revision)
    )
  end

  def git!(root, *arguments)
    stdout, stderr, status = Open3.capture3("git", "-C", root, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
