module Agents
  class TriageAgent
    GREETING_PATTERNS = [
      /\A(?:hi|hello|hey|hey there|yo|good morning|good afternoon|good evening)[.!? ]*\z/i,
      /\A(?:can you help\??|help\??)\z/i
    ].freeze
    OFF_TOPIC_PATTERNS = [
      /weather/i
    ].freeze
    KNOWLEDGE_MIN_SCORE = 2

    def initialize(ticket:, llm_client: nil)
      @ticket = ticket
      @llm_client = llm_client
    end

    def call
      human_request_result = explicit_human_handoff_result
      return human_request_result if human_request_result

      rule_result = matched_support_rule_result
      return rule_result if rule_result

      knowledge_result = knowledge_answer
      return knowledge_result if knowledge_result

      blocker_fallback = blocked_request_handoff_result
      return blocker_fallback if blocker_fallback

      conversational_fallback = fallback_conversation_result
      return conversational_fallback if conversational_fallback

      return llm_triage if @llm_client

      default_clarify_result
    end

    private

    def explicit_human_handoff_result
      return unless @llm_client

      response = @llm_client.complete_json(
        task: "human_handoff_intent",
        prompt: <<~PROMPT,
          Decide whether the customer is explicitly asking to stop automated support and be handed off to a human.
          Return keys:
          - needs_human_handoff: boolean
          - confidence: decimal between 0 and 1
          - reasoning_summary: short sentence
          - tags: array of strings
          Requirements:
          - only return true when the customer is clearly asking for a human, support agent, real person, handoff, transfer, or escalation
          - frustration alone is not enough unless it clearly asks for a human
          - requests for contact details or business hours are not the same as asking for a human handoff in this chat
        PROMPT
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

    def matched_support_rule_result
      match = SupportRuleMatcher.new(company: @ticket.company, content: latest_message.content).call
      return unless match

      match.attributes.merge(input_snapshot: latest_message.content)
    end

    def knowledge_answer
      return if public_knowledge_blocked_by_rule?

      matches = PublicKnowledge::Retriever.new(company: @ticket.company, query: latest_message.content).matches
      return if matches.empty?
      return if matches.first.score < KNOWLEDGE_MIN_SCORE

      return llm_knowledge_answer(matches) if @llm_client

      fallback_knowledge_answer(matches.first.chunk)
    end

    def llm_knowledge_answer(matches)
      response = @llm_client.complete_json(
        task: "knowledge_answer",
        prompt: <<~PROMPT,
          Draft a customer-facing support reply using only the provided public knowledge chunks.
          Return keys:
          - reply: string
          - confidence: decimal between 0 and 1
          - reasoning_summary: short sentence
          - cited_source_url: optional string
          - tags: array of strings
          Requirements:
          - answer naturally and concisely
          - if the question is yes/no and the knowledge supports it, answer directly
          - do not include URLs or citation text directly in reply
          - set cited_source_url only when one provided source page directly supports the answer
          - leave cited_source_url blank when the provided knowledge does not directly answer the question
          - never cite a generic, unrelated, or fallback page just to add a link
          - do not invent policies, tools, account data, or operational actions
          - do not claim uncertainty if the provided knowledge is sufficient
        PROMPT
        context: {
          company: @ticket.company.name,
          latest_message: latest_message.content,
          knowledge_chunks: matches.map do |match|
            {
              content: match.chunk.content,
              score: match.score,
              source_title: match.chunk.source&.title,
              source_url: match.chunk.source&.url,
              manual_entry_title: match.chunk.manual_entry&.title
            }
          end
        }
      )

      {
        source: "public_knowledge_llm",
        status: "awaiting_customer",
        category: "policy",
        priority: "normal",
        route: "knowledge_answer",
        current_layer: "triage",
        confidence: numeric_confidence(response[:confidence]),
        decision: "knowledge_answer",
        reply: compose_llm_knowledge_reply(response[:reply], response[:cited_source_url], matches),
        reasoning_summary: response[:reasoning_summary].presence || "Answered from public knowledge with LLM synthesis.",
        input_snapshot: latest_message.content,
        tags: normalized_tags(response[:tags], fallback_tags: knowledge_tags(matches))
      }
    rescue StandardError
      fallback_knowledge_answer(matches.first.chunk)
    end

    def fallback_knowledge_answer(best_chunk)
      {
        source: "public_knowledge",
        status: "awaiting_customer",
        category: "policy",
        priority: "normal",
        route: "knowledge_answer",
        current_layer: "triage",
        confidence: 0.9,
        decision: "knowledge_answer",
        reply: PublicKnowledge::AnswerComposer.new(question: latest_message.content, chunk: best_chunk).call,
        reasoning_summary: "Answered directly from company public knowledge.",
        input_snapshot: latest_message.content,
        tags: fallback_knowledge_tags(best_chunk)
      }
    end

    def compose_llm_knowledge_reply(reply, cited_source_url, matches)
      reply_text = reply.to_s.strip
      return reply_text if reply_text.blank?

      source_url = validated_cited_source_url(cited_source_url, matches)
      return reply_text unless source_url

      "#{reply_text} Source: #{source_url}"
    end

    def validated_cited_source_url(cited_source_url, matches)
      candidate = cited_source_url.to_s.strip
      return if candidate.blank?

      allowed_urls = matches.filter_map { |match| match.chunk.source&.url.presence }.uniq
      allowed_urls.include?(candidate) ? candidate : nil
    end

    def llm_triage
      response = @llm_client.complete_json(
        task: "triage",
        prompt: <<~PROMPT,
          Classify the customer support request.
          Return keys:
          - category: one of billing, delivery, refund, policy, account, technical, other
          - priority: one of low, normal, high
          - route: clarify, knowledge_answer, specialist, or offer_human_handoff
          - confidence: decimal between 0 and 1
          - needs_human_now: boolean
          - reply: optional string when route is clarify or knowledge_answer or offer_human_handoff
          - reasoning_summary: short sentence
          - tags: array of strings
          Rules:
          - greetings, vague openers, or low-information messages should use clarify with a short company-specific follow-up question
          - off-topic chatter should use clarify with a brief redirect back to company support
          - requests that need human involvement should use offer_human_handoff, not escalate automatically
          - if the request mentions embassy rejection, government rejection, or a disputed refund, route to offer_human_handoff
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
      default_clarify_result(source: "llm_error_fallback", confidence: 0.0, reasoning_summary: "LLM triage failure: #{e.message}")
    end

    def build_llm_result(response)
      route = normalized_route(response)

      return clarify_result(response) if route == "clarify"
      return knowledge_answer_result(response) if route == "knowledge_answer"
      return handoff_offer_result(response) if route == "offer_human_handoff"

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

    def latest_message
      @ticket.messages.order(:created_at).last
    end

    def public_knowledge_blocked_by_rule?
      SupportRuleMatcher.new(company: @ticket.company, content: latest_message.content, blocker_only: true).call.present?
    end

    def blocked_request_handoff_result
      return unless public_knowledge_blocked_by_rule?

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

    def fallback_conversation_result
      return default_clarify_result if greeting_message?
      return off_topic_redirect_result if off_topic_message?

      nil
    end

    def greeting_message?
      GREETING_PATTERNS.any? { |pattern| latest_message.content.to_s.match?(pattern) }
    end

    def off_topic_message?
      OFF_TOPIC_PATTERNS.any? { |pattern| latest_message.content.to_s.match?(pattern) }
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

    def off_topic_redirect_result
      {
        source: "fallback",
        status: "awaiting_customer",
        category: "other",
        priority: "low",
        route: "clarify",
        current_layer: "triage",
        confidence: 0.92,
        decision: "clarify",
        reply: "I’m here to help with #{@ticket.company.name} support. Tell me what you need help with and I’ll take it from there.",
        reasoning_summary: "The message is off-topic, so triage redirected the customer back to product support.",
        input_snapshot: latest_message.content,
        tags: %w[clarify off-topic]
      }
    end

    def normalized_route(response)
      return "offer_human_handoff" if response[:needs_human_now]

      candidate = response[:route].to_s
      return "clarify" if candidate == "clarify"
      return "knowledge_answer" if candidate == "knowledge_answer"
      return "offer_human_handoff" if %w[offer_human_handoff escalate].include?(candidate)

      "specialist"
    end

    def clarify_result(response)
      {
        source: "llm",
        status: "awaiting_customer",
        category: normalized_category(response[:category]),
        priority: normalized_priority(response[:priority]),
        route: "clarify",
        current_layer: "triage",
        confidence: numeric_confidence(response[:confidence]),
        decision: "clarify",
        reply: response[:reply].presence || default_clarify_result[:reply],
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

    def handoff_offer_result(response)
      human_handoff_offer_result(
        source: "llm",
        category: normalized_category(response[:category]),
        priority: normalized_priority(response[:priority]),
        current_layer: "triage",
        confidence: numeric_confidence(response[:confidence]),
        escalation_reason: "The request requires human review.",
        handoff_note: "A human specialist should review this case before the next reply.",
        summary: response[:reasoning_summary].presence || "Triage determined the request should be reviewed by a human specialist.",
        reply: response[:reply].presence || "This case needs human review. Use the button below if you want a human specialist to take over.",
        reasoning_summary: response[:reasoning_summary].presence || "Triage offered a human handoff.",
        input_snapshot: latest_message.content,
        tags: normalized_tags(response[:tags], fallback_tags: triage_tags(response, "offer_human_handoff"))
      )
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

    def normalized_tags(raw_tags, fallback_tags:)
      tags = Array(raw_tags).filter_map { |tag| normalize_tag(tag) }
      tags.presence || fallback_tags
    end

    def fallback_knowledge_tags(chunk)
      [
        "public-knowledge",
        "knowledge-answer",
        "policy",
        normalize_tag(chunk.source&.title),
        normalize_tag(chunk.manual_entry&.title),
        normalize_tag(country_from(latest_message.content))
      ].compact.uniq
    end

    def knowledge_tags(matches)
      matches.flat_map { |match| fallback_knowledge_tags(match.chunk) }.uniq
    end

    def triage_tags(response, route)
      tags = [
        normalized_category(response[:category]),
        route == "escalate" ? "human-review" : "triage",
        route
      ]
      country = country_from(latest_message.content)
      tags << country if country
      tags.compact.uniq
    end

    def country_from(content)
      text = content.to_s.downcase
      return "canada" if text.include?("canada")

      nil
    end

    def normalize_tag(value)
      candidate = value.to_s.parameterize
      candidate.presence
    end
  end
end
