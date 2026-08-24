# frozen_string_literal: true

require "digest"
require "bigdecimal"
require "json"
require "open3"

# Immutable bridge between the source candidate that produced the uploaded
# build and the post-upload ASC tooling allowed to act on it. The binary was built
# from +source_head+; a later tooling-only commit must never be represented as
# the binary's source.
module NovaStationPinballReleaseProvenance
  class Error < RuntimeError; end

  Contract = Struct.new(
    :app_root,
    :artifact_root,
    :run_id,
    :candidate_id,
    :candidate_receipt_sha256,
    :ipa_upload_intent_sha256,
    :ipa_upload_receipt_sha256,
    :release_manifest_sha256,
    :target_build_sha256,
    :source_head,
    :version,
    :build,
    :app_id,
    :app_version_id,
    :bundle_id,
    :origin_url,
    :asc_build_id,
    :uploaded_date,
    :ipa_sha256,
    :workshop_iap_id,
    :workshop_product_id,
    :workshop_version_id,
    :allowed_tooling_paths,
    keyword_init: true
  )

  APP_ROOT = File.expand_path("../..", __dir__)
  APP_REVIEW_DETAIL_ID = "976c462e-b150-48f3-bf93-fb056e1e6970"
  APP_REVIEW_SOURCE_NOTE = [
    624, "e84d0e43bb941b9967165f84e4f929d64a6b09d1267c73e075b7af51929b215b"
  ].freeze
  APP_REVIEW_RECOVERY_NOTE = [
    3_898, "940dc92a915638305980d4d5c411e7ea3a2612ec8bbbe0d25b8a9b971f1af345"
  ].freeze
  APP_REVIEW_TARGET_NOTE = [
    3_953, "15fc5ee015ac226f1cb5e1ae6cee225aa0b9a9a61c379e2f48dcf3526f069ab3"
  ].freeze
  WORKSHOP_SOURCE_NOTE = [
    931, "fc1240ab71410baa808ff90cf057dd7cc89cd00f45a5ffb6adf852a4c5d4ff6f"
  ].freeze
  WORKSHOP_TARGET_NOTE = [
    1_312, "58b87d2d341a7061446c5c07d4507d7100605b78e4bbb4a6877ae90aac474db3"
  ].freeze
  WORKSHOP_SCREENSHOT = {
    "id" => "ae977029-29cf-403b-bd60-c7b2cb18a275",
    "fileName" => "SOURCE",
    "fileSize" => 227_746,
    "sourceFileChecksum" => "8a7cd3cb4bd20017ab9384226476a962",
    "state" => "COMPLETE",
    "errors" => nil,
    "warnings" => nil
  }.freeze
  WORKSHOP_CATALOGUE = {
    "localizations" => [
      {
        "id" => "f70d3c97-40f8-46c9-aa5e-67822dbd7943",
        "locale" => "en-US", "name" => "The Workshop",
        "description" => "Unlimited rewind, replay and shot drills."
      },
      {
        "id" => "269a412f-6140-4345-a40a-ef0712e43ac6",
        "locale" => "fr-FR", "name" => "L’Atelier",
        "description" => "Rembobinage, revisionnage et atelier de tir."
      }
    ].freeze,
    "availability_id" => "6803400833",
    "territory_count" => 175,
    "territory_ids_sha256" =>
      "95087f3eecee49207a08367a6fac82fd364151d370dfc95f4081f449c0230b9b",
    "price_schedule_id" => "6803400833",
    "base_territory" => "FRA",
    "base_currency" => "EUR",
    "manual_price_id" =>
      "eyJzIjoiNjgwMzQwMDgzMyIsInQiOiJGUkEiLCJwIjoiMTAwNjIiLCJzZCI6MC4wLCJlZCI6MC4wfQ",
    "price_point_id" =>
      "eyJzIjoiNjgwMzQwMDgzMyIsInQiOiJGUkEiLCJwIjoiMTAwNjIifQ",
    "customer_price" => "4.99"
  }.freeze
  SOURCE_SELECTED_BUILD = {
    "id" => "41e4e41e-010e-47cf-a921-89dfc988424d",
    "version" => "1",
    "processingState" => "VALID",
    "uploadedDate" => "2026-08-11T05:34:07-07:00",
    "expired" => false,
    "usesNonExemptEncryption" => false
  }.freeze
  CURRENT = Contract.new(
    app_root: APP_ROOT,
    artifact_root: "Builds/AppStore/NovaStationPinball",
    run_id: "nova-100-b3-20260824-gcid1",
    candidate_id: "cc12d0573343babadbefeded29c51b2d327211fcd8c4ed8ae2e40b42cf7ea81b",
    candidate_receipt_sha256: "6f9ba07b27ade94c29ee8ea1b24d721184ee7d5aa8f446e6612b65eda52061f6",
    ipa_upload_intent_sha256: "e62ae26f24084bd7d66cb949a28652dd4b54d2cd332c785ce8d9dd5e21f9eccf",
    ipa_upload_receipt_sha256: "3339e0fcd827b9f622cf75f3d0a5bdf523931d1b37e1da5075a616b8fdf7f070",
    release_manifest_sha256: "a3c65ce599f245475600167c715fe1ec4e063fa89a6db05b3d6b4fc557889fc0",
    target_build_sha256: "5492e818824d484861efb6aed9968735228f249370447714cdf16e0f8db307a3",
    source_head: "1976f999a762deb43cd3dcad7ad957592eda879e",
    version: "1.0",
    build: "3",
    app_id: "6799920176",
    app_version_id: "1739b449-a776-42ee-8b31-0997496c2a09",
    bundle_id: "com.bnjdpn.NovaStationPinball",
    origin_url: "https://github.com/bnjdpn/NovaStationPinball.git",
    asc_build_id: "44ba6b70-0936-4201-b984-21a5f4752f95",
    uploaded_date: "2026-08-24T02:54:21-07:00",
    ipa_sha256: "83a461be1bb78bb1c82dbfbb585d9cfecc4aab77bfc5c7e8611dacbcc3c5eab6",
    workshop_iap_id: "6803400833",
    workshop_product_id: "com.bnjdpn.NovaStationPinball.workshop",
    workshop_version_id: "bc22c948-ea0e-4bae-be8f-c78d091dd27b",
    allowed_tooling_paths: %w[
      scripts/app_store/release_provenance.rb
    ].freeze
  ).freeze

  module_function

  def verify_release_arguments!(bundle_id:, version:, build: nil, contract: CURRENT)
    unless bundle_id.to_s == contract.bundle_id && version.to_s == contract.version &&
           (build.nil? || build.to_s == contract.build)
      raise Error, "Requested release resource differs from the uploaded build"
    end
    true
  end

  def verify_local!(run_id:, candidate_id:, contract: CURRENT)
    unless run_id.to_s == contract.run_id && candidate_id.to_s == contract.candidate_id
      raise Error, "Release mutation requires the exact uploaded candidate"
    end

    head = git!(contract, "rev-parse", "HEAD")
    origin = git!(contract, "rev-parse", "origin/main")
    branch = git!(contract, "branch", "--show-current")
    origin_url = git!(contract, "remote", "get-url", "origin")
    dirty = git!(contract, "status", "--porcelain", "--untracked-files=all")
    unless head == origin && branch == "main" &&
           origin_url == contract.origin_url && dirty.empty?
      raise Error, "Repository branch, HEAD, origin/main, URL or clean-tree proof differs"
    end
    verify_no_git_operation!(contract)
    unless git_success?(contract, "merge-base", "--is-ancestor", contract.source_head, head)
      raise Error, "Current tooling HEAD does not descend from the uploaded source HEAD"
    end
    changed = git!(contract, "diff", "--name-only", "#{contract.source_head}..#{head}")
      .lines.map(&:strip).reject(&:empty?).sort
    unexpected = changed - contract.allowed_tooling_paths
    unless unexpected.empty?
      raise Error, "Post-upload HEAD changes product or release data: #{unexpected.join(',')}"
    end

    run_root = File.join(contract.app_root, contract.artifact_root, contract.run_id)
    receipt_path = File.join(run_root, "logs", "candidate-receipt.json")
    receipt = read_json!(
      receipt_path, expected_sha256: contract.candidate_receipt_sha256,
      expected_mode: 0o600
    )
    verify_candidate_receipt!(receipt, contract, run_root)
    verify_source_manifest!(receipt.fetch("source_manifest"), contract)
    verify_release_files!(receipt, contract, run_root)
    {
      "source_head" => contract.source_head,
      "tooling_head" => head,
      "candidate_id" => contract.candidate_id,
      "run_id" => contract.run_id,
      "version" => contract.version,
      "build" => contract.build,
      "ipa_sha256" => contract.ipa_sha256
    }
  rescue KeyError, JSON::ParserError => error
    raise Error, "Release provenance is incomplete: #{error.message}"
  end

  # Network-backed remote readback is deliberately separate from verify_local!
  # so deterministic unit tests can exercise local provenance without reaching
  # GitHub. Every real mutation preflight calls both functions.
  def verify_remote!(contract: CURRENT)
    head = git!(contract, "rev-parse", "HEAD")
    lines = git_raw!(
      contract, "ls-remote", "--heads", "origin", "refs/heads/main"
    ).lines.map(&:strip).reject(&:empty?)
    expected = "#{head}\trefs/heads/main"
    unless lines == [expected]
      raise Error, "Remote origin/main does not equal the guarded tooling HEAD"
    end
    head
  end

  def verify_live_build!(client:, contract: CURRENT)
    apps = client.get_all("/v1/apps", {
      "filter[bundleId]" => contract.bundle_id,
      "fields[apps]" => "bundleId",
      "limit" => "20"
    }).fetch("data").select do |app|
      app["id"] == contract.app_id &&
        app.dig("attributes", "bundleId") == contract.bundle_id
    end
    raise Error, "Exact ASC app identity differs" unless apps.length == 1

    builds = client.get_all("/v1/builds", {
      "filter[app]" => contract.app_id,
      "filter[preReleaseVersion.version]" => contract.version,
      "filter[preReleaseVersion.platform]" => "IOS",
      "fields[builds]" =>
        "version,processingState,uploadedDate,expired,usesNonExemptEncryption",
      "limit" => "200"
    }).fetch("data").select do |build|
      build.dig("attributes", "version").to_s == contract.build
    end
    raise Error, "Exact ASC build is missing or ambiguous" unless builds.length == 1

    verify_build_resource!(builds.first, contract: contract)
  rescue KeyError => error
    raise Error, "ASC build provenance is incomplete: #{error.message}"
  end

  def verify_app_version!(client:, allowed_states:, contract: CURRENT)
    unless allowed_states.instance_of?(Array) && !allowed_states.empty? &&
           allowed_states.all? { |state| state.instance_of?(String) && !state.empty? }
      raise Error, "App-version allowed states are missing"
    end
    versions = client.get_all(
      "/v1/apps/#{contract.app_id}/appStoreVersions",
      {
        "filter[platform]" => "IOS",
        "filter[versionString]" => contract.version,
        "fields[appStoreVersions]" =>
          "versionString,appStoreState,appVersionState,platform,build",
        "limit" => "20"
      }
    ).fetch("data").select do |version|
        version["id"] == contract.app_version_id &&
        version.dig("attributes", "versionString") == contract.version &&
        version.dig("attributes", "platform") == "IOS" &&
        allowed_states.include?(version.dig("attributes", "appStoreState")) &&
        allowed_states.include?(version.dig("attributes", "appVersionState"))
    end
    raise Error, "Exact iOS App Store version is missing or ambiguous" unless versions.length == 1

    versions.first
  rescue KeyError => error
    raise Error, "ASC app-version provenance is incomplete: #{error.message}"
  end

  def verify_selected_build!(client:, version_id:, contract: CURRENT)
    unless version_id == contract.app_version_id
      raise Error, "App Store version identity differs from the uploaded candidate"
    end
    response = client.get(
      "/v1/appStoreVersions/#{version_id}/build",
      {
        "fields[builds]" =>
          "version,processingState,uploadedDate,expired,usesNonExemptEncryption"
      },
      optional: true
    )
    build = response && response["data"]
    raise Error, "Exact uploaded build is not selected" unless build

    verify_build_resource!(build, contract: contract)
  end

  def selected_build_state!(client:, version_id:, contract: CURRENT)
    unless version_id == contract.app_version_id
      raise Error, "App Store version identity differs from the uploaded candidate"
    end
    response = client.get(
      "/v1/appStoreVersions/#{version_id}/build",
      {
        "fields[builds]" =>
          "version,processingState,uploadedDate,expired,usesNonExemptEncryption"
      },
      optional: true
    )
    build = response && response["data"]
    raise Error, "Selected build is missing" unless build

    actual = build_identity(build)
    return :source if actual == SOURCE_SELECTED_BUILD
    return :target if actual == build_identity_for(contract)

    raise Error, "Selected build is neither the audited source nor the target build"
  end

  # GET-only readiness shared by recovery and the final review mutator. During
  # recovery the two specifically audited source notes are accepted; review
  # submission requires both checked-in target notes.
  def verify_review_readiness!(client:, allow_source_notes: false,
                               allowed_workshop_parent_states: ["READY_TO_SUBMIT"],
                               allowed_workshop_states: %w[
                                 PREPARE_FOR_SUBMISSION READY_FOR_REVIEW
                               ],
                               contract: CURRENT, catalogue: WORKSHOP_CATALOGUE)
    detail = client.get(
      "/v1/appStoreVersions/#{contract.app_version_id}/appStoreReviewDetail",
      {
        "fields[appStoreReviewDetails]" =>
          "notes,demoAccountRequired,contactFirstName,contactLastName," \
          "contactPhone,contactEmail"
      }
    ).fetch("data")
    detail_attributes = detail.fetch("attributes")
    allowed_app_notes = [APP_REVIEW_TARGET_NOTE]
    if allow_source_notes
      allowed_app_notes.concat([APP_REVIEW_SOURCE_NOTE, APP_REVIEW_RECOVERY_NOTE])
    end
    contacts_present = %w[
      contactFirstName contactLastName contactPhone contactEmail
    ].all? do |field|
      value = detail_attributes[field]
      value.instance_of?(String) && !value.strip.empty?
    end
    unless detail.fetch("id") == APP_REVIEW_DETAIL_ID &&
           allowed_app_notes.include?(note_identity(detail_attributes["notes"])) &&
           detail_attributes["demoAccountRequired"] == false &&
           contacts_present
      raise Error, "App Review detail or note differs from the audited release"
    end

    purchase = client.get(
      "/v2/inAppPurchases/#{contract.workshop_iap_id}",
      {
        "fields[inAppPurchases]" =>
          "name,productId,inAppPurchaseType,state,reviewNote,familySharable"
      }
    ).fetch("data")
    purchase_attributes = purchase.fetch("attributes")
    allowed_workshop_notes = [WORKSHOP_TARGET_NOTE]
    allowed_workshop_notes << WORKSHOP_SOURCE_NOTE if allow_source_notes
    unless purchase.fetch("id") == contract.workshop_iap_id &&
           purchase_attributes["name"] == "Nova Station Pinball Workshop" &&
           purchase_attributes["productId"] == contract.workshop_product_id &&
           purchase_attributes["inAppPurchaseType"] == "NON_CONSUMABLE" &&
           allowed_workshop_parent_states.include?(purchase_attributes["state"]) &&
           purchase_attributes["familySharable"] == false &&
           allowed_workshop_notes.include?(
             note_identity(purchase_attributes["reviewNote"])
           )
      raise Error, "Workshop identity, state or note differs from the audited release"
    end

    versions = client.get_all(
      "/v2/inAppPurchases/#{contract.workshop_iap_id}/versions",
      { "fields[inAppPurchaseVersions]" => "version,state", "limit" => "50" }
    ).fetch("data")
    version = versions.first
    unless versions.length == 1 && version.fetch("id") == contract.workshop_version_id &&
           version.fetch("type") == "inAppPurchaseVersions" &&
           version.dig("attributes", "version").to_s == "1" &&
           allowed_workshop_states.include?(
             version.dig("attributes", "state")
           )
      raise Error, "Workshop version differs from the frozen review resource"
    end

    localizations = client.get_all(
      "/v2/inAppPurchases/#{contract.workshop_iap_id}/inAppPurchaseLocalizations",
      {
        "fields[inAppPurchaseLocalizations]" => "locale,name,description",
        "limit" => "50"
      }
    ).fetch("data").map do |item|
      attributes = item.fetch("attributes")
      {
        "id" => item.fetch("id"), "locale" => attributes["locale"],
        "name" => attributes["name"], "description" => attributes["description"]
      }
    end.sort_by { |item| item.fetch("locale") }
    unless localizations == catalogue.fetch("localizations")
      raise Error, "Workshop localizations differ from the audited catalogue"
    end

    availability = client.get(
      "/v2/inAppPurchases/#{contract.workshop_iap_id}/inAppPurchaseAvailability",
      {
        "fields[inAppPurchaseAvailabilities]" =>
          "availableInNewTerritories,availableTerritories"
      }
    ).fetch("data")
    territories = client.get_all(
      "/v1/inAppPurchaseAvailabilities/#{availability.fetch('id')}/availableTerritories",
      { "limit" => "200" }
    ).fetch("data")
    territory_ids = territories.map do |territory|
      unless territory["type"] == "territories" && !territory["id"].to_s.empty?
        raise Error, "Workshop availability contains an invalid territory"
      end
      territory.fetch("id")
    end
    territory_digest = Digest::SHA256.hexdigest(
      territory_ids.sort.join("\n")
    )
    unless availability.fetch("type") == "inAppPurchaseAvailabilities" &&
           availability.fetch("id") == catalogue.fetch("availability_id") &&
           availability.dig("attributes", "availableInNewTerritories") == true &&
           territory_ids.uniq.length == catalogue.fetch("territory_count") &&
           territory_ids.length == catalogue.fetch("territory_count") &&
           territory_digest == catalogue.fetch("territory_ids_sha256")
      raise Error, "Workshop availability or territories differ"
    end

    verify_workshop_price!(
      client: client, contract: contract, catalogue: catalogue
    )

    screenshot = client.get(
      "/v2/inAppPurchases/#{contract.workshop_iap_id}/appStoreReviewScreenshot",
      {
        "fields[inAppPurchaseAppStoreReviewScreenshots]" =>
          "fileName,fileSize,sourceFileChecksum,assetDeliveryState"
      }
    ).fetch("data")
    screenshot_attributes = screenshot.fetch("attributes")
    actual_screenshot = {
      "id" => screenshot.fetch("id"),
      "type" => screenshot.fetch("type"),
      "fileName" => screenshot_attributes["fileName"],
      "fileSize" => screenshot_attributes["fileSize"],
      "sourceFileChecksum" => screenshot_attributes["sourceFileChecksum"],
      "state" => screenshot_attributes.dig("assetDeliveryState", "state"),
      "errors" => screenshot_attributes.dig("assetDeliveryState", "errors"),
      "warnings" => screenshot_attributes.dig("assetDeliveryState", "warnings")
    }
    expected_screenshot = WORKSHOP_SCREENSHOT.merge(
      "type" => "inAppPurchaseAppStoreReviewScreenshots"
    )
    unless actual_screenshot == expected_screenshot
      raise Error, "Workshop review screenshot differs from the frozen candidate asset"
    end

    {
      "app_review_detail_id" => detail.fetch("id"),
      "workshop_version_id" => version.fetch("id"),
      "workshop_screenshot_id" => screenshot.fetch("id")
    }
  rescue KeyError => error
    raise Error, "ASC review readiness is incomplete: #{error.message}"
  end

  def verify_workshop_price!(client:, contract:, catalogue:)
    schedule = client.get(
      "/v2/inAppPurchases/#{contract.workshop_iap_id}/iapPriceSchedule",
      {
        "fields[inAppPurchasePriceSchedules]" =>
          "baseTerritory,manualPrices,automaticPrices"
      }
    ).fetch("data")
    base = client.get(
      "/v1/inAppPurchasePriceSchedules/#{schedule.fetch('id')}/baseTerritory",
      { "fields[territories]" => "currency" }
    ).fetch("data")
    unless schedule.fetch("type") == "inAppPurchasePriceSchedules" &&
           schedule.fetch("id") == catalogue.fetch("price_schedule_id") &&
           base.fetch("type") == "territories" &&
           base.fetch("id") == catalogue.fetch("base_territory") &&
           base.dig("attributes", "currency") == catalogue.fetch("base_currency")
      raise Error, "Workshop base price territory or currency contract differs"
    end

    query = {
      "filter[territory]" => catalogue.fetch("base_territory"),
      "include" => "inAppPurchasePricePoint",
      "fields[inAppPurchasePrices]" =>
        "startDate,endDate,inAppPurchasePricePoint,territory",
      "fields[inAppPurchasePricePoints]" => "customerPrice,territory",
      "limit" => "200"
    }
    manual = client.get_all(
      "/v1/inAppPurchasePriceSchedules/#{schedule.fetch('id')}/manualPrices",
      query
    )
    automatic = client.get_all(
      "/v1/inAppPurchasePriceSchedules/#{schedule.fetch('id')}/automaticPrices",
      query
    )
    raise Error, "Workshop automatic prices differ" unless automatic.fetch("data") == []
    records = manual.fetch("data")
    raise Error, "Workshop manual price is missing or ambiguous" unless records.length == 1

    record = records.first
    link = record.dig("relationships", "inAppPurchasePricePoint", "data")
    territory = record.dig("relationships", "territory", "data")
    points = manual.fetch("included", []).select do |item|
      item["type"] == "inAppPurchasePricePoints" && item["id"] == link&.fetch("id", nil)
    end
    point = points.first
    unless record.fetch("type") == "inAppPurchasePrices" &&
           record.fetch("id") == catalogue.fetch("manual_price_id") &&
           record.dig("attributes", "startDate").nil? &&
           record.dig("attributes", "endDate").nil? &&
           link == {
             "type" => "inAppPurchasePricePoints",
             "id" => catalogue.fetch("price_point_id")
           } && (territory.nil? || territory == {
             "type" => "territories", "id" => catalogue.fetch("base_territory")
           }) && points.length == 1 &&
           BigDecimal(point.dig("attributes", "customerPrice").to_s) ==
             BigDecimal(catalogue.fetch("customer_price"))
      raise Error, "Workshop active FRA/EUR price differs"
    end
    true
  rescue ArgumentError, KeyError => error
    raise Error, "Workshop price readback is incomplete: #{error.message}"
  end

  def selected_build_exact?(client:, version_id:, contract: CURRENT)
    verify_selected_build!(client: client, version_id: version_id, contract: contract)
    true
  rescue Error
    false
  end

  def note_identity(value)
    return [nil, nil] unless value.instance_of?(String)

    [value.bytesize, Digest::SHA256.hexdigest(value)]
  end

  def verify_build_resource!(build, contract: CURRENT)
    expected = build_identity_for(contract)
    actual = build_identity(build)
    raise Error, "ASC build does not match the uploaded IPA proof" unless actual == expected

    build
  end

  def build_identity_for(contract)
    {
      "id" => contract.asc_build_id,
      "version" => contract.build,
      "processingState" => "VALID",
      "uploadedDate" => contract.uploaded_date,
      "expired" => false,
      "usesNonExemptEncryption" => false
    }
  end

  def build_identity(build)
    {
      "id" => build["id"],
      "version" => build.dig("attributes", "version").to_s,
      "processingState" => build.dig("attributes", "processingState"),
      "uploadedDate" => build.dig("attributes", "uploadedDate"),
      "expired" => build.dig("attributes", "expired"),
      "usesNonExemptEncryption" =>
        build.dig("attributes", "usesNonExemptEncryption")
    }
  end

  def release_identity(local:, build:, contract: CURRENT)
    verify_build_resource!(build, contract: contract)
    expected_local = %w[
      source_head tooling_head candidate_id run_id version build ipa_sha256
    ]
    unless local.instance_of?(Hash) && local.keys.sort == expected_local.sort
      raise Error, "Local release identity has an invalid shape"
    end
    {
      "candidate_id" => local.fetch("candidate_id"),
      "run_id" => local.fetch("run_id"),
      "source_head" => local.fetch("source_head"),
      "version" => local.fetch("version"),
      "build" => local.fetch("build"),
      "asc_build_id" => build.fetch("id"),
      "uploaded_date" => build.dig("attributes", "uploadedDate"),
      "ipa_sha256" => local.fetch("ipa_sha256")
    }
  end

  def verify_candidate_receipt!(receipt, contract, run_root)
    accepted_validation = [
      {
        "passed" => true,
        "commands" => [{
          "argv" => [
            "bin/apple-release", "lane", "NovaStationPinball",
            "release_contract"
          ],
          "status" => 0
        }]
      },
      {
        "passed" => true,
        "commands" => [{
          "argv" => ["fastlane", "release_contract"],
          "status" => 0
        }]
      }
    ]
    unless receipt.keys.sort == %w[
      app artifacts asc execution_id final_commit schema_version source_manifest
      toolchain validation
    ].sort &&
           receipt.fetch("schema_version") == 1 &&
           receipt.fetch("app") == "nova-station-pinball" &&
           receipt.fetch("execution_id") == contract.run_id &&
           accepted_validation.include?(receipt.fetch("validation")) &&
           receipt.fetch("asc") == {
             "uploaded" => true, "readback" => "success", "state" => "VALID"
           } && receipt.fetch("final_commit").nil?
      raise Error, "Candidate receipt identity or validation differs"
    end

    artifacts = receipt.fetch("artifacts")
    unless artifacts.is_a?(Array) &&
           artifacts.map { |artifact| artifact["path"] }.uniq.length == artifacts.length
      raise Error, "Candidate receipt artifacts are invalid or duplicated"
    end
    artifacts.each do |artifact|
      relative = artifact.fetch("path")
      unless relative.is_a?(String) && !relative.empty? &&
             artifact.fetch("sha256").to_s.match?(/\A[0-9a-f]{64}\z/)
        raise Error, "Candidate artifact identity is invalid"
      end
      absolute = File.expand_path(relative, run_root)
      unless absolute.start_with?("#{File.expand_path(run_root)}/") && regular_file?(absolute) &&
             Digest::SHA256.file(absolute).hexdigest == artifact.fetch("sha256")
        raise Error, "Candidate artifact bytes differ: #{relative}"
      end
    end
  end

  def verify_source_manifest!(manifest, contract)
    unless manifest.keys.sort == %w[base_head candidate_id entries schema_version] &&
           manifest.fetch("schema_version") == 1 &&
           manifest.fetch("base_head") == contract.source_head &&
           manifest.fetch("candidate_id") == contract.candidate_id
      raise Error, "Candidate source manifest identity differs"
    end
    unsigned = {
      "schema_version" => manifest.fetch("schema_version"),
      "base_head" => manifest.fetch("base_head"),
      "entries" => manifest.fetch("entries")
    }
    unless Digest::SHA256.hexdigest(JSON.generate(unsigned)) == contract.candidate_id
      raise Error, "Candidate source manifest digest differs"
    end

    entries = manifest.fetch("entries")
    unless entries.is_a?(Array) &&
           entries.map { |entry| entry.fetch("path") }.uniq.length == entries.length
      raise Error, "Candidate source manifest contains duplicate paths"
    end
    expected = entries.to_h { |entry| [entry.fetch("path"), entry] }
    actual = commit_entries(contract, contract.source_head)
    raise Error, "Candidate source manifest does not match its source commit" unless actual == expected
  end

  def verify_release_files!(receipt, contract, run_root)
    artifact = receipt.fetch("artifacts").select do |item|
      item["path"] == "archives/NovaStationPinball.ipa"
    end
    unless artifact == [{
      "path" => "archives/NovaStationPinball.ipa", "sha256" => contract.ipa_sha256
    }]
      raise Error, "Candidate receipt does not bind the uploaded IPA"
    end

    expected_upload = {
      "schema_version" => 1,
      "phase" => "observed",
      "kind" => "ipa",
      "candidate_id" => contract.candidate_id,
      "version" => contract.version,
      "payload" => {
        "build" => contract.build, "count" => 1,
        "sha256" => contract.ipa_sha256
      }
    }
    intent = read_json!(
      File.join(run_root, "logs", "ipa-upload-intent.json"),
      expected_sha256: contract.ipa_upload_intent_sha256, expected_mode: 0o600
    )
    expected_intent = expected_upload.merge("phase" => "intent")
    raise Error, "IPA upload intent differs" unless intent == expected_intent

    upload = read_json!(
      File.join(run_root, "logs", "ipa-upload-receipt.json"),
      expected_sha256: contract.ipa_upload_receipt_sha256, expected_mode: 0o600
    )
    raise Error, "IPA upload receipt differs" unless upload == expected_upload

    release = read_json!(
      File.join(run_root, "logs", "release-manifest.json"),
      expected_sha256: contract.release_manifest_sha256, expected_mode: 0o600
    )
    unless release == {
      "schema_version" => 1,
      "candidate_id" => contract.candidate_id,
      "version" => contract.version,
      "build" => contract.build,
      "ipa_sha256" => contract.ipa_sha256
    }
      raise Error, "Release manifest differs from the uploaded IPA"
    end

    target = read_json!(
      File.join(run_root, "logs", "target-build.json"),
      expected_sha256: contract.target_build_sha256, expected_mode: 0o600
    )
    unless target == { "version" => contract.version, "build" => contract.build }
      raise Error, "Target-build receipt differs"
    end
  end

  def read_json!(path, expected_sha256: nil, expected_mode: nil)
    raise Error, "Release proof is missing or redirected: #{path}" unless regular_file?(path)
    if expected_sha256 && Digest::SHA256.file(path).hexdigest != expected_sha256
      raise Error, "Release proof bytes differ: #{path}"
    end
    if expected_mode && (File.stat(path).mode & 0o777) != expected_mode
      raise Error, "Release proof mode differs: #{path}"
    end
    JSON.parse(File.binread(path))
  end

  def verify_no_git_operation!(contract)
    %w[
      MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge
      rebase-apply sequencer
    ].each do |marker|
      path = git!(contract, "rev-parse", "--git-path", marker)
      if File.exist?(path) || File.symlink?(path)
        raise Error, "A Git operation is still in progress: #{marker}"
      end
    end
    true
  end

  def regular_file?(path)
    File.file?(path) && !File.symlink?(path)
  end

  def commit_entries(contract, commit)
    stdout = git_raw!(contract, "ls-tree", "-rz", "--full-tree", commit)
    stdout.split("\0", -1).each_with_object({}) do |row, result|
      next if row.empty?

      metadata, path = row.split("\t", 2)
      mode, type, object = metadata.split(" ", 3)
      next unless type == "blob"

      bytes = git_raw!(contract, "cat-file", "blob", object)
      result[path] = {
        "path" => path,
        "type" => mode == "120000" ? "symlink" : "file",
        "mode" => mode,
        "sha256" => Digest::SHA256.hexdigest(bytes)
      }
    end
  end

  def git!(contract, *arguments)
    git_raw!(contract, *arguments).strip
  end

  def git_raw!(contract, *arguments)
    stdout, stderr, status = Open3.capture3(
      "git", "-C", contract.app_root, *arguments
    )
    raise Error, "Git provenance failed: #{stderr.strip}" unless status.success?

    stdout
  end

  def git_success?(contract, *arguments)
    _stdout, _stderr, status = Open3.capture3(
      "git", "-C", contract.app_root, *arguments
    )
    status.success?
  end
end
