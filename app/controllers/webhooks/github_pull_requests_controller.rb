require "openssl"

module Webhooks
  class GithubPullRequestsController < ActionController::API
    def create
      raw_body = request.raw_post

      return head :unauthorized unless valid_signature?(raw_body)
      return head :accepted unless request.headers["X-GitHub-Event"].to_s == "pull_request"

      payload = JSON.parse(raw_body)
      GithubPullRequestReviewDispatcher.call(
        payload,
        delivery_id: request.headers["X-GitHub-Delivery"].to_s
      )

      head :accepted
    rescue JSON::ParserError
      render json: { error: "invalid json" }, status: :bad_request
    end

    private

    def valid_signature?(raw_body)
      secret = github_webhook_secret
      signature = request.headers["X-Hub-Signature-256"].to_s

      return false if secret.blank? || signature.blank?

      expected = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body)}"
      ActiveSupport::SecurityUtils.secure_compare(signature, expected)
    end

    # ENV wins so tests can override; in production ENV is empty and the
    # secret comes from encrypted Rails credentials, surviving every deploy
    # without depending on a per-deploy shell env var.
    def github_webhook_secret
      ENV["GITHUB_WEBHOOK_SECRET"].to_s.presence ||
        Rails.application.credentials.dig(:github_app, :webhook_secret).to_s
    end
  end
end
