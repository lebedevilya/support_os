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
    ticket.messages.create!(role: "user", content: "Hi")
    ticket.messages.create!(role: "assistant", content: "Hello! What do you need help with?")
    ticket.messages.create!(role: "user", content: "How long does it take?")

    llm_client = FakeKnowledgeLlmClient.new(
      {
        needs_human_handoff: false,
        confidence: 0.94,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        reply: "It usually takes under 60 seconds.",
        confidence: 0.93,
        reasoning_summary: "Answered from the homepage delivery timing text.",
        cited_source_url: "https://www.aipassportphoto.co/"
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal 1, ticket.agent_runs.count
    assert_equal [ "user", "assistant", "user", "assistant" ], ticket.messages.order(:created_at).pluck(:role)
    reply = ticket.messages.order(:created_at).last.content
    assert_includes reply, "60 seconds"
    assert_includes reply, "Source:"
    assert_includes reply, "https://www.aipassportphoto.co/"
    assert_equal "policy", ticket.category
    assert_equal [ "human_handoff_intent", "knowledge_answer" ], llm_client.calls.map { |call| call[:task] }
    knowledge_call = llm_client.calls.find { |call| call[:task] == "knowledge_answer" }
    assert_includes knowledge_call[:context][:knowledge_chunks].first[:content], "Under 60 seconds"
    assert_equal [
      [ "user", "Hi" ],
      [ "assistant", "Hello! What do you need help with?" ],
      [ "user", "How long does it take?" ]
    ], knowledge_call[:context][:message_history]
    assert_includes knowledge_call[:prompt], "do not include URLs or citation text directly in reply"
    assert_includes knowledge_call[:prompt], "set cited_source_url only when one provided source page directly supports the answer"
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
        needs_human_handoff: false,
        confidence: 0.94,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        reply: "Yes, you can. Canada passport photos are supported.",
        confidence: 0.94,
        reasoning_summary: "Answered from the supported countries text.",
        cited_source_url: "https://www.aipassportphoto.co/"
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

  test "grounds office location questions in retrieved public knowledge instead of llm fabrication" do
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
      extracted_text: "Registered Address Picanha L.L.C-FZ United Arab Emirates."
    )
    source.chunks.create!(
      company: company,
      content: "Registered Address Picanha L.L.C-FZ United Arab Emirates.",
      position: 0,
      token_estimate: 8
    )
    distracting_terms_source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/terms",
      title: "Terms",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "Picanha L.L.C-FZ is registered in the United Arab Emirates and users must provide a valid email address."
    )
    distracting_terms_source.chunks.create!(
      company: company,
      content: "Picanha L.L.C-FZ is registered in the United Arab Emirates and users must provide a valid email address.",
      position: 0,
      token_estimate: 15
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "I want to know location of your office")

    llm_client = FakeKnowledgeLlmClient.new(
      {
        needs_human_handoff: false,
        confidence: 0.94,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        reply: "We don’t have the office location publicly listed. Please contact support@aipassportphoto.co for help.",
        confidence: 0.9,
        reasoning_summary: "Answered from the contact page.",
        cited_source_url: nil
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    reply = ticket.reload.messages.order(:created_at).last.content

    assert_includes reply, "Picanha"
    assert_includes reply, "United Arab Emirates"
    refute_includes reply, "Imaginetown"
    refute_includes reply, "123 Photo Blvd"
  end

  test "does not append a source link when the llm does not provide a directly supporting source" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "review@example.com")

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/privacy",
      title: "Privacy Policy",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "We explain how personal data is processed and stored."
    )
    source.chunks.create!(
      company: company,
      content: "We explain how personal data is processed and stored.",
      position: 0,
      token_estimate: 10
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "How much will it cost?")

    llm_client = FakeKnowledgeLlmClient.new(
      {
        needs_human_handoff: false,
        confidence: 0.94,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        reply: "The provided public information does not include pricing details.",
        confidence: 0.52,
        reasoning_summary: "The retrieved privacy content does not answer pricing.",
        cited_source_url: nil
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    reply = ticket.reload.messages.order(:created_at).last.content

    refute_includes reply, "Source:"
    refute_match(%r{https?://}, reply)
  end

  test "does not answer an operational delivery issue from public knowledge" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")

    SupportRule.create!(
      company: company,
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

  test "public knowledge can be blocked by support-rule boundary without a routing rule" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "review@example.com")

    SupportRule.create!(
      company: company,
      name: "Payment questions should not use public knowledge",
      active: true,
      priority: 10,
      match_type: "any_terms",
      terms: "payment\nreceipt",
      route: "specialist",
      category: "other",
      priority_level: "normal",
      confidence: 0.9,
      reasoning_summary: "Payment-related questions should not be answered from public knowledge.",
      blocks_public_knowledge: true
    )

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/privacy",
      title: "Privacy Policy",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "We explain how personal data is processed and stored."
    )
    source.chunks.create!(
      company: company,
      content: "We explain how personal data is processed and stored.",
      position: 0,
      token_estimate: 10
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Can I get a payment receipt?")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal true, ticket.human_handoff_available
    assert_equal "fallback", JSON.parse(ticket.agent_runs.order(:created_at).first.output_snapshot).fetch("source")
  end

  test "general payment faq can still answer from public knowledge when the blocker only covers operational billing cases" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "review@example.com")

    SupportRule.create!(
      company: company,
      name: "Operational billing requests should not use public knowledge",
      active: true,
      priority: 10,
      match_type: "any_terms",
      terms: "paid\nrefund\ninvoice\nreceipt",
      route: "specialist",
      category: "other",
      priority_level: "normal",
      confidence: 0.9,
      reasoning_summary: "Operational billing questions should not be answered from public knowledge.",
      blocks_public_knowledge: true
    )

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/pricing",
      title: "Pricing",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "We support card payments through Visa, Mastercard, American Express, Apple Pay, and Google Pay."
    )
    source.chunks.create!(
      company: company,
      content: "We support card payments through Visa, Mastercard, American Express, Apple Pay, and Google Pay.",
      position: 0,
      token_estimate: 18
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "What payment systems u support?")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal false, ticket.human_handoff_available
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.messages.order(:created_at).last.content, "Visa"
    assert_equal "public_knowledge", JSON.parse(ticket.agent_runs.order(:created_at).first.output_snapshot).fetch("source")
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

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal false, ticket.human_handoff_available
    assert_equal 1, ticket.agent_runs.count
    refute_equal "public_knowledge", JSON.parse(ticket.agent_runs.order(:created_at).first.output_snapshot).fetch("source")
  end

  test "does not answer from public knowledge on a vague follow-up with no clear support intent" do
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
      extracted_text: "Most passport photo requests are completed in under 60 seconds."
    )
    source.chunks.create!(
      company: company,
      content: "Most passport photo requests are completed in under 60 seconds.",
      position: 0,
      token_estimate: 10
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "i dont get it")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal false, ticket.human_handoff_available
    refute_equal "public_knowledge", JSON.parse(ticket.agent_runs.order(:created_at).first.output_snapshot).fetch("source")
  end

  test "does not answer a low-information help message from support-contact knowledge" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "review@example.com")

    manual_entry = Knowledge::ManualEntry.create!(
      company: company,
      title: "Support contact",
      content: "Customers can contact AI Passport Photo support through the website contact page or by emailing help@aipassportphoto.co.",
      status: "active"
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Please help")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    refute_equal "public_knowledge", JSON.parse(ticket.agent_runs.order(:created_at).first.output_snapshot).fetch("source")
    refute_includes ticket.messages.order(:created_at).last.content, manual_entry.content
    assert_includes ticket.messages.order(:created_at).last.content, "What do you need help with today?"
  end

  test "does not answer a greeting plus generic support request from support-contact knowledge" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "review@example.com")

    Knowledge::ManualEntry.create!(
      company: company,
      title: "Support contact",
      content: "Customers can contact AI Passport Photo support through the website contact page or by emailing help@aipassportphoto.co.",
      status: "active"
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "Hello, support?")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    refute_equal "public_knowledge", JSON.parse(ticket.agent_runs.order(:created_at).first.output_snapshot).fetch("source")
    assert_includes ticket.messages.order(:created_at).last.content, "What do you need help with today?"
  end

  test "does not answer a pricing question from incidental terms-of-service text" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "review@example.com")

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/terms",
      title: "Terms of Service",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "By accessing or using the service, you agree to these terms. The service is operated by Picanha L.L.C-FZ."
    )
    source.chunks.create!(
      company: company,
      content: "By accessing or using the service, you agree to these terms. The service is operated by Picanha L.L.C-FZ.",
      position: 0,
      token_estimate: 20
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "What is the cost of using the service?")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    refute_equal "public_knowledge", JSON.parse(ticket.agent_runs.order(:created_at).first.output_snapshot).fetch("source")
    refute_includes ticket.messages.order(:created_at).last.content, "Terms of Service"
    refute_includes ticket.messages.order(:created_at).last.content, "Picanha"
  end

  test "curated manual knowledge is preferred for important faq answers" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "review@example.com")

    noisy_source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/terms",
      title: "Terms of Service",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "Canada users agree to the website terms and passport service conditions."
    )
    noisy_source.chunks.create!(
      company: company,
      content: "Canada users agree to the website terms and passport service conditions.",
      position: 0,
      token_estimate: 12
    )

    manual_entry = Knowledge::ManualEntry.create!(
      company: company,
      title: "Canada passport photos",
      content: "AI Passport Photo supports Canada passport photos and checks the photo against the required 50 x 70 mm format.",
      status: "active"
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
        needs_human_handoff: false,
        confidence: 0.94,
        reasoning_summary: "The customer is not explicitly asking for a human handoff."
      },
      {
        reply: "Yes, you can. Canada passport photos are supported.",
        confidence: 0.96,
        reasoning_summary: "Answered from the curated Canada passport photo guidance.",
        cited_source_url: nil
      }
    )

    SupportPipeline.new(ticket: ticket, llm_client: llm_client).call

    knowledge_call = llm_client.calls.find { |call| call[:task] == "knowledge_answer" }
    knowledge_chunks = knowledge_call[:context][:knowledge_chunks]

    assert_equal manual_entry.title, knowledge_chunks.first[:manual_entry_title]
    assert_includes knowledge_chunks.first[:content], "50 x 70 mm"
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
