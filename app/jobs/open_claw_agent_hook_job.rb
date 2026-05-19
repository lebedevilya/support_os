class OpenClawAgentHookJob < ApplicationJob
  queue_as :default

  def perform(name:, message:, idempotency_key:)
    OpenClaw::AgentHookClient.call(
      name: name,
      message: message,
      idempotency_key: idempotency_key
    )
  end
end
