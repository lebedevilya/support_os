module Agents
  class TriageAgent
    KNOWLEDGE_MIN_SCORE = 2

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
        input_snapshot: latest_message.content,
        tags: %w[other human-review unknown-request]
      }
    end

    private

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
          - route: knowledge_answer, specialist, or escalate
          - confidence: decimal between 0 and 1
          - needs_human_now: boolean
          - reply: optional string when route is knowledge_answer
          - reasoning_summary: short sentence
          - tags: array of strings
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
        input_snapshot: latest_message.content,
        tags: %w[other human-review llm-failure]
      }
    end

    def build_llm_result(response)
      route =
        if response[:needs_human_now] || response[:route].to_s == "escalate"
          "escalate"
        else
          "specialist"
        end

      {
        source: "llm",
        status: route == "escalate" ? "escalated" : "in_progress",
        category: normalized_category(response[:category]),
        priority: normalized_priority(response[:priority]),
        route: route,
        current_layer: route == "escalate" ? "human" : "specialist",
        confidence: numeric_confidence(response[:confidence]),
        decision: route == "escalate" ? "escalate" : "triage",
        reply: nil,
        escalation_reason: (route == "escalate" ? "The request requires human review." : nil),
        handoff_note: (route == "escalate" ? "Escalated for human review based on the triage decision." : nil),
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
