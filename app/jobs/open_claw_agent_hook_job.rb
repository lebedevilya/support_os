class OpenClawAgentHookJob < ApplicationJob
  GH_TOKEN_PLACEHOLDER = "__GH_TOKEN__".freeze

  queue_as :default

  # `github_app`, if provided, must be a hash with :installation_id (required)
  # and :repository_id (optional, used to scope the token to one repo). When
  # present, the job mints a fresh GitHub App installation token and
  # substitutes it into the message in place of #{GH_TOKEN_PLACEHOLDER},
  # so the token never lands in the job's serialized arguments or in logs.
  def perform(name:, message:, idempotency_key:, github_app: nil)
    final_message = inject_app_token(message, github_app)

    OpenClaw::AgentHookClient.call(
      name: name,
      message: final_message,
      idempotency_key: idempotency_key
    )
  end

  private

  def inject_app_token(message, github_app)
    return message unless github_app && message.include?(GH_TOKEN_PLACEHOLDER)

    github_app = github_app.symbolize_keys
    repository_ids = Array(github_app[:repository_id]).compact
    repository_ids = nil if repository_ids.empty?

    result = Github::AppToken.installation_token(
      installation_id: github_app.fetch(:installation_id),
      repository_ids: repository_ids
    )

    message.sub(GH_TOKEN_PLACEHOLDER, result.fetch(:token))
  end
end
