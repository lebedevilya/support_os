require "test_helper"
require "base64"
require "net/http"

module Github
  class AppTokenTest < ActiveSupport::TestCase
    KEY = OpenSSL::PKey::RSA.new(2048).freeze

    test "requests an installation token with a signed JWT and scoped permissions" do
      captured_request = nil
      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured_request = request
        body = {
          token: "ghs_installation_token",
          expires_at: "2030-01-01T00:00:00Z"
        }.to_json
        response = Net::HTTPOK.new("1.1", "200", "OK")
        response.instance_variable_set(:@read, true)
        response.body = body
        response
      end

      with_stubbed_http_start(http) do
        with_credentials(app_id: 42, private_key: KEY.to_pem) do
          result = AppToken.installation_token(
            installation_id: 999,
            repository_ids: [ 7 ]
          )

          assert_equal "ghs_installation_token", result.fetch(:token)
          assert_equal "2030-01-01T00:00:00Z", result.fetch(:expires_at)
        end
      end

      assert_equal "/app/installations/999/access_tokens", captured_request.path
      assert_match(/\ABearer eyJ/, captured_request["Authorization"])

      header_b64, payload_b64, signature_b64 = captured_request["Authorization"].sub("Bearer ", "").split(".")
      header = JSON.parse(Base64.urlsafe_decode64(header_b64))
      payload = JSON.parse(Base64.urlsafe_decode64(payload_b64))
      assert_equal "RS256", header.fetch("alg")
      assert_equal 42, payload.fetch("iss")
      assert KEY.public_key.verify(
        OpenSSL::Digest::SHA256.new,
        Base64.urlsafe_decode64(signature_b64),
        "#{header_b64}.#{payload_b64}"
      ), "JWT signature should verify against the App's public key"

      body = JSON.parse(captured_request.body)
      assert_equal [ 7 ], body.fetch("repository_ids")
      assert_equal "read",  body.dig("permissions", "contents")
      assert_equal "write", body.dig("permissions", "pull_requests")
    end

    test "raises a helpful error when GitHub rejects the JWT" do
      http = Object.new
      http.define_singleton_method(:request) do |_|
        response = Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized")
        response.instance_variable_set(:@read, true)
        response.body = '{"message":"A JSON web token could not be decoded"}'
        response
      end

      with_stubbed_http_start(http) do
        with_credentials(app_id: 42, private_key: KEY.to_pem) do
          error = assert_raises(AppToken::Error) do
            AppToken.installation_token(installation_id: 999)
          end
          assert_match(/HTTP 401/, error.message)
        end
      end
    end

    private

    def with_credentials(values)
      previous = Rails.application.credentials.github_app
      Rails.application.credentials.github_app = values
      yield
    ensure
      Rails.application.credentials.github_app = previous
    end

    def with_stubbed_http_start(http)
      original = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) do |_host, _port, use_ssl:, &block|
        block.call(http)
      end
      yield
    ensure
      Net::HTTP.define_singleton_method(:start) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end
  end
end
