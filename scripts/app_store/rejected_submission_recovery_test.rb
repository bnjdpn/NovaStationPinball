# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "rejected_submission_recovery"

class NovaStationPinballRejectedSubmissionRecoveryTest < Minitest::Test
  Recovery = NovaStationPinballRejectedSubmissionRecovery

  class FakeClient
    attr_accessor :ambiguous_patch_path, :ambiguous_patch_applies
    attr_accessor :workshop_version_type, :workshop_version_value
    attr_reader :mutations, :submission_state, :tips, :app_review_note,
                :workshop_review_note

    def initialize
      @mutations = []
      @submission_state = Recovery::CANCELABLE_SUBMISSION_STATE
      @tips = Recovery::RETIRED_IAPS.each_with_object({}) do |definition, result|
        result[definition.fetch("id")] = {
          "product_id" => definition.fetch("product_id"),
          "state" => Recovery::SOURCE_TIP_STATE,
          "availability" => nil
        }
      end
      @app_review_note = "outdated App Review note"
      @workshop_review_note = "outdated Workshop note"
      @review_detail_id = "review-detail-1"
      @contacts = {
        "contactFirstName" => "Review",
        "contactLastName" => "Contact",
        "contactPhone" => "+33000000000",
        "contactEmail" => "review@example.invalid"
      }
      @demo_account_required = false
      @workshop_state = "READY_TO_SUBMIT"
      @workshop_version_type = "inAppPurchaseVersions"
      @workshop_version_value = 1
      @workshop_version_state = "PREPARE_FOR_SUBMISSION"
    end

    def make_recovery_prerequisites_exact!(source_notes)
      @submission_state = Recovery::CANCEL_TERMINAL_STATE
      @tips.each do |iap_id, tip|
        tip["state"] = Recovery::TARGET_TIP_STATE
        tip["availability"] = {
          "id" => "availability-#{iap_id}",
          "available_in_new_territories" => false,
          "territories" => []
        }
      end
      @app_review_note = source_notes.app_review_note
    end

    def get(path, _params = {}, optional: false)
      case path
      when "/v1/reviewSubmissions/#{Recovery::OLD_SUBMISSION_ID}"
        resource(
          "reviewSubmissions", Recovery::OLD_SUBMISSION_ID,
          "state" => @submission_state,
          "platform" => "IOS",
          "submittedDate" => "2026-08-22T00:00:00Z"
        )
      when %r{\A/v2/inAppPurchases/([^/]+)/inAppPurchaseAvailability\z}
        tip = @tips.fetch(Regexp.last_match(1))
        availability = tip.fetch("availability")
        return nil if availability.nil? && optional
        raise "missing availability" if availability.nil?

        resource(
          "inAppPurchaseAvailabilities", availability.fetch("id"),
          "availableInNewTerritories" =>
            availability.fetch("available_in_new_territories")
        )
      when %r{\A/v2/inAppPurchases/([^/]+)\z}
        iap_id = Regexp.last_match(1)
        return workshop_resource if iap_id == Recovery::WORKSHOP_IAP_ID

        tip_resource(iap_id)
      when "/v1/appStoreVersions/#{Recovery::APP_VERSION_ID}/appStoreReviewDetail"
        resource(
          "appStoreReviewDetails", @review_detail_id,
          @contacts.merge(
            "notes" => @app_review_note,
            "demoAccountRequired" => @demo_account_required
          )
        )
      else
        raise "unexpected GET #{path}"
      end
    end

    def get_all(path, _params = {})
      case path
      when "/v1/reviewSubmissions/#{Recovery::OLD_SUBMISSION_ID}/items"
        {
          "data" => Recovery::OLD_SUBMISSION_RESOURCES.each_with_index.map do |pair, index|
            type, id = pair
            relationship = type == "appStoreVersions" ?
              "appStoreVersion" : "inAppPurchaseVersion"
            {
              "type" => "reviewSubmissionItems",
              "id" => "item-#{index}",
              "relationships" => {
                relationship => { "data" => { "type" => type, "id" => id } }
              }
            }
          end
        }
      when "/v1/apps/#{Recovery::APP_ID}/reviewSubmissions"
        {
          "data" => [
            {
              "type" => "reviewSubmissions",
              "id" => Recovery::OLD_SUBMISSION_ID,
              "attributes" => {
                "state" => @submission_state,
                "platform" => "IOS"
              }
            }
          ]
        }
      when %r{\A/v1/inAppPurchaseAvailabilities/([^/]+)/availableTerritories\z}
        availability_id = Regexp.last_match(1)
        availability = @tips.values.map { |tip| tip["availability"] }.compact.find do |item|
          item.fetch("id") == availability_id
        end
        raise "unknown availability" unless availability

        { "data" => availability.fetch("territories") }
      when "/v2/inAppPurchases/#{Recovery::WORKSHOP_IAP_ID}/versions"
        {
          "data" => [
            {
              "type" => @workshop_version_type,
              "id" => Recovery::WORKSHOP_VERSION_ID,
              "attributes" => {
                "version" => @workshop_version_value,
                "state" => @workshop_version_state
              }
            }
          ]
        }
      else
        raise "unexpected GET_ALL #{path}"
      end
    end

    def patch(path, body)
      @mutations << ["PATCH", path, deep_stringify(body)]
      if path == @ambiguous_patch_path && !@ambiguous_patch_applies
        raise IOError, "simulated response loss"
      end

      case path
      when "/v1/reviewSubmissions/#{Recovery::OLD_SUBMISSION_ID}"
        @submission_state = Recovery::CANCEL_TERMINAL_STATE
      when "/v1/appStoreReviewDetails/#{@review_detail_id}"
        @app_review_note = body.dig(:data, :attributes, :notes)
      when "/v2/inAppPurchases/#{Recovery::WORKSHOP_IAP_ID}"
        @workshop_review_note = body.dig(:data, :attributes, :reviewNote)
      else
        raise "unexpected PATCH #{path}"
      end
      if path == @ambiguous_patch_path
        raise IOError, "simulated response loss after server apply"
      end
      {}
    end

    def post(path, body)
      @mutations << ["POST", path, deep_stringify(body)]
      raise "unexpected POST #{path}" unless path == "/v1/inAppPurchaseAvailabilities"

      iap_id = body.dig(
        :data, :relationships, :inAppPurchase, :data, :id
      )
      tip = @tips.fetch(iap_id)
      tip["availability"] = {
        "id" => "availability-#{iap_id}",
        "available_in_new_territories" => false,
        "territories" => []
      }
      tip["state"] = Recovery::TARGET_TIP_STATE
      {}
    end

    private

    def tip_resource(iap_id)
      tip = @tips.fetch(iap_id)
      resource(
        "inAppPurchases", iap_id,
        "productId" => tip.fetch("product_id"),
        "inAppPurchaseType" => "CONSUMABLE",
        "state" => tip.fetch("state")
      )
    end

    def workshop_resource
      resource(
        "inAppPurchases", Recovery::WORKSHOP_IAP_ID,
        "name" => "Nova Station Pinball Workshop",
        "productId" => Recovery::WORKSHOP_PRODUCT_ID,
        "inAppPurchaseType" => "NON_CONSUMABLE",
        "state" => @workshop_state,
        "reviewNote" => @workshop_review_note
      )
    end

    def resource(type, id, attributes)
      { "data" => { "type" => type, "id" => id, "attributes" => attributes } }
    end

    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          result[key.to_s] = deep_stringify(item)
        end
      when Array
        value.map { |item| deep_stringify(item) }
      else
        value
      end
    end
  end

  def test_default_status_is_read_only
    client = FakeClient.new
    coordinator = coordinator(client: client)

    status = coordinator.status

    assert_equal "read_only", status.fetch("mode")
    assert_equal false, status.fetch("mutations")
    assert_equal [], client.mutations
    assert_equal 6, status.fetch("operations").length
  end

  def test_apply_requires_an_explicit_run_id
    assert_raises(Recovery::Error) do
      Recovery::CLI.options!(["--apply"], app_root: app_root)
    end
    options = Recovery::CLI.options!(
      ["--apply", "--run-id", "nova-recovery-1"], app_root: app_root
    )
    assert_equal true, options.fetch(:apply)
    assert_equal "nova-recovery-1", options.fetch(:run_id)
  end

  def test_intent_without_receipt_is_strictly_get_only
    Dir.mktmpdir("nova-recovery") do |directory|
      client = FakeClient.new
      store = proof_store(directory)
      coordinator = coordinator(client: client, proof_store: store, timeout: 0)
      operation = coordinator.operations.first
      snapshot = operation.snapshot
      assert_equal :transport, store.claim!(
        operation: operation.key, identity: operation.identity(snapshot)
      )

      assert_raises(Recovery::ReadbackTimeout) { coordinator.apply! }
      assert_equal [], client.mutations
      assert File.file?(store.paths(operation.key).first)
      refute File.exist?(store.paths(operation.key).last)
      assert_equal 0o600, File.stat(store.paths(operation.key).first).mode & 0o777
    end
  end

  def test_ambiguous_transport_is_never_retried
    Dir.mktmpdir("nova-recovery") do |directory|
      client = FakeClient.new
      cancel_path = "/v1/reviewSubmissions/#{Recovery::OLD_SUBMISSION_ID}"
      client.ambiguous_patch_path = cancel_path
      store = proof_store(directory)
      coordinator = coordinator(client: client, proof_store: store, timeout: 0)

      assert_raises(Recovery::ReadbackTimeout) { coordinator.apply! }
      assert_equal 1, mutation_count(client, "PATCH", cancel_path)
      assert File.file?(store.paths("cancel-old-submission").first)
      refute File.exist?(store.paths("cancel-old-submission").last)

      assert_raises(Recovery::ReadbackTimeout) { coordinator.apply! }
      assert_equal 1, mutation_count(client, "PATCH", cancel_path)
    end
  end

  def test_a_new_run_id_cannot_bypass_an_ambiguous_global_intent
    Dir.mktmpdir("nova-recovery") do |directory|
      client = FakeClient.new
      cancel_path = "/v1/reviewSubmissions/#{Recovery::OLD_SUBMISSION_ID}"
      client.ambiguous_patch_path = cancel_path
      first_store = Recovery::ProofStore.new(
        artifact_root: directory, run_id: "nova-recovery-first"
      )
      assert_raises(Recovery::ReadbackTimeout) do
        coordinator(client: client, proof_store: first_store, timeout: 0).apply!
      end
      assert_equal 1, mutation_count(client, "PATCH", cancel_path)

      second_store = Recovery::ProofStore.new(
        artifact_root: directory, run_id: "nova-recovery-second"
      )
      assert_equal first_store.directory, second_store.directory
      assert_raises(Recovery::ReadbackTimeout) do
        coordinator(client: client, proof_store: second_store, timeout: 0).apply!
      end
      assert_equal 1, mutation_count(client, "PATCH", cancel_path)
    end
  end

  def test_ambiguous_transport_with_exact_readback_gets_a_receipt_without_retry
    Dir.mktmpdir("nova-recovery") do |directory|
      client = FakeClient.new
      cancel_path = "/v1/reviewSubmissions/#{Recovery::OLD_SUBMISSION_ID}"
      client.ambiguous_patch_path = cancel_path
      client.ambiguous_patch_applies = true
      store = proof_store(directory)

      result = coordinator(client: client, proof_store: store).apply!

      assert_equal 1, mutation_count(client, "PATCH", cancel_path)
      warning = result.fetch("transport_warnings").first
      assert_equal "cancel-old-submission", warning.fetch("operation")
      assert_equal "IOError", warning.fetch("error_class")
      assert_equal 0, warning.fetch("retries")
      assert File.file?(store.paths("cancel-old-submission").last)
    end
  end

  def test_full_recovery_is_sequential_and_has_exact_readbacks
    Dir.mktmpdir("nova-recovery") do |directory|
      client = FakeClient.new
      store = proof_store(directory)
      source_notes = notes
      result = coordinator(
        client: client, proof_store: store, source_notes: source_notes
      ).apply!

      assert_equal "apply", result.fetch("mode")
      assert_equal true, result.fetch("mutations")
      assert_equal [], result.fetch("transport_warnings")
      assert_equal Recovery::CANCEL_TERMINAL_STATE, client.submission_state
      assert_equal source_notes.app_review_note, client.app_review_note
      assert_equal source_notes.workshop_review_note, client.workshop_review_note

      expected_transports = [
        ["PATCH", "/v1/reviewSubmissions/#{Recovery::OLD_SUBMISSION_ID}"],
        ["POST", "/v1/inAppPurchaseAvailabilities"],
        ["POST", "/v1/inAppPurchaseAvailabilities"],
        ["POST", "/v1/inAppPurchaseAvailabilities"],
        ["PATCH", "/v1/appStoreReviewDetails/review-detail-1"],
        ["PATCH", "/v2/inAppPurchases/#{Recovery::WORKSHOP_IAP_ID}"]
      ]
      assert_equal expected_transports,
                   client.mutations.map { |method, path, _body| [method, path] }
      cancel_body = client.mutations.first.fetch(2)
      assert_equal({ "canceled" => true },
                   cancel_body.dig("data", "attributes"))
      assert_equal Recovery::OLD_SUBMISSION_ID,
                   cancel_body.dig("data", "id")
      retired_bodies = client.mutations[1, 3].map(&:last)
      retired_ids = retired_bodies.map do |body|
        body.dig("data", "relationships", "inAppPurchase", "data", "id")
      end
      assert_equal Recovery::RETIRED_IAPS.map { |item| item.fetch("id") },
                   retired_ids
      retired_bodies.each do |body|
        assert_equal false,
                     body.dig("data", "attributes", "availableInNewTerritories")
        assert_equal [],
                     body.dig("data", "relationships", "availableTerritories", "data")
      end

      cancel = operation_readback(result, "cancel-old-submission")
      assert_equal true, cancel.fetch("exact")
      assert_equal "COMPLETE", cancel.fetch("state")
      assert_equal [], cancel.fetch("active_submission_ids")

      Recovery::RETIRED_IAPS.each do |definition|
        tip = operation_readback(result, definition.fetch("key"))
        assert_equal true, tip.fetch("exact")
        assert_equal false, tip.fetch("available_in_new_territories")
        assert_equal 0, tip.fetch("available_territory_count")
        assert_equal "CONSUMABLE", tip.fetch("type")
        assert_equal Recovery::TARGET_TIP_STATE, tip.fetch("state")
      end

      app_note = operation_readback(result, "sync-app-review-note")
      assert_equal Digest::SHA256.hexdigest(source_notes.app_review_note),
                   app_note.fetch("note_sha256")
      workshop = operation_readback(result, "sync-workshop-review-note")
      assert_equal Digest::SHA256.hexdigest(source_notes.workshop_review_note),
                   workshop.fetch("note_sha256")
      assert_equal Recovery::WORKSHOP_VERSION_ID,
                   workshop.fetch("version_id")

      proof_files = Dir.glob(File.join(store.directory, "*.json"))
      assert_equal 12, proof_files.length
      proof_files.each do |path|
        assert_equal 0o600, File.stat(path).mode & 0o777
      end

      mutation_count_before_resume = client.mutations.length
      resumed = coordinator(
        client: client, proof_store: store, source_notes: source_notes
      ).apply!
      assert_equal mutation_count_before_resume, client.mutations.length
      assert resumed.fetch("operations").all? do |operation|
        operation.fetch("transport") == "readback_only"
      end
    end
  end

  def test_public_retired_iap_gate_requires_false_zero_and_exact_parent_state
    client = FakeClient.new
    definition = Recovery::RETIRED_IAPS.first
    client.post("/v1/inAppPurchaseAvailabilities", {
      data: {
        type: "inAppPurchaseAvailabilities",
        attributes: { availableInNewTerritories: false },
        relationships: {
          availableTerritories: { data: [] },
          inAppPurchase: {
            data: { type: "inAppPurchases", id: definition.fetch("id") }
          }
        }
      }
    })

    readback = Recovery::RetiredIapReadback.exact!(
      client: client, iap_id: definition.fetch("id"),
      product_id: definition.fetch("product_id")
    )
    assert_equal false, readback.fetch("available_in_new_territories")
    assert_equal 0, readback.fetch("available_territory_count")
    assert_equal Recovery::TARGET_TIP_STATE, readback.fetch("state")

    client.tips.fetch(definition.fetch("id"))
          .fetch("availability").fetch("territories") << {
            "type" => "territories", "id" => "FRA"
          }
    assert_raises(Recovery::Error) do
      Recovery::RetiredIapReadback.exact!(
        client: client, iap_id: definition.fetch("id"),
        product_id: definition.fetch("product_id")
      )
    end
  end

  def test_workshop_version_number_is_strictly_one
    client = FakeClient.new
    client.workshop_version_value = "1junk"
    operation = coordinator(client: client).operations.last
    snapshot = operation.snapshot

    assert_equal false, snapshot.fetch("exact")
    assert_raises(Recovery::Error) { operation.observe(snapshot) }
  end

  def test_note_drift_is_rejected_before_any_write
    client = FakeClient.new
    verified = notes

    assert_raises(Recovery::Error) do
      Recovery::SourceNotes.new(
        app_review_note: verified.app_review_note + " drift",
        workshop_review_note: verified.workshop_review_note
      )
    end
    assert_equal [], client.mutations
  end

  def test_malformed_workshop_version_or_type_causes_zero_writes
    [
      ["1junk", "inAppPurchaseVersions"],
      [1, "wrongResourceType"]
    ].each do |version_value, version_type|
      Dir.mktmpdir("nova-recovery") do |directory|
        source_notes = notes
        client = FakeClient.new
        client.make_recovery_prerequisites_exact!(source_notes)
        client.workshop_version_value = version_value
        client.workshop_version_type = version_type

        assert_raises(Recovery::Error) do
          coordinator(
            client: client, proof_store: proof_store(directory),
            source_notes: source_notes
          ).apply!
        end
        assert_equal [], client.mutations
      end
    end
  end

  def test_note_patches_contain_only_the_exact_note_attribute
    Dir.mktmpdir("nova-recovery") do |directory|
      client = FakeClient.new
      source_notes = notes
      coordinator(
        client: client, proof_store: proof_store(directory),
        source_notes: source_notes
      ).apply!

      app_patch = client.mutations.find do |method, path, _body|
        method == "PATCH" && path.start_with?("/v1/appStoreReviewDetails/")
      end.fetch(2)
      assert_equal({ "notes" => source_notes.app_review_note },
                   app_patch.dig("data", "attributes"))
      workshop_patch = client.mutations.find do |method, path, _body|
        method == "PATCH" &&
          path == "/v2/inAppPurchases/#{Recovery::WORKSHOP_IAP_ID}"
      end.fetch(2)
      assert_equal({ "reviewNote" => source_notes.workshop_review_note },
                   workshop_patch.dig("data", "attributes"))
    end
  end

  def test_checked_in_note_sources_have_the_verified_exact_limits_and_hashes
    source_notes = Recovery::SourceNotes.load!(
      app_review_path:
        File.join(app_root, "fastlane/metadata/review_information/notes.txt"),
      products_path: File.join(app_root, "fastlane/pro_products.json")
    )

    assert_equal 3_898, source_notes.app_review_note.bytesize
    assert_operator source_notes.app_review_note.bytesize, :<, 4_000
    assert_equal "940dc92a915638305980d4d5c411e7ea3a2612ec8bbbe0d25b8a9b971f1af345",
                 Digest::SHA256.hexdigest(source_notes.app_review_note)
    assert_equal 1_312, source_notes.workshop_review_note.bytesize
    assert_operator source_notes.workshop_review_note.bytesize, :<, 4_000
    assert_equal "58b87d2d341a7061446c5c07d4507d7100605b78e4bbb4a6877ae90aac474db3",
                 Digest::SHA256.hexdigest(source_notes.workshop_review_note)
  end

  private

  def app_root
    File.expand_path("../..", __dir__)
  end

  def notes
    Recovery::SourceNotes.load!(
      app_review_path:
        File.join(app_root, "fastlane/metadata/review_information/notes.txt"),
      products_path: File.join(app_root, "fastlane/pro_products.json")
    )
  end

  def proof_store(directory)
    Recovery::ProofStore.new(
      artifact_root: directory, run_id: "nova-recovery-test"
    )
  end

  def coordinator(client:, proof_store: nil, source_notes: notes, timeout: 1)
    Recovery::Coordinator.new(
      client: client, source_notes: source_notes, proof_store: proof_store,
      timeout: timeout, interval: 0,
      monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      sleeper: ->(_seconds) {}
    )
  end

  def mutation_count(client, method, path)
    client.mutations.count do |candidate_method, candidate_path, _body|
      candidate_method == method && candidate_path == path
    end
  end

  def operation_readback(result, key)
    result.fetch("operations").find do |operation|
      operation.fetch("operation") == key
    end.fetch("readback")
  end
end
