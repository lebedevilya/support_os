module Agents
  class SpecialistAgent
    ACTION_NONE = "none".freeze

    include Agents::Shared::Normalizers

    def initialize(ticket:, triage_result:, llm_client: nil)
      @ticket = ticket
      @triage_result = triage_result
      @llm_client = llm_client
    end

    def call
      case @triage_result.fetch(:category)
      when "policy" then resolve_policy
      when "delivery" then resolve_delivery
      when "technical" then resolve_technical
      else escalate_unknown
      end
    end

    private

    def resolve_policy
      article = @ticket.company.knowledge_articles.find_by(category: "policy") ||
        @ticket.company.knowledge_articles.first

      response = @llm_client.complete_json(
        task: "specialist",
        prompt: Specialist::Prompts::POLICY,
        context: {
          company: @ticket.company.name,
          category: @triage_result[:category],
          latest_message: latest_message.content,
          message_history: message_history,
          knowledge_articles: [ { title: article.title, content: article.content } ],
          tool_results: []
        }
      )
      llm_specialist_result(response)
    rescue StandardError => e
      llm_failure_result("Policy specialist failed: #{e.message}")
    end

    def resolve_delivery
      record = @ticket.company.business_records.find_by(customer_email: @ticket.customer.email)
      return record_not_found_result unless record

      lookup_result = create_tool_call!(
        tool_name: "lookup_photo_request",
        input_payload: { email: @ticket.customer.email },
        output_payload: { external_id: record.external_id, status: record.status, payload: record.payload }
      )

      action = llm_action_choice(
        category: "delivery",
        allowed_actions: [ ACTION_NONE, "resend_download_link", "escalate" ],
        record: record,
        tool_results: [ tool_payload(lookup_result) ]
      )
      return action_escalation_result("Delivery request needs human review after record lookup.") if action == "escalate"

      tool_results = [ tool_payload(lookup_result) ]
      if action == "resend_download_link"
        return action_escalation_result("Download link resend is not allowed for this request.") unless resend_allowed?(record)

        tool_results << tool_payload(resend_download_link!(record))
      end

      response = @llm_client.complete_json(
        task: "specialist",
        prompt: Specialist::Prompts::GENERAL,
        context: build_specialist_context(record, tool_results)
      )
      llm_specialist_result(response)
    rescue StandardError => e
      llm_failure_result("Delivery specialist failed: #{e.message}")
    end

    def resolve_technical
      record = @ticket.company.business_records.find_by(customer_email: @ticket.customer.email)
      return record_not_found_result unless record

      lookup_result = create_tool_call!(
        tool_name: "lookup_deployment",
        input_payload: { email: @ticket.customer.email },
        output_payload: { external_id: record.external_id, status: record.status, payload: record.payload }
      )

      action = llm_action_choice(
        category: "technical",
        allowed_actions: [ ACTION_NONE, "reboot_node", "escalate" ],
        record: record,
        tool_results: [ tool_payload(lookup_result) ]
      )
      return action_escalation_result("Technical request needs human review after deployment lookup.") if action == "escalate"

      tool_results = [ tool_payload(lookup_result) ]
      if action == "reboot_node"
        return action_escalation_result("Node reboot is not allowed for this deployment.") unless reboot_allowed?(record)

        tool_results << tool_payload(reboot_node!(record))
      end

      response = @llm_client.complete_json(
        task: "specialist",
        prompt: Specialist::Prompts::GENERAL,
        context: build_specialist_context(record, tool_results)
      )
      llm_specialist_result(response)
    rescue StandardError => e
      llm_failure_result("Technical specialist failed: #{e.message}")
    end

    def escalate_unknown
      handoff_offer_result(
        reason: "No specialist path is implemented for this category.",
        reply: "This case needs a human specialist. Use the button below if you want a human to take over.",
        summary: "No safe specialist workflow exists for the current category.",
        tags: %w[human-review unsupported-category]
      )
    end

    def build_specialist_context(record, tool_results)
      {
        company: @ticket.company.name,
        category: @triage_result[:category],
        latest_message: latest_message.content,
        message_history: message_history,
        knowledge_articles: related_articles,
        tool_results: tool_results,
        business_record: {
          external_id: record.external_id,
          status: record.status,
          payload: record.payload
        }
      }
    end

    def llm_action_choice(category:, allowed_actions:, record:, tool_results:)
      response = @llm_client.complete_json(
        task: "specialist_action",
        prompt: Specialist::Prompts.action_choice(allowed_actions: allowed_actions),
        context: {
          company: @ticket.company.name,
          category: category,
          latest_message: latest_message.content,
          message_history: message_history,
          business_record: {
            external_id: record.external_id,
            status: record.status,
            payload: record.payload
          },
          tool_results: tool_results
        }
      )

      choice = response[:action].to_s
      allowed_actions.include?(choice) ? choice : ACTION_NONE
    rescue StandardError
      ACTION_NONE
    end

    def resend_download_link!(record)
      payload = record.payload.deep_dup
      payload["asset_delivery"] = "resent"
      payload["last_resent_at"] = Time.current.iso8601
      record.update!(payload: payload)

      create_tool_call!(
        tool_name: "resend_download_link",
        input_payload: { external_id: record.external_id },
        output_payload: {
          external_id: record.external_id,
          download_url: payload["download_url"],
          completed: true
        }
      )
    end

    def reboot_node!(record)
      payload = record.payload.deep_dup
      payload["last_reboot_at"] = Time.current.iso8601
      record.update!(status: "rebooting", payload: payload)

      create_tool_call!(
        tool_name: "reboot_node",
        input_payload: { external_id: record.external_id, node_name: payload["node_name"] },
        output_payload: {
          external_id: record.external_id,
          node_name: payload["node_name"],
          status: "rebooting",
          completed: true
        }
      )
    end

    def resend_allowed?(record)
      record.payload["resend_allowed"] == true && record.payload["download_url"].present?
    end

    def reboot_allowed?(record)
      record.payload["reboot_allowed"] == true
    end

    def create_tool_call!(tool_name:, input_payload:, output_payload:)
      @ticket.tool_calls.create!(
        tool_name: tool_name,
        status: "success",
        input_payload: input_payload.to_json,
        output_payload: output_payload.to_json
      )
    end

    def tool_payload(tool_result)
      {
        tool_name: tool_result.tool_name,
        status: tool_result.status,
        output: JSON.parse(tool_result.output_payload)
      }
    end

    def llm_specialist_result(response)
      resolve = response[:resolve_ticket] == true

      {
        source: "llm",
        status: "awaiting_customer",
        current_layer: "specialist",
        confidence: numeric_confidence(response[:confidence]),
        decision: resolve ? "answered" : "offer_human_handoff",
        reply: response[:reply].presence || (resolve ? nil : "This case needs human review. Use the button below if you want a human specialist to take over."),
        summary: resolve ? nil : (response[:reasoning_summary].presence || "The specialist decision requires human review."),
        escalation_reason: resolve ? nil : "The specialist decision requires human review.",
        handoff_note: resolve ? nil : "A human specialist should review this case before the next reply.",
        reasoning_summary: response[:reasoning_summary].presence || "Specialist completed.",
        input_snapshot: latest_message.content,
        human_handoff_available: !resolve,
        tags: normalized_tags(response[:tags], fallback_tags: specialist_tags(resolve))
      }
    end

    def llm_failure_result(message)
      handoff_offer_result(
        source: "llm_error_fallback",
        confidence: 0.0,
        reason: message,
        reply: "I could not safely complete this request automatically. If you want, I can connect you with a human specialist.",
        summary: message,
        tags: normalized_tags(nil, fallback_tags: specialist_tags(false) + [ "llm-failure" ])
      )
    end

    def record_not_found_result
      handoff_offer_result(
        reason: "No matching business record was found.",
        reply: "I could not safely verify your request automatically. If you want, I can connect you with a human specialist.",
        summary: "Request requires human review because no matching business record was found.",
        tags: %w[human-review missing-record]
      )
    end

    def action_escalation_result(reason)
      handoff_offer_result(
        reason: reason,
        reply: "I could not safely complete that request automatically. If you want, I can connect you with a human specialist.",
        summary: reason,
        tags: normalized_tags(nil, fallback_tags: specialist_tags(false))
      )
    end

    def handoff_offer_result(reason:, reply:, summary:, tags:, source: "fallback", confidence: 0.64)
      {
        source: source,
        status: "awaiting_customer",
        current_layer: "specialist",
        confidence: confidence,
        decision: "offer_human_handoff",
        route: "offer_human_handoff",
        escalation_reason: reason,
        handoff_note: "A human specialist should review this case before the next reply because it needs human review.",
        summary: summary,
        reply: reply,
        reasoning_summary: reason,
        input_snapshot: latest_message.content,
        human_handoff_available: true,
        tags: tags
      }
    end

    def specialist_tags(resolve)
      tags = [ @triage_result[:category], resolve ? "answered" : "human-review" ]
      tags << "supported-country" if @triage_result[:category] == "policy"
      tags << "asset-delivery" if @triage_result[:category] == "delivery"
      tags += %w[provisioning node] if @triage_result[:category] == "technical"
      tags.filter_map { |tag| normalize_tag(tag) }.uniq
    end

    def related_articles
      @ticket.company.knowledge_articles.where(category: [ @triage_result[:category], "policy", "technical", "delivery" ]).map do |article|
        { title: article.title, content: article.content }
      end
    end

    def latest_message
      @latest_message ||= @ticket.messages.order(:created_at).last
    end

    def message_history
      @message_history ||= @ticket.messages.order(:created_at).pluck(:role, :content)
    end
  end
end
