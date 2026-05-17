require "test_helper"
require "net/http"

module OpenClaw
  class AgentHookClientTest < ActiveSupport::TestCase
    test "posts agent hooks with the free OpenRouter model" do
      request = nil
      http = Object.new
      http.define_singleton_method(:request) do |received_request|
        request = received_request
        Net::HTTPOK.new("1.1", "200", "OK")
      end

      with_stubbed_http_start(http) do
        with_env(
          "OPENCLAW_HOOKS_TOKEN" => "hook-token",
          "OPENCLAW_HOOKS_URL" => "http://openclaw.test/hooks/agent"
        ) do
          AgentHookClient.call(
            message: "Review this PR",
            name: "GitHub PR review",
            idempotency_key: "github-pr-review:repo:1:sha"
          )
        end
      end

      body = JSON.parse(request.body)

      assert_equal "Bearer hook-token", request["Authorization"]
      assert_equal "github-pr-review:repo:1:sha", request["X-OpenClaw-Idempotency-Key"]
      assert_equal "openrouter/free", body.fetch("model")
      assert_equal "high", body.fetch("thinking")
      assert_equal false, body.fetch("deliver")
    end

    private

    def with_env(values)
      previous = values.keys.to_h { |key| [ key, ENV[key] ] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
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
