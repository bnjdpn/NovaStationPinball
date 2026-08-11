# frozen_string_literal: true

require "json"
require "pathname"

module NovaStationPinballMetadataPreflight
  METADATA_RELATIVE = "fastlane/metadata"
  RATING_RELATIVE = "fastlane/metadata/app_rating_config.json"

  module_function

  def resolve!(root:, config:)
    app_root = File.expand_path(root)
    unless File.directory?(app_root) && !File.symlink?(app_root)
      raise ArgumentError, "App root must be a regular directory"
    end
    unless config.instance_of?(Hash) && config["age_rating"] == RATING_RELATIVE
      raise ArgumentError, "Age-rating path must match the canonical metadata file"
    end

    metadata_path = safe_path!(app_root, METADATA_RELATIVE, directory: true)
    rating_path = safe_path!(app_root, RATING_RELATIVE, directory: false)
    rating = JSON.parse(File.binread(rating_path))
    unless rating.instance_of?(Hash) && !rating.empty?
      raise ArgumentError, "Age-rating configuration must be a non-empty object"
    end

    {
      metadata_path: metadata_path,
      app_rating_config_path: rating_path
    }
  rescue JSON::ParserError => error
    raise ArgumentError, "Invalid age-rating configuration: #{error.message}"
  end

  def safe_path!(root, relative, directory:)
    unless relative.instance_of?(String) && !relative.empty? &&
           !Pathname.new(relative).absolute?
      raise ArgumentError, "Metadata path must be app-local"
    end
    path = File.expand_path(relative, root)
    unless path.start_with?("#{root}#{File::SEPARATOR}")
      raise ArgumentError, "Metadata path escaped the app root"
    end

    current = root
    Pathname.new(path).relative_path_from(Pathname.new(root)).each_filename do |part|
      current = File.join(current, part)
      raise ArgumentError, "Metadata path traverses a symbolic link" if File.symlink?(current)
    end
    valid = directory ? File.directory?(path) : File.file?(path)
    raise ArgumentError, "Metadata path is missing or has the wrong type" unless valid
    unless Pathname.new(path).absolute?
      raise ArgumentError, "Metadata path did not resolve absolutely"
    end
    path
  rescue ArgumentError => error
    raise error
  end
  private_class_method :safe_path!
end
