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

    assert_equal "resolved", ticket.status
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

    assert_equal "resolved", ticket.status
    assert_equal "technical", ticket.category
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.messages.order(:created_at).last.content, "still provisioning"
    assert_equal [ "TriageAgent", "SpecialistAgent" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    assert_equal [ "lookup_deployment" ], ticket.tool_calls.order(:created_at).pluck(:tool_name)
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
        reasoning_summary: "The customer is asking a supported-country question."
      },
      {
        reply: "Yes. Canada passport photos are supported.",
        resolve_ticket: true,
        confidence: 0.93,
        used_knowledge_articles: [ "Supported Countries" ],
        used_tools: [],
        reasoning_summary: "The company knowledge base confirms Canada is supported."
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    assert_equal "resolved", ticket.status
    assert_equal 2, llm_client.calls.size
    assert_equal [ "triage", "specialist" ], llm_client.calls.map { |call| call[:task] }
    assert_includes ticket.messages.order(:created_at).last.content, "Canada"
    triage_run = ticket.agent_runs.order(:created_at).first
    specialist_run = ticket.agent_runs.order(:created_at).second
    assert_equal "llm", JSON.parse(triage_run.output_snapshot).fetch("source")
    assert_equal "llm", JSON.parse(specialist_run.output_snapshot).fetch("source")
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
