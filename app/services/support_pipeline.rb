require_relative "llm/client"

class SupportPipeline
  TRIAGE_CONFIDENCE_THRESHOLD = 0.6
  SPECIALIST_CONFIDENCE_THRESHOLD = 0.7

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
    triage_result = apply_triage_guardrails(
      Agents::TriageAgent.new(ticket: @ticket, llm_client: @llm_client).call
    )
    create_agent_run("TriageAgent", triage_result)
    assign_tags!(triage_result)

    @ticket.update!(
      status: triage_result.fetch(:status),
      category: triage_result.fetch(:category),
      priority: triage_result.fetch(:priority),
      current_layer: triage_result.fetch(:current_layer),
      last_confidence: triage_result.fetch(:confidence),
      summary: triage_result[:summary],
      escalation_reason: triage_result[:escalation_reason],
      handoff_note: triage_result[:handoff_note],
      human_handoff_available: triage_result[:human_handoff_available] || false
    )

    return create_triage_reply!(triage_result) if %w[knowledge_answer clarify offer_human_handoff].include?(triage_result[:route])

    specialist_result = apply_specialist_guardrails(
      Agents::SpecialistAgent.new(ticket: @ticket, triage_result: triage_result, llm_client: @llm_client).call,
      category: triage_result[:category],
      priority: triage_result[:priority]
    )
    create_agent_run("SpecialistAgent", specialist_result, attach_unlinked_tool_calls: true)
    assign_tags!(triage_result, specialist_result)

    @ticket.update!(
      status: specialist_result.fetch(:status),
      current_layer: specialist_result.fetch(:current_layer),
      summary: specialist_result[:summary],
      escalation_reason: specialist_result[:escalation_reason],
      handoff_note: specialist_result[:handoff_note],
      last_confidence: specialist_result.fetch(:confidence),
      human_handoff_available: specialist_result[:human_handoff_available] || false
    )

    create_outbound_message!(specialist_result)

    specialist_result
  end

  private

  def create_outbound_message!(specialist_result)
    content = specialist_result[:reply].presence || specialist_result[:handoff_note]
    @ticket.messages.create!(role: "assistant", content: content)
  end

  def create_triage_reply!(triage_result)
    assign_tags!(triage_result)
    @ticket.messages.create!(role: "assistant", content: triage_result.fetch(:reply))
    triage_result
  end

  def apply_triage_guardrails(result)
    return result if result[:route] == "offer_human_handoff"
    return result if result[:route] == "clarify"
    return result if result.fetch(:confidence) >= TRIAGE_CONFIDENCE_THRESHOLD

    guardrail_handoff_result(
      result,
      threshold: TRIAGE_CONFIDENCE_THRESHOLD,
      reply: "I’m not confident enough to handle this automatically. If you want, I can connect you with a human specialist.",
      handoff_note: "A human specialist should review this case because triage confidence was below the automation threshold and this needs human review.",
      current_layer: "triage"
    )
  end

  def apply_specialist_guardrails(result, category:, priority:)
    return result if result[:route] == "offer_human_handoff"
    return result.fetch(:confidence) >= SPECIALIST_CONFIDENCE_THRESHOLD ? result : guardrail_handoff_result(
      result.merge(category: category, priority: priority),
      threshold: SPECIALIST_CONFIDENCE_THRESHOLD,
      reply: "I’m not confident enough to complete this safely. If you want, I can connect you with a human specialist.",
      handoff_note: "A human specialist should review this case because specialist confidence was below the automation threshold and this needs human review.",
      current_layer: result[:current_layer].presence || "specialist"
    )
  end

  def guardrail_handoff_result(result, threshold:, handoff_note:, reply:, current_layer:)
    result.merge(
      status: "awaiting_customer",
      route: "offer_human_handoff",
      current_layer: current_layer,
      decision: "offer_human_handoff",
      reply: reply,
      summary: "Automation confidence #{result.fetch(:confidence)} was below the required threshold of #{threshold}.",
      escalation_reason: "Automation confidence #{result.fetch(:confidence)} was below the required threshold of #{threshold}.",
      handoff_note: handoff_note,
      reasoning_summary: "#{result[:reasoning_summary]} Human handoff was offered by the pipeline confidence guardrail.",
      human_handoff_available: true
    )
  end

  def assign_tags!(*results)
    tags = results.flat_map { |result| tag_candidates_for(result) }.uniq
    return if tags.empty?

    @ticket.tag_list.add(tags)
    @ticket.save! if @ticket.changed?
  end

  def tag_candidates_for(result)
    explicit_tags = Array(result[:tags]).filter_map { |tag| normalize_tag(tag) }
    return explicit_tags if explicit_tags.any?

    [
      result[:category],
      result[:current_layer],
      result[:status],
      result[:decision],
      result[:matched_rule_name]
    ].filter_map { |value| normalize_tag(value) }
  end

  def normalize_tag(value)
    candidate = value.to_s.parameterize
    candidate.presence
  end

  def create_agent_run(agent_name, result, attach_unlinked_tool_calls: false)
    Rails.logger.info(
      "[SupportPipeline] #{agent_name} source=#{result[:source]} status=#{result[:status]} " \
      "category=#{result[:category]} confidence=#{result[:confidence]}"
    )

    agent_run = @ticket.agent_runs.create!(
      agent_name: agent_name,
      status: result.fetch(:status),
      decision: result[:decision],
      confidence: result.fetch(:confidence),
      input_snapshot: result[:input_snapshot],
      output_snapshot: result.to_json,
      reasoning_summary: result[:reasoning_summary]
    )

    attach_pending_tool_calls!(agent_run) if attach_unlinked_tool_calls
    agent_run
  end

  def attach_pending_tool_calls!(agent_run)
    @ticket.tool_calls.where(agent_run_id: nil).update_all(agent_run_id: agent_run.id)
  end
end
