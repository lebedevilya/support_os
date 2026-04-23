module Agents
  class TriageAgent
    KNOWLEDGE_MIN_SCORE = 2
    STRONG_KNOWLEDGE_MATCH_SCORE = 4

    include Agents::Shared::Normalizers

    def initialize(ticket:, llm_client: nil)
      @ticket = ticket
      @llm_client = llm_client
    end

    def call
      human_result = explicit_human_handoff_result
      return human_result if human_result

      intent = classify_intent
      return intent_clarify_result(intent) if intent&.dig(:route).to_s == "clarify"

      rule_result = matched_support_rule_result(intent)
      return rule_result if rule_result

      knowledge_result = answer_from_knowledge(intent)
      return knowledge_result if knowledge_result

      blocker_result = blocked_request_handoff_result(intent)
      return blocker_result if blocker_result

      specialist_result = intent_specialist_result(intent)
      return specialist_result if specialist_result

      llm_triage
    end

    private

    def explicit_human_handoff_result
      response = @llm_client.complete_json(
        task: "human_handoff_intent",
        prompt: Triage::Prompts::HUMAN_HANDOFF,
        context: {
          company: @ticket.company.name,
          latest_message: latest_message.content,
          message_history: @ticket.messages.order(:created_at).pluck(:role, :content)
        }
      )
      return unless response[:needs_human_handoff] == true

      human_handoff_offer_result(
        source: "llm_human_handoff",
        category: "other",
        priority: "high",
        current_layer: "triage",
        confidence: numeric_confidence(response[:confidence]),
        escalation_reason: "The customer explicitly requested human support.",
        handoff_note: "The customer explicitly asked for a human specialist in this chat.",
        summary: "The customer explicitly requested human support.",
        reply: "A human specialist can take over this conversation. Use the button below if you want to chat with a human.",
        reasoning_summary: response[:reasoning_summary].presence || "Explicit human handoff request bypassed automated support.",
        input_snapshot: latest_message.content,
        tags: normalized_tags(response[:tags], fallback_tags: %w[human-review explicit-human-request escalate])
      )
    rescue StandardError
      nil
    end

    def classify_intent
      response = @llm_client.complete_json(
        task: "intent_classification",
        prompt: Triage::Prompts::INTENT_CLASSIFICATION,
        context: {
          company: @ticket.company.name,
          latest_message: latest_message.content,
          message_history: message_history
        }
      )

      return unless response.is_a?(Hash)
      return unless %w[clarify knowledge_answer specialist].include?(response[:route].to_s)

      response
    rescue StandardError
      nil
    end

    def answer_from_knowledge(intent)
      return if knowledge_blocked_by_rule?(intent)
      return if intent && intent[:route].to_s != "knowledge_answer"

      matches = PublicKnowledge::Retriever.new(company: @ticket.company, query: latest_message.content).matches
      return if matches.empty?
      return if matches.first.score < KNOWLEDGE_MIN_SCORE

      Triage::KnowledgeAnswerer.new(ticket: @ticket, llm_client: @llm_client).call(matches)
    end

    def matched_support_rule_result(intent = nil)
      match = SupportRuleMatcher.new(company: @ticket.company, content: latest_message.content).call
      return if informational_better_from_knowledge?(match, intent)
      return unless match

      match.attributes.merge(input_snapshot: latest_message.content)
    end

    def knowledge_blocked_by_rule?(intent = nil)
      match = SupportRuleMatcher.new(company: @ticket.company, content: latest_message.content, blocker_only: true).call
      return false unless match
      return false if informational_question?(intent) && strong_knowledge_match?

      true
    end

    def blocked_request_handoff_result(intent = nil)
      return unless knowledge_blocked_by_rule?(intent)

      human_handoff_offer_result(
        source: "fallback",
        category: "other",
        priority: "normal",
        current_layer: "triage",
        confidence: 0.7,
        escalation_reason: "This request needs specialist or human review and should not be answered from public knowledge.",
        handoff_note: "A human specialist should review this request because it falls outside the public-knowledge support path.",
        summary: "The request matched a support boundary that blocks public-knowledge answers.",
        reply: "This request needs a specialist review. If you want, I can connect you with a human specialist.",
        reasoning_summary: "The request was blocked from public-knowledge answering and no safe automated fallback was available.",
        input_snapshot: latest_message.content,
        tags: %w[human-review support-boundary]
      )
    end

    def llm_triage
      response = @llm_client.complete_json(
        task: "triage",
        prompt: Triage::Prompts::TRIAGE,
        context: {
          company: @ticket.company.name,
          customer_email: @ticket.customer.email,
          latest_message: latest_message.content,
          message_history: @ticket.messages.order(:created_at).pluck(:role, :content)
        }
      )

      build_llm_triage_result(response)
    rescue StandardError => e
      default_clarify_result(source: "llm_error_fallback", confidence: 0.0, reasoning_summary: "LLM triage failure: #{e.message}")
    end

    def build_llm_triage_result(response)
      route = normalized_route(response)

      return clarify_result(response, fallback_reply: default_clarify_result[:reply], force_fallback_reply: true) if unsolicited_handoff_response?(response)
      return clarify_result(response) if route == "clarify"
      return knowledge_answer_result(response) if route == "knowledge_answer"

      {
        source: "llm",
        status: "in_progress",
        category: normalized_category(response[:category]),
        priority: normalized_priority(response[:priority]),
        route: route,
        current_layer: "specialist",
        confidence: numeric_confidence(response[:confidence]),
        decision: "triage",
        reply: nil,
        reasoning_summary: response[:reasoning_summary].presence || "Triage completed.",
        input_snapshot: latest_message.content,
        tags: normalized_tags(response[:tags], fallback_tags: triage_tags(response, route))
      }
    end

    def intent_clarify_result(intent)
      {
        source: "llm_intent",
        status: "awaiting_customer",
        category: normalized_category(intent[:category]),
        priority: normalized_priority(intent[:priority]),
        route: "clarify",
        current_layer: "triage",
        confidence: numeric_confidence(intent[:confidence]),
        decision: "clarify",
        reply: intent[:reply].presence || default_clarify_result[:reply],
        reasoning_summary: intent[:reasoning_summary].presence || "The LLM classifier requested clarification.",
        input_snapshot: latest_message.content,
        tags: normalized_tags(intent[:tags], fallback_tags: %w[clarify])
      }
    end

    def intent_specialist_result(intent)
      return unless intent&.dig(:route).to_s == "specialist"

      {
        source: "llm_intent",
        status: "in_progress",
        category: normalized_category(intent[:category]),
        priority: normalized_priority(intent[:priority]),
        route: "specialist",
        current_layer: "specialist",
        confidence: numeric_confidence(intent[:confidence]),
        decision: "triage",
        reply: nil,
        reasoning_summary: intent[:reasoning_summary].presence || "The LLM classifier routed this request to specialist review.",
        input_snapshot: latest_message.content,
        tags: normalized_tags(intent[:tags], fallback_tags: %w[triage specialist])
      }
    end

    def default_clarify_result(source: "fallback", confidence: 0.9, reasoning_summary: "The message is too vague to route yet.")
      {
        source: source,
        status: "awaiting_customer",
        category: "other",
        priority: "low",
        route: "clarify",
        current_layer: "triage",
        confidence: confidence,
        decision: "clarify",
        reply: "Hello! I can help with #{@ticket.company.name} support. What do you need help with today?",
        reasoning_summary: reasoning_summary,
        input_snapshot: latest_message.content,
        tags: %w[clarify greeting]
      }
    end

    def clarify_result(response, fallback_reply: nil, force_fallback_reply: false)
      reply = if force_fallback_reply
        fallback_reply || default_clarify_result[:reply]
      else
        response[:reply].presence || fallback_reply || default_clarify_result[:reply]
      end

      {
        source: "llm",
        status: "awaiting_customer",
        category: normalized_category(response[:category]),
        priority: normalized_priority(response[:priority]),
        route: "clarify",
        current_layer: "triage",
        confidence: numeric_confidence(response[:confidence]),
        decision: "clarify",
        reply: reply,
        reasoning_summary: response[:reasoning_summary].presence || "The customer needs to clarify the support request.",
        input_snapshot: latest_message.content,
        tags: normalized_tags(response[:tags], fallback_tags: %w[clarify])
      }
    end

    def knowledge_answer_result(response)
      {
        source: "llm",
        status: "awaiting_customer",
        category: normalized_category(response[:category]),
        priority: normalized_priority(response[:priority]),
        route: "knowledge_answer",
        current_layer: "triage",
        confidence: numeric_confidence(response[:confidence]),
        decision: "knowledge_answer",
        reply: response[:reply],
        reasoning_summary: response[:reasoning_summary].presence || "Triage answered directly.",
        input_snapshot: latest_message.content,
        tags: normalized_tags(response[:tags], fallback_tags: triage_tags(response, "knowledge_answer"))
      }
    end

    def human_handoff_offer_result(source:, category:, priority:, current_layer:, confidence:, escalation_reason:, handoff_note:, summary:, reply:, reasoning_summary:, input_snapshot:, tags:)
      {
        source: source,
        status: "awaiting_customer",
        category: category,
        priority: priority,
        route: "offer_human_handoff",
        current_layer: current_layer,
        confidence: confidence,
        decision: "offer_human_handoff",
        escalation_reason: escalation_reason,
        handoff_note: handoff_note,
        summary: summary,
        reply: reply,
        reasoning_summary: reasoning_summary,
        input_snapshot: input_snapshot,
        human_handoff_available: true,
        tags: tags
      }
    end

    def normalized_route(response)
      return "clarify" if response[:needs_human_now]

      candidate = response[:route].to_s
      return "clarify" if candidate == "clarify"
      return "knowledge_answer" if candidate == "knowledge_answer"
      return "clarify" if %w[offer_human_handoff escalate].include?(candidate)

      "specialist"
    end

    def unsolicited_handoff_response?(response)
      response[:needs_human_now] || %w[offer_human_handoff escalate].include?(response[:route].to_s)
    end

    def informational_better_from_knowledge?(match, intent = nil)
      return false unless match&.attributes&.dig(:route) == "offer_human_handoff"
      return false unless informational_question?(intent) || latest_message.content.to_s.include?("?")

      strong_knowledge_match?
    end

    def strong_knowledge_match?
      top_match = PublicKnowledge::Retriever.new(company: @ticket.company, query: latest_message.content).matches.first
      top_match.present? && top_match.score >= STRONG_KNOWLEDGE_MATCH_SCORE
    end

    def informational_question?(intent)
      intent&.dig(:request_mode).to_s == "informational"
    end

    def triage_tags(response, route)
      tags = [ normalized_category(response[:category]), route == "escalate" ? "human-review" : "triage", route ]
      tags.compact.uniq
    end

    def latest_message
      @latest_message ||= @ticket.messages.order(:created_at).last
    end

    def message_history
      @message_history ||= @ticket.messages.order(:created_at).pluck(:role, :content)
    end
  end
end
