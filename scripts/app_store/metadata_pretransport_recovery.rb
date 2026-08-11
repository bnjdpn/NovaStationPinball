#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require_relative "../../fastlane/metadata_preflight"
require_relative "adopt_media"

module NovaStationPinballMetadataPretransportRecovery
  APP_SLUG = "NovaStationPinball"
  VERSION = "1.0"
  SHA256 = /\A[0-9a-f]{64}\z/.freeze
  COMMIT = /\A[0-9a-f]{40}\z/.freeze
  RUN_ID = /\A[0-9A-Za-z][0-9A-Za-z._-]{2,127}\z/.freeze
  RECOVERY_RELATIVE = "fastlane/metadata_pretransport_recovery.json"
  ADOPTION_RELATIVE = "fastlane/media_adoption_contract.json"
  ACTIVE_FILES = %w[
    media-adoption.json metadata-upload-intent.json release-checkpoints.json
  ].sort.freeze
  CONTRACT_KEYS = %w[
    active_files app_slug contract_self_sha256 historical_adoption_contract_sha256
    historical_candidate_id historical_head metadata_expected_sha256
    pretransport_proof release_run_id schema_version source_changes
  ].sort.freeze
  PRETRANSPORT_KEYS = %w[
    action_run_called configuration_error invalid_parameters_error proven
    wrapper_classification
  ].sort.freeze
  SOURCE_CHANGE_KEYS = %w[after_sha256 before_sha256 path].freeze
  CONFIGURATION_ERROR =
    "Error setting value './metadata/app_rating_config.json' for option 'app_rating_config_path'"
  INVALID_PARAMETERS_ERROR =
    "You passed invalid parameters to 'upload_to_app_store'."
  WRAPPER_CLASSIFICATION =
    "metadata transport returned ambiguously after its intent was recorded (FastlaneCore::Interface::FastlaneError)"

  class RecoveryError < StandardError; end

  module_function

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

  def validate_contract!(document)
    unless document.instance_of?(Hash) && document.keys.sort == CONTRACT_KEYS &&
           document["schema_version"] == 1 &&
           document["app_slug"] == APP_SLUG &&
           document["release_run_id"].to_s.match?(RUN_ID) &&
           document["historical_head"].to_s.match?(COMMIT) &&
           document["historical_candidate_id"].to_s.match?(SHA256) &&
           document["historical_adoption_contract_sha256"].to_s.match?(SHA256) &&
           document["metadata_expected_sha256"].to_s.match?(SHA256) &&
           document["contract_self_sha256"].to_s.match?(SHA256)
      raise RecoveryError, "Metadata recovery contract identity is incomplete"
    end
    unsigned = document.reject { |key, _| key == "contract_self_sha256" }
    unless Digest::SHA256.hexdigest(canonical_bytes(unsigned)) ==
           document.fetch("contract_self_sha256")
      raise RecoveryError, "Metadata recovery contract self digest changed"
    end

    files = document["active_files"]
    unless files.instance_of?(Hash) && files.keys.sort == ACTIVE_FILES &&
           files.values.all? { |value| value.to_s.match?(SHA256) }
      raise RecoveryError, "Historical active-file hashes are incomplete"
    end
    validate_pretransport_proof!(document.fetch("pretransport_proof"))
    validate_source_changes!(document.fetch("source_changes"))
    document
  end

  def validate_pretransport_proof!(proof)
    valid = proof.instance_of?(Hash) && proof.keys.sort == PRETRANSPORT_KEYS &&
      proof["proven"] == true && proof["action_run_called"] == false &&
      proof["configuration_error"] == CONFIGURATION_ERROR &&
      proof["invalid_parameters_error"] == INVALID_PARAMETERS_ERROR &&
      proof["wrapper_classification"] == WRAPPER_CLASSIFICATION
    raise RecoveryError, "Exact local pretransport failure is not proven" unless valid
    proof
  end

  def validate_source_changes!(changes)
    unless changes.instance_of?(Array) &&
           changes.all? { |item| item.instance_of?(Hash) } &&
           changes.map { |item| item["path"] } ==
             changes.map { |item| item["path"] }.sort.uniq
      raise RecoveryError, "Recovery source changes must be sorted and unique"
    end
    changes.each do |item|
      path = item["path"]
      valid = item.keys.sort == SOURCE_CHANGE_KEYS &&
        path.instance_of?(String) && !path.empty? &&
        !Pathname.new(path).absolute? && !path.split("/").include?("..") &&
        (item["before_sha256"].nil? || item["before_sha256"].to_s.match?(SHA256)) &&
        item["after_sha256"].to_s.match?(SHA256) &&
        ![RECOVERY_RELATIVE, ADOPTION_RELATIVE].include?(path)
      raise RecoveryError, "Recovery source change is not exact" unless valid
    end
    changes
  end

  def load_contract(path)
    unless File.file?(path) && !File.symlink?(path)
      raise RecoveryError, "Metadata recovery contract must be a regular file"
    end
    validate_contract!(JSON.parse(File.binread(path)))
  rescue JSON::ParserError => error
    raise RecoveryError, "Invalid metadata recovery contract: #{error.message}"
  end

  class SourceVerifier
    def initialize(app_root:, current_candidate_id:)
      @app_root = File.realpath(app_root)
      @current_candidate_id = current_candidate_id.to_s
    end

    def call(contract)
      unless @current_candidate_id.match?(SHA256) &&
             NovaStationPinballMediaAdoption.candidate_id(@app_root) ==
               @current_candidate_id
        raise RecoveryError, "Current release candidate identity is not exact"
      end
      status = git!("status", "--porcelain=v1", "--untracked-files=all")
      raise RecoveryError, "Recovery source must be committed and clean" unless status.empty?

      historical = contract.fetch("historical_head")
      resolved = git!("rev-parse", "--verify", "#{historical}^{commit}").strip
      raise RecoveryError, "Historical recovery commit is missing" unless resolved == historical
      git!("merge-base", "--is-ancestor", historical, "HEAD")
      current = git!("rev-parse", "HEAD").strip
      changes = git!("diff", "--name-only", "--no-renames", historical, current)
        .lines.map(&:strip).reject(&:empty?).sort
      expected = contract.fetch("source_changes").map { |item| item.fetch("path") }
      expected += [RECOVERY_RELATIVE, ADOPTION_RELATIVE]
      unless changes == expected.sort
        raise RecoveryError, "Recovery source drift is outside the exact patch"
      end
      contract.fetch("source_changes").each do |item|
        path = item.fetch("path")
        before = NovaStationPinballMediaAdoption.file_sha256_at_commit(
          @app_root, historical, path
        )
        after = NovaStationPinballMediaAdoption.file_sha256_at_commit(
          @app_root, current, path
        )
        unless before == item["before_sha256"] && after == item.fetch("after_sha256")
          raise RecoveryError, "Recovery source hash changed: #{path}"
        end
      end
      verify_contract_lineage!(contract, historical, current)
      true
    rescue NovaStationPinballMediaAdoption::AdoptionError => error
      raise RecoveryError, error.message
    end

    private

    def git!(*arguments)
      NovaStationPinballMediaAdoption.git!(@app_root, *arguments)
    end

    def verify_contract_lineage!(contract, historical, current)
      previous = NovaStationPinballMediaAdoption.file_sha256_at_commit(
        @app_root, historical, ADOPTION_RELATIVE
      )
      unless previous == contract.fetch("historical_adoption_contract_sha256")
        raise RecoveryError, "Historical adoption contract hash differs"
      end
      adoption = JSON.parse(File.binread(File.join(@app_root, ADOPTION_RELATIVE)))
      unless adoption["baseline_head"] == historical &&
             adoption["baseline_contract_sha256"] == previous
        raise RecoveryError, "Successive media adoption lineage is not exact"
      end
      recovery_path = File.join(@app_root, RECOVERY_RELATIVE)
      unless File.file?(recovery_path) && !File.symlink?(recovery_path) &&
             NovaStationPinballMediaAdoption.file_sha256_at_commit(
               @app_root, current, RECOVERY_RELATIVE
             ) == Digest::SHA256.file(recovery_path).hexdigest
        raise RecoveryError, "Recovery contract is not the committed current file"
      end
    rescue JSON::ParserError => error
      raise RecoveryError, "Invalid successive adoption contract: #{error.message}"
    end
  end

  class OfflinePretransportVerifier
    def initialize(app_root:, config:)
      @app_root = File.realpath(app_root)
      @config = config
    end

    def call(_contract)
      gem "fastlane", "2.237.0"
      require "fastlane"
      require "fastlane/actions/upload_to_app_store"
      action_runs = 0
      observed = nil
      begin
        Dir.chdir(@app_root) do
          configuration = FastlaneCore::Configuration.create(
            Fastlane::Actions::UploadToAppStoreAction.available_options,
            app_rating_config_path: "./metadata/app_rating_config.json"
          )
          action_runs += 1
          Fastlane::Actions::UploadToAppStoreAction.run(configuration)
        end
      rescue FastlaneCore::Interface::FastlaneError => error
        observed = error
      end
      unless action_runs.zero? && observed &&
             observed.message.include?("Could not find config file")
        raise RecoveryError, "Historical pretransport failure did not reproduce offline"
      end

      paths = NovaStationPinballMetadataPreflight.resolve!(
        root: @app_root, config: @config
      )
      configuration = Dir.chdir(@app_root) do
        FastlaneCore::Configuration.create(
          Fastlane::Actions::UploadToAppStoreAction.available_options,
          app_rating_config_path: paths.fetch(:app_rating_config_path)
        )
      end
      unless configuration[:app_rating_config_path] ==
             paths.fetch(:app_rating_config_path)
        raise RecoveryError, "Corrected absolute rating path failed offline preflight"
      end
      true
    rescue Gem::LoadError, LoadError, ArgumentError => error
      raise RecoveryError, "Offline metadata pretransport proof failed: #{error.message}"
    end
  end

  class Recovery
    def initialize(app_root:, run_id:, contract:, current_candidate_id:,
                   source_verifier: nil, pretransport_verifier: nil, config: nil)
      @app_root = File.realpath(app_root)
      @run_id = run_id.to_s
      @contract = NovaStationPinballMetadataPretransportRecovery.validate_contract!(
        contract
      )
      unless @contract.fetch("release_run_id") == @run_id
        raise RecoveryError, "Recovery contract targets another release run"
      end
      @current_candidate_id = current_candidate_id.to_s
      @source_verifier = source_verifier || SourceVerifier.new(
        app_root: @app_root, current_candidate_id: @current_candidate_id
      )
      @pretransport_verifier = pretransport_verifier ||
        OfflinePretransportVerifier.new(app_root: @app_root, config: config)
      @logs = safe_logs_path!
      @archive_root = File.join(@logs, "recovery", "metadata-pretransport-v1")
    end

    def recover!(status_reader:)
      existing = existing_receipt
      if existing
        verify_archives!
        cleanup_active!
        return existing.merge("state" => "already_recovered")
      end

      @source_verifier.call(@contract)
      @pretransport_verifier.call(@contract)
      verify_historical_active!
      status = status_reader.call
      summary = validate_fresh_incomplete_status!(status)
      archive_active!
      write_json_once!(File.join(@archive_root, "fresh-metadata-readback.json"), summary)
      receipt = recovery_receipt(summary)
      write_json_once!(receipt_path, receipt)
      verify_archives!
      cleanup_active!
      receipt
    end

    private

    def safe_logs_path!
      root = File.join(
        @app_root, "Builds", "AppStore", APP_SLUG, @run_id, "logs"
      )
      expected = File.join(@app_root, "Builds", "AppStore", APP_SLUG)
      unless root.start_with?("#{expected}#{File::SEPARATOR}") &&
             File.directory?(root) && !File.symlink?(root)
        raise RecoveryError, "Historical release log root is missing or unsafe"
      end
      root
    end

    def active_path(name)
      File.join(@logs, name)
    end

    def archive_path(name)
      File.join(@archive_root, name)
    end

    def receipt_path
      File.join(@archive_root, "recovery-receipt.json")
    end

    def verify_historical_active!
      expected = @contract.fetch("active_files")
      ACTIVE_FILES.each do |name|
        path = active_path(name)
        unless File.file?(path) && !File.symlink?(path) &&
               Digest::SHA256.file(path).hexdigest == expected.fetch(name)
          raise RecoveryError, "Historical active proof differs: #{name}"
        end
      end
      verify_intent!(JSON.parse(File.binread(active_path("metadata-upload-intent.json"))))
      verify_checkpoints!(JSON.parse(File.binread(active_path("release-checkpoints.json"))))
      verify_adoption!(JSON.parse(File.binread(active_path("media-adoption.json"))))
    rescue JSON::ParserError, KeyError => error
      raise RecoveryError, "Historical proof is invalid: #{error.message}"
    end

    def verify_intent!(intent)
      valid = intent.instance_of?(Hash) && intent["schema_version"] == 1 &&
        intent["phase"] == "intent" && intent["kind"] == "metadata" &&
        intent["candidate_id"] == @contract.fetch("historical_candidate_id") &&
        intent["version"] == VERSION &&
        intent.dig("payload", "sha256") ==
          @contract.fetch("metadata_expected_sha256")
      raise RecoveryError, "Historical metadata intent identity differs" unless valid
    end

    def verify_checkpoints!(document)
      identity = document["identity"]
      metadata = document.dig("checkpoints", "metadata_upload")
      valid = document["schema_version"] == 1 &&
        identity.instance_of?(Hash) && identity["app"] == APP_SLUG &&
        identity["version"] == VERSION &&
        identity["candidate_id"] == @contract.fetch("historical_candidate_id") &&
        metadata.instance_of?(Hash) && metadata["state"] == "failed" &&
        metadata["attempts"] == 2 && metadata["evidence"].nil?
      raise RecoveryError, "Historical failed checkpoint identity differs" unless valid
    end

    def verify_adoption!(document)
      valid = document["schema_version"] == 1 &&
        document["provenance_mode"] == "adopted_from" &&
        document["app_slug"] == APP_SLUG &&
        document["release_run_id"] == @run_id &&
        document["source_candidate_id"] ==
          @contract.fetch("historical_candidate_id")
      raise RecoveryError, "Historical adoption receipt identity differs" unless valid
    end

    def validate_fresh_incomplete_status!(status)
      metadata = status.is_a?(Hash) ? status["metadata"] : nil
      expected = @contract.fetch("metadata_expected_sha256")
      valid = metadata.instance_of?(Hash) && metadata["complete"] == false &&
        metadata["expected_sha256"] == expected &&
        metadata["actual_sha256"].to_s.match?(SHA256) &&
        metadata["actual_sha256"] != expected
      unless valid
        raise RecoveryError,
              "Fresh GET does not prove that historical metadata was not uploaded"
      end
      {
        "schema_version" => 1,
        "release_run_id" => @run_id,
        "metadata_complete" => false,
        "expected_sha256" => expected,
        "actual_sha256" => metadata.fetch("actual_sha256")
      }
    end

    def archive_active!
      FileUtils.mkdir_p(@archive_root, mode: 0o700)
      raise RecoveryError, "Recovery archive root is a symbolic link" if
        File.symlink?(@archive_root)
      ACTIVE_FILES.each do |name|
        source = active_path(name)
        expected = @contract.dig("active_files", name)
        bytes = File.binread(source)
        unless Digest::SHA256.hexdigest(bytes) == expected
          raise RecoveryError, "Historical proof changed during archive: #{name}"
        end
        write_bytes_once!(archive_path(name), bytes)
      end
    end

    def verify_archives!
      ACTIVE_FILES.each do |name|
        path = archive_path(name)
        unless File.file?(path) && !File.symlink?(path) &&
               Digest::SHA256.file(path).hexdigest ==
                 @contract.dig("active_files", name) &&
               (File.stat(path).mode & 0o777) == 0o600
          raise RecoveryError, "Immutable recovery archive differs: #{name}"
        end
      end
      true
    end

    def cleanup_active!
      ACTIVE_FILES.each do |name|
        path = active_path(name)
        next unless File.exist?(path) || File.symlink?(path)
        unless File.file?(path) && !File.symlink?(path) &&
               Digest::SHA256.file(path).hexdigest ==
                 @contract.dig("active_files", name)
          raise RecoveryError, "Active proof changed before cleanup: #{name}"
        end
        File.unlink(path)
      end
    end

    def recovery_receipt(summary)
      {
        "schema_version" => 1,
        "state" => "recovered",
        "app_slug" => APP_SLUG,
        "release_run_id" => @run_id,
        "historical_head" => @contract.fetch("historical_head"),
        "historical_candidate_id" =>
          @contract.fetch("historical_candidate_id"),
        "current_candidate_id" => @current_candidate_id,
        "archived_files" => @contract.fetch("active_files"),
        "fresh_metadata_readback_sha256" => Digest::SHA256.hexdigest(
          NovaStationPinballMetadataPretransportRecovery.canonical_bytes(summary)
        )
      }
    end

    def existing_receipt
      return nil unless File.exist?(receipt_path) || File.symlink?(receipt_path)
      unless File.file?(receipt_path) && !File.symlink?(receipt_path)
        raise RecoveryError, "Recovery receipt is not a regular file"
      end
      actual = JSON.parse(File.binread(receipt_path))
      summary_path = File.join(@archive_root, "fresh-metadata-readback.json")
      summary = JSON.parse(File.binread(summary_path))
      expected = recovery_receipt(summary)
      unless actual == expected && (File.stat(receipt_path).mode & 0o777) == 0o600
        raise RecoveryError, "Immutable recovery receipt differs"
      end
      actual
    rescue JSON::ParserError, Errno::ENOENT => error
      raise RecoveryError, "Invalid recovery receipt: #{error.message}"
    end

    def write_json_once!(path, document)
      write_bytes_once!(path, JSON.pretty_generate(document) + "\n")
    end

    def write_bytes_once!(path, bytes)
      if File.exist?(path) || File.symlink?(path)
        unless File.file?(path) && !File.symlink?(path) &&
               File.binread(path) == bytes
          raise RecoveryError, "Immutable recovery file differs: #{File.basename(path)}"
        end
        File.chmod(0o600, path)
        return false
      end
      FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(bytes)
        file.flush
        file.fsync
      end
      File.chmod(0o600, path)
      true
    rescue Errno::EEXIST
      retry
    end
  end

  module CLI
    module_function

    def run(argv)
      options = {
        app_root: File.expand_path("../..", __dir__),
        config: File.expand_path("../../fastlane/release_config.json", __dir__),
        contract: File.expand_path("../../#{RECOVERY_RELATIVE}", __dir__),
        key_path: ENV["ASC_API_KEY_PATH"]
      }
      OptionParser.new do |flags|
        flags.on("--app-root PATH") { |value| options[:app_root] = value }
        flags.on("--run-id ID") { |value| options[:run_id] = value }
        flags.on("--config PATH") { |value| options[:config] = value }
        flags.on("--contract PATH") { |value| options[:contract] = value }
        flags.on("--key-path PATH") { |value| options[:key_path] = value }
      end.parse!(argv)
      config = JSON.parse(File.binread(options.fetch(:config)))
      contract = NovaStationPinballMetadataPretransportRecovery.load_contract(
        options.fetch(:contract)
      )
      run_id = options.fetch(:run_id)
      require_relative "status"
      unless NovaStationPinballAscCredentials.available?(key_path: options[:key_path])
        raise RecoveryError, "ASC key is required for the fresh GET-only proof"
      end
      candidate = NovaStationPinballMediaAdoption.candidate_id(options.fetch(:app_root))
      client = NovaStationPinballAscClient.new(key_path: options[:key_path])
      recovery = Recovery.new(
        app_root: options.fetch(:app_root), run_id: run_id,
        contract: contract, current_candidate_id: candidate, config: config
      )
      receipt = recovery.recover!(
        status_reader: -> {
          NovaStationPinballAscStatus.read(client: client, config: config)
        }
      )
      puts JSON.pretty_generate(receipt)
      0
    rescue ArgumentError, KeyError, JSON::ParserError, RecoveryError,
           NovaStationPinballAscError => error
      warn "metadata_pretransport_recovery: #{error.message}"
      1
    end
  end
end

exit NovaStationPinballMetadataPretransportRecovery::CLI.run(ARGV) if
  $PROGRAM_NAME == __FILE__
