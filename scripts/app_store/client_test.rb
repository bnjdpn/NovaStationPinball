# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "net/http"
require_relative "client"

class NovaStationPinballAscClientTest < Minitest::Test
  Token = Struct.new(:text)
  Response = Struct.new(:body, :code) do
    def is_a?(klass)
      klass == Net::HTTPSuccess
    end
  end

  def test_get_refreshes_the_jwt_for_each_poll_without_transport_retry
    tokens = %w[first second third]
    observed = []
    client = NovaStationPinballAscClient.new(
      token_factory: -> { Token.new(tokens.shift) },
      request_runner: lambda do |_uri, request|
        observed << request["Authorization"]
        Response.new(JSON.generate("data" => []), "200")
      end
    )

    3.times { client.get("/v1/apps") }

    assert_equal %w[Bearer\ first Bearer\ second Bearer\ third], observed
  end

  def test_post_uses_one_fresh_jwt_but_never_retries_transport
    calls = 0
    client = NovaStationPinballAscClient.new(
      token_factory: -> { Token.new("fresh") },
      request_runner: lambda do |_uri, _request|
        calls += 1
        raise IOError, "connection reset"
      end
    )

    assert_raises(IOError) { client.post("/v1/example", "data" => {}) }
    assert_equal 1, calls
  end
end
