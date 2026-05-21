require "base64"
require "json"
require "net/http"
require "openssl"

module Github
  # Mints short-lived GitHub App installation tokens.
  #
  # GitHub Apps don't have static tokens. To act as the App you sign a JWT
  # with the App's private key, then exchange that JWT for a 1-hour
  # installation access token scoped to a specific installation (and
  # optionally a subset of its repositories and permissions).
  #
  # See: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app
  class AppToken
    class Error < StandardError; end

    GITHUB_API = "https://api.github.com".freeze
    JWT_TTL_SECONDS = 540 # 9 minutes; GitHub enforces a 10-minute max
    DEFAULT_PERMISSIONS = {
      contents: "read",
      pull_requests: "write",
      metadata: "read"
    }.freeze

    def self.installation_token(**kwargs)
      new.installation_token(**kwargs)
    end

    def installation_token(installation_id:, repository_ids: nil, permissions: DEFAULT_PERMISSIONS)
      uri = URI.join(GITHUB_API, "/app/installations/#{installation_id}/access_tokens")

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{jwt}"
      request["Accept"] = "application/vnd.github+json"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      request["Content-Type"] = "application/json"

      body = {}
      body[:repository_ids] = repository_ids if repository_ids
      body[:permissions]    = permissions    if permissions
      request.body = body.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Installation token request failed (HTTP #{response.code}): #{response.body}"
      end

      parsed = JSON.parse(response.body)
      { token: parsed.fetch("token"), expires_at: parsed["expires_at"] }
    end

    private

    def jwt
      now = Time.now.to_i
      header  = base64url(JSON.dump(alg: "RS256", typ: "JWT"))
      payload = base64url(JSON.dump(iat: now - 60, exp: now + JWT_TTL_SECONDS, iss: app_id))
      signing_input = "#{header}.#{payload}"
      signature = base64url(private_key.sign(OpenSSL::Digest::SHA256.new, signing_input))
      "#{signing_input}.#{signature}"
    end

    def app_id
      credentials.fetch(:app_id)
    end

    def private_key
      @private_key ||= OpenSSL::PKey::RSA.new(credentials.fetch(:private_key))
    end

    def credentials
      Rails.application.credentials.github_app || raise(Error, "Missing :github_app in Rails credentials")
    end

    def base64url(value)
      Base64.urlsafe_encode64(value, padding: false)
    end
  end
end
