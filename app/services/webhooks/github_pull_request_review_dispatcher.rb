module Webhooks
  class GithubPullRequestReviewDispatcher
    # Any repository under this GitHub owner is eligible for automated review.
    ALLOWED_OWNER = "byhuman-ink".freeze

    REVIEW_ACTIONS = %w[
      opened
      reopened
      synchronize
      ready_for_review
    ].freeze

    Result = Data.define(:status)

    def self.call(payload, delivery_id:)
      new(payload, delivery_id: delivery_id).call
    end

    def initialize(payload, delivery_id:)
      @payload = payload
      @delivery_id = delivery_id
    end

    def call
      return Result.new(:ignored) unless reviewable?

      # Enqueue the OpenClaw call so the GitHub webhook request returns
      # immediately instead of blocking on a long-running agent HTTP call.
      OpenClawAgentHookJob.perform_later(
        name: "GitHub PR review",
        message: review_message,
        idempotency_key: idempotency_key
      )

      Result.new(:dispatched)
    end

    private

    attr_reader :payload, :delivery_id

    def reviewable?
      REVIEW_ACTIONS.include?(action) &&
        repository_owner == ALLOWED_OWNER &&
        pull_request.present? &&
        !pull_request.fetch("draft", false)
    end

    def action
      payload["action"].to_s
    end

    def repository_full_name
      payload.dig("repository", "full_name").to_s
    end

    def repository_owner
      repository_full_name.split("/").first.to_s
    end

    def pull_request
      payload["pull_request"]
    end

    def pr_number
      pull_request.fetch("number")
    end

    def pr_url
      pull_request.fetch("html_url")
    end

    def head_sha
      pull_request.dig("head", "sha").to_s
    end

    def idempotency_key
      [
        "github-pr-review",
        repository_full_name,
        pr_number,
        head_sha.presence || delivery_id
      ].join(":")
    end

    def review_message
      <<~TEXT
        Review this GitHub pull request and post the result back to the PR.

        Repository: #{repository_full_name}
        Pull request: #{pr_url}
        PR number: #{pr_number}
        Event action: #{action}
        Base branch: #{pull_request.dig("base", "ref")}
        Head branch: #{pull_request.dig("head", "ref")}
        Head SHA: #{head_sha}

        Use the github skill or gh CLI to inspect the PR diff, changed files, existing comments, and CI state.
        Focus on bugs, regressions, security/privacy issues, data-loss risks, missing tests, and deployment risks.
        Post exactly one concise PR comment with your findings using gh.
        If there are no blocking issues, post a short comment saying no blocking issues were found and mention any residual test or deployment risk.
        Do not make code changes.
      TEXT
    end
  end
end
