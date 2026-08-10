#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "securerandom"
require_relative "media_contract"

module NovaStationPinballMediaAdoption
  APP_SLUG = "NovaStationPinball"
  SHA256 = /\A[0-9a-f]{64}\z/.freeze
  COMMIT = /\A[0-9a-f]{40}\z/.freeze
  RUN_ID = /\A[0-9A-Za-z][0-9A-Za-z._-]{2,127}\z/.freeze
  CONTRACT_PATH = "fastlane/media_adoption_contract.json"
  MEDIA_LOCALES = %w[en-US fr-FR].freeze
  MEDIA_DEVICES = %w[iphone-17-pro-max iphone-se-3 ipad-pro-13-m5].freeze
  HUMAN_REVIEW_PATHS = (
    ["review.md"] +
    MEDIA_LOCALES.product(MEDIA_DEVICES).map do |locale, device|
      "screenshots/#{locale}-#{device}.png"
    end +
    MEDIA_LOCALES.product(MEDIA_DEVICES).flat_map do |locale, device|
      %W[
        motion/#{locale}-#{device}-boundaries.png
        motion/#{locale}-#{device}-regular-2fps.png
      ]
    end
  ).sort.freeze
  CONTRACT_KEYS = %w[
    allowed_source_changes app_slug baseline_head contract_self_sha256
    media_proof preview_count release_run_id schema_version screenshot_count
    source_revision
  ].freeze
  SOURCE_CHANGE_KEYS = %w[
    after_sha256 before_sha256 class path
  ].freeze

  class AdoptionError < StandardError; end

  module_function

  def candidate_id(repo_root)
    root = File.realpath(repo_root)
    base_head = git!(root, "rev-parse", "HEAD").strip
    paths = git!(
      root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"
    ).split("\0", -1).reject(&:empty?).sort
    indexed_modes = git!(root, "ls-files", "-s", "-z")
      .split("\0", -1).each_with_object({}) do |row, result|
        next if row.empty?

        metadata, path = row.split("\t", 2)
        result[path] = metadata.to_s.split(" ", 2).first if path
      end
    entries = paths.map do |relative|
      absolute = safe_path!(root, relative, "candidate entry")
      if File.symlink?(absolute)
        stat = File.lstat(absolute)
        candidate_entry(relative, stat, Digest::SHA256.hexdigest(File.readlink(absolute)), "symlink")
      elsif File.file?(absolute)
        stat = File.lstat(absolute)
        candidate_entry(relative, stat, Digest::SHA256.file(absolute).hexdigest, "file")
      elsif !File.exist?(absolute) && indexed_modes.key?(relative)
        {
          "path" => relative,
          "type" => "deleted",
          "mode" => indexed_modes.fetch(relative),
          "sha256" => nil
        }
      else
        raise AdoptionError, "unsupported release candidate entry: #{relative}"
      end
    end
    document = {
      "schema_version" => 1,
      "base_head" => base_head,
      "entries" => entries
    }
    Digest::SHA256.hexdigest(JSON.generate(document))
  end

  def candidate_entry(relative, stat, sha256, type)
    {
      "path" => relative,
      "type" => type,
      "mode" => format("%06o", stat.mode & 0o177777),
      "sha256" => sha256
    }
  end

  def git!(root, *arguments)
    stdout, stderr, status = Open3.capture3("git", "-C", root, *arguments)
    return stdout if status.success?

    raise AdoptionError, "git #{arguments.first} failed: #{stderr.strip}"
  end

  def source_fingerprint_at_commit(repo_root, commit)
    root = File.realpath(repo_root)
    resolved = git!(root, "rev-parse", "--verify", "#{commit}^{commit}").strip
    raise AdoptionError, "source fingerprint commit did not resolve exactly" unless resolved == commit

    records = git!(root, "ls-tree", "-rz", "--full-tree", commit)
      .split("\0", -1).reject(&:empty?).map do |row|
        metadata, relative = row.split("\t", 2)
        mode, type, object = metadata.to_s.split(" ", 3)
        next if source_fingerprint_excluded?(relative)
        raise AdoptionError, "source fingerprint forbids symbolic links" if mode == "120000"
        raise AdoptionError, "source fingerprint encountered a non-file entry" unless type == "blob"

        content = git!(root, "cat-file", "blob", object)
        permission = format("%03o", Integer(mode, 8) & 0o777)
        [relative, permission, Digest::SHA256.hexdigest(content)]
      end.compact
    digest = Digest::SHA256.new
    records.sort_by(&:first).each do |relative, permission, sha256|
      digest << relative << "\0" << permission << "\0" << sha256 << "\n"
    end
    digest.hexdigest
  rescue ArgumentError => error
    raise AdoptionError, "invalid source fingerprint tree: #{error.message}"
  end

  def source_fingerprint_excluded?(relative)
    NovaStationPinballMediaContract::SourceFingerprint::EXCLUDED_PREFIXES.any? do |prefix|
      prefix.end_with?("/") ?
        relative == prefix.delete_suffix("/") || relative.start_with?(prefix) :
        relative == prefix
    end || relative.include?(".xcuserdatad/") || relative.end_with?(".xcuserstate")
  end

  def safe_path!(root, relative, label)
    unless relative.instance_of?(String) && !relative.empty? &&
           !Pathname.new(relative).absolute?
      raise AdoptionError, "#{label} must be app-local"
    end
    path = File.expand_path(relative, root)
    unless path.start_with?("#{root}#{File::SEPARATOR}")
      raise AdoptionError, "#{label} escaped its root"
    end
    path
  end

  def canonical(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end

  def canonical_bytes(value)
    JSON.generate(canonical(value))
  end

  def validate_contract_self_digest!(contract)
    digest = contract["contract_self_sha256"]
    unless digest.to_s.match?(SHA256)
      raise AdoptionError, "adoption contract self digest must be a SHA-256"
    end
    unsigned = contract.reject { |key, _| key == "contract_self_sha256" }
    unless Digest::SHA256.hexdigest(canonical_bytes(unsigned)) == digest
      raise AdoptionError, "adoption contract self digest changed"
    end
    digest
  end

  def exact_source_change_records!(value)
    unless value.instance_of?(Array) && !value.empty? &&
           value.all? { |item| item.instance_of?(Hash) }
      raise AdoptionError, "allowed_source_changes must be an object list"
    end
    paths = value.map { |item| item["path"] }
    unless paths.all? { |path| path.instance_of?(String) && !path.empty? } &&
           paths == paths.uniq.sort && !paths.include?(CONTRACT_PATH)
      raise AdoptionError, "allowed_source_changes must be sorted, unique and exclude the contract"
    end
    value.each do |item|
      relative = item["path"]
      parts = relative.to_s.split(File::SEPARATOR)
      valid = item.keys.sort == SOURCE_CHANGE_KEYS &&
        item["class"] == "release_tooling" &&
        !Pathname.new(relative.to_s).absolute? && !parts.include?("..") &&
        (item["before_sha256"].nil? || item["before_sha256"].to_s.match?(SHA256)) &&
        item["after_sha256"].to_s.match?(SHA256)
      raise AdoptionError, "allowed source change record is not exact" unless valid
    end
    value
  end

  def validate_media_proof_schema!(value)
    unless value.instance_of?(Hash) && value.keys.sort == %w[
      human_review manifest previews screenshots system_overlay
    ]
      raise AdoptionError, "media proof schema is not exact"
    end
    {
      "screenshots" => 36,
      "previews" => 6,
      "manifest" => 1
    }.each do |name, count|
      payload = value[name]
      unless payload.instance_of?(Hash) && payload.keys.sort == %w[count sha256] &&
             payload["count"] == count && payload["sha256"].to_s.match?(SHA256)
        raise AdoptionError, "#{name} media proof is not exact"
      end
    end
    overlay = value["system_overlay"]
    unless overlay.instance_of?(Hash) && overlay.keys.sort == %w[
      reports scanned_frames semantic_sha256 violation_count
    ] && overlay["reports"] == 6 && overlay["scanned_frames"] == 4_320 &&
           overlay["violation_count"] == 0 &&
           overlay["semantic_sha256"].to_s.match?(SHA256)
      raise AdoptionError, "system-overlay media proof is not exact"
    end
    human = value["human_review"]
    unless human.instance_of?(Hash) && human.keys.sort == %w[count sha256 verdict] &&
           human["count"] == HUMAN_REVIEW_PATHS.length &&
           human["sha256"].to_s.match?(SHA256) && human["verdict"] == "PASS"
      raise AdoptionError, "human-review media proof is not exact"
    end
    value
  end

  def file_sha256_at_commit(repo_root, commit, relative)
    root = File.realpath(repo_root)
    rows = git!(root, "ls-tree", "-z", commit, "--", relative)
      .split("\0", -1).reject(&:empty?)
    return nil if rows.empty?
    raise AdoptionError, "source change path is ambiguous: #{relative}" unless rows.length == 1

    metadata, observed = rows.first.split("\t", 2)
    mode, type, object = metadata.to_s.split(" ", 3)
    unless observed == relative && type == "blob" && mode != "120000"
      raise AdoptionError, "source change must be one regular Git blob: #{relative}"
    end
    Digest::SHA256.hexdigest(git!(root, "cat-file", "blob", object))
  end

  def tree_payload!(root, extensions:, expected_count:)
    expanded = File.expand_path(root)
    unless File.directory?(expanded) && !File.symlink?(expanded)
      raise AdoptionError, "missing regular media directory: #{expanded}"
    end
    allowed = extensions.map(&:downcase).uniq.sort
    records = []
    Dir.glob(File.join(expanded, "**", "*"), File::FNM_DOTMATCH).sort.each do |path|
      relative = Pathname.new(path).relative_path_from(Pathname.new(expanded)).to_s
      raise AdoptionError, "media tree contains a symlink: #{relative}" if File.symlink?(path)
      next if File.directory?(path)
      unless File.file?(path) && allowed.include?(File.extname(path).downcase)
        raise AdoptionError, "media tree contains a foreign entry: #{relative}"
      end
      records << "#{relative}\0#{Digest::SHA256.file(path).hexdigest}"
    end
    unless records.length == expected_count
      raise AdoptionError,
            "media tree has #{records.length} files, expected #{expected_count}"
    end
    {
      "count" => records.length,
      "sha256" => Digest::SHA256.hexdigest(records.join("\n"))
    }
  end

  def file_payload!(path, label)
    expanded = File.expand_path(path)
    unless File.file?(expanded) && !File.symlink?(expanded)
      raise AdoptionError, "missing regular #{label}: #{expanded}"
    end
    { "count" => 1, "sha256" => Digest::SHA256.file(expanded).hexdigest }
  end

  class Contract
    def initialize(repo_root:, run_root:, contract_path:, candidate_id:, output_path:,
                   media_validator: nil)
      @repo_root = File.realpath(repo_root)
      @run_root = File.realpath(run_root)
      @contract_path = File.realpath(contract_path)
      @candidate_id = candidate_id.to_s
      output_directory = File.realpath(File.dirname(output_path))
      @output_path = File.join(output_directory, File.basename(output_path))
      @media_validator = media_validator || method(:validate_media!)
    rescue Errno::ENOENT => error
      raise AdoptionError, "adoption path is missing: #{error.message}"
    end

    def validate!
      contract = read_contract!
      validate_paths!(contract)
      release_head, source_changes = validate_source!(contract)
      validate_candidate!
      report = @media_validator.call(contract.fetch("source_revision"))
      validate_report!(report, contract)
      media = media_payload!(contract)
      unsigned = {
        "schema_version" => 1,
        "provenance_mode" => "adopted_from",
        "app_slug" => APP_SLUG,
        "release_run_id" => contract.fetch("release_run_id"),
        "baseline_head" => contract.fetch("baseline_head"),
        "release_head" => release_head,
        "source_revision" => contract.fetch("source_revision"),
        "source_candidate_id" => @candidate_id,
        "adoption_contract_sha256" => Digest::SHA256.file(@contract_path).hexdigest,
        "source_changes" => source_changes,
        "media" => media
      }
      document = unsigned.merge(
        "media_candidate_id" => Digest::SHA256.hexdigest(
          JSON.generate(NovaStationPinballMediaAdoption.canonical(unsigned))
        )
      )
      write_once!(document)
      document
    end

    private

    def read_contract!
      unless File.file?(@contract_path) && !File.symlink?(@contract_path)
        raise AdoptionError, "media adoption contract must be a regular file"
      end
      document = JSON.parse(File.binread(@contract_path))
      unless document.instance_of?(Hash) && document.keys.sort == CONTRACT_KEYS &&
             document["schema_version"] == 2 &&
             document["app_slug"] == APP_SLUG &&
             document["release_run_id"].to_s.match?(RUN_ID) &&
             document["baseline_head"].to_s.match?(COMMIT) &&
             document["source_revision"].to_s.match?(SHA256) &&
             document["screenshot_count"] == 36 &&
             document["preview_count"] == 6
        raise AdoptionError, "media adoption contract is incomplete or inexact"
      end
      NovaStationPinballMediaAdoption.exact_source_change_records!(
        document.fetch("allowed_source_changes")
      )
      NovaStationPinballMediaAdoption.validate_media_proof_schema!(
        document.fetch("media_proof")
      )
      NovaStationPinballMediaAdoption.validate_contract_self_digest!(document)
      document
    rescue JSON::ParserError => error
      raise AdoptionError, "invalid media adoption contract: #{error.message}"
    end

    def validate_paths!(contract)
      expected_run = File.join(
        @repo_root, "Builds", "AppStore", APP_SLUG,
        contract.fetch("release_run_id")
      )
      raise AdoptionError, "adoption targets a different release run" unless @run_root == expected_run
      expected_contract = File.join(@repo_root, CONTRACT_PATH)
      raise AdoptionError, "adoption contract path is not canonical" unless @contract_path == expected_contract
      expected_output = File.join(@run_root, "logs", "media-adoption.json")
      raise AdoptionError, "adoption receipt path is not canonical" unless @output_path == expected_output
    end

    def validate_source!(contract)
      status = NovaStationPinballMediaAdoption.git!(
        @repo_root, "status", "--porcelain=v1", "--untracked-files=all"
      )
      raise AdoptionError, "release source must be committed and clean" unless status.empty?

      baseline = contract.fetch("baseline_head")
      resolved = NovaStationPinballMediaAdoption.git!(
        @repo_root, "rev-parse", "--verify", "#{baseline}^{commit}"
      ).strip
      raise AdoptionError, "baseline head did not resolve exactly" unless resolved == baseline
      unless NovaStationPinballMediaAdoption.source_fingerprint_at_commit(
        @repo_root, baseline
      ) == contract.fetch("source_revision")
        raise AdoptionError,
              "baseline head does not match the adopted source fingerprint"
      end
      NovaStationPinballMediaAdoption.git!(
        @repo_root, "merge-base", "--is-ancestor", baseline, "HEAD"
      )
      release_head = NovaStationPinballMediaAdoption.git!(
        @repo_root, "rev-parse", "HEAD"
      ).strip
      changes = changed_paths(baseline, release_head)
      expected_records = contract.fetch("allowed_source_changes")
      expected_paths = expected_records.map { |item| item.fetch("path") }
      unless changes == (expected_paths + [CONTRACT_PATH]).sort
        raise AdoptionError,
              "source drift is not the exact release-only adoption patch"
      end
      proof = expected_records.map do |record|
        path = record.fetch("path")
        before_sha256 = NovaStationPinballMediaAdoption.file_sha256_at_commit(
          @repo_root, baseline, path
        )
        after_sha256 = NovaStationPinballMediaAdoption.file_sha256_at_commit(
          @repo_root, release_head, path
        )
        unless before_sha256 == record["before_sha256"] &&
               after_sha256 == record.fetch("after_sha256")
          raise AdoptionError, "source bytes changed outside the frozen hashes: #{path}"
        end
        record
      end
      contract_before = NovaStationPinballMediaAdoption.file_sha256_at_commit(
        @repo_root, baseline, CONTRACT_PATH
      )
      contract_after = NovaStationPinballMediaAdoption.file_sha256_at_commit(
        @repo_root, release_head, CONTRACT_PATH
      )
      unless contract_before.nil? && contract_after == Digest::SHA256.file(@contract_path).hexdigest
        raise AdoptionError, "adoption contract must be one exact canonical source addition"
      end
      proof << {
        "path" => CONTRACT_PATH,
        "class" => "adoption_contract",
        "before_sha256" => nil,
        "after_sha256" => contract_after
      }
      [release_head, proof.sort_by { |item| item.fetch("path") }]
    end

    def changed_paths(baseline, release_head)
      output = NovaStationPinballMediaAdoption.git!(
        @repo_root, "diff", "--name-only", "--no-renames", baseline, release_head
      )
      output.lines.map(&:strip).reject(&:empty?).sort
    end

    def validate_candidate!
      unless @candidate_id.match?(SHA256) &&
             NovaStationPinballMediaAdoption.candidate_id(@repo_root) == @candidate_id
        raise AdoptionError, "source candidate id does not match the exact clean repository"
      end
    end

    def validate_media!(source_revision)
      NovaStationPinballMediaContract::Contract.new(
        run_root: @run_root,
        source_revision: source_revision
      ).validate!
    rescue NovaStationPinballMediaContract::ContractError => error
      raise AdoptionError, "frozen media validation failed: #{error.message}"
    end

    def validate_report!(report, contract)
      unless report.instance_of?(Hash) && report["pending_cells"] == 0 &&
             Array(report["cells"]).length == 36 &&
             Array(report["screenshots"]).length == contract.fetch("screenshot_count") &&
             Array(report["app_previews"]).length == contract.fetch("preview_count")
        raise AdoptionError, "frozen media validator returned an incomplete matrix"
      end
    end

    def media_payload!(contract)
      screenshots = NovaStationPinballMediaAdoption.tree_payload!(
        File.join(@run_root, "screenshots"),
        extensions: %w[.png .jpg .jpeg],
        expected_count: contract.fetch("screenshot_count")
      )
      previews = NovaStationPinballMediaAdoption.tree_payload!(
        File.join(@run_root, "app_previews"),
        extensions: %w[.mov .mp4],
        expected_count: contract.fetch("preview_count")
      )
      actual = {
        "screenshots" => screenshots,
        "previews" => previews,
        "manifest" => NovaStationPinballMediaAdoption.file_payload!(
          File.join(@run_root, "logs", "media-manifest.json"),
          "media manifest"
        ),
        "system_overlay" => overlay_payload!(previews),
        "human_review" => human_review_payload!(contract)
      }
      expected = contract["media_proof"]
      if expected && actual != expected
        raise AdoptionError,
              "frozen media or review evidence changed from the exact adopted run"
      end
      actual
    end

    def overlay_payload!(previews)
      root = File.join(@run_root, "logs", "system-overlay")
      unless File.directory?(root) && !File.symlink?(root)
        raise AdoptionError, "missing regular system-overlay evidence directory"
      end
      paths = Dir.glob(File.join(root, "*.json")).sort
      raise AdoptionError, "system-overlay evidence must contain six reports" unless paths.length == 6
      preview_hashes = Dir.glob(File.join(@run_root, "app_previews", "*", "*.mov"))
        .sort.map { |path| Digest::SHA256.file(path).hexdigest }
      observed_hashes = []
      semantic_records = []
      scanned_frames = paths.sum do |path|
        raise AdoptionError, "system-overlay report may not be a symlink" if File.symlink?(path)
        payload = JSON.parse(File.binread(path))
        valid = payload.instance_of?(Hash) &&
          payload.keys.sort == %w[
            expected_frame_count frame_rate generated_at scanned_frame_count
            schema_version status top_band video_path video_sha256
            violation_count violation_spans violating_frames
          ].sort &&
          payload["schema_version"] == 1 && payload["status"] == "pass" &&
          payload["expected_frame_count"] == 720 &&
          payload["scanned_frame_count"] == 720 &&
          payload["frame_rate"] == 30.0 && payload["top_band"].instance_of?(Hash) &&
          payload["violation_count"] == 0 &&
          payload["violation_spans"] == [] && payload["violating_frames"] == [] &&
          payload["video_sha256"].to_s.match?(SHA256)
        raise AdoptionError, "system-overlay report is incomplete" unless valid
        video_path = File.realpath(payload.fetch("video_path"))
        relative_video = Pathname.new(video_path)
          .relative_path_from(Pathname.new(@run_root)).to_s
        unless relative_video.start_with?("app_previews/") &&
               File.file?(video_path) && !File.symlink?(video_path)
          raise AdoptionError, "system-overlay report targets a foreign preview"
        end
        observed_hashes << payload.fetch("video_sha256")
        semantic_records << {
          "report" => File.basename(path),
          "video" => relative_video,
          "video_sha256" => payload.fetch("video_sha256"),
          "expected_frame_count" => payload.fetch("expected_frame_count"),
          "scanned_frame_count" => payload.fetch("scanned_frame_count"),
          "frame_rate" => payload.fetch("frame_rate"),
          "top_band" => payload.fetch("top_band"),
          "violation_count" => payload.fetch("violation_count"),
          "violation_spans" => payload.fetch("violation_spans"),
          "violating_frames" => payload.fetch("violating_frames")
        }
        payload.fetch("scanned_frame_count")
      rescue Errno::ENOENT, ArgumentError, JSON::ParserError => error
        raise AdoptionError, "invalid system-overlay report: #{error.message}"
      end
      unless observed_hashes.sort == preview_hashes.sort && scanned_frames == 4_320 &&
             previews.fetch("count") == 6
        raise AdoptionError, "system-overlay evidence does not cover the exact six previews"
      end
      {
        "reports" => paths.length,
        "scanned_frames" => scanned_frames,
        "violation_count" => 0,
        "semantic_sha256" => Digest::SHA256.hexdigest(
          NovaStationPinballMediaAdoption.canonical_bytes(semantic_records)
        )
      }
    end

    def human_review_payload!(contract)
      path = File.join(@run_root, "logs", "human-review", "review.md")
      root = File.dirname(path)
      observed = Dir.glob(File.join(root, "**", "*"))
        .select { |entry| File.file?(entry) && !File.symlink?(entry) }
        .map do |entry|
          Pathname.new(entry).relative_path_from(Pathname.new(root)).to_s
        end.sort
      unless observed == HUMAN_REVIEW_PATHS
        raise AdoptionError,
              "human review must contain the exact review and 18 canonical contact sheets"
      end
      payload = NovaStationPinballMediaAdoption.tree_payload!(
        root, extensions: %w[.md .png],
        expected_count: HUMAN_REVIEW_PATHS.length
      )
      text = File.read(path, encoding: "UTF-8")
      expected = [
        "- Run: `#{contract.fetch('release_run_id')}`",
        "- Source fingerprint: `#{contract.fetch('source_revision')}`",
        "- Verdict: **PASS**"
      ]
      unless expected.all? { |line| text.lines.map(&:strip).include?(line) }
        raise AdoptionError, "human media review is missing the exact PASS identity"
      end
      payload.merge("verdict" => "PASS")
    end

    def write_once!(document)
      if File.exist?(@output_path) || File.symlink?(@output_path)
        unless File.file?(@output_path) && !File.symlink?(@output_path) &&
               JSON.parse(File.binread(@output_path)) == document
          raise AdoptionError, "immutable media adoption receipt changed"
        end
        File.chmod(0o600, @output_path)
        return
      end

      directory = File.dirname(@output_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      raise AdoptionError, "adoption receipt directory may not be a symlink" if File.symlink?(directory)
      temporary = File.join(
        directory,
        ".#{File.basename(@output_path)}.tmp-#{Process.pid}-#{SecureRandom.hex(6)}"
      )
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(document) + "\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, @output_path)
      File.chmod(0o600, @output_path)
    rescue JSON::ParserError => error
      raise AdoptionError, "invalid existing adoption receipt: #{error.message}"
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end
  end

  module CLI
    module_function

    def run(argv)
      options = {}
      OptionParser.new do |flags|
        flags.banner = "Usage: adopt_media.rb --repo-root PATH --run-root PATH --contract PATH --candidate-id SHA256 --output PATH"
        flags.on("--repo-root PATH") { |value| options[:repo_root] = value }
        flags.on("--run-root PATH") { |value| options[:run_root] = value }
        flags.on("--contract PATH") { |value| options[:contract_path] = value }
        flags.on("--candidate-id SHA256") { |value| options[:candidate_id] = value }
        flags.on("--output PATH") { |value| options[:output_path] = value }
      end.parse!(argv)
      required = %i[repo_root run_root contract_path candidate_id output_path]
      missing = required.reject { |key| options.key?(key) }
      raise AdoptionError, "missing adoption arguments: #{missing.join(', ')}" unless missing.empty?

      receipt = Contract.new(**options).validate!
      puts "media_adoption: OK (#{receipt.dig('media', 'screenshots', 'count')} screenshots, #{receipt.dig('media', 'previews', 'count')} previews)"
      0
    rescue AdoptionError, OptionParser::ParseError => error
      warn "media_adoption: #{error.message}"
      1
    end
  end
end

exit NovaStationPinballMediaAdoption::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
