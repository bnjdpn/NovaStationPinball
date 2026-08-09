# frozen_string_literal: true

require "cfpropertylist"
require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "reencode_app_previews"

class NovaStationPreviewReencodingTest < Minitest::Test
  SOURCE_RUN = "task12-final-v8-20260722"
  LOCALE = "en-US"
  DEVICE = "iphone-17-pro-max"
  UDID = "7E783310-B816-426A-9D63-92A8E11042A6"
  TOKEN = "c" * 32
  SCENARIOS = NovaStationPinballMediaContract::SCENARIOS

  FakeStatus = Struct.new(:value) do
    def success?
      value
    end
  end

  FakeRunner = Struct.new(:width, :height) do
    def capture(*_arguments, **_options)
      [JSON.generate("streams" => [{ "width" => width, "height" => height }]), "", FakeStatus.new(true)]
    end
  end

  def test_accepts_a_complete_source_receipt_and_returns_only_verified_provenance
    with_source do |fixture|
      receipt = load_receipt(fixture)

      assert_equal 0.309, receipt.fetch("capture_trim_offset_seconds")
      assert_equal Digest::SHA256.file(fixture.fetch(:raw)).hexdigest, receipt.fetch("source_sha256")
      assert_equal SOURCE_RUN, receipt.fetch("source_run_id")
      assert_equal UDID, receipt.fetch("udid")
      assert_equal LOCALE, receipt.fetch("locale")
      assert_equal Digest::SHA256.hexdigest(TOKEN), receipt.fetch("handshake_sha256")
      assert_equal [1_320, 2_868], receipt.values_at("width", "height")
      assert_equal "transpose=clock", receipt.fetch("source_transform")
    end
  end

  def test_rejects_a_symlinked_source_manifest
    with_source do |fixture|
      target = "#{fixture.fetch(:manifest)}.real"
      File.rename(fixture.fetch(:manifest), target)
      File.symlink(target, fixture.fetch(:manifest))

      assert_contract_error("regular non-symlink") { load_receipt(fixture) }
    end
  end

  def test_rejects_a_raw_file_swapped_after_the_source_manifest_was_written
    with_source do |fixture|
      File.binwrite(fixture.fetch(:raw), "different raw capture")

      assert_contract_error("raw source checksum") { load_receipt(fixture) }
    end
  end

  def test_rejects_the_wrong_source_locale
    with_source do |fixture|
      mutate_manifest(fixture) { |cells| cells.each { |cell| cell["preview_raw_locale"] = "fr-FR" } }

      assert_contract_error("source locale") { load_receipt(fixture) }
    end
  end

  def test_rejects_the_wrong_source_device_cell_set
    with_source do |fixture|
      mutate_manifest(fixture) { |cells| cells.each { |cell| cell["device"] = "iphone-se-3" } }

      assert_contract_error("six source preview cells") { load_receipt(fixture) }
    end
  end

  def test_rejects_the_wrong_source_run_id
    with_source do |fixture|
      mutate_manifest(fixture) { |cells| cells.each { |cell| cell["preview_raw_source_run_id"] = "foreign-run" } }

      assert_contract_error("source run id") { load_receipt(fixture) }
    end
  end

  def test_rejects_a_source_capture_udid_different_from_the_owned_device
    with_source do |fixture|
      mutate_manifest(fixture) do |cells|
        cells.each { |cell| cell["preview_raw_udid"] = "11111111-1111-1111-1111-111111111111" }
      end

      assert_contract_error("source capture UDID") { load_receipt(fixture) }
    end
  end

  def test_rejects_a_handshake_hash_different_from_the_real_xctestrun_token
    with_source do |fixture|
      mutate_manifest(fixture) { |cells| cells.each { |cell| cell["preview_raw_handshake_sha256"] = "d" * 64 } }

      assert_contract_error("handshake") { load_receipt(fixture) }
    end
  end

  def test_rejects_an_xctestrun_whose_locale_does_not_match_the_source_cells
    with_source do |fixture|
      write_xctestrun(fixture.fetch(:xctestrun), token: TOKEN, locale: "fr-FR")

      assert_contract_error("xctestrun locale") { load_receipt(fixture) }
    end
  end

  def test_rejects_a_malformed_xctestrun_without_one_ui_test_target
    with_source do |fixture|
      write_plist(fixture.fetch(:xctestrun), "TestConfigurations" => [])

      assert_contract_error("xctestrun UI target") { load_receipt(fixture) }
    end
  end

  def test_accepts_the_legacy_root_xctestrun_format_emitted_by_xcode_26
    with_source do |fixture|
      environment = { "NOVA_MEDIA_HANDSHAKE_TOKEN" => TOKEN, "NOVA_MEDIA_LOCALE" => LOCALE }
      target = {
        "BlueprintName" => "NovaStationPinballUITests",
        "TestBundlePath" => "/tmp/NovaStationPinballUITests.xctest",
        "EnvironmentVariables" => environment,
        "TestingEnvironmentVariables" => environment,
        "EnvironmentVariablesEnabled" => environment.transform_values { true }
      }
      write_plist(fixture.fetch(:xctestrun), {
        "NovaStationPinballTests" => { "BlueprintName" => "NovaStationPinballTests" },
        "NovaStationPinballUITests" => target,
        "__xctestrun_metadata__" => { "FormatVersion" => 1 }
      })

      assert_equal UDID, load_receipt(fixture).fetch("udid")
    end
  end

  def test_rejects_inconsistent_trim_offsets_across_the_six_scenarios
    with_source do |fixture|
      mutate_manifest(fixture) { |cells| cells.last["capture_trim_offset_seconds"] = 0.777 }

      assert_contract_error("trim offset") { load_receipt(fixture) }
    end
  end

  def test_rejects_inconsistent_raw_dimensions_or_source_transform
    with_source do |fixture|
      mutate_manifest(fixture) do |cells|
        cells.last["preview_raw_width"] = 750
        cells.last["preview_raw_transform"] = "transpose=cclock"
      end

      assert_contract_error("raw provenance") { load_receipt(fixture) }
    end
  end

  private

  def receipt_class
    assert defined?(NovaStationPinballPreviewReencoding::SourceReceipt),
           "missing source provenance validator"
    NovaStationPinballPreviewReencoding::SourceReceipt
  end

  def load_receipt(fixture)
    receipt_class.load!(
      manifest_path: fixture.fetch(:manifest), source_execution_id: SOURCE_RUN,
      locale: LOCALE, device_id: DEVICE, raw_path: fixture.fetch(:raw),
      xctestrun_path: fixture.fetch(:xctestrun), expected_udid: UDID,
      runner: FakeRunner.new(1_320, 2_868)
    )
  end

  def assert_contract_error(fragment)
    error = assert_raises(NovaStationPinballMediaContract::ContractError) { yield }
    assert_includes error.message, fragment
  end

  def with_source
    Dir.mktmpdir("nova-reencode-source", "/private/tmp") do |root|
      raw = File.join(root, "raw.mov")
      xctestrun = File.join(root, "NovaStationPinball-AppPreviewUITests.xctestrun")
      manifest = File.join(root, "media-manifest.json")
      File.binwrite(raw, "verified raw capture")
      write_xctestrun(xctestrun, token: TOKEN, locale: LOCALE)
      raw_sha = Digest::SHA256.file(raw).hexdigest
      handshake_sha = Digest::SHA256.hexdigest(TOKEN)
      cells = SCENARIOS.map do |scenario|
        {
          "locale" => LOCALE, "device" => DEVICE, "scenario" => scenario,
          "capture_trim_offset_seconds" => 0.309,
          "preview_raw_source_sha256" => raw_sha,
          "preview_raw_source_run_id" => SOURCE_RUN,
          "preview_raw_width" => 1_320, "preview_raw_height" => 2_868,
          "preview_raw_transform" => "transpose=clock",
          "preview_raw_udid" => UDID, "preview_raw_locale" => LOCALE,
          "preview_raw_handshake_sha256" => handshake_sha
        }
      end
      File.write(manifest, JSON.generate("cells" => cells), perm: 0o600)
      yield manifest: manifest, raw: raw, xctestrun: xctestrun
    end
  end

  def mutate_manifest(fixture)
    payload = JSON.parse(File.read(fixture.fetch(:manifest)))
    yield payload.fetch("cells")
    File.write(fixture.fetch(:manifest), JSON.generate(payload), perm: 0o600)
  end

  def write_xctestrun(path, token:, locale:)
    environment = { "NOVA_MEDIA_HANDSHAKE_TOKEN" => token, "NOVA_MEDIA_LOCALE" => locale }
    write_plist(path, {
      "TestConfigurations" => [{
        "Name" => "Test Scheme Action",
        "TestTargets" => [{
          "BlueprintName" => "NovaStationPinballUITests",
          "TestBundlePath" => "/tmp/NovaStationPinballUITests.xctest",
          "EnvironmentVariables" => environment,
          "TestingEnvironmentVariables" => environment,
          "EnvironmentVariablesEnabled" => environment.transform_values { true }
        }]
      }],
      "__xctestrun_metadata__" => { "FormatVersion" => 2 }
    })
  end

  def write_plist(path, payload)
    list = CFPropertyList::List.new
    list.value = CFPropertyList.guess(payload)
    list.save(path, CFPropertyList::List::FORMAT_XML)
  end
end
