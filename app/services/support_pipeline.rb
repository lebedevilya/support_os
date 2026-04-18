require_relative "llm/client"

class SupportPipeline
  def initialize(ticket:, llm_client: :auto)
    @ticket = ticket
    @llm_client =
      if llm_client == :auto
        LLM::Client.build_from_env
      elsif llm_client == false
        nil
      else
        llm_client
      end
  end

  def call
    triage_result = Agents::TriageAgent.new(ticket: @ticket, llm_client: @llm_client).call
    create_agent_run("TriageAgent", triage_result)

    @ticket.update!(
      status: triage_result.fetch(:status),
      category: triage_result.fetch(:category),
      priority: triage_result.fetch(:priority),
      current_layer: triage_result.fetch(:current_layer),
      last_confidence: triage_result.fetch(:confidence)
    )

    return escalate!(triage_result) if triage_result[:route] == "escalate"
    return create_knowledge_answer!(triage_result) if triage_result[:route] == "knowledge_answer"

    specialist_result = Agents::SpecialistAgent.new(ticket: @ticket, triage_result: triage_result, llm_client: @llm_client).call
    create_agent_run("SpecialistAgent", specialist_result)

    @ticket.update!(
      status: specialist_result.fetch(:status),
      current_layer: specialist_result.fetch(:current_layer),
      summary: specialist_result[:reasoning_summary],
      escalation_reason: specialist_result[:escalation_reason],
      handoff_note: specialist_result[:handoff_note],
      last_confidence: specialist_result.fetch(:confidence)
    )

    create_outbound_message!(specialist_result)

    specialist_result
  end

  private

  def create_agent_run(agent_name, result)
    Rails.logger.info(
      "[SupportPipeline] #{agent_name} source=#{result[:source]} status=#{result[:status]} " \
      "category=#{result[:category]} confidence=#{result[:confidence]}"
    )

    @ticket.agent_runs.create!(
      agent_name: agent_name,
      status: result.fetch(:status),
      decision: result[:decision],
      confidence: result.fetch(:confidence),
      input_snapshot: result[:input_snapshot],
      output_snapshot: result.to_json,
      reasoning_summary: result[:reasoning_summary]
    )
  end

  def escalate!(triage_result)
    @ticket.update!(
      escalation_reason: triage_result[:escalation_reason],
      handoff_note: triage_result[:handoff_note]
    )

    Rails.logger.info(
      "[SupportPipeline] HumanHandoff source=#{triage_result[:source]} status=#{triage_result[:status]} " \
      "reason=#{triage_result[:escalation_reason]}"
    )

    @ticket.agent_runs.create!(
      agent_name: "HumanHandoff",
      status: "completed",
      decision: "handoff",
      confidence: triage_result[:confidence],
      input_snapshot: triage_result[:input_snapshot],
      output_snapshot: triage_result.to_json,
      reasoning_summary: "#{triage_result[:handoff_note]} (source: #{triage_result[:source]})"
    )

    @ticket.messages.create!(role: "human", content: triage_result[:handoff_note])
    triage_result
  end

  def create_outbound_message!(specialist_result)
    role = specialist_result[:status] == "escalated" ? "human" : "assistant"
    content = specialist_result[:reply].presence || specialist_result[:handoff_note]

    @ticket.messages.create!(role: role, content: content)
  end

  def create_knowledge_answer!(triage_result)
    @ticket.messages.create!(role: "assistant", content: triage_result.fetch(:reply))
    triage_result
  end
end
