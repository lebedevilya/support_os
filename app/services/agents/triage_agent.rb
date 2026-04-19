module Agents
  class TriageAgent
    KNOWLEDGE_MIN_SCORE = 2
    OPERATIONAL_TERMS = [
      "paid",
      "payment",
      "refund",
      "rejected",
      "did not receive",
      "didn't receive",
      "download link",
      "my file",
      "my order",
      "used the wrong email",
      "wrong email",
      "my node",
      "provisioning",
      "invoice",
      "receipt"
    ].freeze

    def initialize(ticket:, llm_client: nil)
      @ticket = ticket
      @llm_client = llm_client
    end

    def call
      rule_result = matched_support_rule_result
      return rule_result if rule_result

      knowledge_result = knowledge_answer
      return knowledge_result if knowledge_result

      return llm_triage if @llm_client

      content = latest_message.content.downcase

      if supported_country?(content)
        {
          source: "fallback",
          status: "in_progress",
          category: "policy",
          priority: "normal",
          route: "specialist",
          current_layer: "specialist",
          confidence: 0.88,
          decision: "resolve_policy",
          reasoning_summary: "The customer is asking a supported-countries policy question.",
          input_snapshot: latest_message.content
        }
      elsif missing_asset?(content)
        {
          source: "fallback",
          status: "in_progress",
          category: "delivery",
          priority: "normal",
          route: "specialist",
          current_layer: "specialist",
          confidence: 0.82,
          decision: "resolve_delivery",
          reasoning_summary: "The customer is asking about a missing delivered asset.",
          input_snapshot: latest_message.content
        }
      elsif provisioning_status?(content)
        {
          source: "fallback",
          status: "in_progress",
          category: "technical",
          priority: "normal",
          route: "specialist",
          current_layer: "specialist",
          confidence: 0.84,
          decision: "resolve_provisioning",
          reasoning_summary: "The customer is asking about node provisioning status.",
          input_snapshot: latest_message.content
        }
      else
        {
          source: "fallback",
          status: "escalated",
          category: "other",
          priority: "normal",
          route: "escalate",
          current_layer: "human",
          confidence: 0.55,
          decision: "escalate",
          escalation_reason: "The request is outside the supported demo cases.",
          handoff_note: "Escalated for human review because the request does not fit the current automated support envelope.",
          reasoning_summary: "Unknown request type for the current demo scope.",
          input_snapshot: latest_message.content
        }
      end
    end

    private

    def matched_support_rule_result
      match = SupportRuleMatcher.new(company: @ticket.company, content: latest_message.content).call
      return unless match

      match.attributes.merge(input_snapshot: latest_message.content)
    end

    def knowledge_answer
      return if operational_or_sensitive_request?

      matches = PublicKnowledge::Retriever.new(company: @ticket.company, query: latest_message.content).matches
      return if matches.empty?
      return if matches.first.score < KNOWLEDGE_MIN_SCORE

      best_chunk = matches.first.chunk

      {
        source: "public_knowledge",
        status: "resolved",
        category: "policy",
        priority: "normal",
        route: "knowledge_answer",
        current_layer: "triage",
        confidence: 0.9,
        decision: "knowledge_answer",
        reply: best_chunk.content,
        reasoning_summary: "Answered directly from company public knowledge.",
        input_snapshot: latest_message.content
      }
    end

    def llm_triage
      response = @llm_client.complete_json(
        task: "triage",
        prompt: <<~PROMPT,
          Classify the customer support request.
          Return keys:
          - category: one of billing, delivery, refund, policy, account, technical, other
          - priority: one of low, normal, high
          - route: knowledge_answer, specialist, or escalate
          - confidence: decimal between 0 and 1
          - needs_human_now: boolean
          - reply: optional string when route is knowledge_answer
          - reasoning_summary: short sentence
          If the request mentions embassy rejection, government rejection, or a disputed refund, route to escalate.
        PROMPT
        context: {
          company: @ticket.company.name,
          customer_email: @ticket.customer.email,
          latest_message: latest_message.content,
          message_history: @ticket.messages.order(:created_at).pluck(:role, :content)
        }
      )

      build_llm_result(response)
    rescue StandardError => e
      {
        source: "llm_error_fallback",
        status: "escalated",
        category: "other",
        priority: "normal",
        route: "escalate",
        current_layer: "human",
        confidence: 0.0,
        decision: "escalate",
        escalation_reason: "The LLM triage step failed.",
        handoff_note: "Escalated for human review because automated triage failed: #{e.message}",
        reasoning_summary: "LLM triage failure.",
        input_snapshot: latest_message.content
      }
    end

    def build_llm_result(response)
      route =
        if response[:needs_human_now] || response[:route].to_s == "escalate"
          "escalate"
        elsif response[:route].to_s == "knowledge_answer"
          "knowledge_answer"
        else
          "specialist"
        end

      {
        source: "llm",
        status: route == "escalate" ? "escalated" : (route == "knowledge_answer" ? "resolved" : "in_progress"),
        category: normalized_category(response[:category]),
        priority: normalized_priority(response[:priority]),
        route: route,
        current_layer: route == "escalate" ? "human" : (route == "knowledge_answer" ? "triage" : "specialist"),
        confidence: numeric_confidence(response[:confidence]),
        decision: route == "escalate" ? "escalate" : (route == "knowledge_answer" ? "knowledge_answer" : "triage"),
        reply: response[:reply],
        escalation_reason: (route == "escalate" ? "The request requires human review." : nil),
        handoff_note: (route == "escalate" ? "Escalated for human review based on the triage decision." : nil),
        reasoning_summary: response[:reasoning_summary].presence || "Triage completed.",
        input_snapshot: latest_message.content
      }
    end

    def latest_message
      @ticket.messages.order(:created_at).last
    end

    def operational_or_sensitive_request?
      content = latest_message.content.downcase
      OPERATIONAL_TERMS.any? { |term| content.include?(term) }
    end

    def normalized_category(value)
      allowed = %w[billing delivery refund policy account technical other]
      candidate = value.to_s
      allowed.include?(candidate) ? candidate : "other"
    end

    def normalized_priority(value)
      allowed = %w[low normal high]
      candidate = value.to_s
      allowed.include?(candidate) ? candidate : "normal"
    end

    def numeric_confidence(value)
      number = value.to_f
      return 0.0 if number.nan?

      [ [ number, 0.0 ].max, 1.0 ].min
    end

    def supported_country?(content)
      content.include?("support") && content.include?("canada")
    end

    def missing_asset?(content)
      content.include?("didn't receive") || content.include?("did not receive")
    end

    def provisioning_status?(content)
      content.include?("provisioning") || content.include?("node status")
    end
  end
end
