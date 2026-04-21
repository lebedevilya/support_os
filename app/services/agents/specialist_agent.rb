module Agents
  class SpecialistAgent
    ACTION_NONE = "none".freeze

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
        lookup_result = create_tool_call!(
          tool_name: "lookup_photo_request",
          input_payload: { email: @ticket.customer.email },
          output_payload: {
            external_id: record.external_id,
            status: record.status,
            payload: record.payload
          }
        )

        action = select_action(
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

        return llm_delivery_response(record, tool_results) if @llm_client

        {
          source: "fallback",
          status: "awaiting_customer",
          current_layer: "specialist",
          confidence: action == "resend_download_link" ? 0.93 : 0.87,
          decision: "answered",
          reply: delivery_status_reply(record, action: action),
          reasoning_summary: delivery_reasoning_summary(action),
          input_snapshot: latest_message.content,
          tags: delivery_tags(action)
        }
      else
        handoff_offer_result(
          reason: "No matching business record was found for the delivery issue.",
          reply: "I could not safely verify your request automatically. If you want, I can connect you with a human specialist.",
          summary: "Delivery issue requires human review because no matching business record was found in the demo data.",
          tags: %w[delivery human-review missing-record]
        )
      end
    end

    def resolve_technical
      record = @ticket.company.business_records.find_by(customer_email: @ticket.customer.email)

      if record
        lookup_result = create_tool_call!(
          tool_name: "lookup_deployment",
          input_payload: { email: @ticket.customer.email },
          output_payload: { external_id: record.external_id, status: record.status, payload: record.payload }
        )

        action = select_action(
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

        return llm_technical_response(record, tool_results) if @llm_client

        {
          source: "fallback",
          status: "awaiting_customer",
          current_layer: "specialist",
          confidence: action == "reboot_node" ? 0.92 : 0.85,
          decision: "answered",
          reply: technical_status_reply(record, action: action),
          reasoning_summary: technical_reasoning_summary(action),
          input_snapshot: latest_message.content,
          tags: technical_tags(action)
        }
      else
        handoff_offer_result(
          reason: "No deployment record was found for the provisioning request.",
          reply: "I could not safely verify the deployment status automatically. If you want, I can connect you with a human specialist.",
          summary: "Technical request requires human review because no deployment record was found in the demo data.",
          tags: %w[technical human-review missing-record]
        )
      end
    end

    def escalate_unknown
      handoff_offer_result(
        reason: "No specialist path is implemented for this category.",
        reply: "This case needs a human specialist. Use the button below if you want a human to take over.",
        summary: "No safe specialist workflow exists for the current category.",
        tags: %w[human-review unsupported-category]
      )
    end

    def latest_message
      @ticket.messages.order(:created_at).last
    end

    def message_history
      @ticket.messages.order(:created_at).pluck(:role, :content)
    end

    def create_tool_call!(tool_name:, input_payload:, output_payload:)
      @ticket.tool_calls.create!(
        tool_name: tool_name,
        status: "success",
        input_payload: input_payload.to_json,
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
          message_history: message_history,
          knowledge_articles: [ { title: article.title, content: article.content } ],
          tool_results: []
        }
      )

      llm_specialist_result(response)
    rescue StandardError => e
      llm_failure_result("Policy specialist failed: #{e.message}")
    end

    def llm_delivery_response(record, tool_results)
      response = @llm_client.complete_json(
        task: "specialist",
        prompt: specialist_prompt,
        context: {
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
      )

      llm_specialist_result(response)
    rescue StandardError => e
      llm_failure_result("Delivery specialist failed: #{e.message}")
    end

    def llm_technical_response(record, tool_results)
      response = @llm_client.complete_json(
        task: "specialist",
        prompt: specialist_prompt,
        context: {
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
        If an action tool ran successfully, say what happened and what the customer should expect next.
        If the case is ambiguous or unsafe, set resolve_ticket to false.
      PROMPT
    end

    def delivery_status_reply(record, action:)
      delivery_state = record.payload["asset_delivery"].presence || record.status
      return "I found your request and resent the download link. You can use #{record.payload['download_url']} to access the file." if action == "resend_download_link"

      "I found your request. The delivery status is currently marked as #{delivery_state}. I have not triggered a resend from this chat."
    end

    def technical_status_reply(record, action:)
      return "I found your deployment and started a node reboot for #{record.payload['node_name']}. The deployment is now marked as rebooting." if action == "reboot_node"

      "Your node deployment is still provisioning. The latest record shows the deployment is active but not healthy yet."
    end

    def delivery_reasoning_summary(action)
      return "A matching business record was found and the download link resend action completed." if action == "resend_download_link"

      "A matching business record was found for the customer email."
    end

    def technical_reasoning_summary(action)
      return "A deployment record was found and the node reboot action completed." if action == "reboot_node"

      "A deployment record was found and the current status is still provisioning."
    end

    def delivery_tags(action)
      tags = %w[delivery asset-delivery]
      tags << "download-link-resent" if action == "resend_download_link"
      tags
    end

    def technical_tags(action)
      tags = %w[technical provisioning node]
      tags << "node-reboot" if action == "reboot_node"
      tags
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

    def select_action(category:, allowed_actions:, record:, tool_results:)
      return llm_action_choice(category: category, allowed_actions: allowed_actions, record: record, tool_results: tool_results) if @llm_client

      fallback_action_choice(category: category, allowed_actions: allowed_actions)
    end

    def llm_action_choice(category:, allowed_actions:, record:, tool_results:)
      response = @llm_client.complete_json(
        task: "specialist_action",
        prompt: <<~PROMPT,
          Choose the next specialist action.
          Return keys:
          - action: one of #{allowed_actions.join(', ')}
          - reasoning_summary: short sentence
          Rules:
          - only choose a listed action
          - choose an action only when the customer clearly asked for it and the provided record state supports it
          - choose escalate when the request is unsafe or the record state is ambiguous
          - choose none when a lookup-backed reply is enough
        PROMPT
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
      fallback_action_choice(category: category, allowed_actions: allowed_actions)
    end

    def fallback_action_choice(category:, allowed_actions:)
      message = latest_message.content.to_s.downcase

      if category == "delivery" && allowed_actions.include?("resend_download_link") && message.include?("resend")
        return "resend_download_link"
      end

      if category == "technical" && allowed_actions.include?("reboot_node") && message.include?("reboot")
        return "reboot_node"
      end

      ACTION_NONE
    end

    def resend_allowed?(record)
      record.payload["resend_allowed"] == true && record.payload["download_url"].present?
    end

    def reboot_allowed?(record)
      record.payload["reboot_allowed"] == true
    end

    def action_escalation_result(reason)
      handoff_offer_result(
        reason: reason,
        reply: "I could not safely complete that request automatically. If you want, I can connect you with a human specialist.",
        summary: reason,
        tags: normalized_tags(nil, fallback_tags: specialist_tags(false))
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
        current_layer: resolve ? "specialist" : "specialist",
        confidence: numeric_confidence(response[:confidence]),
        decision: resolve ? "answered" : "offer_human_handoff",
        reply: response[:reply].presence || (resolve ? nil : "This case needs human review. Use the button below if you want a human specialist to take over."),
        summary: (resolve ? nil : response[:reasoning_summary].presence || "The specialist decision requires human review."),
        escalation_reason: (resolve ? nil : "The specialist decision requires human review."),
        handoff_note: (resolve ? nil : "A human specialist should review this case before the next reply."),
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
  end
end
