require "pagy"

module ApplicationHelper
  include Pagy::NumericHelpers

  URL_PATTERN = %r{https?://[^\s<]+}.freeze

  def linked_message_content(text)
    safe_join(linkify_segments(text.to_s))
  end

  def format_confidence(value)
    number = value.to_f
    return "n/a" if number <= 0

    "#{(number * 100).round}%"
  end

  def pretty_json(value)
    JSON.pretty_generate(parse_json_like(value))
  rescue JSON::ParserError, TypeError
    value.to_s
  end

  def ticket_status_label(ticket)
    return "Needs support" if ticket.status == "escalated"
    return "Waiting on support" if ticket.manual_takeover? && ticket.status == "in_progress"
    return "Waiting on customer" if ticket.status == "awaiting_customer"
    return "Resolved" if ticket.status == "resolved"
    return "New" if ticket.status == "new"

    ticket.status.to_s.humanize
  end

  def ticket_status_badge_class(ticket)
    return "bg-rose-100 text-rose-900" if ticket.status == "escalated"
    return "bg-amber-100 text-amber-900" if ticket.manual_takeover? && ticket.status == "in_progress"
    return "bg-emerald-100 text-emerald-900" if ticket.status == "awaiting_customer"
    return "bg-slate-100 text-slate-700"
  end

  def agent_source_label(snapshot)
    source = parse_json_like(snapshot)["source"].to_s

    case source
    when "support_rule" then "Support rule"
    when "llm_human_handoff" then "Human handoff intent"
    when "public_knowledge" then "Public knowledge"
    when "public_knowledge_llm" then "Public knowledge + LLM"
    when "llm" then "LLM"
    when "llm_error_fallback" then "LLM fallback"
    when "fallback" then "Fallback"
    else
      source.presence || "Unknown"
    end
  rescue JSON::ParserError, TypeError, NoMethodError
    "Unknown"
  end

  def trace_step_label(run)
    case run.agent_name
    when "TriageAgent" then "Triage step"
    when "SpecialistAgent" then "Specialist step"
    when "HumanHandoff" then "Human handoff"
    else
      run.agent_name
    end
  end

  def tool_kind_label(tool_name)
    action_tools = %w[resend_download_link reboot_node]
    action_tools.include?(tool_name) ? "Action completed" : "Lookup tool"
  end

  def widget_scenarios_for(company)
    return [] unless company

    case company.slug
    when "aipassportphoto"
      [
        { prompt: "Can I make a picture for UK visa?", email: "review@example.com" },
        { prompt: "How long does it take?", email: "timing@example.com" },
        { prompt: "What is the status of my photo request?", email: "anna@example.com" },
        { prompt: "I did not receive my file, resend the download link", email: "sara@example.com" },
        { prompt: "My photo was rejected by the embassy and I want a refund right now", email: "refund@example.com" }
      ]
    when "nodes-garden"
      [
        { prompt: "What states can a deployment go through?", email: "lifecycle@example.com" },
        { prompt: "How does billing work?", email: "billing@example.com" },
        { prompt: "My node is still provisioning after 20 minutes", email: "operator@example.com" },
        { prompt: "Reboot my node", email: "operator@example.com" },
        { prompt: "Connect me to a human in this chat", email: "human@example.com" }
      ]
    else
      []
    end
  end

  private

  def parse_json_like(value)
    return value if value.is_a?(Hash) || value.is_a?(Array)

    JSON.parse(value.to_s)
  end

  def linkify_segments(text)
    text.split(URL_PATTERN).zip(text.scan(URL_PATTERN)).flat_map do |plain_text, url|
      parts = []
      parts << ERB::Util.html_escape(plain_text) if plain_text.present?
      if url.present?
        parts << link_to(
          url,
          url,
          target: "_blank",
          rel: "noopener noreferrer",
          class: "text-sky-700 underline underline-offset-2"
        )
      end
      parts
    end.compact
  end
end
