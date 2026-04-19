require "test_helper"

class SupportPipelinePublicAnswerTest < ActiveSupport::TestCase
  test "answers faq-style question from public knowledge at triage level" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "review@example.com")

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/",
      title: "Homepage",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "Under 60 seconds. Upload your photo, our AI processes it instantly, and you can download or print your compliant passport photo right away."
    )
    source.chunks.create!(
      company: company,
      content: "Under 60 seconds. Upload your photo, our AI processes it instantly, and you can download or print your compliant passport photo right away.",
      position: 0,
      token_estimate: 24
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "How long does it take?")

    llm_client = FakeKnowledgeLlmClient.new(
      {
        reply: "It usually takes under 60 seconds. Source: Homepage — https://www.aipassportphoto.co/.",
        confidence: 0.93,
        reasoning_summary: "Answered from the homepage delivery timing text."
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal 1, ticket.agent_runs.count
    assert_equal [ "user", "assistant" ], ticket.messages.order(:created_at).pluck(:role)
    reply = ticket.messages.order(:created_at).last.content
    assert_includes reply, "60 seconds"
    assert_includes reply, "Source:"
    assert_equal "policy", ticket.category
    assert_equal [ "knowledge_answer" ], llm_client.calls.map { |call| call[:task] }
    assert_includes llm_client.calls.first[:context][:knowledge_chunks].first[:content], "Under 60 seconds"
  end

  test "uses the llm to compose a yes-no faq answer from public knowledge" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "review@example.com")

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/",
      title: "Homepage",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "We support passport and visa photo requirements for Canada, the US, the UK, and 100+ countries."
    )
    source.chunks.create!(
      company: company,
      content: "We support passport and visa photo requirements for Canada, the US, the UK, and 100+ countries.",
      position: 0,
      token_estimate: 18
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Can I make Canada passport picture?")

    llm_client = FakeKnowledgeLlmClient.new(
      {
        reply: "Yes, you can. Canada passport photos are supported. Source: Homepage — https://www.aipassportphoto.co/.",
        confidence: 0.94,
        reasoning_summary: "Answered from the supported countries text."
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    reply = ticket.messages.order(:created_at).last.content

    assert_includes reply, "Yes"
    assert_includes reply, "Canada"
    assert_includes reply, "Source:"
    refute_match(/\AWe support passport and visa photo requirements/m, reply)
  end

  test "does not answer an operational delivery issue from public knowledge" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/contact",
      title: "Contact",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "If you did not receive your download link, check your spam folder first. If you still cannot find it, email support@aipassportphoto.co with the email address used at checkout."
    )
    source.chunks.create!(
      company: company,
      content: "If you did not receive your download link, check your spam folder first. If you still cannot find it, email support@aipassportphoto.co with the email address used at checkout.",
      position: 0,
      token_estimate: 30
    )

    BusinessRecord.create!(
      company: company,
      record_type: "photo_request",
      external_id: "APP-1001",
      customer_email: "anna@example.com",
      status: "completed",
      payload: {
        asset_delivery: "sent",
        download_url: "https://example.test/download/APP-1001"
      }
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "I paid but did not receive my file")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "delivery", ticket.category
    assert_equal 2, ticket.agent_runs.count
    assert_equal [ "TriageAgent", "SpecialistAgent" ], ticket.agent_runs.order(:created_at).pluck(:agent_name)
    refute_equal "public_knowledge", JSON.parse(ticket.agent_runs.order(:created_at).first.output_snapshot).fetch("source")
  end

  test "does not answer from public knowledge on a weak incidental match" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "review@example.com")

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/contact",
      title: "Contact",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "Contact support at help@aipassportphoto.co for manual assistance."
    )
    source.chunks.create!(
      company: company,
      content: "Contact support at help@aipassportphoto.co for manual assistance.",
      position: 0,
      token_estimate: 10
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "support")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "escalated", ticket.status
    assert_equal "human", ticket.current_layer
    assert_equal 2, ticket.agent_runs.count
    refute_equal "public_knowledge", JSON.parse(ticket.agent_runs.order(:created_at).first.output_snapshot).fetch("source")
  end
end

class FakeKnowledgeLlmClient
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
