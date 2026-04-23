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
    assert_equal [ "human_handoff_intent", "intent_classification", "specialist" ], llm_client.calls.map { |call| call[:task] }
    assert_includes ticket.messages.order(:created_at).last.content, "Canada"
    assert_equal [ "canada", "passport", "policy", "supported-country" ], ticket.reload.tag_list.sort
    triage_call = llm_client.calls.find { |call| call[:task] == "intent_classification" }
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
    assert_equal "llm_intent", JSON.parse(triage_run.output_snapshot).fetch("source")
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

  test "llm triage downgrades unsolicited human handoff decisions to clarification" do
    ticket = @company.tickets.create!(
      customer: @customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "What payment systems u support?")
    ticket.messages.create!(role: "assistant", content: "We process all payments securely through Stripe.")
    ticket.messages.create!(role: "user", content: "Ok how much is the fish")
    ticket.messages.create!(role: "assistant", content: "Could you please clarify your question so I can assist you better?")
    ticket.messages.create!(role: "user", content: "I need some fish")

    llm_client = FakeLlmClient.new(
      {
        needs_human_handoff: false,
        confidence: 0.96,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        category: "other",
        priority: "low",
        route: "offer_human_handoff",
        confidence: 0.66,
        needs_human_now: true,
        reply: "This request needs specialist review. If you want, I can connect you with a human specialist.",
        reasoning_summary: "The request looks unrelated to the supported business domain.",
        tags: [ "off-topic" ]
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal false, ticket.manual_takeover
    assert_equal false, ticket.human_handoff_available
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.messages.order(:created_at).last.content, "What do you need help with today?"
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
