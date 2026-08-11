#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module NovaStationPinballAscCredentials
  ENV_KEYS = %w[
    APP_STORE_CONNECT_API_KEY_KEY_ID
    APP_STORE_CONNECT_API_KEY_ISSUER_ID
    APP_STORE_CONNECT_API_KEY_KEY
  ].freeze

  module_function

  def available?(key_path: nil)
    (key_path && File.file?(key_path) && !File.symlink?(key_path)) ||
      ENV_KEYS.all? { |key| !ENV[key].to_s.empty? }
  end

  def token(key_path: nil)
    require "spaceship"
    if key_path && File.file?(key_path) && !File.symlink?(key_path)
      return Spaceship::ConnectAPI::Token.from(filepath: key_path)
    end

    missing = ENV_KEYS.select { |key| ENV[key].to_s.empty? }
    unless missing.empty?
      raise ArgumentError,
            "Missing App Store Connect credentials: #{missing.join(', ')}"
    end
    Spaceship::ConnectAPI::Token.create(
      key_id: ENV.fetch("APP_STORE_CONNECT_API_KEY_KEY_ID"),
      issuer_id: ENV.fetch("APP_STORE_CONNECT_API_KEY_ISSUER_ID"),
      key: ENV.fetch("APP_STORE_CONNECT_API_KEY_KEY"),
      is_key_content_base64: ENV["APP_STORE_CONNECT_API_KEY_IS_BASE64"] == "1",
      in_house: false
    )
  end
end

class NovaStationPinballAscError < StandardError
  attr_reader :method, :path, :status

  def initialize(method:, path:, status:, body:)
    @method = method
    @path = path
    @status = status
    super("#{method} #{path} -> #{status}: #{body}")
  end
end

class NovaStationPinballAscClient
  BASE_URL = "https://api.appstoreconnect.apple.com"

  def initialize(key_path: nil, token: nil, token_factory: nil, request_runner: nil)
    if token && token_factory
      raise ArgumentError, "Provide either a fixed token or a token factory"
    end
    @token_factory = token_factory || if token
                                        -> { token }
                                      else
                                        -> {
                                          NovaStationPinballAscCredentials.token(
                                            key_path: key_path
                                          )
                                        }
                                      end
    @request_runner = request_runner || method(:perform_request)
  end

  def get(path, params = {}, optional: false)
    request(Net::HTTP::Get, uri_for(path, params), optional: optional, retries: 2)
  end

  def get_all(path, params = {})
    data = []
    included = []
    current = uri_for(path, params)
    loop do
      payload = request(Net::HTTP::Get, current, retries: 2)
      items = payload.fetch("data", [])
      data.concat(items.is_a?(Array) ? items : [items].compact)
      included.concat(payload.fetch("included", []))
      next_link = payload.dig("links", "next")
      break unless next_link

      current = URI(next_link)
    end
    { "data" => data, "included" => included }
  end

  # Mutations deliberately never retry. Their caller records an immutable intent
  # before invoking these methods and resumes with GET-only verification.
  def post(path, body)
    request(Net::HTTP::Post, uri_for(path), body: body, retries: 0)
  end

  def patch(path, body)
    request(Net::HTTP::Patch, uri_for(path), body: body, retries: 0)
  end

  def delete(path)
    request(Net::HTTP::Delete, uri_for(path), retries: 0)
  end

  private

  def uri_for(path, params = {})
    return path if path.is_a?(URI)

    query = URI.encode_www_form(params)
    URI("#{BASE_URL}#{path}#{query.empty? ? '' : "?#{query}"}")
  end

  def request(request_class, uri, body: nil, optional: false, retries: 0)
    attempt = 0
    loop do
      request = request_class.new(uri)
      token = @token_factory.call
      unless token.respond_to?(:text) && !token.text.to_s.empty?
        raise ArgumentError, "ASC token factory returned an invalid token"
      end
      request["Authorization"] = "Bearer #{token.text}"
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body) if body
      response = @request_runner.call(uri, request)
      return {} if response.is_a?(Net::HTTPNoContent)
      return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
      return nil if optional && response.code == "404"
      if request_class == Net::HTTP::Get &&
         response.is_a?(Net::HTTPServerError) && attempt < retries
        attempt += 1
        sleep(attempt * 2)
        next
      end
      raise NovaStationPinballAscError.new(
        method: request.method,
        path: uri.request_uri,
        status: response.code,
        body: response.body
      )
    end
  rescue JSON::ParserError => error
    raise NovaStationPinballAscError.new(
      method: request_class.name.split("::").last.upcase,
      path: uri.request_uri,
      status: "invalid-json",
      body: error.message
    )
  end

  def perform_request(uri, request)
    Net::HTTP.start(
      uri.host, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 120
    ) { |http| http.request(request) }
  end
end
