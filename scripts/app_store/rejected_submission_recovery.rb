#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require_relative "client"

module NovaStationPinballRejectedSubmissionRecovery
  APP_ID = "6799920176"
  BUNDLE_ID = "com.bnjdpn.NovaStationPinball"
  VERSION = "1.0"
  APP_VERSION_ID = "1739b449-a776-42ee-8b31-0997496c2a09"
  OLD_SUBMISSION_ID = "6a144aef-6ad1-4a44-8404-e1966c7bde32"
  WORKSHOP_IAP_ID = "6803400833"
  WORKSHOP_PRODUCT_ID = "com.bnjdpn.NovaStationPinball.workshop"
  WORKSHOP_VERSION_ID = "bc22c948-ea0e-4bae-be8f-c78d091dd27b"
  APP_REVIEW_NOTE_BYTES = 3_898
  APP_REVIEW_NOTE_SHA256 =
    "940dc92a915638305980d4d5c411e7ea3a2612ec8bbbe0d25b8a9b971f1af345"
  WORKSHOP_REVIEW_NOTE_BYTES = 1_312
  WORKSHOP_REVIEW_NOTE_SHA256 =
    "58b87d2d341a7061446c5c07d4507d7100605b78e4bbb4a6877ae90aac474db3"

  OLD_SUBMISSION_RESOURCES = [
    ["appStoreVersions", APP_VERSION_ID],
    ["inAppPurchaseVersions", "00c2829d-f8c4-477e-baf9-58e17970bd06"],
    ["inAppPurchaseVersions", "94c14af3-905f-4b5c-95bf-da31af6d2891"],
    ["inAppPurchaseVersions", "c3b91b29-3d41-484e-a6b7-f0285415d2ad"]
  ].sort.freeze

  RETIRED_IAPS = [
    {
      "key" => "retire-tip-cafe",
      "id" => "6799922833",
      "product_id" => "com.bnjdpn.NovaStationPinball.tip.cafe"
    },
    {
      "key" => "retire-tip-merci",
      "id" => "6799924582",
      "product_id" => "com.bnjdpn.NovaStationPinball.tip.merci"
    },
    {
      "key" => "retire-tip-soutien",
      "id" => "6799926328",
      "product_id" => "com.bnjdpn.NovaStationPinball.tip.soutien"
    }
  ].freeze

  SOURCE_TIP_STATE = "READY_TO_SUBMIT"
  TARGET_TIP_STATE = "DEVELOPER_REMOVED_FROM_SALE"
  CANCELABLE_SUBMISSION_STATE = "UNRESOLVED_ISSUES"
  CANCEL_TRANSITION_STATES = %w[CANCELING COMPLETING].freeze
  CANCEL_TERMINAL_STATE = "COMPLETE"
  WORKSHOP_PARENT_STATES = %w[READY_TO_SUBMIT].freeze
  WORKSHOP_VERSION_STATES = %w[
    PREPARE_FOR_SUBMISSION READY_FOR_REVIEW
  ].freeze
  NOTE_LIMIT_BYTES = 4_000

  class Error < StandardError; end
  class ReadbackTimeout < Error; end
  class ProofError < Error; end

  module_function

  def canonical(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) do |key, result|
        result[key] = canonical(value.fetch(key))
      end
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end

  def body_sha256(body)
    Digest::SHA256.hexdigest(JSON.generate(canonical(body)))
  end

  class SourceNotes
    attr_reader :app_review_note, :workshop_review_note

    def initialize(app_review_note:, workshop_review_note:)
      @app_review_note = normalize!(
        app_review_note, "App Review note",
        expected_bytes: APP_REVIEW_NOTE_BYTES,
        expected_sha256: APP_REVIEW_NOTE_SHA256
      )
      @workshop_review_note = normalize!(
        workshop_review_note, "Workshop review note",
        expected_bytes: WORKSHOP_REVIEW_NOTE_BYTES,
        expected_sha256: WORKSHOP_REVIEW_NOTE_SHA256
      )
    end

    def self.load!(app_review_path:, products_path:)
      app_review_note = read_regular_file!(app_review_path).strip
      products = JSON.parse(read_regular_file!(products_path))
      matches = products.fetch("products").select do |product|
        product.fetch("product_id") == WORKSHOP_PRODUCT_ID
      end
      unless matches.length == 1
        raise Error, "Workshop product source must contain exactly one product"
      end
      product = matches.first
      unless product.fetch("type") == "NON_CONSUMABLE"
        raise Error, "Workshop product source has the wrong type"
      end

      new(
        app_review_note: app_review_note,
        workshop_review_note: product.fetch("review_notes")
      )
    rescue JSON::ParserError, KeyError => error
      raise Error, "Invalid local review-note source: #{error.message}"
    end

    def self.read_regular_file!(path)
      expanded = File.expand_path(path)
      unless File.file?(expanded) && !File.symlink?(expanded)
        raise Error, "Review-note source must be a regular non-symlink file"
      end
      text = File.binread(expanded).force_encoding(Encoding::UTF_8)
      raise Error, "Review-note source is not valid UTF-8" unless text.valid_encoding?

      text
    end
    private_class_method :read_regular_file!

    private

    def normalize!(value, label, expected_bytes:, expected_sha256:)
      unless value.instance_of?(String) && value.valid_encoding? && !value.empty?
        raise Error, "#{label} must be non-empty UTF-8"
      end
      if value.bytesize >= NOTE_LIMIT_BYTES
        raise Error, "#{label} must remain below #{NOTE_LIMIT_BYTES} bytes"
      end
      unless value.bytesize == expected_bytes &&
             Digest::SHA256.hexdigest(value) == expected_sha256
        raise Error, "#{label} differs from the verified recovery content"
      end

      value.dup.freeze
    end
  end

  # Every proof file is an immutable creation. An intent with no receipt is a
  # permanent GET-only recovery state across run ids: claim! never grants
  # another mutation transport after the exclusive intent has been observed.
  class ProofStore
    RUN_ID = /\A[0-9A-Za-z][0-9A-Za-z._-]{2,127}\z/.freeze
    OPERATION = /\A[a-z0-9][a-z0-9-]{2,127}\z/.freeze

    attr_reader :directory, :run_id

    def initialize(artifact_root:, run_id:)
      @artifact_root = File.expand_path(artifact_root)
      @run_id = run_id.to_s
      raise ProofError, "Invalid recovery run id" unless @run_id.match?(RUN_ID)

      # The ledger is deliberately global to the app artifact root, rather
      # than nested under a run id. A fresh --run-id therefore cannot bypass
      # an ambiguous intent created by an earlier invocation.
      @directory = File.join(
        @artifact_root, "rejected-submission-recovery-ledger"
      )
      ensure_secure_directory!
    end

    def phase(operation:, identity:)
      intent_path, receipt_path = paths(operation)
      if present?(receipt_path)
        intent = read_intent!(intent_path, operation, identity)
        read_receipt!(receipt_path, intent)
        return :observed
      end
      return :missing unless present?(intent_path)

      read_intent!(intent_path, operation, identity)
      :get_only
    end

    def claim!(operation:, identity:)
      current = phase(operation: operation, identity: identity)
      return current unless current == :missing

      expected = intent_document(operation, identity)
      created = write_once!(paths(operation).first, expected)
      return :transport if created

      phase(operation: operation, identity: identity)
    end

    def record_observed!(operation:, identity:, observed:)
      intent_path, receipt_path = paths(operation)
      intent = read_intent!(intent_path, operation, identity)
      receipt = intent.merge(
        "phase" => "observed",
        "observed" => NovaStationPinballRejectedSubmissionRecovery.canonical(
          observed
        )
      )
      created = write_once!(receipt_path, receipt)
      read_exact!(receipt_path, receipt) unless created
      receipt
    end

    def paths(operation)
      key = operation.to_s
      raise ProofError, "Invalid recovery operation key" unless key.match?(OPERATION)

      [
        File.join(@directory, "#{key}-intent.json"),
        File.join(@directory, "#{key}-receipt.json")
      ]
    end

    private

    def intent_document(operation, identity)
      unless identity.instance_of?(Hash) && !identity.empty? &&
             identity.keys.all? { |key| key.instance_of?(String) }
        raise ProofError, "Recovery mutation identity must be a non-empty object"
      end
      {
        "schema_version" => 1,
        "phase" => "intent",
        "run_id" => @run_id,
        "operation" => operation.to_s,
        "identity" => NovaStationPinballRejectedSubmissionRecovery.canonical(
          identity
        )
      }
    end

    def read_receipt!(path, expected_intent)
      receipt = read_document!(path)
      expected_base = expected_intent.merge("phase" => "observed")
      observed = receipt["observed"]
      actual_base = receipt.reject { |key, _value| key == "observed" }
      unless actual_base == expected_base && observed.instance_of?(Hash) &&
             !observed.empty?
        raise ProofError, "Recovery receipt identity differs"
      end
      receipt
    end

    def read_intent!(path, operation, identity)
      actual = read_document!(path)
      expected_identity =
        NovaStationPinballRejectedSubmissionRecovery.canonical(identity)
      valid = actual.instance_of?(Hash) &&
        actual.keys.sort == %w[identity operation phase run_id schema_version] &&
        actual["schema_version"] == 1 && actual["phase"] == "intent" &&
        actual["operation"] == operation.to_s &&
        actual["run_id"].to_s.match?(RUN_ID) &&
        actual["identity"] == expected_identity
      raise ProofError, "Recovery proof identity differs" unless valid

      actual
    end

    def read_exact!(path, expected)
      actual = read_document!(path)
      raise ProofError, "Recovery proof identity differs" unless actual == expected

      actual
    end

    def read_document!(path)
      unless File.file?(path) && !File.symlink?(path)
        raise ProofError, "Recovery proof must be a regular non-symlink file"
      end
      unless (File.stat(path).mode & 0o777) == 0o600
        raise ProofError, "Recovery proof mode must be 0600"
      end
      JSON.parse(File.binread(path))
    rescue JSON::ParserError => error
      raise ProofError, "Invalid recovery proof JSON: #{error.message}"
    end

    def present?(path)
      File.exist?(path) || File.symlink?(path)
    end

    def write_once!(path, document)
      ensure_secure_directory!
      raise ProofError, "Recovery proof path must not be a symlink" if File.symlink?(path)

      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.chmod(0o600)
        file.write(JSON.pretty_generate(document) + "\n")
        file.flush
        file.fsync
      end
      sync_directory!
      true
    rescue Errno::EEXIST
      false
    end

    def ensure_secure_directory!
      components = [@artifact_root]
      components << @directory
      components.each do |component|
        if File.exist?(component) || File.symlink?(component)
          if File.symlink?(component) || !File.directory?(component)
            raise ProofError, "Recovery proof directory must not be a symlink"
          end
        else
          FileUtils.mkdir(component, mode: 0o700)
        end
      end
      File.chmod(0o700, @directory)
    end

    def sync_directory!
      File.open(@directory, File::RDONLY) do |directory|
        directory.fsync
      end
    end
  end

  # Public GET-only contract for release gates. It deliberately has no access
  # to ProofStore or mutation methods, so review_submission.rb can reuse it
  # without widening its authorization surface.
  module RetiredIapReadback
    module_function

    def snapshot(client:, iap_id:, product_id:)
      purchase = fetch_data!(
        client.get(
          "/v2/inAppPurchases/#{iap_id}",
          { "fields[inAppPurchases]" => "productId,inAppPurchaseType,state" }
        ),
        type: "inAppPurchases", id: iap_id
      )
      availability_response = client.get(
        "/v2/inAppPurchases/#{iap_id}/inAppPurchaseAvailability",
        {
          "fields[inAppPurchaseAvailabilities]" =>
            "availableInNewTerritories,availableTerritories"
        },
        optional: true
      )
      availability = availability_response && availability_response["data"]
      availability_id = nil
      available_in_new_territories = nil
      territory_count = nil
      if availability
        unless availability.fetch("type") == "inAppPurchaseAvailabilities"
          raise Error, "Retired IAP availability has the wrong resource type"
        end
        availability_id = availability.fetch("id")
        available_in_new_territories =
          availability.dig("attributes", "availableInNewTerritories")
        territory_count = client.get_all(
          "/v1/inAppPurchaseAvailabilities/#{availability_id}/availableTerritories",
          { "limit" => "200" }
        ).fetch("data").length
      end
      attributes = purchase.fetch("attributes")
      state = attributes["state"]
      {
        "iap_id" => iap_id,
        "product_id" => attributes["productId"],
        "type" => attributes["inAppPurchaseType"],
        "state" => state,
        "availability_id" => availability_id,
        "available_in_new_territories" => available_in_new_territories,
        "available_territory_count" => territory_count,
        "exact" => attributes["productId"] == product_id &&
          attributes["inAppPurchaseType"] == "CONSUMABLE" &&
          state == TARGET_TIP_STATE &&
          available_in_new_territories == false && territory_count == 0
      }
    rescue KeyError => error
      raise Error, "Retired IAP readback is incomplete: #{error.message}"
    end

    def exact!(client:, iap_id:, product_id:)
      result = snapshot(
        client: client, iap_id: iap_id, product_id: product_id
      )
      unless result.fetch("exact")
        raise Error,
              "Retired IAP must have exact type, state, availability and territories"
      end
      result
    end

    def fetch_data!(payload, type:, id:)
      data = payload && payload["data"]
      unless data.instance_of?(Hash) && data["type"] == type && data["id"] == id
        raise Error, "Retired IAP is missing or has the wrong identity"
      end
      data
    end
    private_class_method :fetch_data!
  end

  class Operation
    attr_reader :key

    def initialize(key:, identity:, reader:, preflight:, observer:, mutation:)
      @key = key
      @identity = identity
      @reader = reader
      @preflight = preflight
      @observer = observer
      @mutation = mutation
    end

    def snapshot
      @reader.call
    end

    def identity(snapshot)
      @identity.call(snapshot)
    end

    def preflight(snapshot)
      @preflight.call(snapshot)
    end

    def observe(snapshot)
      @observer.call(snapshot)
    end

    def mutate(snapshot)
      @mutation.call(snapshot)
    end
  end

  class Coordinator
    attr_reader :operations

    def initialize(client:, source_notes:, proof_store: nil, timeout: 300,
                   interval: 5, monotonic: nil, sleeper: nil)
      @client = client
      @source_notes = source_notes
      @proof_store = proof_store
      @timeout = Float(timeout)
      @interval = Float(interval)
      raise Error, "Recovery timeout must not be negative" if @timeout.negative?
      raise Error, "Recovery interval must not be negative" if @interval.negative?

      @monotonic = monotonic || lambda {
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      }
      @sleeper = sleeper || Kernel.method(:sleep)
      @transport_warnings = []
      @operations = build_operations.freeze
    end

    def status
      {
        "schema_version" => 1,
        "mode" => "read_only",
        "app_id" => APP_ID,
        "app_version_id" => APP_VERSION_ID,
        "mutations" => false,
        "operations" => @operations.map do |operation|
          { "operation" => operation.key }.merge(operation.snapshot)
        end
      }
    end

    def apply!
      raise Error, "A durable proof store is required for --apply" unless @proof_store

      @transport_warnings = []
      results = @operations.map { |operation| execute!(operation) }
      {
        "schema_version" => 1,
        "mode" => "apply",
        "app_id" => APP_ID,
        "app_version_id" => APP_VERSION_ID,
        "mutations" => results.any? do |result|
          %w[attempted ambiguous].include?(result["transport"])
        end,
        "operations" => results,
        "transport_warnings" => @transport_warnings.dup
      }
    end

    private

    def execute!(operation)
      first = operation.snapshot
      identity = operation.identity(first)
      phase = @proof_store.phase(
        operation: operation.key, identity: identity
      )

      if phase == :observed
        operation.observe(first)
        ensure_exact!(operation, first)
        return operation_result(operation, first, "readback_only", phase)
      end

      if phase == :get_only
        observed = wait_for_exact!(operation)
        @proof_store.record_observed!(
          operation: operation.key, identity: identity, observed: observed
        )
        return operation_result(operation, observed, "get_only", :observed)
      end

      return operation_result(operation, first, "not_needed", :missing) if first["exact"]

      disposition = operation.preflight(first)
      if disposition == :get_only
        observed = wait_for_exact!(operation)
        return operation_result(operation, observed, "get_only", :missing)
      end
      unless disposition == :mutate
        raise Error, "Invalid recovery preflight disposition for #{operation.key}"
      end

      claim = @proof_store.claim!(
        operation: operation.key, identity: identity
      )
      if claim == :observed
        observed = wait_for_exact!(operation)
        return operation_result(operation, observed, "readback_only", claim)
      end
      if claim == :get_only
        observed = wait_for_exact!(operation)
        @proof_store.record_observed!(
          operation: operation.key, identity: identity, observed: observed
        )
        return operation_result(operation, observed, "get_only", :observed)
      end
      raise Error, "Recovery proof did not grant one transport" unless claim == :transport

      transport = "attempted"
      begin
        operation.mutate(first)
      rescue StandardError => error
        transport = "ambiguous"
        @transport_warnings << {
          "operation" => operation.key,
          "error_class" => error.class.name,
          "retries" => 0
        }
      end

      observed = wait_for_exact!(operation)
      @proof_store.record_observed!(
        operation: operation.key, identity: identity, observed: observed
      )
      operation_result(operation, observed, transport, :observed)
    end

    def wait_for_exact!(operation)
      deadline = @monotonic.call + @timeout
      loop do
        snapshot = operation.snapshot
        operation.observe(snapshot)
        return snapshot if snapshot["exact"]
        if @monotonic.call >= deadline
          raise ReadbackTimeout,
                "#{operation.key} remains unconfirmed; its intent is GET-only"
        end

        @sleeper.call(@interval)
      end
    end

    def ensure_exact!(operation, snapshot)
      return if snapshot["exact"]

      raise Error, "#{operation.key} drifted after its durable receipt"
    end

    def operation_result(operation, snapshot, transport, proof_phase)
      {
        "operation" => operation.key,
        "transport" => transport,
        "proof_phase" => proof_phase.to_s,
        "readback" => snapshot
      }
    end

    def build_operations
      [cancel_operation] + RETIRED_IAPS.map do |definition|
        retired_iap_operation(definition)
      end + [app_review_note_operation, workshop_note_operation]
    end

    def cancel_operation
      path = "/v1/reviewSubmissions/#{OLD_SUBMISSION_ID}"
      body = {
        data: {
          type: "reviewSubmissions", id: OLD_SUBMISSION_ID,
          attributes: { canceled: true }
        }
      }
      Operation.new(
        key: "cancel-old-submission",
        identity: lambda do |_snapshot|
          request_identity(
            action: "cancel_review_submission", method: "PATCH",
            path: path, body: body,
            target: {
              "state" => CANCEL_TERMINAL_STATE,
              "resources" => OLD_SUBMISSION_RESOURCES,
              "active_submission_ids" => []
            }
          )
        end,
        reader: method(:cancel_snapshot),
        preflight: method(:cancel_preflight),
        observer: method(:cancel_observer),
        mutation: ->(_snapshot) { @client.patch(path, body) }
      )
    end

    def retired_iap_operation(definition)
      path = "/v1/inAppPurchaseAvailabilities"
      body = {
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
      }
      Operation.new(
        key: definition.fetch("key"),
        identity: lambda do |_snapshot|
          request_identity(
            action: "retire_in_app_purchase", method: "POST",
            path: path, body: body,
            target: {
              "iap_id" => definition.fetch("id"),
              "product_id" => definition.fetch("product_id"),
              "type" => "CONSUMABLE",
              "state" => TARGET_TIP_STATE,
              "available_in_new_territories" => false,
              "available_territory_count" => 0
            }
          )
        end,
        reader: -> { retired_iap_snapshot(definition) },
        preflight: ->(snapshot) { retired_iap_preflight(snapshot) },
        observer: ->(snapshot) { retired_iap_observer(snapshot) },
        mutation: ->(_snapshot) { @client.post(path, body) }
      )
    end

    def app_review_note_operation
      note = @source_notes.app_review_note
      Operation.new(
        key: "sync-app-review-note",
        identity: lambda do |snapshot|
          path = "/v1/appStoreReviewDetails/#{snapshot.fetch('review_detail_id')}"
          body = app_review_note_body(snapshot.fetch("review_detail_id"), note)
          request_identity(
            action: "sync_app_review_note", method: "PATCH",
            path: path, body: body,
            target: note_target(note).merge(
              "app_version_id" => APP_VERSION_ID,
              "review_detail_id" => snapshot.fetch("review_detail_id")
            )
          )
        end,
        reader: -> { app_review_note_snapshot(note) },
        preflight: method(:app_review_note_preflight),
        observer: method(:app_review_note_observer),
        mutation: lambda do |snapshot|
          detail_id = snapshot.fetch("review_detail_id")
          @client.patch(
            "/v1/appStoreReviewDetails/#{detail_id}",
            app_review_note_body(detail_id, note)
          )
        end
      )
    end

    def workshop_note_operation
      note = @source_notes.workshop_review_note
      path = "/v2/inAppPurchases/#{WORKSHOP_IAP_ID}"
      body = {
        data: {
          type: "inAppPurchases", id: WORKSHOP_IAP_ID,
          attributes: { reviewNote: note }
        }
      }
      Operation.new(
        key: "sync-workshop-review-note",
        identity: lambda do |_snapshot|
          request_identity(
            action: "sync_workshop_review_note", method: "PATCH",
            path: path, body: body,
            target: note_target(note).merge(
              "iap_id" => WORKSHOP_IAP_ID,
              "product_id" => WORKSHOP_PRODUCT_ID,
              "version_id" => WORKSHOP_VERSION_ID,
              "version" => 1,
              "version_states" => WORKSHOP_VERSION_STATES
            )
          )
        end,
        reader: -> { workshop_note_snapshot(note) },
        preflight: method(:workshop_note_preflight),
        observer: method(:workshop_note_observer),
        mutation: ->(_snapshot) { @client.patch(path, body) }
      )
    end

    def request_identity(action:, method:, path:, body:, target:)
      {
        "action" => action,
        "request" => {
          "method" => method,
          "path" => path,
          "body_sha256" =>
            NovaStationPinballRejectedSubmissionRecovery.body_sha256(body)
        },
        "target" => target
      }
    end

    def note_target(note)
      {
        "bytes" => note.bytesize,
        "sha256" => Digest::SHA256.hexdigest(note)
      }
    end

    def cancel_snapshot
      submission = fetch_data!(
        @client.get(
          "/v1/reviewSubmissions/#{OLD_SUBMISSION_ID}",
          {
            "fields[reviewSubmissions]" =>
              "state,submittedDate,platform,items"
          }
        ),
        type: "reviewSubmissions", id: OLD_SUBMISSION_ID,
        label: "old review submission"
      )
      items = @client.get_all(
        "/v1/reviewSubmissions/#{OLD_SUBMISSION_ID}/items",
        {
          "include" => "appStoreVersion,inAppPurchaseVersion",
          "fields[reviewSubmissionItems]" =>
            "state,appStoreVersion,inAppPurchaseVersion",
          "limit" => "200"
        }
      ).fetch("data")
      resources = items.map { |item| review_item_resource!(item) }.sort
      submissions = @client.get_all(
        "/v1/apps/#{APP_ID}/reviewSubmissions",
        {
          "fields[reviewSubmissions]" => "state,submittedDate,platform",
          "limit" => "50"
        }
      ).fetch("data")
      active_ids = submissions.reject do |candidate|
        candidate.dig("attributes", "state") == CANCEL_TERMINAL_STATE
      end.map { |candidate| candidate.fetch("id") }.sort
      state = submission.dig("attributes", "state")
      platform = submission.dig("attributes", "platform")
      {
        "submission_id" => OLD_SUBMISSION_ID,
        "state" => state,
        "platform" => platform,
        "resources" => resources,
        "active_submission_ids" => active_ids,
        "exact" => state == CANCEL_TERMINAL_STATE &&
          platform == "IOS" && resources == OLD_SUBMISSION_RESOURCES &&
          active_ids.empty?
      }
    rescue KeyError => error
      raise Error, "Old review submission readback is incomplete: #{error.message}"
    end

    def review_item_resource!(item)
      relationships = {
        "appStoreVersion" => "appStoreVersions",
        "inAppPurchaseVersion" => "inAppPurchaseVersions"
      }
      resources = relationships.map do |relationship, expected_type|
        resource = item.dig("relationships", relationship, "data")
        next unless resource
        unless resource["type"] == expected_type && !resource["id"].to_s.empty?
          raise Error, "Old review submission item has an invalid relationship"
        end
        [resource.fetch("type"), resource.fetch("id")]
      end.compact
      unless resources.length == 1
        raise Error, "Old review submission item must identify one resource"
      end

      resources.first
    end

    def cancel_preflight(snapshot)
      cancel_observer(snapshot)
      return :get_only if CANCEL_TRANSITION_STATES.include?(snapshot.fetch("state"))
      unless snapshot.fetch("state") == CANCELABLE_SUBMISSION_STATE
        raise Error, "Old review submission is not in the expected reject state"
      end

      :mutate
    end

    def cancel_observer(snapshot)
      unless snapshot.fetch("platform") == "IOS" &&
             snapshot.fetch("resources") == OLD_SUBMISSION_RESOURCES
        raise Error, "Old review submission identity differs from the recovery contract"
      end
      allowed = [CANCELABLE_SUBMISSION_STATE, CANCEL_TERMINAL_STATE] +
        CANCEL_TRANSITION_STATES
      unless allowed.include?(snapshot.fetch("state"))
        raise Error, "Old review submission entered an unexpected state"
      end
      expected_active = snapshot.fetch("state") == CANCEL_TERMINAL_STATE ?
        [] : [OLD_SUBMISSION_ID]
      unless snapshot.fetch("active_submission_ids") == expected_active
        raise Error, "Another active review submission blocks safe recovery"
      end

      snapshot
    end

    def retired_iap_snapshot(definition)
      RetiredIapReadback.snapshot(
        client: @client, iap_id: definition.fetch("id"),
        product_id: definition.fetch("product_id")
      )
    end

    def retired_iap_identity!(snapshot)
      definition = RETIRED_IAPS.find do |candidate|
        candidate.fetch("id") == snapshot.fetch("iap_id")
      end
      unless definition &&
             snapshot.fetch("product_id") == definition.fetch("product_id") &&
             snapshot.fetch("type") == "CONSUMABLE"
        raise Error, "Retired IAP identity differs from the recovery contract"
      end
    end

    def retired_iap_preflight(snapshot)
      retired_iap_identity!(snapshot)
      unless snapshot.fetch("state") == SOURCE_TIP_STATE &&
             snapshot.fetch("availability_id").nil?
        raise Error, "Retired IAP is not safe for the one-shot availability POST"
      end

      :mutate
    end

    def retired_iap_observer(snapshot)
      retired_iap_identity!(snapshot)
      unless [SOURCE_TIP_STATE, TARGET_TIP_STATE].include?(snapshot.fetch("state"))
        raise Error, "Retired IAP entered an unexpected state"
      end
      if snapshot.fetch("availability_id")
        unless snapshot.fetch("available_in_new_territories") == false &&
               snapshot.fetch("available_territory_count") == 0
          raise Error, "Retired IAP availability differs from the exact target"
        end
      elsif snapshot.fetch("state") != SOURCE_TIP_STATE
        raise Error, "Retired IAP state and availability are inconsistent"
      end

      snapshot
    end

    def app_review_note_snapshot(expected_note)
      detail = fetch_data!(
        @client.get(
          "/v1/appStoreVersions/#{APP_VERSION_ID}/appStoreReviewDetail",
          {
            "fields[appStoreReviewDetails]" =>
              "notes,demoAccountRequired,contactFirstName,contactLastName," \
              "contactPhone,contactEmail"
          },
          optional: true
        ),
        type: "appStoreReviewDetails", id: nil,
        label: "App Review detail"
      )
      attributes = detail.fetch("attributes")
      note = attributes["notes"]
      contacts_present = %w[
        contactFirstName contactLastName contactPhone contactEmail
      ].all? do |field|
        value = attributes[field]
        value.instance_of?(String) && !value.strip.empty?
      end
      {
        "app_version_id" => APP_VERSION_ID,
        "review_detail_id" => detail.fetch("id"),
        "note_bytes" => note.instance_of?(String) ? note.bytesize : nil,
        "note_sha256" =>
          note.instance_of?(String) ? Digest::SHA256.hexdigest(note) : nil,
        "demo_account_required" => attributes["demoAccountRequired"],
        "contact_fields_present" => contacts_present,
        "exact" => note == expected_note &&
          attributes["demoAccountRequired"] == false && contacts_present
      }
    rescue KeyError => error
      raise Error, "App Review detail readback is incomplete: #{error.message}"
    end

    def app_review_note_preflight(snapshot)
      app_review_note_observer(snapshot)
      :mutate
    end

    def app_review_note_observer(snapshot)
      unless snapshot.fetch("app_version_id") == APP_VERSION_ID &&
             !snapshot.fetch("review_detail_id").to_s.empty? &&
             snapshot.fetch("demo_account_required") == false &&
             snapshot.fetch("contact_fields_present")
        raise Error, "App Review detail cannot be patched without preserving contacts"
      end
      snapshot
    end

    def app_review_note_body(detail_id, note)
      {
        data: {
          type: "appStoreReviewDetails", id: detail_id,
          attributes: { notes: note }
        }
      }
    end

    def workshop_note_snapshot(expected_note)
      purchase = fetch_data!(
        @client.get(
          "/v2/inAppPurchases/#{WORKSHOP_IAP_ID}",
          {
            "fields[inAppPurchases]" =>
              "name,productId,inAppPurchaseType,state,reviewNote"
          }
        ),
        type: "inAppPurchases", id: WORKSHOP_IAP_ID, label: "Workshop IAP"
      )
      versions = @client.get_all(
        "/v2/inAppPurchases/#{WORKSHOP_IAP_ID}/versions",
        {
          "fields[inAppPurchaseVersions]" => "version,state",
          "limit" => "50"
        }
      ).fetch("data")
      matches = versions.select { |version| version["id"] == WORKSHOP_VERSION_ID }
      unless matches.length == 1 && versions.length == 1
        raise Error, "Workshop IAP version catalogue differs from the recovery contract"
      end
      version = matches.first
      unless version["type"] == "inAppPurchaseVersions"
        raise Error, "Workshop IAP version has the wrong resource type"
      end
      attributes = purchase.fetch("attributes")
      note = attributes["reviewNote"]
      version_number = version.dig("attributes", "version")
      version_state = version.dig("attributes", "state")
      {
        "iap_id" => WORKSHOP_IAP_ID,
        "product_id" => attributes["productId"],
        "type" => attributes["inAppPurchaseType"],
        "state" => attributes["state"],
        "version_id" => WORKSHOP_VERSION_ID,
        "version" => version_number,
        "version_state" => version_state,
        "note_bytes" => note.instance_of?(String) ? note.bytesize : nil,
        "note_sha256" =>
          note.instance_of?(String) ? Digest::SHA256.hexdigest(note) : nil,
        "exact" => attributes["productId"] == WORKSHOP_PRODUCT_ID &&
          attributes["inAppPurchaseType"] == "NON_CONSUMABLE" &&
          WORKSHOP_PARENT_STATES.include?(attributes["state"]) &&
          workshop_version_one?(version_number) &&
          WORKSHOP_VERSION_STATES.include?(version_state) &&
          note == expected_note
      }
    rescue KeyError => error
      raise Error, "Workshop IAP readback is incomplete: #{error.message}"
    end

    def workshop_note_preflight(snapshot)
      workshop_note_observer(snapshot)
      :mutate
    end

    def workshop_note_observer(snapshot)
      unless snapshot.fetch("iap_id") == WORKSHOP_IAP_ID &&
             snapshot.fetch("product_id") == WORKSHOP_PRODUCT_ID &&
             snapshot.fetch("type") == "NON_CONSUMABLE" &&
             WORKSHOP_PARENT_STATES.include?(snapshot.fetch("state")) &&
             snapshot.fetch("version_id") == WORKSHOP_VERSION_ID &&
             workshop_version_one?(snapshot.fetch("version")) &&
             WORKSHOP_VERSION_STATES.include?(snapshot.fetch("version_state"))
        raise Error, "Workshop IAP identity or reviewable state differs"
      end
      snapshot
    end

    def workshop_version_one?(value)
      value == 1 || value == "1"
    end

    def fetch_data!(payload, type:, id:, label:)
      data = payload && payload["data"]
      unless data.instance_of?(Hash) && data["type"] == type &&
             (id.nil? || data["id"] == id)
        raise Error, "#{label} is missing or has the wrong identity"
      end
      data
    end
  end

  module CLI
    module_function

    def options!(argv, app_root:)
      options = {
        apply: false,
        run_id: nil,
        key_path: ENV["ASC_API_KEY_PATH"],
        timeout: 300.0,
        interval: 5.0,
        config: File.join(app_root, "fastlane", "release_config.json"),
        app_review_note:
          File.join(app_root, "fastlane", "metadata", "review_information", "notes.txt"),
        products: File.join(app_root, "fastlane", "pro_products.json")
      }
      OptionParser.new do |parser|
        parser.banner = "Usage: rejected_submission_recovery.rb [--apply --run-id ID]"
        parser.on("--apply") { options[:apply] = true }
        parser.on("--run-id ID") { |value| options[:run_id] = value }
        parser.on("--key-path PATH") { |value| options[:key_path] = value }
        parser.on("--timeout SECONDS", Float) { |value| options[:timeout] = value }
        parser.on("--interval SECONDS", Float) { |value| options[:interval] = value }
      end.parse!(argv)
      if options[:apply] && options[:run_id].to_s.empty?
        raise Error, "--apply requires an explicit --run-id"
      end
      options
    end

    def run!(argv, stdout: $stdout)
      app_root = File.expand_path("../..", __dir__)
      options = options!(argv, app_root: app_root)
      config = JSON.parse(File.binread(options.fetch(:config)))
      validate_config!(config)
      source_notes = SourceNotes.load!(
        app_review_path: options.fetch(:app_review_note),
        products_path: options.fetch(:products)
      )
      client = NovaStationPinballAscClient.new(
        key_path: options.fetch(:key_path)
      )
      proof_store = nil
      if options[:apply]
        artifact_root = File.expand_path(config.fetch("artifact_root"), app_root)
        unless artifact_root.start_with?("#{app_root}/")
          raise Error, "Recovery artifact root escapes the app repository"
        end
        proof_store = ProofStore.new(
          artifact_root: artifact_root, run_id: options.fetch(:run_id)
        )
      end
      coordinator = Coordinator.new(
        client: client, source_notes: source_notes, proof_store: proof_store,
        timeout: options.fetch(:timeout), interval: options.fetch(:interval)
      )
      result = options[:apply] ? coordinator.apply! : coordinator.status
      stdout.puts(JSON.pretty_generate(result))
      result
    end

    def validate_config!(config)
      unless config.fetch("app_slug") == "NovaStationPinball" &&
             config.fetch("bundle_id") == BUNDLE_ID &&
             config.fetch("version") == VERSION &&
             config.fetch("artifact_root") ==
               "Builds/AppStore/NovaStationPinball"
        raise Error, "Release configuration differs from the recovery scope"
      end
      active = config.fetch("iap_products").map do |product|
        [product.fetch("product_id"), product.fetch("type")]
      end
      unless active == [[WORKSHOP_PRODUCT_ID, "NON_CONSUMABLE"]]
        raise Error, "Active IAP configuration differs from the recovery scope"
      end
      retired = config.fetch("retired_iap_products").map do |product|
        [
          product.fetch("product_id"), product.fetch("type"),
          product.fetch("target_state")
        ]
      end.sort
      expected = RETIRED_IAPS.map do |product|
        [product.fetch("product_id"), "CONSUMABLE", TARGET_TIP_STATE]
      end.sort
      unless retired == expected
        raise Error, "Retired IAP configuration differs from the recovery scope"
      end
      true
    rescue KeyError => error
      raise Error, "Release configuration is incomplete: #{error.message}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    NovaStationPinballRejectedSubmissionRecovery::CLI.run!(ARGV)
  rescue StandardError => error
    warn "rejected_submission_recovery: #{error.class}: #{error.message}"
    exit 1
  end
end
