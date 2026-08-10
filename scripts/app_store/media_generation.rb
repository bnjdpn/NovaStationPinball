# frozen_string_literal: true

require "digest"
require "cfpropertylist"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "time"
require_relative "media_contract"

module NovaStationPinballMediaGeneration
  APP_ROOT = File.expand_path("../..", __dir__)
  UUID_PATTERN = /\A[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\z/i
  IDENTIFIER_PATTERN = /\A[a-z0-9][a-z0-9._-]{0,79}\z/
  REQUIRED_RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
  REQUIRED_DEVICE_TYPES = {
    "iphone-17-pro-max" => ["iphone", "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"],
    "iphone-se-3" => ["iphone", "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"],
    "ipad-pro-13-m5" => ["ipad", "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"]
  }.freeze

  class SystemRunner
    def capture(*arguments, chdir: nil)
      return Open3.capture3(*arguments) unless chdir

      Open3.capture3(*arguments, chdir: chdir)
    end
  end

  class XCTestRunConfigurator
    HANDSHAKE_KEY = "NOVA_MEDIA_HANDSHAKE_TOKEN"
    LOCALE_KEY = "NOVA_MEDIA_LOCALE"

    def find!(derived_data:)
      products = File.join(File.expand_path(derived_data), "Build", "Products")
      candidates = Dir.glob(File.join(products, "**", "*.xctestrun")).select do |path|
        File.file?(path) && !File.symlink?(path)
      end
      unless candidates.length == 1
        raise NovaStationPinballMediaContract::ContractError,
              "build-for-testing must produce exactly one regular xctestrun; found #{candidates.length}"
      end
      candidates.first
    end

    def inject_environment!(source:, destination:, isolation_root:, target_name:, environment:)
      source = File.expand_path(source)
      destination = File.expand_path(destination)
      isolation_root = File.expand_path(isolation_root)
      unless File.file?(source) && !File.symlink?(source)
        raise NovaStationPinballMediaContract::ContractError,
              "xctestrun source must be a regular non-symlink file"
      end
      validate_environment!(environment)
      payload = CFPropertyList.native_types(CFPropertyList::List.new(file: source).value)
      unless payload.is_a?(Hash)
        raise NovaStationPinballMediaContract::ContractError, "xctestrun root must be a dictionary"
      end
      payload = replace_testroot(payload, File.dirname(source))
      targets = test_targets(payload, target_name)
      unless targets.length == 1
        raise NovaStationPinballMediaContract::ContractError,
              "xctestrun must contain exactly one #{target_name} target; found #{targets.length}"
      end
      target = targets.first
      inject_dictionary!(target, "EnvironmentVariables", environment)
      inject_dictionary!(target, "TestingEnvironmentVariables", environment)
      inject_dictionary!(target, "EnvironmentVariablesEnabled", environment.transform_values { true })

      ensure_safe_destination!(destination, isolation_root)
      FileUtils.mkdir_p(File.dirname(destination), mode: 0o700)
      temporary = "#{destination}.tmp-#{Process.pid}-#{Thread.current.object_id}"
      list = CFPropertyList::List.new
      list.value = CFPropertyList.guess(payload)
      list.save(temporary, CFPropertyList::List::FORMAT_XML)
      File.chmod(0o600, temporary)
      File.rename(temporary, destination)
      destination
    rescue NovaStationPinballMediaContract::ContractError
      raise
    rescue StandardError => error
      raise NovaStationPinballMediaContract::ContractError, "invalid xctestrun: #{error.message}"
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    private

    def validate_environment!(environment)
      unless environment.is_a?(Hash) && environment.keys == [HANDSHAKE_KEY, LOCALE_KEY] &&
             environment.fetch(HANDSHAKE_KEY).to_s.match?(/\A[0-9a-f]{32}\z/) &&
             NovaStationPinballMediaContract::LOCALES.include?(environment.fetch(LOCALE_KEY))
        raise NovaStationPinballMediaContract::ContractError,
              "xctestrun environment must contain only a valid App Preview handshake token and locale"
      end
    end

    def replace_testroot(value, test_root)
      case value
      when String then value.gsub("__TESTROOT__", test_root)
      when Array then value.map { |item| replace_testroot(item, test_root) }
      when Hash then value.to_h { |key, item| [key, replace_testroot(item, test_root)] }
      else value
      end
    end

    def test_targets(payload, target_name)
      configurations = payload["TestConfigurations"]
      candidates = if configurations.is_a?(Array)
        configurations.flat_map do |configuration|
          configuration.is_a?(Hash) && configuration["TestTargets"].is_a?(Array) ?
            configuration["TestTargets"] : []
        end
      else
        payload.reject { |key, _value| key == "__xctestrun_metadata__" }.values
      end
      candidates.select do |target|
        target.is_a?(Hash) &&
          (target["BlueprintName"] == target_name ||
           File.basename(target["TestBundlePath"].to_s).include?(target_name))
      end
    end

    def inject_dictionary!(target, key, values)
      current = target[key]
      current = target[key] = {} if current.nil?
      unless current.is_a?(Hash)
        raise NovaStationPinballMediaContract::ContractError, "xctestrun #{key} must be a dictionary"
      end
      current.update(values)
    end

    def ensure_safe_destination!(destination, isolation_root)
      unless destination.start_with?("#{isolation_root}/")
        raise NovaStationPinballMediaContract::ContractError,
              "xctestrun copy must stay inside its execution scratch"
      end
      relative = Pathname.new(destination).relative_path_from(Pathname.new(isolation_root))
      current = isolation_root
      [".", *relative.each_filename.to_a[0...-1]].each do |component|
        current = File.join(current, component) unless component == "."
        if (File.exist?(current) || File.symlink?(current)) && File.symlink?(current)
          raise NovaStationPinballMediaContract::ContractError, "xctestrun destination traverses a symlink"
        end
      end
      if File.symlink?(destination)
        raise NovaStationPinballMediaContract::ContractError, "xctestrun destination must not be a symlink"
      end
    end
  end

  class Configuration
    attr_reader :locales, :udids, :execution_id

    def initialize(locales:, execution_id:, pool_config_path:, lease_paths:)
      @locales = locales
      @execution_id = execution_id
      @pool_config_path = File.expand_path(pool_config_path.to_s)
      @lease_paths = lease_paths
      @lease_documents = {}
      @pool = nil
      @udids = {}
      validate!
    end

    def validate!
      unless locales.is_a?(Array) && locales.length.between?(1, 2) && locales.uniq == locales &&
             (locales - NovaStationPinballMediaContract::LOCALES).empty?
        raise NovaStationPinballMediaContract::ContractError,
              "media generation requires one or two distinct configured locales"
      end
      unless execution_id.is_a?(String) && execution_id.match?(IDENTIFIER_PATTERN)
        raise NovaStationPinballMediaContract::ContractError, "invalid media execution id"
      end
      load_owned_pool!
      self
    end

    def locale_batches
      locales.each_slice(2).to_a
    end

    def xcodebuild_arguments(kind:, locale:, device:, run_root:)
      assert_owned!
      validate_selection!(locale, device)
      suite = case kind
              when :screenshots then "StoreScreenshotUITests"
              when :app_previews then "AppPreviewUITests"
              else raise NovaStationPinballMediaContract::ContractError, "unknown media generation kind: #{kind}"
              end
      scratch = scratch_root(run_root, locale, device, kind)
      FileUtils.mkdir_p(File.join(scratch, "xcresult"))
      [
        "xcodebuild", "test",
        "-scheme", "NovaStationPinball",
        "-destination", "platform=iOS Simulator,id=#{udids.fetch(device)}",
        "-derivedDataPath", File.join(scratch, "DerivedData"),
        "-resultBundlePath", File.join(scratch, "xcresult", "#{suite}.xcresult"),
        "-parallel-testing-enabled", "NO",
        "-maximum-parallel-testing-workers", "1",
        "-maximum-concurrent-test-simulator-destinations", "1",
        "-testLanguage", locale.split("-", 2).first,
        "-testRegion", locale.split("-", 2).last,
        "-only-testing:NovaStationPinballUITests/#{suite}"
      ]
    end

    def build_for_testing_arguments(kind:, device:, run_root:)
      assert_owned!
      validate_device!(device)
      suite = suite_for(kind)
      scratch = canonical_scratch_root(run_root, device, kind)
      FileUtils.mkdir_p(File.join(scratch, "xcresult"))
      [
        "xcodebuild",
        "-scheme", "NovaStationPinball",
        "-destination", "generic/platform=iOS Simulator",
        "-derivedDataPath", File.join(scratch, "DerivedData"),
        "-resultBundlePath", File.join(scratch, "xcresult", "#{suite}-build-for-testing.xcresult"),
        "-parallel-testing-enabled", "NO",
        "-maximum-parallel-testing-workers", "1",
        "-maximum-concurrent-test-simulator-destinations", "1",
        "-only-testing:NovaStationPinballUITests/#{suite}",
        "CODE_SIGNING_ALLOWED=NO", "COMPILER_INDEX_STORE_ENABLE=NO",
        "build-for-testing"
      ]
    end

    def test_without_building_arguments(kind:, locale:, device:, run_root:, xctestrun:)
      assert_owned!
      validate_selection!(locale, device)
      suite = suite_for(kind)
      scratch = scratch_root(run_root, locale, device, kind)
      canonical_derived_data = File.join(canonical_scratch_root(run_root, device, kind), "DerivedData")
      [
        "xcodebuild", "test-without-building",
        "-xctestrun", File.expand_path(xctestrun),
        "-destination", "platform=iOS Simulator,id=#{udids.fetch(device)}",
        "-derivedDataPath", canonical_derived_data,
        "-resultBundlePath", File.join(scratch, "xcresult", "#{suite}.xcresult"),
        "-parallel-testing-enabled", "NO",
        "-maximum-parallel-testing-workers", "1",
        "-maximum-concurrent-test-simulator-destinations", "1",
        "-testLanguage", locale.split("-", 2).first,
        "-testRegion", locale.split("-", 2).last,
        "-only-testing:NovaStationPinballUITests/#{suite}"
      ]
    end

    def scratch_root(run_root, locale, device, kind)
      validate_selection!(locale, device)
      File.join(
        "/private/tmp/apps-factory/NovaStationPinball",
        execution_id, kind.to_s, locale, device
      )
    end

    def canonical_scratch_root(run_root, device, kind)
      validate_device!(device)
      suite_for(kind)
      File.join(
        "/private/tmp/apps-factory/NovaStationPinball",
        execution_id, kind.to_s, "canonical", device
      )
    end

    def assert_owned!
      @lease_documents.each do |media_id, expected|
        path = @lease_paths.fetch(media_id)
        current = read_regular_json!(path, "simulator lease")
        unless current == expected
          raise NovaStationPinballMediaContract::ContractError, "simulator lease ownership changed for #{media_id}"
        end
      end
      true
    end

    private

    def suite_for(kind)
      case kind
      when :screenshots then "StoreScreenshotUITests"
      when :app_previews then "AppPreviewUITests"
      else raise NovaStationPinballMediaContract::ContractError, "unknown media generation kind: #{kind}"
      end
    end

    def load_owned_pool!
      @pool = read_regular_json!(@pool_config_path, "simulator pool config")
      unless @pool.is_a?(Hash) && @pool["schema_version"] == 1 && @pool["devices"].is_a?(Array) &&
             @pool["lock_root"].is_a?(String) && File.expand_path(@pool["lock_root"]) == @pool["lock_root"]
        raise NovaStationPinballMediaContract::ContractError, "simulator pool config is invalid"
      end
      lock_root = @pool.fetch("lock_root")
      raise NovaStationPinballMediaContract::ContractError, "simulator lock root is unsafe" if File.symlink?(lock_root)
      unless @lease_paths.is_a?(Hash) && @lease_paths.keys.sort == REQUIRED_DEVICE_TYPES.keys.sort
        raise NovaStationPinballMediaContract::ContractError, "an exact pool lease is required for every media device"
      end

      REQUIRED_DEVICE_TYPES.each do |media_id, (role, device_type)|
        device = @pool.fetch("devices").find { |candidate| candidate["media_id"] == media_id }
        unless device && device["role"] == role && device["device_type"] == device_type &&
               device["runtime"] == REQUIRED_RUNTIME && device["udid"].to_s.match?(UUID_PATTERN)
          raise NovaStationPinballMediaContract::ContractError,
                "pool device #{media_id} must match its exact model and iOS 26.2 runtime"
        end
        lease_path = File.expand_path(@lease_paths.fetch(media_id).to_s)
        expected_lease_path = File.join(lock_root, "#{device.fetch('id')}.lock")
        unless lease_path == expected_lease_path
          raise NovaStationPinballMediaContract::ContractError, "lease path is not the fixed-pool lock for #{media_id}"
        end
        lease = read_regular_json!(lease_path, "simulator lease")
        validate_lease!(lease, device, media_id)
        @lease_documents[media_id] = lease.freeze
        @lease_paths[media_id] = lease_path
        @udids[media_id] = device.fetch("udid").upcase
      end
      unless @udids.values.uniq.length == REQUIRED_DEVICE_TYPES.length
        raise NovaStationPinballMediaContract::ContractError, "each media device must have a distinct owned UDID"
      end
      @udids.freeze
    end

    def validate_lease!(lease, device, media_id)
      expected_keys = %w[app device_id execution_id pid schema_version started_at token udid]
      unless lease.is_a?(Hash) && lease.keys.sort == expected_keys && lease["schema_version"] == 1 &&
             lease["device_id"] == device["id"] && lease["udid"].to_s.casecmp?(device["udid"].to_s) &&
             lease["app"] == "nova-station-pinball" && lease["execution_id"] == execution_id &&
             lease["pid"].is_a?(Integer) && lease["pid"].positive? && lease["token"].to_s.match?(/\A[0-9a-f]{32}\z/)
        raise NovaStationPinballMediaContract::ContractError, "simulator lease is not owned by this execution for #{media_id}"
      end
      Time.iso8601(lease.fetch("started_at"))
      Process.kill(0, lease.fetch("pid"))
    rescue ArgumentError, Errno::ESRCH, Errno::EPERM
      raise NovaStationPinballMediaContract::ContractError, "simulator lease owner is not live for #{media_id}"
    end

    def read_regular_json!(path, label)
      expanded = File.expand_path(path.to_s)
      unless File.file?(expanded) && !File.symlink?(expanded)
        raise NovaStationPinballMediaContract::ContractError, "#{label} must be a regular non-symlink file"
      end
      JSON.parse(File.binread(expanded))
    rescue JSON::ParserError => error
      raise NovaStationPinballMediaContract::ContractError, "invalid #{label} JSON: #{error.message}"
    end

    def validate_selection!(locale, device)
      raise NovaStationPinballMediaContract::ContractError, "locale is not selected: #{locale}" unless locales.include?(locale)
      validate_device!(device)
    end

    def validate_device!(device)
      raise NovaStationPinballMediaContract::ContractError, "unknown media device: #{device}" unless udids.key?(device)
    end
  end

  class ManifestStore
    def initialize(run_root:, source_revision:)
      @run_root = File.expand_path(run_root)
      @source_revision = source_revision
      @path = File.join(@run_root, NovaStationPinballMediaContract::MANIFEST_PATH)
    end

    def prepare_or_load!
      if File.file?(@path)
        manifest = JSON.parse(File.read(@path, encoding: "UTF-8"))
        unless manifest["source_revision"] == @source_revision
          raise NovaStationPinballMediaContract::ContractError,
                "existing media run is stale; use a new run id"
        end
        manifest
      else
        NovaStationPinballMediaContract::ManifestBuilder.new(
          run_root: @run_root,
          source_revision: @source_revision
        ).prepare!
      end
    end

    def update!
      FileUtils.mkdir_p(File.dirname(@path))
      File.open("#{@path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        manifest = prepare_or_load!
        yield manifest
        temporary = "#{@path}.tmp-#{Process.pid}-#{Thread.current.object_id}"
        File.write(temporary, "#{JSON.pretty_generate(manifest)}\n", mode: "w", perm: 0o600)
        File.rename(temporary, @path)
      ensure
        FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
      end
    end
  end

  class GeneratorBase
    attr_reader :app_root, :run_root, :configuration, :runner, :source_revision

    def initialize(app_root:, run_id:, locales:, execution_id: nil, pool_config_path: nil, lease_paths: {},
                   prepare_only: false, runner: SystemRunner.new)
      @app_root = File.expand_path(app_root)
      validate_run_id!(run_id)
      @run_root = File.join(@app_root, "Builds", "AppStore", "NovaStationPinball", run_id)
      @configuration = unless prepare_only
        Configuration.new(
          locales: locales, execution_id: execution_id,
          pool_config_path: pool_config_path, lease_paths: lease_paths
        )
      end
      @runner = runner
      @source_revision = NovaStationPinballMediaContract::SourceFingerprint.new(@app_root).value
      @store = ManifestStore.new(run_root: @run_root, source_revision: @source_revision)
    end

    def prepare_only!
      @store.prepare_or_load!
    end

    private

    def run_xcodebuild!(arguments)
      stdout, stderr, status = runner.capture(*arguments, chdir: app_root)
      return stdout if status.success?

      raise NovaStationPinballMediaContract::ContractError,
            "media XCTest failed: #{[stdout, stderr].join("\n").strip}"
    end

    def validate_run_id!(run_id)
      unless run_id.to_s.match?(/\A[0-9A-Za-z][0-9A-Za-z._-]{0,79}\z/)
        raise NovaStationPinballMediaContract::ContractError, "invalid media run id"
      end
    end

    def mark_artifact!(locale:, device:, kind:, path:, capture_trim_offset: nil, screenshot_source_offset: nil,
                       preview_provenance: nil)
      checksum = Digest::SHA256.file(path).hexdigest
      @store.update! do |manifest|
        manifest.fetch("cells").select do |cell|
          cell["locale"] == locale && cell["device"] == device
        end.each do |cell|
          if kind == :screenshot
            next unless File.expand_path(cell.fetch("screenshot_path"), run_root) == File.expand_path(path)
            cell["screenshot_sha256"] = checksum
            cell["screenshot_source_preview_path"] = cell.fetch("preview_path")
            cell["screenshot_source_offset_seconds"] = screenshot_source_offset
            cell["screenshot_captured_at"] = Time.now.utc.iso8601(6)
          else
            unless capture_trim_offset.is_a?(Numeric) && capture_trim_offset.finite? &&
                   capture_trim_offset.positive? && capture_trim_offset <= 45.0
              raise NovaStationPinballMediaContract::ContractError,
                    "invalid measured App Preview capture trim offset"
            end
            cell["preview_sha256"] = checksum
            cell["capture_trim_offset_seconds"] = capture_trim_offset
            provenance = preview_provenance || {}
            %w[source_sha256 source_run_id width height transform udid locale handshake_sha256].each do |key|
              cell["preview_raw_#{key}"] = provenance[key]
            end
          end
          cell["status"] = "captured" if cell["screenshot_sha256"] && cell["preview_sha256"]
        end
      end
    end
  end

  module CLIOptions
    module_function

    def parse(argv, program:)
      options = {
        app_root: APP_ROOT, locales: [], lease_paths: {}, prepare_only: false
      }
      OptionParser.new do |flags|
        flags.banner = "Usage: #{program} --run-id ID [--locale LOCALE] [--execution-id ID --pool-config PATH --lease DEVICE=PATH] [--prepare-only]"
        flags.on("--app-root PATH") { |value| options[:app_root] = value }
        flags.on("--run-id ID") { |value| options[:run_id] = value }
        flags.on("--locale LOCALE") { |value| options[:locales] << value }
        flags.on("--execution-id ID") { |value| options[:execution_id] = value }
        flags.on("--pool-config PATH") { |value| options[:pool_config_path] = value }
        flags.on("--lease DEVICE=PATH") do |value|
          device, path = value.split("=", 2)
          raise OptionParser::InvalidArgument, "invalid --lease" unless device && path
          options[:lease_paths][device] = path
        end
        flags.on("--prepare-only") { options[:prepare_only] = true }
      end.parse!(argv)
      raise NovaStationPinballMediaContract::ContractError, "--run-id is required" unless options[:run_id]
      options[:locales] = NovaStationPinballMediaContract::LOCALES if options[:locales].empty?
      unless options[:prepare_only]
        %i[execution_id pool_config_path].each do |key|
          raise NovaStationPinballMediaContract::ContractError, "--#{key.to_s.tr('_', '-')} is required" if options[key].to_s.empty?
        end
      end
      options
    end
  end
end
