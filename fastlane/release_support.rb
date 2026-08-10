# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"

module NovaStationPinballReleaseSupport
  KINDS = %w[
    metadata screenshots previews ipa select_build submit_review
  ].freeze

  class AmbiguousTransport < StandardError
    attr_reader :kind, :error_class

    def initialize(kind, error)
      @kind = kind
      @error_class = error.class.name
      super("#{kind} transport returned ambiguously after its intent was recorded")
    end
  end

  module_function

  def transport_once!(intent_path:, receipt_path:, kind:, candidate_id:, version:, payload:)
    intent = proof_document(
      phase: "intent", kind: kind, candidate_id: candidate_id,
      version: version, payload: payload
    )
    receipt = intent.merge("phase" => "observed")
    if File.exist?(receipt_path) || File.symlink?(receipt_path)
      read_exact!(intent_path, intent)
      read_exact!(receipt_path, receipt)
      return :observed
    end

    created = write_once!(intent_path, intent)
    unless created
      read_exact!(intent_path, intent)
      return :get_only
    end

    begin
      yield
    rescue StandardError => error
      raise AmbiguousTransport.new(kind, error)
    end
    :transported
  end

  def mark_observed!(intent_path:, receipt_path:, kind:, candidate_id:, version:, payload:)
    intent = proof_document(
      phase: "intent", kind: kind, candidate_id: candidate_id,
      version: version, payload: payload
    )
    receipt = intent.merge("phase" => "observed")
    read_exact!(intent_path, intent)
    created = write_once!(receipt_path, receipt)
    read_exact!(receipt_path, receipt) unless created
    receipt
  end

  def write_target_build_once!(path:, version:, build:)
    target = target_document(version: version, build: build)
    created = write_once!(path, target)
    read_exact!(path, target) unless created
    target
  end

  def read_target_build!(path:, version:)
    unless File.file?(path) && !File.symlink?(path)
      raise ArgumentError, "Missing regular target build receipt: #{path}"
    end
    document = JSON.parse(File.binread(path))
    expected_version = version.to_s.strip
    unless document.instance_of?(Hash) && document.keys.sort == %w[build version] &&
           document["version"] == expected_version &&
           document["build"].to_s.match?(/\A[1-9][0-9]*\z/)
      raise ArgumentError, "Target build receipt does not match version #{expected_version}"
    end
    { "version" => document.fetch("version"), "build" => document.fetch("build").to_s }
  rescue JSON::ParserError => error
    raise ArgumentError, "Invalid target build receipt: #{error.message}"
  end

  def tree_payload!(path:, extensions:, expected_count:)
    root = File.expand_path(path)
    unless File.directory?(root) && !File.symlink?(root)
      raise ArgumentError, "Missing regular media directory: #{root}"
    end
    extensions = extensions.map(&:downcase).uniq.sort
    unless extensions.all? { |extension| extension.match?(/\A\.[a-z0-9]+\z/) }
      raise ArgumentError, "Invalid media extension contract"
    end
    unless expected_count.instance_of?(Integer) && expected_count.positive?
      raise ArgumentError, "Expected media count must be positive"
    end

    entries = Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).reject do |candidate|
      %w[. ..].include?(File.basename(candidate)) || File.directory?(candidate)
    end.sort
    symlink = entries.find { |candidate| File.symlink?(candidate) }
    raise ArgumentError, "Media tree contains a symbolic link" if symlink
    files = entries.select { |candidate| File.file?(candidate) }
    foreign = files.reject { |candidate| extensions.include?(File.extname(candidate).downcase) }
    unless foreign.empty?
      raise ArgumentError, "Media tree contains a foreign file: #{foreign.first}"
    end
    unless files.length == expected_count
      raise ArgumentError, "Media tree has #{files.length} files, expected #{expected_count}"
    end

    records = files.map do |candidate|
      relative = Pathname.new(candidate).relative_path_from(Pathname.new(root)).to_s
      "#{relative}\0#{Digest::SHA256.file(candidate).hexdigest}"
    end
    {
      "count" => files.length,
      "sha256" => Digest::SHA256.hexdigest(records.join("\n"))
    }
  end

  def file_payload!(path:, expected_sha256: nil)
    expanded = File.expand_path(path)
    unless File.file?(expanded) && !File.symlink?(expanded)
      raise ArgumentError, "Missing regular release file: #{expanded}"
    end
    digest = Digest::SHA256.file(expanded).hexdigest
    expected = expected_sha256.to_s.strip.downcase
    if !expected.empty? && (!expected.match?(/\A[0-9a-f]{64}\z/) || expected != digest)
      raise ArgumentError, "Release file SHA-256 does not match the verified checkpoint"
    end
    { "count" => 1, "sha256" => digest }
  end

  def candidate_id!(value)
    normalized = value.to_s.strip.downcase
    unless normalized.match?(/\A[0-9a-f]{64}\z/)
      raise ArgumentError, "APPS_FACTORY_CANDIDATE_ID must be an exact SHA-256"
    end
    normalized
  end

  def run_id!(value)
    normalized = value.to_s.strip
    unless normalized.match?(/\A[0-9A-Za-z][0-9A-Za-z._-]{2,127}\z/)
      raise ArgumentError, "Release run id is invalid"
    end
    normalized
  end

  def proof_document(phase:, kind:, candidate_id:, version:, payload:)
    unless KINDS.include?(kind)
      raise ArgumentError, "Unsupported mutation proof kind: #{kind.inspect}"
    end
    normalized_version = version.to_s.strip
    raise ArgumentError, "Release version is required" if normalized_version.empty?
    unless payload.instance_of?(Hash) && !payload.empty? &&
           payload.keys.all? { |key| key.instance_of?(String) }
      raise ArgumentError, "Mutation payload identity must be a non-empty object"
    end
    {
      "schema_version" => 1,
      "phase" => phase,
      "kind" => kind,
      "candidate_id" => candidate_id!(candidate_id),
      "version" => normalized_version,
      "payload" => canonical(payload)
    }
  end
  private_class_method :proof_document

  def target_document(version:, build:)
    normalized_version = version.to_s.strip
    normalized_build = build.to_s.strip
    raise ArgumentError, "Target version is required" if normalized_version.empty?
    unless normalized_build.match?(/\A[1-9][0-9]*\z/)
      raise ArgumentError, "Target build must be a positive integer"
    end
    { "version" => normalized_version, "build" => normalized_build }
  end
  private_class_method :target_document

  def write_once!(path, document)
    expanded = File.expand_path(path)
    raise ArgumentError, "Proof path must not be a symlink" if File.symlink?(expanded)
    directory = File.dirname(expanded)
    FileUtils.mkdir_p(directory, mode: 0o700)
    raise ArgumentError, "Proof directory must not be a symlink" if File.symlink?(directory)
    File.open(expanded, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(JSON.pretty_generate(document) + "\n")
      file.flush
      file.fsync
    end
    true
  rescue Errno::EEXIST
    false
  end
  private_class_method :write_once!

  def read_exact!(path, expected)
    expanded = File.expand_path(path)
    unless File.file?(expanded) && !File.symlink?(expanded)
      raise ArgumentError, "Missing regular mutation proof: #{expanded}"
    end
    actual = JSON.parse(File.binread(expanded))
    unless actual == expected
      raise ArgumentError, "Mutation proof identity differs from this release candidate"
    end
    actual
  rescue JSON::ParserError => error
    raise ArgumentError, "Invalid mutation proof: #{error.message}"
  end
  private_class_method :read_exact!

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
  private_class_method :canonical
end
