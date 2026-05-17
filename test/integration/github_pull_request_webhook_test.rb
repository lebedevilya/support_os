require "test_helper"
require "openssl"

class GithubPullRequestWebhookTest < ActionDispatch::IntegrationTest
  test "rejects requests without a valid github signature" do
    with_webhook_secret("github-secret") do
      post "/webhooks/github/pull_request",
           params: github_payload.to_json,
           headers: github_headers(signature: "sha256=bad")
    end

    assert_response :unauthorized
  end

  test "ignores non pull request events" do
    dispatched = false

    with_webhook_secret("github-secret") do
      body = github_payload.to_json

      with_stubbed_dispatcher(proc { dispatched = true }) do
        post "/webhooks/github/pull_request",
             params: body,
             headers: github_headers(event: "push", body: body)
      end
    end

    assert_response :accepted
    assert_equal false, dispatched
  end

  test "dispatches eligible pull request events to openclaw" do
    captured = nil
    body = github_payload.to_json

    with_webhook_secret("github-secret") do
      with_stubbed_dispatcher(proc { |payload, delivery_id:| captured = [ payload, delivery_id ] }) do
        post "/webhooks/github/pull_request",
             params: body,
             headers: github_headers(body: body)
      end
    end

    assert_response :accepted
    assert_equal "byhuman-ink/byhuman", captured.first.fetch("repository").fetch("full_name")
    assert_equal "delivery-123", captured.second
  end

  private

  def github_payload
    {
      action: "opened",
      repository: {
        full_name: "byhuman-ink/byhuman"
      },
      pull_request: {
        number: 4,
        title: "Refactor shared provenance",
        html_url: "https://github.com/byhuman-ink/byhuman/pull/4",
        draft: false,
        base: {
          ref: "main"
        },
        head: {
          ref: "refactor/shared-provenance",
          sha: "abc123"
        }
      }
    }.deep_stringify_keys
  end

  def github_headers(event: "pull_request", body: github_payload.to_json, signature: nil)
    {
      "CONTENT_TYPE" => "application/json",
      "X-GitHub-Event" => event,
      "X-GitHub-Delivery" => "delivery-123",
      "X-Hub-Signature-256" => signature || signature_for(body)
    }
  end

  def signature_for(body)
    digest = OpenSSL::HMAC.hexdigest("SHA256", "github-secret", body)
    "sha256=#{digest}"
  end

  def with_webhook_secret(secret)
    previous = ENV["GITHUB_WEBHOOK_SECRET"]
    ENV["GITHUB_WEBHOOK_SECRET"] = secret
    yield
  ensure
    ENV["GITHUB_WEBHOOK_SECRET"] = previous
  end

  def with_stubbed_dispatcher(callable)
    dispatcher = Webhooks::GithubPullRequestReviewDispatcher
    original = dispatcher.method(:call)

    dispatcher.define_singleton_method(:call) { |*args, **kwargs| callable.call(*args, **kwargs) }
    yield
  ensure
    dispatcher.define_singleton_method(:call) { |*args, **kwargs| original.call(*args, **kwargs) }
  end
end
