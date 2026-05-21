require "net/http"

module OpenClaw
  class AgentHookClient
    class Error < StandardError; end

    def self.call(message:, name:, idempotency_key:)
      new.call(message: message, name: name, idempotency_key: idempotency_key)
    end

    def call(message:, name:, idempotency_key:)
      token = openclaw_token
      raise Error, "OpenClaw token is not configured (set credentials.openclaw.hooks_token or ENV OPENCLAW_HOOKS_TOKEN)" if token.blank?

      uri = URI(ENV.fetch("OPENCLAW_HOOKS_URL", "http://127.0.0.1:18789/hooks/agent"))
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request["X-OpenClaw-Idempotency-Key"] = idempotency_key
      request.body = {
        name: name,
        agentId: "main",
        message: message,
        wakeMode: "now",
        deliver: false,
        model: "openrouter/free",
        thinking: "high",
        timeoutSeconds: 900
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      return response if response.is_a?(Net::HTTPSuccess)

      raise Error, "OpenClaw hook failed with HTTP #{response.code}: #{response.body}"
    end

    private

    # ENV wins so tests can override; in production ENV is typically empty
    # and the token comes from encrypted Rails credentials so it survives
    # every deploy without a fragile shell-env handshake.
    def openclaw_token
      ENV["OPENCLAW_HOOKS_TOKEN"].to_s.presence ||
        Rails.application.credentials.dig(:openclaw, :hooks_token).to_s
    end
  end
end
