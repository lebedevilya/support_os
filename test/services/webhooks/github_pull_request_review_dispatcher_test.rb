require "test_helper"

module Webhooks
  class GithubPullRequestReviewDispatcherTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "ignores unsupported repositories" do
      result = dispatch(payload(repository: "other/repo"))

      assert_equal :ignored, result.status
      assert_empty calls
    end

    test "ignores unsupported actions" do
      result = dispatch(payload(action: "edited"))

      assert_equal :ignored, result.status
      assert_empty calls
    end

    test "ignores draft pull requests" do
      result = dispatch(payload(draft: true))

      assert_equal :ignored, result.status
      assert_empty calls
    end

    test "sends review prompt to openclaw for eligible pull requests" do
      result = dispatch(payload)

      assert_equal :dispatched, result.status
      assert_equal 1, calls.size

      call = calls.first
      assert_equal "GitHub PR review", call.fetch(:name)
      assert_equal "github-pr-review:byhuman-ink/byhuman:4:abc123", call.fetch(:idempotency_key)
      assert_includes call.fetch(:message), "Repository: byhuman-ink/byhuman"
      assert_includes call.fetch(:message), "Pull request: https://github.com/byhuman-ink/byhuman/pull/4"
      assert_includes call.fetch(:message), "Post exactly one concise PR comment"
      assert_includes call.fetch(:message), "export GH_TOKEN=test-installation-token"
      refute_includes call.fetch(:message), "__GH_TOKEN__"
      assert_equal [ { installation_id: 555, repository_id: 999 } ], token_calls
    end

    private

    def setup
      @calls = []
      @original_call = OpenClaw::AgentHookClient.method(:call)
      calls = @calls
      OpenClaw::AgentHookClient.define_singleton_method(:call) do |**kwargs|
        calls << kwargs
      end

      @token_calls = []
      @original_token = Github::AppToken.method(:installation_token)
      token_calls = @token_calls
      Github::AppToken.define_singleton_method(:installation_token) do |**kwargs|
        token_calls << kwargs.slice(:installation_id).merge(repository_id: Array(kwargs[:repository_ids]).first)
        { token: "test-installation-token", expires_at: nil }
      end
    end

    def teardown
      original_call = @original_call
      OpenClaw::AgentHookClient.define_singleton_method(:call) { |**kwargs| original_call.call(**kwargs) }
      original_token = @original_token
      Github::AppToken.define_singleton_method(:installation_token) { |**kwargs| original_token.call(**kwargs) }
    end

    attr_reader :calls, :token_calls

    def dispatch(payload)
      # The dispatcher enqueues OpenClawAgentHookJob; run it inline so the
      # AgentHookClient stub still observes the call.
      result = nil
      perform_enqueued_jobs do
        result = GithubPullRequestReviewDispatcher.call(payload, delivery_id: "delivery-123")
      end
      result
    end

    def payload(action: "opened", repository: "byhuman-ink/byhuman", draft: false)
      {
        "action" => action,
        "installation" => {
          "id" => 555
        },
        "repository" => {
          "id" => 999,
          "full_name" => repository
        },
        "pull_request" => {
          "number" => 4,
          "title" => "Refactor shared provenance",
          "html_url" => "https://github.com/byhuman-ink/byhuman/pull/4",
          "draft" => draft,
          "base" => {
            "ref" => "main"
          },
          "head" => {
            "ref" => "refactor/shared-provenance",
            "sha" => "abc123"
          }
        }
      }
    end
  end
end
