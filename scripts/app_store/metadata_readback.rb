# frozen_string_literal: true

require "digest"
require "json"

module NovaStationPinballMetadataReadback
  VERSION_FILES = {
    "description.txt" => "description",
    "keywords.txt" => "keywords",
    "marketing_url.txt" => "marketingUrl",
    "promotional_text.txt" => "promotionalText",
    "support_url.txt" => "supportUrl"
  }.freeze
  APP_INFO_FILES = {
    "name.txt" => "name",
    "privacy_url.txt" => "privacyPolicyUrl",
    "subtitle.txt" => "subtitle"
  }.freeze

  module_function

  def proof(client:, version:, app_info:, config:, root:)
    unless config.dig("release_pipeline", "metadata_readback_contract") == "deliver-v1"
      raise ArgumentError, "Unsupported metadata readback contract"
    end
    raise ArgumentError, "Metadata readback requires an App Store version" unless version
    raise ArgumentError, "Metadata readback requires editable App Info" unless app_info

    expected, local_errors = expected_payload(config, root)
    actual, remote_errors = actual_payload(client, version, app_info, expected)
    mismatches = (local_errors + remote_errors + compare(expected, actual)).uniq.sort_by do |item|
      [item.fetch("path").to_s, item.fetch("reason").to_s]
    end
    expected_digest = digest(expected)
    actual_digest = digest(actual)
    {
      "schema_version" => 1,
      "contract" => "deliver-v1",
      "complete" => mismatches.empty? && expected_digest == actual_digest,
      "locales" => locales(config),
      "checked" => checked(expected),
      "omissions" => config.dig("release_pipeline", "metadata_expected_omissions"),
      "mismatches" => mismatches,
      "expected_sha256" => expected_digest,
      "actual_sha256" => actual_digest
    }
  end

  def identity(config:, root:)
    expected, errors = expected_payload(config, root)
    unless errors.empty?
      raise ArgumentError,
            "Local metadata is incomplete: #{errors.map { |item| item.fetch('path') }.join(', ')}"
    end
    {
      "count" => expected.fetch("version_localizations").length *
        (VERSION_FILES.length + APP_INFO_FILES.length) + 4,
      "sha256" => digest(expected)
    }
  end

  def expected_payload(config, root)
    configured = locales(config)
    metadata_root = File.join(File.expand_path(root), "fastlane", "metadata")
    errors = []
    directories = if File.directory?(metadata_root) && !File.symlink?(metadata_root)
                    Dir.children(metadata_root).select do |entry|
                      entry != "review_information" &&
                        File.directory?(File.join(metadata_root, entry))
                    end.sort
                  else
                    []
                  end
    (configured - directories).each do |locale|
      errors << issue("local_metadata.locales.#{locale}", "missing")
    end
    (directories - configured).each do |locale|
      errors << issue("local_metadata.locales.#{locale}", "unexpected")
    end

    version_localizations = localized_payload(
      metadata_root, configured, VERSION_FILES, errors
    )
    app_info_localizations = localized_payload(
      metadata_root, configured, APP_INFO_FILES, errors
    )
    review_fields = config.dig(
      "release_pipeline", "metadata_review_information_fields"
    )
    unless review_fields == ["notes"]
      raise ArgumentError, "Configured review information fields are invalid"
    end
    review = {
      "notes" => read_text(
        File.join(metadata_root, "review_information", "notes.txt"),
        "local_metadata.review_information.notes.txt", errors
      ),
      "demoAccountRequired" => false,
      "appStoreReviewAttachments" => []
    }
    rating = read_json(
      File.join(File.expand_path(root), config.fetch("age_rating")),
      "local_metadata.app_rating_config.json", errors
    )
    [
      {
        "version_localizations" => version_localizations,
        "app_info_localizations" => app_info_localizations,
        "version" => {
          "copyright" => read_text(
            File.join(metadata_root, "copyright.txt"),
            "local_metadata.copyright.txt", errors
          ),
          "releaseType" => "AFTER_APPROVAL"
        },
        "app_info" => {
          "primaryCategory" => read_text(
            File.join(metadata_root, "primary_category.txt"),
            "local_metadata.primary_category.txt", errors
          )
        },
        "review_information" => review,
        "age_rating" => rating
      },
      errors
    ]
  end

  def actual_payload(client, version, app_info, expected)
    errors = []
    version_fields = expected.fetch("version_localizations").values.first.keys
    version_localizations = indexed_localizations(
      client.get_all(
        "/v1/appStoreVersions/#{version.fetch('id')}/appStoreVersionLocalizations",
        {
          "fields[appStoreVersionLocalizations]" =>
            (["locale"] + version_fields).join(","),
          "limit" => "200"
        }
      ).fetch("data"),
      version_fields, "version_localizations", errors
    )
    info_fields = expected.fetch("app_info_localizations").values.first.keys
    app_info_localizations = indexed_localizations(
      client.get_all(
        "/v1/appInfos/#{app_info.fetch('id')}/appInfoLocalizations",
        {
          "fields[appInfoLocalizations]" => (["locale"] + info_fields).join(","),
          "limit" => "200"
        }
      ).fetch("data"),
      info_fields, "app_info_localizations", errors
    )
    category = client.get(
      "/v1/appInfos/#{app_info.fetch('id')}/primaryCategory",
      { "fields[appCategories]" => "platforms" }
    )["data"]
    review_response = client.get(
      "/v1/appStoreVersions/#{version.fetch('id')}/appStoreReviewDetail",
      {
        "fields[appStoreReviewDetails]" => "notes,demoAccountRequired",
        "include" => "appStoreReviewAttachments",
        "limit[appStoreReviewAttachments]" => "50"
      },
      optional: true
    )
    review = review_response && review_response["data"]
    rating_fields = expected.fetch("age_rating").keys
    rating = client.get(
      "/v1/appInfos/#{app_info.fetch('id')}/ageRatingDeclaration",
      { "fields[ageRatingDeclarations]" => rating_fields.join(",") }
    )["data"]
    [
      {
        "version_localizations" => version_localizations,
        "app_info_localizations" => app_info_localizations,
        "version" => {
          "copyright" => version.dig("attributes", "copyright"),
          "releaseType" => version.dig("attributes", "releaseType")
        },
        "app_info" => { "primaryCategory" => category && category["id"] },
        "review_information" => review && {
          "notes" => review.dig("attributes", "notes"),
          "demoAccountRequired" => review.dig(
            "attributes", "demoAccountRequired"
          ),
          "appStoreReviewAttachments" => Array(
            review.dig("relationships", "appStoreReviewAttachments", "data")
          ).map { |item| item["id"] }.compact.sort
        },
        "age_rating" => rating &&
          rating.fetch("attributes", {}).slice(*rating_fields)
      },
      errors
    ]
  end

  def locales(config)
    value = config.dig("release_pipeline", "metadata_locales")
    unless value.is_a?(Array) && !value.empty? &&
           value.all? { |locale| locale.is_a?(String) && !locale.empty? } &&
           value.uniq.length == value.length
      raise ArgumentError, "Configured metadata locales are invalid"
    end
    value.sort
  end

  def localized_payload(root, configured_locales, files, errors)
    configured_locales.to_h do |locale|
      fields = files.to_h do |file, attribute|
        [
          attribute,
          read_text(
            File.join(root, locale, file),
            "local_metadata.#{locale}.#{file}", errors
          )
        ]
      end
      [locale, fields]
    end
  end

  def indexed_localizations(items, fields, surface, errors)
    items.each_with_object({}) do |item, result|
      locale = item.dig("attributes", "locale")
      if !locale.is_a?(String) || locale.empty? || result.key?(locale)
        errors << issue("#{surface}.#{locale}", "invalid_or_duplicate")
        next
      end
      result[locale] = fields.to_h do |field|
        [field, item.dig("attributes", field)]
      end
    end
  end

  def read_text(path, proof_path, errors)
    unless File.file?(path) && !File.symlink?(path)
      errors << issue(proof_path, "missing")
      return nil
    end
    value = File.binread(path).force_encoding(Encoding::UTF_8).strip
    if value.empty? || !value.valid_encoding?
      errors << issue(proof_path, value.empty? ? "empty" : "invalid_utf8")
    end
    value
  end

  def read_json(path, proof_path, errors)
    unless File.file?(path) && !File.symlink?(path)
      errors << issue(proof_path, "missing")
      return {}
    end
    value = JSON.parse(File.binread(path))
    unless value.is_a?(Hash) && !value.empty?
      errors << issue(proof_path, "invalid")
      return {}
    end
    value
  rescue JSON::ParserError
    errors << issue(proof_path, "invalid")
    {}
  end

  def compare(expected, actual, path = nil)
    if expected.is_a?(Hash)
      return [issue(path, "missing")] unless actual.is_a?(Hash)

      return (expected.keys | actual.keys).flat_map do |key|
        child = [path, key].compact.join(".")
        if !actual.key?(key)
          [issue(child, "missing")]
        elsif !expected.key?(key)
          [issue(child, "unexpected")]
        else
          compare(expected[key], actual[key], child)
        end
      end
    end
    expected == actual ? [] : [issue(path, actual.nil? ? "missing" : "different")]
  end

  def checked(expected)
    {
      "version_localizations" => {
        "locales" => expected.fetch("version_localizations").keys.sort,
        "fields" => expected.fetch("version_localizations").values.first.keys.sort
      },
      "app_info_localizations" => {
        "locales" => expected.fetch("app_info_localizations").keys.sort,
        "fields" => expected.fetch("app_info_localizations").values.first.keys.sort
      },
      "version" => expected.fetch("version").keys.sort,
      "app_info" => expected.fetch("app_info").keys.sort,
      "review_information" => expected.fetch("review_information").keys.sort,
      "age_rating" => expected.fetch("age_rating").keys.sort
    }
  end

  def digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end

  def canonical(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, canonical(value[key])] }
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end

  def issue(path, reason)
    { "path" => path, "reason" => reason }
  end
end
