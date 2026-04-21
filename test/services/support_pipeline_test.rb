require "test_helper"

class SupportPipelineTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    @customer = Customer.create!(email: "anna@example.com")
  end

  test "resolves a supported country question with triage and specialist traces" do
    SupportRule.create!(
      company: @company,
      name: "Supported country policy questions",
      active: true,
      priority: 20,
      match_type: "all_terms",
      terms: "support\ncanada",
      route: "specialist",
      category: "policy",
      priority_level: "normal",
      confidence: 0.88,
      reasoning_summary: "Supported-country policy questions can go to the policy specialist."
    )

    KnowledgeArticle.create!(
      company: @company,
      title: "Supported Countries",
      category: "policy",
      content: "We support passport photo formats for Canada, the US, the UK, and Schengen countries."
    )

    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Do you support Canada passport photos?")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "specialist", ticket.current_layer
    assert_equal "policy", ticket.category
    assert_equal 2, ticket.agent_runs.count
    assert_equal [ "TriageAgent", "SpecialistAgent" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.messages.order(:created_at).last.content, "Canada"
  end

  test "answers UK visa support question from triage public knowledge instead of specialist" do
    source = Knowledge::Source.create!(
      company: @company,
      url: "https://www.aipassportphoto.co/",
      title: "AI Passport Photo",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "Our AI removes the background, adjusts lighting, and checks every requirement for US, UK, Canada, and 100+ countries. Delivered instantly."
    )
    source.chunks.create!(
      company: @company,
      content: "Our AI removes the background, adjusts lighting, and checks every requirement for US, UK, Canada, and 100+ countries. Delivered instantly.",
      position: 0,
      token_estimate: 24
    )

    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Can I make a picture for UK visa?")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal 1, ticket.agent_runs.count
    assert_equal [ "TriageAgent" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.messages.order(:created_at).last.content, "UK"
  end

  test "offers a manual human handoff for an embassy refund dispute" do
    SupportRule.create!(
      name: "Embassy refund dispute",
      active: true,
      priority: 10,
      match_type: "all_terms",
      terms: "embassy\nrefund",
      route: "escalate",
      category: "refund",
      priority_level: "high",
      confidence: 0.92,
      reasoning_summary: "Embassy rejection disputes require human review.",
      escalation_reason: "Refund dispute requires human review.",
      handoff_note: "Escalated for human review because the customer reports an embassy rejection dispute."
    )

    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "My photo was rejected by the embassy and I want a refund right now")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal "refund", ticket.category
    assert_equal false, ticket.manual_takeover
    assert_equal true, ticket.human_handoff_available
    assert_equal 1, ticket.agent_runs.count
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.escalation_reason, "human review"
    assert_includes ticket.handoff_note, "embassy"
    assert_equal "support_rule", JSON.parse(ticket.agent_runs.order(:created_at).first.output_snapshot).fetch("source")
  end

  test "resolves a nodes garden provisioning status question from a deployment record" do
    company = Company.create!(
      name: "nodes.garden",
      slug: "nodes-garden",
      description: "Node deployment support",
      support_email: "support@nodes.garden"
    )
    customer = Customer.create!(email: "operator@example.com")

    SupportRule.create!(
      company: company,
      name: "Provisioning status questions",
      active: true,
      priority: 20,
      match_type: "any_terms",
      terms: "provisioning\nnode status",
      route: "specialist",
      category: "technical",
      priority_level: "normal",
      confidence: 0.84,
      reasoning_summary: "Provisioning and node-status questions can go to the technical specialist."
    )

    BusinessRecord.create!(
      company: company,
      record_type: "node_deployment",
      external_id: "ND-1001",
      customer_email: "operator@example.com",
      status: "provisioning",
      payload: {
        node_name: "validator-1",
        last_error: nil
      }
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "My node is still provisioning after 20 minutes")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "technical", ticket.category
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.messages.order(:created_at).last.content, "still provisioning"
    assert_equal [ "TriageAgent", "SpecialistAgent" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    assert_equal [ "lookup_deployment" ], ticket.tool_calls.order(:created_at).pluck(:tool_name)
    assert_equal ticket.agent_runs.order(:created_at).last, ticket.tool_calls.order(:created_at).last.agent_run
  end

  test "delivery reply does not claim a resend when only a lookup tool was used" do
    SupportRule.create!(
      company: @company,
      name: "Missing asset delivery questions",
      active: true,
      priority: 20,
      match_type: "any_terms",
      terms: "did not receive\ndidn't receive",
      route: "specialist",
      category: "delivery",
      priority_level: "normal",
      confidence: 0.82,
      reasoning_summary: "Missing asset questions can go to the delivery specialist."
    )

    BusinessRecord.create!(
      company: @company,
      record_type: "photo_request",
      external_id: "APP-1001",
      customer_email: "anna@example.com",
      status: "completed",
      payload: {
        asset_delivery: "sent",
        download_url: "https://example.test/download/APP-1001"
      }
    )

    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "I paid but did not receive my file")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    reply = ticket.messages.order(:created_at).last.content

    assert_equal "awaiting_customer", ticket.status
    assert_equal [ "lookup_photo_request" ], ticket.tool_calls.order(:created_at).pluck(:tool_name)
    assert_equal ticket.agent_runs.order(:created_at).last, ticket.tool_calls.order(:created_at).last.agent_run
    refute_includes reply.downcase, "resent"
    assert_includes reply.downcase, "delivery status"
  end

  test "specialist can resend a download link through explicit tool calls" do
    SupportRule.create!(
      company: @company,
      name: "Resend download link requests",
      active: true,
      priority: 15,
      match_type: "all_terms",
      terms: "resend\ndownload link",
      route: "specialist",
      category: "delivery",
      priority_level: "high",
      confidence: 0.9,
      reasoning_summary: "Download-link resend requests should go to the delivery specialist."
    )

    BusinessRecord.create!(
      company: @company,
      record_type: "photo_request",
      external_id: "APP-1001",
      customer_email: "anna@example.com",
      status: "completed",
      payload: {
        asset_delivery: "sent",
        download_url: "https://example.test/download/APP-1001",
        resend_allowed: true
      }
    )

    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "I did not receive my file, resend the download link")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "specialist", ticket.current_layer
    assert_equal [ "lookup_photo_request", "resend_download_link" ], ticket.tool_calls.order(:created_at).pluck(:tool_name)
    assert_equal [ "TriageAgent", "SpecialistAgent" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    assert_equal ticket.agent_runs.order(:created_at).last, ticket.tool_calls.order(:created_at).last.agent_run
    assert_includes ticket.messages.order(:created_at).last.content.downcase, "resent"
    assert_includes ticket.messages.order(:created_at).last.content, "https://example.test/download/APP-1001"

    payload = @company.business_records.find_by!(external_id: "APP-1001").payload
    assert_equal "resent", payload["asset_delivery"]
    assert payload["last_resent_at"].present?
  end

  test "specialist can reboot a node through explicit tool calls" do
    company = Company.create!(
      name: "nodes.garden",
      slug: "nodes-garden",
      description: "Node deployment support",
      support_email: "support@nodes.garden"
    )
    customer = Customer.create!(email: "operator@example.com")

    SupportRule.create!(
      company: company,
      name: "Node reboot requests",
      active: true,
      priority: 15,
      match_type: "all_terms",
      terms: "reboot\nnode",
      route: "specialist",
      category: "technical",
      priority_level: "high",
      confidence: 0.9,
      reasoning_summary: "Explicit reboot requests should go to the technical specialist."
    )

    BusinessRecord.create!(
      company: company,
      record_type: "node_deployment",
      external_id: "ND-1001",
      customer_email: "operator@example.com",
      status: "provisioning",
      payload: {
        node_name: "validator-1",
        last_error: nil,
        reboot_allowed: true
      }
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Reboot my node")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "specialist", ticket.current_layer
    assert_equal [ "lookup_deployment", "reboot_node" ], ticket.tool_calls.order(:created_at).pluck(:tool_name)
    assert_equal ticket.agent_runs.order(:created_at).last, ticket.tool_calls.order(:created_at).last.agent_run
    assert_includes ticket.messages.order(:created_at).last.content.downcase, "reboot"

    record = company.business_records.find_by!(external_id: "ND-1001")
    assert_equal "rebooting", record.status
    assert record.payload["last_reboot_at"].present?
  end

  test "uses an injected llm client for triage and specialist decisions" do
    KnowledgeArticle.create!(
      company: @company,
      title: "Supported Countries",
      category: "policy",
      content: "We support passport photo formats for Canada, the US, the UK, and Schengen countries."
    )

    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Hi")
    ticket.messages.create!(role: "assistant", content: "Hello! What do you need help with?")
    ticket.messages.create!(role: "user", content: "Do you support Canada passport photos?")

    llm_client = FakeLlmClient.new(
      {
        needs_human_handoff: false,
        confidence: 0.94,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        category: "policy",
        priority: "normal",
        route: "specialist",
        confidence: 0.91,
        needs_human_now: false,
        reasoning_summary: "The customer is asking a supported-country question.",
        tags: [ "passport", "canada" ]
      },
      {
        reply: "Yes. Canada passport photos are supported.",
        resolve_ticket: true,
        confidence: 0.93,
        used_knowledge_articles: [ "Supported Countries" ],
        used_tools: [],
        reasoning_summary: "The company knowledge base confirms Canada is supported.",
        tags: [ "policy", "canada", "supported-country" ]
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal 3, llm_client.calls.size
    assert_equal [ "human_handoff_intent", "triage", "specialist" ], llm_client.calls.map { |call| call[:task] }
    assert_includes ticket.messages.order(:created_at).last.content, "Canada"
    assert_equal [ "canada", "passport", "policy", "supported-country" ], ticket.reload.tag_list.sort
    triage_call = llm_client.calls.find { |call| call[:task] == "triage" }
    specialist_call = llm_client.calls.find { |call| call[:task] == "specialist" }
    expected_history = [
      [ "user", "Hi" ],
      [ "assistant", "Hello! What do you need help with?" ],
      [ "user", "Do you support Canada passport photos?" ]
    ]
    assert_equal expected_history, triage_call[:context][:message_history]
    assert_equal expected_history, specialist_call[:context][:message_history]
    triage_run = ticket.agent_runs.order(:created_at).first
    specialist_run = ticket.agent_runs.order(:created_at).second
    assert_equal "llm", JSON.parse(triage_run.output_snapshot).fetch("source")
    assert_equal "llm", JSON.parse(specialist_run.output_snapshot).fetch("source")
  end

  test "clarifies a greeting instead of escalating to human" do
    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "hey there")

    llm_client = FakeLlmClient.new(
      {
        needs_human_handoff: false,
        confidence: 0.93,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        category: "other",
        priority: "low",
        route: "clarify",
        confidence: 0.97,
        needs_human_now: false,
        reply: "Hello! I can help with AI Passport Photo support. What do you need help with today?",
        reasoning_summary: "This is a greeting with no concrete support issue yet.",
        tags: [ "greeting", "clarify" ]
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal false, ticket.manual_takeover
    assert_equal false, ticket.human_handoff_available
    assert_equal [ "TriageAgent" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    assert_equal [ "user", "assistant" ], ticket.messages.order(:created_at).pluck(:role)
    assert_includes ticket.messages.order(:created_at).last.content, "What do you need help with today?"
  end

  test "non llm triage still falls back to a generic clarification message" do
    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "नमस्ते")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal false, ticket.human_handoff_available
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.messages.order(:created_at).last.content, "What do you need help with today?"
  end

  test "offers manual human handoff instead of auto escalating when triage confidence is below the guardrail" do
    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Do you support Canada passport photos?")

    llm_client = FakeLlmClient.new(
      {
        needs_human_handoff: false,
        confidence: 0.94,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        category: "policy",
        priority: "normal",
        route: "specialist",
        confidence: 0.59,
        needs_human_now: false,
        reasoning_summary: "This looks like a support question but confidence is weak."
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal false, ticket.manual_takeover
    assert_equal true, ticket.human_handoff_available
    assert_equal 1, ticket.agent_runs.count
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.summary, "confidence"
    assert_includes ticket.escalation_reason, "confidence"
    assert_includes ticket.messages.order(:created_at).last.content.downcase, "human"
  end

  test "offers manual human handoff when triage confidence is below the guardrail" do
    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Do you support Canada passport photos?")

    llm_client = FakeLlmClient.new(
      {
        needs_human_handoff: false,
        confidence: 0.94,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        category: "policy",
        priority: "normal",
        route: "specialist",
        confidence: 0.59,
        needs_human_now: false,
        reasoning_summary: "This looks like a support question but confidence is weak."
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal false, ticket.manual_takeover
    assert_equal true, ticket.human_handoff_available
    assert_equal 1, ticket.agent_runs.count
    assert_equal [ "TriageAgent" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    assert_equal 2, llm_client.calls.size
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.escalation_reason, "confidence"
  end

  test "offers manual human handoff when specialist confidence is below the guardrail even if it drafted a reply" do
    KnowledgeArticle.create!(
      company: @company,
      title: "Supported Countries",
      category: "policy",
      content: "We support passport photo formats for Canada, the US, the UK, and Schengen countries."
    )

    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Do you support Canada passport photos?")

    llm_client = FakeLlmClient.new(
      {
        needs_human_handoff: false,
        confidence: 0.94,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        category: "policy",
        priority: "normal",
        route: "specialist",
        confidence: 0.91,
        needs_human_now: false,
        reasoning_summary: "The customer is asking a supported-country question."
      },
      {
        reply: "Yes. Canada passport photos are supported.",
        resolve_ticket: true,
        confidence: 0.69,
        used_knowledge_articles: [ "Supported Countries" ],
        used_tools: [],
        reasoning_summary: "The knowledge is relevant but confidence is still too weak."
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "specialist", ticket.current_layer
    assert_equal false, ticket.manual_takeover
    assert_equal true, ticket.human_handoff_available
    assert_equal 2, ticket.agent_runs.count
    assert_equal [ "TriageAgent", "SpecialistAgent" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.escalation_reason, "confidence"
    assert_includes ticket.handoff_note, "human review"
  end

  test "offers manual human handoff instead of auto escalating when specialist confidence is below the guardrail" do
    KnowledgeArticle.create!(
      company: @company,
      title: "Supported Countries",
      category: "policy",
      content: "We support passport photo formats for Canada, the US, the UK, and Schengen countries."
    )

    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Do you support Canada passport photos?")

    llm_client = FakeLlmClient.new(
      {
        needs_human_handoff: false,
        confidence: 0.94,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        category: "policy",
        priority: "normal",
        route: "specialist",
        confidence: 0.91,
        needs_human_now: false,
        reasoning_summary: "The customer is asking a supported-country question."
      },
      {
        reply: "Yes. Canada passport photos are supported.",
        resolve_ticket: true,
        confidence: 0.69,
        used_knowledge_articles: [ "Supported Countries" ],
        used_tools: [],
        reasoning_summary: "The knowledge is relevant but confidence is still too weak."
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "specialist", ticket.current_layer
    assert_equal false, ticket.manual_takeover
    assert_equal true, ticket.human_handoff_available
    assert_equal [ "TriageAgent", "SpecialistAgent" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.summary, "confidence"
    assert_includes ticket.messages.order(:created_at).last.content.downcase, "human"
  end

  test "llm triage offers manual human handoff for an explicit request before public knowledge routing" do
    source = Knowledge::Source.create!(
      company: @company,
      url: "https://www.aipassportphoto.co/contact",
      title: "Contact",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "Customers can contact AI Passport Photo support through the website contact page or by emailing help@aipassportphoto.co."
    )
    source.chunks.create!(
      company: @company,
      content: "Customers can contact AI Passport Photo support through the website contact page or by emailing help@aipassportphoto.co.",
      position: 0,
      token_estimate: 16
    )

    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "please call someone from support")

    llm_client = FakeLlmClient.new(
      {
        needs_human_handoff: true,
        confidence: 0.97,
        reasoning_summary: "The customer is explicitly asking for human support."
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal false, ticket.manual_takeover
    assert_equal true, ticket.human_handoff_available
    assert_equal [ "human_handoff_intent" ], llm_client.calls.map { |call| call[:task] }
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    refute_equal "public_knowledge", JSON.parse(ticket.agent_runs.order(:created_at).first.output_snapshot).fetch("source")
  end

  class FakeLlmClient
    attr_reader :calls

    def initialize(*responses)
      @responses = responses
      @calls = []
    end

    def complete_json(task:, prompt:, context:)
      @calls << { task: task, prompt: prompt, context: context }
      @responses.shift
    end
  end
end
