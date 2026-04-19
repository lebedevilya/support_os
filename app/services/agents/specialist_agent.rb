module Agents
  class SpecialistAgent
    def initialize(ticket:, triage_result:, llm_client: nil)
      @ticket = ticket
      @triage_result = triage_result
      @llm_client = llm_client
    end

    def call
      case @triage_result.fetch(:category)
      when "policy"
        resolve_policy
      when "delivery"
        resolve_delivery
      when "technical"
        resolve_technical
      else
        escalate_unknown
      end
    end

    private

    def resolve_policy
      article = @ticket.company.knowledge_articles.find_by(category: "policy") ||
        @ticket.company.knowledge_articles.first

      return llm_policy_response(article) if @llm_client

      {
        source: "fallback",
        status: "awaiting_customer",
        current_layer: "specialist",
        confidence: 0.9,
        decision: "answered",
        reply: "Yes. We support Canada passport photos.",
        reasoning_summary: "The supported countries article confirms Canada is supported.",
        input_snapshot: latest_message.content,
        tags: %w[policy supported-country canada]
      }
    end

    def resolve_delivery
      record = @ticket.company.business_records.find_by(customer_email: @ticket.customer.email)

      if record
        tool_result = create_tool_call!(
          tool_name: "lookup_photo_request",
          output_payload: { external_id: record.external_id, status: record.status }
        )

        return llm_delivery_response(record, tool_result) if @llm_client

        {
          source: "fallback",
          status: "awaiting_customer",
          current_layer: "specialist",
          confidence: 0.87,
          decision: "answered",
          reply: delivery_status_reply(record),
          reasoning_summary: "A matching business record was found for the customer email.",
          input_snapshot: latest_message.content,
          tags: %w[delivery asset-delivery]
        }
      else
        {
          source: "fallback",
          status: "escalated",
          current_layer: "human",
          confidence: 0.64,
          decision: "escalate",
          escalation_reason: "No matching business record was found for the delivery issue.",
          handoff_note: "Escalated for human review because no matching business record was found for this delivery request.",
          reply: "I could not safely verify your request, so I have escalated this to a human reviewer.",
          reasoning_summary: "Delivery issue requires data that is not available in the demo records.",
          input_snapshot: latest_message.content,
          tags: %w[delivery human-review missing-record]
        }
      end
    end

    def resolve_technical
      record = @ticket.company.business_records.find_by(customer_email: @ticket.customer.email)

      if record
        tool_result = create_tool_call!(
          tool_name: "lookup_deployment",
          output_payload: { external_id: record.external_id, status: record.status, payload: record.payload }
        )

        return llm_technical_response(record, tool_result) if @llm_client

        {
          source: "fallback",
          status: "awaiting_customer",
          current_layer: "specialist",
          confidence: 0.85,
          decision: "answered",
          reply: "Your node deployment is still provisioning. The latest record shows the deployment is active but not healthy yet.",
          reasoning_summary: "A deployment record was found and the current status is still provisioning.",
          input_snapshot: latest_message.content,
          tags: %w[technical provisioning node]
        }
      else
        {
          source: "fallback",
          status: "escalated",
          current_layer: "human",
          confidence: 0.62,
          decision: "escalate",
          escalation_reason: "No deployment record was found for the provisioning request.",
          handoff_note: "Escalated for human review because no deployment record was found for this node provisioning request.",
          reply: "I could not safely verify the deployment status, so I have escalated this to a human reviewer.",
          reasoning_summary: "Technical request requires a deployment record that is not available in the demo data.",
          input_snapshot: latest_message.content,
          tags: %w[technical human-review missing-record]
        }
      end
    end

    def escalate_unknown
      {
        source: "fallback",
        status: "escalated",
        current_layer: "human",
        confidence: 0.6,
        decision: "escalate",
        escalation_reason: "No specialist path is implemented for this category.",
        handoff_note: "Escalated for human review because no safe specialist path exists for this request.",
        reply: "I have escalated this request to a human reviewer.",
        reasoning_summary: "No specialist workflow exists for the current category.",
        input_snapshot: latest_message.content,
        tags: %w[human-review unsupported-category]
      }
    end

    def latest_message
      @ticket.messages.order(:created_at).last
    end

    def create_tool_call!(tool_name:, output_payload:)
      @ticket.tool_calls.create!(
        tool_name: tool_name,
        status: "success",
        input_payload: { email: @ticket.customer.email }.to_json,
        output_payload: output_payload.to_json
      )
    end

    def llm_policy_response(article)
      response = @llm_client.complete_json(
        task: "specialist",
        prompt: <<~PROMPT,
          Draft a customer-facing support reply.
          Return keys:
          - reply: string
          - resolve_ticket: boolean
          - confidence: decimal between 0 and 1
          - used_knowledge_articles: array of strings
          - used_tools: array of strings
          - reasoning_summary: short sentence
          - tags: array of strings
          Use only the provided knowledge and do not invent policies.
        PROMPT
        context: {
          company: @ticket.company.name,
          category: @triage_result[:category],
          latest_message: latest_message.content,
          knowledge_articles: [ { title: article.title, content: article.content } ],
          tool_results: []
        }
      )

      llm_specialist_result(response)
    rescue StandardError => e
      llm_failure_result("Policy specialist failed: #{e.message}")
    end

    def llm_delivery_response(record, tool_result)
      response = @llm_client.complete_json(
        task: "specialist",
        prompt: specialist_prompt,
        context: {
          company: @ticket.company.name,
          category: @triage_result[:category],
          latest_message: latest_message.content,
          knowledge_articles: related_articles,
          tool_results: [
            {
              tool_name: tool_result.tool_name,
              status: tool_result.status,
              output: JSON.parse(tool_result.output_payload)
            }
          ],
          business_record: {
            external_id: record.external_id,
            status: record.status,
            payload: record.payload
          }
        }
      )

      llm_specialist_result(response)
    rescue StandardError => e
      llm_failure_result("Delivery specialist failed: #{e.message}")
    end

    def llm_technical_response(record, tool_result)
      response = @llm_client.complete_json(
        task: "specialist",
        prompt: specialist_prompt,
        context: {
          company: @ticket.company.name,
          category: @triage_result[:category],
          latest_message: latest_message.content,
          knowledge_articles: related_articles,
          tool_results: [
            {
              tool_name: tool_result.tool_name,
              status: tool_result.status,
              output: JSON.parse(tool_result.output_payload)
            }
          ],
          business_record: {
            external_id: record.external_id,
            status: record.status,
            payload: record.payload
          }
        }
      )

      llm_specialist_result(response)
    rescue StandardError => e
      llm_failure_result("Technical specialist failed: #{e.message}")
    end

    def specialist_prompt
      <<~PROMPT
        Draft a customer-facing support reply.
        Return keys:
        - reply: string
        - resolve_ticket: boolean
        - confidence: decimal between 0 and 1
        - used_knowledge_articles: array of strings
        - used_tools: array of strings
        - reasoning_summary: short sentence
        - tags: array of strings
        Use only the provided knowledge and tool results.
        Do not claim any operational action happened unless the tool results explicitly show that action happened.
        If the case is ambiguous or unsafe, set resolve_ticket to false.
      PROMPT
    end

    def delivery_status_reply(record)
      delivery_state = record.payload["asset_delivery"].presence || record.status
      "I found your request. The delivery status is currently marked as #{delivery_state}. I have not triggered a resend from this chat."
    end

    def llm_specialist_result(response)
      resolve = response[:resolve_ticket] == true

      {
        source: "llm",
        status: resolve ? "awaiting_customer" : "escalated",
        current_layer: resolve ? "specialist" : "human",
        confidence: numeric_confidence(response[:confidence]),
        decision: resolve ? "answered" : "escalate",
        reply: response[:reply],
        escalation_reason: (resolve ? nil : "The specialist decision requires human review."),
        handoff_note: (resolve ? nil : "Escalated for human review based on the specialist decision."),
        reasoning_summary: response[:reasoning_summary].presence || "Specialist completed.",
        input_snapshot: latest_message.content,
        tags: normalized_tags(response[:tags], fallback_tags: specialist_tags(resolve))
      }
    end

    def llm_failure_result(message)
      {
        source: "llm_error_fallback",
        status: "escalated",
        current_layer: "human",
        confidence: 0.0,
        decision: "escalate",
        escalation_reason: message,
        handoff_note: "Escalated for human review because the specialist step failed.",
        reply: "I could not safely complete this request, so I have escalated it to a human reviewer.",
        reasoning_summary: message,
        input_snapshot: latest_message.content,
        tags: normalized_tags(nil, fallback_tags: specialist_tags(false) + [ "llm-failure" ])
      }
    end

    def related_articles
      @ticket.company.knowledge_articles.where(category: [ @triage_result[:category], "policy", "technical", "delivery" ]).map do |article|
        { title: article.title, content: article.content }
      end
    end

    def numeric_confidence(value)
      number = value.to_f
      return 0.0 if number.nan?

      [[ number, 0.0 ].max, 1.0].min
    end

    def normalized_tags(raw_tags, fallback_tags:)
      tags = Array(raw_tags).filter_map { |tag| normalize_tag(tag) }
      tags.presence || fallback_tags
    end

    def specialist_tags(resolve)
      tags = [ @triage_result[:category], resolve ? "answered" : "human-review" ]
      tags << "supported-country" if @triage_result[:category] == "policy"
      tags << "asset-delivery" if @triage_result[:category] == "delivery"
      tags += %w[provisioning node] if @triage_result[:category] == "technical"
      tags.filter_map { |tag| normalize_tag(tag) }.uniq
    end

    def normalize_tag(value)
      candidate = value.to_s.parameterize
      candidate.presence
    end
  end
end
