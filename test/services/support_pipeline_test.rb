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

  test "escalates an embassy refund dispute to human" do
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

    assert_equal "escalated", ticket.status
    assert_equal "human", ticket.current_layer
    assert_equal "refund", ticket.category
    assert_equal 2, ticket.agent_runs.count
    assert_equal "human", ticket.messages.order(:created_at).last.role
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
    ticket.messages.create!(role: "user", content: "Do you support Canada passport photos?")

    llm_client = FakeLlmClient.new(
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
    assert_equal 2, llm_client.calls.size
    assert_equal [ "triage", "specialist" ], llm_client.calls.map { |call| call[:task] }
    assert_includes ticket.messages.order(:created_at).last.content, "Canada"
    assert_equal [ "canada", "passport", "policy", "supported-country" ], ticket.reload.tag_list.sort
    triage_run = ticket.agent_runs.order(:created_at).first
    specialist_run = ticket.agent_runs.order(:created_at).second
    assert_equal "llm", JSON.parse(triage_run.output_snapshot).fetch("source")
    assert_equal "llm", JSON.parse(specialist_run.output_snapshot).fetch("source")
  end

  test "escalates when triage confidence is below the guardrail" do
    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Do you support Canada passport photos?")

    llm_client = FakeLlmClient.new(
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

    assert_equal "escalated", ticket.status
    assert_equal "human", ticket.current_layer
    assert_equal 2, ticket.agent_runs.count
    assert_equal [ "TriageAgent", "HumanHandoff" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    assert_equal 1, llm_client.calls.size
    assert_equal "human", ticket.messages.order(:created_at).last.role
    assert_includes ticket.escalation_reason, "confidence"
  end

  test "escalates when specialist confidence is below the guardrail even if it drafted a reply" do
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

    assert_equal "escalated", ticket.status
    assert_equal "human", ticket.current_layer
    assert_equal 2, ticket.agent_runs.count
    assert_equal [ "TriageAgent", "SpecialistAgent" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    assert_equal "human", ticket.messages.order(:created_at).last.role
    assert_includes ticket.escalation_reason, "confidence"
    assert_includes ticket.handoff_note, "human review"
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
