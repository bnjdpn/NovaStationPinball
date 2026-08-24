# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "release_provenance"

class NovaStationPinballReleaseProvenanceTest < Minitest::Test
  Provenance = NovaStationPinballReleaseProvenance
  ROOT = File.expand_path("../..", __dir__)

  class AscClient
    attr_accessor :encryption, :platform, :screenshot_state,
                  :workshop_version_id, :selected_build
    attr_reader :catalogue

    def initialize(contract, app_note:, workshop_note:)
      @contract = contract
      @app_note = app_note
      @workshop_note = workshop_note
      @encryption = false
      @platform = "IOS"
      @screenshot_state = "COMPLETE"
      @workshop_version_id = contract.workshop_version_id
      @selected_build = :target
      territory_ids = %w[FRA USA]
      @catalogue = {
        "localizations" => [
          {
            "id" => "loc-en", "locale" => "en-US", "name" => "The Workshop",
            "description" => "Unlimited rewind, replay and shot drills."
          },
          {
            "id" => "loc-fr", "locale" => "fr-FR", "name" => "L’Atelier",
            "description" => "Rembobinage, revisionnage et atelier de tir."
          }
        ],
        "availability_id" => contract.workshop_iap_id,
        "territory_count" => territory_ids.length,
        "territory_ids_sha256" => Digest::SHA256.hexdigest(
          territory_ids.sort.join("\n")
        ),
        "price_schedule_id" => contract.workshop_iap_id,
        "base_territory" => "FRA", "base_currency" => "EUR",
        "manual_price_id" => "manual-price-1",
        "price_point_id" => "price-point-1", "customer_price" => "4.99"
      }
    end

    def get_all(path, _parameters = {})
      case path
      when "/v1/apps"
        { "data" => [{
          "type" => "apps", "id" => @contract.app_id,
          "attributes" => { "bundleId" => @contract.bundle_id }
        }] }
      when "/v1/builds"
        { "data" => [build_resource] }
      when "/v1/apps/#{@contract.app_id}/appStoreVersions"
        { "data" => [{
          "type" => "appStoreVersions", "id" => @contract.app_version_id,
          "attributes" => {
            "versionString" => @contract.version,
            "appStoreState" => "PREPARE_FOR_SUBMISSION",
            "appVersionState" => "PREPARE_FOR_SUBMISSION",
            "platform" => @platform
          }
        }] }
      when "/v2/inAppPurchases/#{@contract.workshop_iap_id}/versions"
        { "data" => [{
          "type" => "inAppPurchaseVersions", "id" => @workshop_version_id,
          "attributes" => {
            "version" => "1", "state" => "PREPARE_FOR_SUBMISSION"
          }
        }] }
      when "/v2/inAppPurchases/#{@contract.workshop_iap_id}/inAppPurchaseLocalizations"
        { "data" => @catalogue.fetch("localizations").map do |item|
          {
            "type" => "inAppPurchaseLocalizations", "id" => item.fetch("id"),
            "attributes" => item.reject { |key, _value| key == "id" }
          }
        end }
      when "/v1/inAppPurchaseAvailabilities/#{@contract.workshop_iap_id}/availableTerritories"
        { "data" => %w[FRA USA].map do |id|
          { "type" => "territories", "id" => id }
        end }
      when "/v1/inAppPurchasePriceSchedules/#{@contract.workshop_iap_id}/manualPrices"
        { "data" => [{
          "type" => "inAppPurchasePrices",
          "id" => @catalogue.fetch("manual_price_id"),
          "attributes" => { "startDate" => nil, "endDate" => nil },
          "relationships" => {
            "inAppPurchasePricePoint" => {
              "data" => {
                "type" => "inAppPurchasePricePoints",
                "id" => @catalogue.fetch("price_point_id")
              }
            },
            "territory" => { "data" => { "type" => "territories", "id" => "FRA" } }
          }
        }], "included" => [{
          "type" => "inAppPurchasePricePoints",
          "id" => @catalogue.fetch("price_point_id"),
          "attributes" => { "customerPrice" => "4.99" }
        }] }
      when "/v1/inAppPurchasePriceSchedules/#{@contract.workshop_iap_id}/automaticPrices"
        { "data" => [], "included" => [] }
      else
        raise "unexpected GET_ALL #{path}"
      end
    end

    def get(path, _parameters = {}, optional: false)
      case path
      when "/v1/appStoreVersions/#{@contract.app_version_id}/build"
        { "data" => @selected_build == :source ? source_build_resource : build_resource }
      when "/v1/appStoreVersions/#{@contract.app_version_id}/appStoreReviewDetail"
        { "data" => {
          "type" => "appStoreReviewDetails",
          "id" => Provenance::APP_REVIEW_DETAIL_ID,
          "attributes" => {
            "notes" => @app_note, "demoAccountRequired" => false,
            "contactFirstName" => "Review", "contactLastName" => "Contact",
            "contactPhone" => "+33000000000",
            "contactEmail" => "private@example.invalid"
          }
        } }
      when "/v2/inAppPurchases/#{@contract.workshop_iap_id}"
        { "data" => {
          "type" => "inAppPurchases", "id" => @contract.workshop_iap_id,
          "attributes" => {
            "name" => "Nova Station Pinball Workshop",
            "productId" => @contract.workshop_product_id,
            "inAppPurchaseType" => "NON_CONSUMABLE",
            "state" => "READY_TO_SUBMIT", "familySharable" => false,
            "reviewNote" => @workshop_note
          }
        } }
      when "/v2/inAppPurchases/#{@contract.workshop_iap_id}/inAppPurchaseAvailability"
        { "data" => {
          "type" => "inAppPurchaseAvailabilities",
          "id" => @catalogue.fetch("availability_id"),
          "attributes" => { "availableInNewTerritories" => true }
        } }
      when "/v2/inAppPurchases/#{@contract.workshop_iap_id}/iapPriceSchedule"
        { "data" => {
          "type" => "inAppPurchasePriceSchedules",
          "id" => @catalogue.fetch("price_schedule_id"), "attributes" => {}
        } }
      when "/v1/inAppPurchasePriceSchedules/#{@contract.workshop_iap_id}/baseTerritory"
        { "data" => {
          "type" => "territories", "id" => "FRA",
          "attributes" => { "currency" => "EUR" }
        } }
      when "/v2/inAppPurchases/#{@contract.workshop_iap_id}/appStoreReviewScreenshot"
        expected = Provenance::WORKSHOP_SCREENSHOT
        { "data" => {
          "type" => "inAppPurchaseAppStoreReviewScreenshots",
          "id" => expected.fetch("id"),
          "attributes" => {
            "fileName" => expected.fetch("fileName"),
            "fileSize" => expected.fetch("fileSize"),
            "sourceFileChecksum" => expected.fetch("sourceFileChecksum"),
            "assetDeliveryState" => {
              "state" => @screenshot_state, "errors" => nil, "warnings" => nil
            }
          }
        } }
      else
        return nil if optional
        raise "unexpected GET #{path}"
      end
    end

    private

    def build_resource
      {
        "type" => "builds", "id" => @contract.asc_build_id,
        "attributes" => {
          "version" => @contract.build, "processingState" => "VALID",
          "uploadedDate" => @contract.uploaded_date, "expired" => false,
          "usesNonExemptEncryption" => @encryption
        }
      }
    end

    def source_build_resource
      source = Provenance::SOURCE_SELECTED_BUILD
      {
        "type" => "builds", "id" => source.fetch("id"),
        "attributes" => {
          "version" => source.fetch("version"),
          "processingState" => source.fetch("processingState"),
          "uploadedDate" => source.fetch("uploadedDate"),
          "expired" => source.fetch("expired"),
          "usesNonExemptEncryption" =>
            source.fetch("usesNonExemptEncryption")
        }
      }
    end
  end

  def test_local_candidate_and_remote_are_bound_to_tooling_only_head
    with_fixture do |contract, _client|
      proof = Provenance.verify_local!(
        run_id: contract.run_id, candidate_id: contract.candidate_id,
        contract: contract
      )
      assert_equal contract.source_head, proof.fetch("source_head")
      assert_equal contract.ipa_sha256, proof.fetch("ipa_sha256")
      assert_equal git(contract.app_root, "rev-parse", "HEAD"),
                   Provenance.verify_remote!(contract: contract)
    end
  end

  def test_local_guard_rejects_dirty_tree_receipt_drift_and_product_commit
    with_fixture do |contract, _client|
      dirty = File.join(contract.app_root, "untracked.txt")
      File.binwrite(dirty, "dirty")
      assert_raises(Provenance::Error) do
        Provenance.verify_local!(
          run_id: contract.run_id, candidate_id: contract.candidate_id,
          contract: contract
        )
      end
      FileUtils.rm_f(dirty)

      receipt = File.join(
        contract.app_root, contract.artifact_root, contract.run_id,
        "logs", "candidate-receipt.json"
      )
      File.open(receipt, "ab") { |file| file.write(" ") }
      assert_raises(Provenance::Error) do
        Provenance.verify_local!(
          run_id: contract.run_id, candidate_id: contract.candidate_id,
          contract: contract
        )
      end
    end

    with_fixture do |contract, _client|
      File.binwrite(File.join(contract.app_root, "product.txt"), "changed")
      git(contract.app_root, "add", "product.txt")
      git(contract.app_root, "commit", "-m", "product drift")
      git(contract.app_root, "push", "origin", "main")
      assert_raises(Provenance::Error) do
        Provenance.verify_local!(
          run_id: contract.run_id, candidate_id: contract.candidate_id,
          contract: contract
        )
      end
    end
  end

  def test_remote_readback_rejects_a_stale_remote_even_if_tracking_ref_is_forged
    with_fixture do |contract, _client|
      tooling = File.join(contract.app_root, "scripts/app_store/tool.rb")
      File.binwrite(tooling, "# second tooling commit\n")
      git(contract.app_root, "add", "scripts/app_store/tool.rb")
      git(contract.app_root, "commit", "-m", "local only")
      git(contract.app_root, "update-ref", "refs/remotes/origin/main", "HEAD")

      Provenance.verify_local!(
        run_id: contract.run_id, candidate_id: contract.candidate_id,
        contract: contract
      )
      assert_raises(Provenance::Error) do
        Provenance.verify_remote!(contract: contract)
      end
    end
  end

  def test_live_build_and_ios_version_are_exact_and_fail_closed
    with_fixture do |contract, client|
      build = Provenance.verify_live_build!(client: client, contract: contract)
      assert_equal contract.asc_build_id, build.fetch("id")
      assert_equal contract.app_version_id,
                   Provenance.verify_app_version!(
                     client: client,
                     allowed_states: ["PREPARE_FOR_SUBMISSION"],
                     contract: contract
                   ).fetch("id")
      Provenance.verify_selected_build!(
        client: client, version_id: contract.app_version_id, contract: contract
      )
      assert_equal :target, Provenance.selected_build_state!(
        client: client, version_id: contract.app_version_id, contract: contract
      )
      client.selected_build = :source
      assert_equal :source, Provenance.selected_build_state!(
        client: client, version_id: contract.app_version_id, contract: contract
      )
      client.selected_build = :target

      client.encryption = true
      assert_raises(Provenance::Error) do
        Provenance.verify_live_build!(client: client, contract: contract)
      end
      client.encryption = false
      client.platform = "MAC_OS"
      assert_raises(Provenance::Error) do
        Provenance.verify_app_version!(
          client: client, allowed_states: ["PREPARE_FOR_SUBMISSION"],
          contract: contract
        )
      end
    end
  end

  def test_final_review_readiness_requires_target_notes_frozen_version_and_screenshot
    with_fixture do |contract, client|
      result = Provenance.verify_review_readiness!(
        client: client, contract: contract, catalogue: client.catalogue
      )
      assert_equal Provenance::WORKSHOP_SCREENSHOT.fetch("id"),
                   result.fetch("workshop_screenshot_id")

      client.screenshot_state = "AWAITING_UPLOAD"
      assert_raises(Provenance::Error) do
        Provenance.verify_review_readiness!(
          client: client, contract: contract, catalogue: client.catalogue
        )
      end
      client.screenshot_state = "COMPLETE"
      client.workshop_version_id = "newer-unfrozen-version"
      assert_raises(Provenance::Error) do
        Provenance.verify_review_readiness!(
          client: client, contract: contract, catalogue: client.catalogue
        )
      end
    end
  end

  private

  def with_fixture
    Dir.mktmpdir("nova-provenance") do |directory|
      repo = File.join(directory, "repo")
      remote = File.join(directory, "origin.git")
      FileUtils.mkdir_p(File.join(repo, "scripts/app_store"))
      git(directory, "init", "--bare", remote)
      git(repo, "init", "-b", "main")
      git(repo, "config", "user.email", "test@example.invalid")
      git(repo, "config", "user.name", "Test")
      File.binwrite(File.join(repo, "product.txt"), "source\n")
      File.binwrite(File.join(repo, ".gitignore"), "artifacts/\n")
      git(repo, "add", "product.txt", ".gitignore")
      git(repo, "commit", "-m", "source")
      source_head = git(repo, "rev-parse", "HEAD")

      preliminary = Provenance::Contract.new(
        app_root: repo, source_head: source_head
      )
      entries = Provenance.commit_entries(preliminary, source_head).values
      unsigned = {
        "schema_version" => 1, "base_head" => source_head, "entries" => entries
      }
      candidate_id = Digest::SHA256.hexdigest(JSON.generate(unsigned))
      manifest = unsigned.merge("candidate_id" => candidate_id)
      run_id = "fixture-fresh4"
      artifact_root = "artifacts"
      run_root = File.join(repo, artifact_root, run_id)
      FileUtils.mkdir_p(File.join(run_root, "archives"))
      FileUtils.mkdir_p(File.join(run_root, "logs"))
      ipa_path = File.join(run_root, "archives", "NovaStationPinball.ipa")
      File.binwrite(ipa_path, "signed ipa bytes")
      ipa_sha = Digest::SHA256.file(ipa_path).hexdigest
      receipt = {
        "schema_version" => 1,
        "app" => "nova-station-pinball",
        "execution_id" => run_id,
        "source_manifest" => manifest,
        "artifacts" => [{
          "path" => "archives/NovaStationPinball.ipa", "sha256" => ipa_sha
        }],
        "toolchain" => {},
        "validation" => {
          "passed" => true,
          "commands" => [{
            "argv" => [
              "bin/apple-release", "lane", "NovaStationPinball",
              "release_contract"
            ],
            "status" => 0
          }]
        },
        "asc" => { "uploaded" => true, "readback" => "success", "state" => "VALID" },
        "final_commit" => nil
      }
      receipt_path = File.join(run_root, "logs", "candidate-receipt.json")
      write_json(receipt_path, receipt)
      upload_receipt = {
        "schema_version" => 1, "phase" => "observed", "kind" => "ipa",
        "candidate_id" => candidate_id, "version" => "1.0",
        "payload" => { "build" => "2", "count" => 1, "sha256" => ipa_sha }
      }
      upload_receipt_path = File.join(
        run_root, "logs", "ipa-upload-receipt.json"
      )
      upload_intent_path = File.join(run_root, "logs", "ipa-upload-intent.json")
      write_json(upload_receipt_path, upload_receipt)
      write_json(upload_intent_path, upload_receipt.merge("phase" => "intent"))
      release_manifest_path = File.join(
        run_root, "logs", "release-manifest.json"
      )
      write_json(release_manifest_path, {
        "schema_version" => 1, "candidate_id" => candidate_id,
        "version" => "1.0", "build" => "2", "ipa_sha256" => ipa_sha
      })
      target_build_path = File.join(run_root, "logs", "target-build.json")
      write_json(target_build_path, {
        "version" => "1.0", "build" => "2"
      })

      File.binwrite(
        File.join(repo, "scripts/app_store/tool.rb"), "# guarded tooling\n"
      )
      git(repo, "add", "scripts/app_store/tool.rb")
      git(repo, "commit", "-m", "tooling")
      git(repo, "remote", "add", "origin", remote)
      git(repo, "push", "-u", "origin", "main")

      contract = Provenance::Contract.new(
        app_root: repo, artifact_root: artifact_root, run_id: run_id,
        candidate_id: candidate_id,
        candidate_receipt_sha256: Digest::SHA256.file(receipt_path).hexdigest,
        ipa_upload_intent_sha256: Digest::SHA256.file(upload_intent_path).hexdigest,
        ipa_upload_receipt_sha256: Digest::SHA256.file(upload_receipt_path).hexdigest,
        release_manifest_sha256: Digest::SHA256.file(release_manifest_path).hexdigest,
        target_build_sha256: Digest::SHA256.file(target_build_path).hexdigest,
        source_head: source_head, version: "1.0", build: "2",
        app_id: "app-1", app_version_id: "version-1",
        bundle_id: "com.example.nova", origin_url: remote,
        asc_build_id: "build-2",
        uploaded_date: "2026-08-24T00:29:40-07:00",
        ipa_sha256: ipa_sha, workshop_iap_id: "workshop-1",
        workshop_product_id: "com.example.nova.workshop",
        workshop_version_id: "workshop-version-1",
        allowed_tooling_paths: ["scripts/app_store/tool.rb"]
      )
      products = JSON.parse(File.binread(File.join(ROOT, "fastlane/pro_products.json")))
      client = AscClient.new(
        contract,
        app_note: File.binread(
          File.join(ROOT, "fastlane/metadata/review_information/notes.txt")
        ).strip,
        workshop_note: products.fetch("products").first.fetch("review_notes")
      )
      yield contract, client
    end
  end

  def write_json(path, document)
    File.binwrite(path, JSON.pretty_generate(document) + "\n")
    File.chmod(0o600, path)
  end

  def git(directory, *arguments)
    stdout, stderr, status = Open3.capture3("git", "-C", directory, *arguments)
    raise "git failed: #{stderr}" unless status.success?

    stdout.strip
  end
end
